import SwiftUI
import Combine

// MARK: - 1. STORAGE & CONFIG (iCloud Sync)

class TokenManager: ObservableObject {
    @Published var token: String = ""
    @Published var username: String = ""
    @Published var repo: String = ""
    
    private let store = NSUbiquitousKeyValueStore.default
    
    init() {
        // Load from iCloud on startup
        self.token = store.string(forKey: "gh_token") ?? ""
        self.username = store.string(forKey: "gh_user") ?? ""
        self.repo = store.string(forKey: "gh_repo") ?? ""
        
        // Listen for changes from other devices
        NotificationCenter.default.addObserver(self, selector: #selector(didChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        store.synchronize()
    }
    
    func save(token: String, user: String, repo: String) {
        self.token = token
        self.username = user
        self.repo = repo
        
        store.set(token, forKey: "gh_token")
        store.set(user, forKey: "gh_user")
        store.set(repo, forKey: "gh_repo")
        store.synchronize()
    }
    
    func logout() {
        save(token: "", user: "", repo: "")
    }
    
    @objc func didChange() {
        DispatchQueue.main.async {
            self.token = self.store.string(forKey: "gh_token") ?? ""
            self.username = self.store.string(forKey: "gh_user") ?? ""
            self.repo = self.store.string(forKey: "gh_repo") ?? ""
        }
    }
    
    var isLoggedIn: Bool { !token.isEmpty && !username.isEmpty && !repo.isEmpty }
}

// MARK: - 2. GITHUB CLIENT (The Engine)

@MainActor
class BuildEngine: ObservableObject {
    @Published var status: String = "Idle"
    @Published var isBuilding: Bool = false
    @Published var progress: Double = 0.0
    @Published var artifactURL: URL?
    @Published var errorMsg: String?
    
    func compile(appName: String, code: String, manager: TokenManager) async {
        guard !manager.token.isEmpty else { return }
        
        withAnimation {
            isBuilding = true
            progress = 0.1
            status = "Initializing..."
            errorMsg = nil
            artifactURL = nil
        }
        
        let config = GitHubConfig(owner: manager.username, repo: manager.repo, token: manager.token)
        
        do {
            // 1. Upload Project Spec
            status = "Configuring Project..."
            progress = 0.2
            let projectYml = makeProjectYml(appName: appName)
            try await uploadFile(content: projectYml, path: "project.yml", config: config)
            
            // 2. Upload Source Code
            status = "Uploading Code..."
            progress = 0.4
            try await uploadFile(content: code, path: "SourceCode.swift", config: config)
            
            // 3. Trigger Build
            status = "Queuing Build..."
            progress = 0.5
            try await triggerWorkflow(config: config)
            
            // 4. Wait for Result
            status = "Compiling in Cloud..."
            let runId = try await monitorBuild(config: config)
            
            // 5. Download
            status = "Downloading IPA..."
            progress = 0.9
            try await downloadArtifact(runId: runId, config: config)
            
            withAnimation {
                status = "Success!"
                progress = 1.0
                isBuilding = false
            }
            
        } catch {
            withAnimation {
                isBuilding = false
                progress = 0.0
                status = "Failed"
                errorMsg = error.localizedDescription
            }
        }
    }
    
    // --- API Helpers ---
    
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
    
    struct GitHubConfig { let owner, repo, token: String }
    
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
        let body: [String: Any] = [
            "message": "Update \(path)",
            "content": Data(content.utf8).base64EncodedString(),
            "sha": sha,
            "branch": "main"
        ]
        putReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, putResp) = try await URLSession.shared.data(for: putReq)
        
        guard (putResp as? HTTPURLResponse)?.statusCode ?? 0 < 300 else {
            throw NSError(domain: "Upload Failed", code: 1, userInfo: [NSLocalizedDescriptionKey: "Check write permissions on token."])
        }
    }
    
    private func triggerWorkflow(config: GitHubConfig) async throws {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/workflows/ios-build.yml/dispatches")!
        var req = request(url: url, token: config.token, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ref": "main"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "Trigger Failed", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start build. Check workflow filename."])
        }
        try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
    }
    
    private func monitorBuild(config: GitHubConfig) async throws -> Int {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/runs?per_page=1")!
        var attempts = 0
        while attempts < 40 { // ~3 mins max
            attempts += 1
            if attempts > 1 { try await Task.sleep(nanoseconds: 5 * 1_000_000_000) }
            
            let (data, _) = try await URLSession.shared.data(for: request(url: url, token: config.token, method: "GET"))
            struct Runs: Decodable { var workflow_runs: [Run] }
            struct Run: Decodable { var id: Int; var status: String; var conclusion: String? }
            
            if let run = try? JSONDecoder().decode(Runs.self, from: data).workflow_runs.first {
                if run.status == "completed" {
                    if run.conclusion == "success" { return run.id }
                    throw NSError(domain: "Build Failed", code: 3, userInfo: [NSLocalizedDescriptionKey: "GitHub Action failed. Check server logs."])
                }
            }
        }
        throw NSError(domain: "Timeout", code: 4, userInfo: [NSLocalizedDescriptionKey: "Build took too long."])
    }
    
    private func downloadArtifact(runId: Int, config: GitHubConfig) async throws {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/runs/\(runId)/artifacts")!
        let (data, _) = try await URLSession.shared.data(for: request(url: url, token: config.token, method: "GET"))
        
        struct ArtList: Decodable { var artifacts: [Artifact] }
        struct Artifact: Decodable { var archive_download_url: String }
        
        guard let dlUrlStr = (try? JSONDecoder().decode(ArtList.self, from: data))?.artifacts.first?.archive_download_url,
              let dlUrl = URL(string: dlUrlStr) else { return }
        
        let (tempUrl, _) = try await URLSession.shared.download(for: request(url: dlUrl, token: config.token, method: "GET"))
        let destUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(runId).zip")
        try? FileManager.default.removeItem(at: destUrl)
        try FileManager.default.moveItem(at: tempUrl, to: destUrl)
        self.artifactURL = destUrl
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

// MARK: - 3. USER INTERFACE (Modern Design)

@main
struct CompilerApp: App {
    @StateObject var tokenManager = TokenManager()
    
    var body: some Scene {
        WindowGroup {
            if tokenManager.isLoggedIn {
                DashboardView().environmentObject(tokenManager)
            } else {
                LoginView().environmentObject(tokenManager)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var manager: TokenManager
    @State private var token = ""
    @State private var user = ""
    @State private var repo = ""
    
    var body: some View {
        ZStack {
            MeshGradientBackground().ignoresSafeArea()
            
            VStack(spacing: 25) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
                
                Text("Compiler")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                VStack(spacing: 15) {
                    CustomTextField(icon: "person.fill", placeholder: "GitHub Username", text: $user)
                    CustomTextField(icon: "folder.fill", placeholder: "Repository Name", text: $repo)
                    CustomTextField(icon: "key.fill", placeholder: "Personal Access Token", text: $token, isSecure: true)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
                
                Button(action: {
                    withAnimation { manager.save(token: token, user: user, repo: repo) }
                }) {
                    Text("Sign In with iCloud")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .shadow(radius: 5)
                }
                .padding(.horizontal)
                .disabled(token.isEmpty || user.isEmpty || repo.isEmpty)
                .opacity((token.isEmpty || user.isEmpty || repo.isEmpty) ? 0.6 : 1)
            }
            .frame(maxWidth: 500)
        }
        .preferredColorScheme(.dark)
    }
}

struct DashboardView: View {
    @EnvironmentObject var manager: TokenManager
    @StateObject var engine = BuildEngine()
    
    @State private var appName = "MyApp"
    @State private var code = """
    import SwiftUI
    
    @main
    struct MyApp: App {
        var body: some Scene {
            WindowGroup {
                Text("Hello World")
                    .font(.largeTitle)
            }
        }
    }
    """
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Dashboard").font(.largeTitle.bold())
                            Text(manager.username + "/" + manager.repo).font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        Button(action: { withAnimation { manager.logout() } }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                                .padding(10)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    // App Name Input
                    HStack {
                        Image(systemName: "app.dashed")
                        TextField("App Name", text: $appName)
                    }
                    .padding()
                    .background(Color(white: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    // Code Editor Area
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $code)
                            .font(.custom("Menlo", size: 14))
                            .scrollContentBackground(.hidden)
                            .background(Color(white: 0.08))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    .padding()
                            )
                        
                        Button("Paste") {
                            if let str = UIPasteboard.general.string { code = str }
                        }
                        .font(.caption.bold())
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(24)
                    }
                    
                    // Build Action Area
                    VStack(spacing: 12) {
                        if engine.isBuilding {
                            VStack {
                                ProgressView(value: engine.progress)
                                    .tint(.blue)
                                Text(engine.status)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        } else if let error = engine.errorMsg {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 5)
                            
                            Button(action: runBuild) {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .MainButtonStyle(color: .red)
                            }
                        } else if let url = engine.artifactURL {
                            Text("Build Successful!")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            ShareLink(item: url) {
                                Label("Save IPA", systemImage: "square.and.arrow.down")
                                    .MainButtonStyle(color: .green)
                            }
                            
                            Button("New Build") {
                                withAnimation { engine.artifactURL = nil }
                            }
                            .font(.caption)
                            .foregroundColor(.gray)
                        } else {
                            Button(action: runBuild) {
                                Label("Compile App", systemImage: "hammer.fill")
                                    .MainButtonStyle(color: .blue)
                            }
                        }
                    }
                    .padding()
                    .background(Color(white: 0.05))
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
    
    func runBuild() {
        Task {
            await engine.compile(appName: appName, code: code, manager: manager)
        }
    }
}

// MARK: - 4. HELPERS & STYLES

struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray).frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding()
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
    }
}

// FIXED: Defined globally so CompilerApp doesn't scope it
struct MainButtonStyleModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: color.opacity(0.4), radius: 8, y: 4)
    }
}

extension View {
    func MainButtonStyle(color: Color) -> some View {
        modifier(MainButtonStyleModifier(color: color))
    }
}

struct MeshGradientBackground: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.indigo.opacity(0.3), .clear], center: .center, startRadius: 50, endRadius: 300)
        }
    }
}
