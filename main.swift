import SwiftUI
import Combine

// MARK: - 1. STORAGE & CONFIG

class TokenManager: ObservableObject {
    @Published var token: String = ""
    @Published var username: String = ""
    @Published var repo: String = ""
    
    private let store = NSUbiquitousKeyValueStore.default
    
    init() {
        self.token = store.string(forKey: "gh_token") ?? ""
        self.username = store.string(forKey: "gh_user") ?? ""
        self.repo = store.string(forKey: "gh_repo") ?? ""
        NotificationCenter.default.addObserver(self, selector: #selector(didChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        store.synchronize()
    }
    
    func save(token: String, user: String, repo: String) {
        self.token = token; self.username = user; self.repo = repo
        store.set(token, forKey: "gh_token"); store.set(user, forKey: "gh_user"); store.set(repo, forKey: "gh_repo")
        store.synchronize()
    }
    
    func logout() { save(token: "", user: "", repo: "") }
    
    @objc func didChange() {
        DispatchQueue.main.async {
            self.token = self.store.string(forKey: "gh_token") ?? ""
            self.username = self.store.string(forKey: "gh_user") ?? ""
            self.repo = self.store.string(forKey: "gh_repo") ?? ""
        }
    }
    var isLoggedIn: Bool { !token.isEmpty && !username.isEmpty && !repo.isEmpty }
}

// MARK: - 2. BUILD ENGINE

@MainActor
class BuildEngine: ObservableObject {
    @Published var status: String = "Idle"
    @Published var isBuilding: Bool = false
    @Published var progress: Double = 0.0
    @Published var artifactURL: URL?
    @Published var errorMsg: String?
    
    struct GitHubConfig { let owner, repo, token: String }
    
    func compile(appName: String, code: String, manager: TokenManager) async {
        guard !manager.token.isEmpty else { return }
        
        withAnimation { isBuilding = true; progress = 0.1; status = "Initializing..."; errorMsg = nil; artifactURL = nil }
        
        let config = GitHubConfig(owner: manager.username, repo: manager.repo, token: manager.token)
        
        do {
            // 1. Upload Project & Code
            status = "Uploading Code..."
            progress = 0.3
            try await uploadFile(content: makeProjectYml(appName: appName), path: "project.yml", config: config)
            try await uploadFile(content: code, path: "SourceCode.swift", config: config)
            
            // 2. Trigger Build
            status = "Queuing Build..."
            progress = 0.5
            try await triggerWorkflow(config: config)
            
            // 3. Monitor
            status = "Compiling in Cloud..."
            let runId = try await monitorBuild(config: config)
            
            // 4. Download Direct IPA from Release
            status = "Fetching IPA..."
            progress = 0.9
            try await downloadDirectIPA(runId: runId, config: config)
            
            withAnimation { status = "Success!"; progress = 1.0; isBuilding = false }
            
        } catch {
            withAnimation { isBuilding = false; progress = 0.0; status = "Failed"; errorMsg = error.localizedDescription }
        }
    }
    
    // --- API Logic ---
    
    private func makeProjectYml(appName: String) -> String {
        return """
        name: \(appName)
        options:
          bundleIdPrefix: neo.uniwalls
        targets:
          \(appName):
            type: application
            platform: iOS
            deploymentTarget: 17.0
            sources: [SourceCode.swift]
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: neo.uniwalls
                DEVELOPMENT_TEAM: VYB7C529CN
                CODE_SIGN_STYLE: Manual
                CODE_SIGN_IDENTITY: "Apple Development"
                PROVISIONING_PROFILE_SPECIFIER: "Developer"
                GENERATE_INFOPLIST_FILE: YES
                MARKETING_VERSION: 1.0
                CURRENT_PROJECT_VERSION: 1
                INFOPLIST_KEY_UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
                INFOPLIST_KEY_UILaunchScreen_Generation: true
        """
    }
    
    private func uploadFile(content: String, path: String, config: GitHubConfig) async throws {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/contents/\(path)")!
        var getReq = request(url: url, token: config.token, method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: getReq)
        var sha = ""
        if (resp as? HTTPURLResponse)?.statusCode == 200 {
            struct FileInfo: Decodable { var sha: String }
            sha = (try? JSONDecoder().decode(FileInfo.self, from: data).sha) ?? ""
        }
        
        var putReq = request(url: url, token: config.token, method: "PUT")
        let body: [String: Any] = ["message": "Update \(path)", "content": Data(content.utf8).base64EncodedString(), "sha": sha, "branch": "main"]
        putReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, putResp) = try await URLSession.shared.data(for: putReq)
        if (putResp as? HTTPURLResponse)?.statusCode ?? 0 >= 300 { throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Upload failed."]) }
    }
    
    private func triggerWorkflow(config: GitHubConfig) async throws {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/workflows/ios-build.yml/dispatches")!
        var req = request(url: url, token: config.token, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ref": "main"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode != 204 { throw NSError(domain: "Trigger", code: 2, userInfo: [NSLocalizedDescriptionKey: "Trigger failed."]) }
        try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
    }
    
    private func monitorBuild(config: GitHubConfig) async throws -> Int {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/runs?per_page=1")!
        var attempts = 0
        while attempts < 40 {
            attempts += 1
            if attempts > 1 { try await Task.sleep(nanoseconds: 5 * 1_000_000_000) }
            let (data, _) = try await URLSession.shared.data(for: request(url: url, token: config.token, method: "GET"))
            struct Runs: Decodable { var workflow_runs: [Run] }
            struct Run: Decodable { var id: Int; var status: String; var conclusion: String? }
            if let run = try? JSONDecoder().decode(Runs.self, from: data).workflow_runs.first {
                if run.status == "completed" {
                    if run.conclusion == "success" { return run.id }
                    throw NSError(domain: "Build", code: 3, userInfo: [NSLocalizedDescriptionKey: "Build failed on server."])
                }
            }
        }
        throw NSError(domain: "Timeout", code: 4, userInfo: [NSLocalizedDescriptionKey: "Build timed out."])
    }
    
    // NEW: Download IPA from Release, then Delete Release
    private func downloadDirectIPA(runId: Int, config: GitHubConfig) async throws {
        let tagName = "build-\(runId)"
        let releaseUrl = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/releases/tags/\(tagName)")!
        
        // 1. Get Release Info
        var attempts = 0
        while attempts < 10 { // Wait for release to appear
            attempts += 1
            let (data, resp) = try await URLSession.shared.data(for: request(url: releaseUrl, token: config.token, method: "GET"))
            
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                struct Release: Decodable { var id: Int; var assets: [Asset] }
                struct Asset: Decodable { var name: String; var url: String } 
                
                if let release = try? JSONDecoder().decode(Release.self, from: data),
                   let asset = release.assets.first(where: { $0.name.hasSuffix(".ipa") }) {
                    
                    // 2. Download Asset (Raw)
                    var dlReq = request(url: URL(string: asset.url)!, token: config.token, method: "GET")
                    dlReq.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    
                    let (tempUrl, _) = try await URLSession.shared.download(for: dlReq)
                    let destUrl = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
                    try? FileManager.default.removeItem(at: destUrl)
                    try FileManager.default.moveItem(at: tempUrl, to: destUrl)
                    self.artifactURL = destUrl
                    
                    // 3. Cleanup: Delete Release
                    let delUrl = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/releases/\(release.id)")!
                    var delReq = request(url: delUrl, token: config.token, method: "DELETE")
                    _ = try? await URLSession.shared.data(for: delReq)
                    
                    // Also delete tag ref
                    let tagUrl = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/git/refs/tags/\(tagName)")!
                    var tagReq = request(url: tagUrl, token: config.token, method: "DELETE")
                    _ = try? await URLSession.shared.data(for: tagReq)
                    
                    return
                }
            }
            try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
        }
        throw NSError(domain: "Download", code: 5, userInfo: [NSLocalizedDescriptionKey: "IPA not found in release."])
    }
    
    private func request(url: URL, token: String, method: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("CompilerApp", forHTTPHeaderField: "User-Agent")
        return r
    }
}

// MARK: - 3. UI

@main
struct CompilerApp: App {
    @StateObject var tokenManager = TokenManager()
    var body: some Scene {
        WindowGroup {
            if tokenManager.isLoggedIn { DashboardView().environmentObject(tokenManager) }
            else { LoginView().environmentObject(tokenManager) }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var manager: TokenManager
    // FIXED: Split multiple state variables to separate lines
    @State private var t = ""
    @State private var u = ""
    @State private var r = ""
    
    var body: some View {
        ZStack {
            MeshGradientBackground().ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "cpu.fill").font(.system(size: 80)).foregroundColor(.white).shadow(radius: 10)
                
                // FIXED: Correct Font syntax for rounded design
                Text("Compiler 3.0")
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundColor(.white)
                
                VStack(spacing: 15) {
                    CustomTextField(icon: "person.fill", placeholder: "GitHub User", text: $u)
                    CustomTextField(icon: "folder.fill", placeholder: "Repo Name", text: $r)
                    CustomTextField(icon: "key.fill", placeholder: "Token (ghp_...)", text: $t, isSecure: true)
                }.padding().background(.ultraThinMaterial).cornerRadius(20).padding()
                
                Button(action: { withAnimation { manager.save(token: t, user: u, repo: r) } }) {
                    Text("Sign In").MainButtonStyle(color: .white).foregroundColor(.black)
                }.padding().disabled(t.isEmpty||u.isEmpty||r.isEmpty).opacity(0.8)
            }.frame(maxWidth: 500)
        }.preferredColorScheme(.dark)
    }
}

struct DashboardView: View {
    @EnvironmentObject var manager: TokenManager
    @StateObject var engine = BuildEngine()
    @State private var appName = "MyApp"
    @State private var code = "// Paste Code Here"
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) { Text("Dashboard").font(.largeTitle.bold()); Text("\(manager.username)/\(manager.repo)").font(.caption).foregroundColor(.gray) }
                        Spacer()
                        Button(action: { manager.logout() }) { Image(systemName: "rectangle.portrait.and.arrow.right").foregroundColor(.red).padding(10).background(Color.red.opacity(0.1)).clipShape(Circle()) }
                    }.padding()
                    
                    HStack { Image(systemName: "app.dashed"); TextField("App Name", text: $appName) }.padding().background(Color(white: 0.1)).cornerRadius(12).padding(.horizontal)
                    
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $code).font(.custom("Menlo", size: 12)).scrollContentBackground(.hidden).background(Color(white: 0.08)).cornerRadius(12).padding().overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1).padding())
                        Button("Paste") { if let s = UIPasteboard.general.string { code = s } }.font(.caption.bold()).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(24)
                    }
                    
                    VStack(spacing: 12) {
                        if engine.isBuilding {
                            ProgressView(value: engine.progress).tint(.blue).padding(.horizontal)
                            Text(engine.status).font(.caption).foregroundColor(.gray)
                        } else if let err = engine.errorMsg {
                            Text("Error: \(err)").font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                            Button(action: run) { Label("Retry", systemImage: "arrow.clockwise").MainButtonStyle(color: .red) }
                        } else if let url = engine.artifactURL {
                            Text("Ready: \(url.lastPathComponent)").font(.caption).foregroundColor(.green)
                            ShareLink(item: url) { Label("Save IPA", systemImage: "square.and.arrow.down").MainButtonStyle(color: .green) }
                            Button("New Build") { withAnimation { engine.artifactURL = nil } }.font(.caption).foregroundColor(.gray)
                        } else {
                            Button(action: run) { Label("Compile App", systemImage: "hammer.fill").MainButtonStyle(color: .blue) }
                        }
                    }.padding().background(Color(white: 0.05))
                }
            }.navigationBarHidden(true)
        }.preferredColorScheme(.dark)
    }
    func run() { Task { await engine.compile(appName: appName, code: code, manager: manager) } }
}

struct CustomTextField: View {
    let icon: String, placeholder: String; @Binding var text: String; var isSecure=false
    var body: some View {
        HStack { Image(systemName: icon).foregroundColor(.gray).frame(width: 20); if isSecure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) } }
            .padding().background(Color.black.opacity(0.4)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
    }
}
struct MainButtonStyleModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View { content.font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(color).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: color.opacity(0.4), radius: 8, y: 4) }
}
extension View { func MainButtonStyle(color: Color) -> some View { modifier(MainButtonStyleModifier(color: color)) } }
struct MeshGradientBackground: View { var body: some View { ZStack { Color.black; LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing) } } }
