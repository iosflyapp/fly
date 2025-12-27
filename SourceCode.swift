import SwiftUI
import Combine

// MARK: - CONFIGURATION

struct GitHubConfig: Codable {
    var owner: String = "iosflyapp"     // Your GitHub Username
    var repo: String = "fly"            // Your Repository Name
    var token: String = ""              // Your Personal Access Token
    var branch: String = "main"
    var workflowId: String = "ios-build.yml"
    
    // Fixed paths to ensure clean overwrites
    var codePath: String = "SourceCode.swift"
    var projectPath: String = "project.yml"
}

// MARK: - GITHUB API CLIENT

@MainActor
class GitHubClient: ObservableObject {
    @Published var statusMessage = "Ready"
    @Published var isBusy = false
    @Published var downloadedURL: URL?
    
    enum APIError: Error {
        case invalidURL
        case requestFailed(reason: String)
        case noArtifacts
    }
    
    // GENERIC UPLOADER (Works for Code OR Project file)
    func uploadFile(content: String, path: String, config: GitHubConfig) async throws {
        let urlStr = "https://api.github.com/repos/\(config.owner)/\(config.repo)/contents/\(path)"
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        
        // 1. Get SHA (Check if file exists)
        var request = makeRequest(url: url, token: config.token, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        var sha: String = ""
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            struct FileInfo: Decodable { var sha: String }
            if let decoded = try? JSONDecoder().decode(FileInfo.self, from: data) { sha = decoded.sha }
        }
        
        // 2. Upload/Update File
        var putReq = makeRequest(url: url, token: config.token, method: "PUT")
        let body: [String: Any] = [
            "message": "Update \(path)",
            "content": Data(content.utf8).base64EncodedString(),
            "sha": sha,
            "branch": config.branch
        ]
        putReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (putData, putResp) = try await URLSession.shared.data(for: putReq)
        if let http = putResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let err = String(data: putData, encoding: .utf8) ?? "Unknown"
            throw APIError.requestFailed(reason: "Upload \(path) failed: \(http.statusCode) \(err)")
        }
    }
    
    // TRIGGER BUILD
    func triggerBuild(config: GitHubConfig) async throws {
        statusMessage = "Starting Build..."
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/workflows/\(config.workflowId)/dispatches")!
        var req = makeRequest(url: url, token: config.token, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ref": config.branch])
        
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.requestFailed(reason: "Trigger failed: \(http.statusCode)")
        }
        try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
    }
    
    // MONITOR & DOWNLOAD
    func monitorAndDownload(config: GitHubConfig) async throws {
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/runs?per_page=1")!
        
        var attempts = 0
        while attempts < 40 {
            attempts += 1
            statusMessage = "Building... (\(attempts * 5)s)"
            
            var req = makeRequest(url: url, token: config.token, method: "GET")
            let (data, _) = try await URLSession.shared.data(for: req)
            
            struct RunList: Decodable { var workflow_runs: [Run] }
            struct Run: Decodable { var id: Int; var status: String; var conclusion: String? }
            
            if let list = try? JSONDecoder().decode(RunList.self, from: data), let run = list.workflow_runs.first {
                if run.status == "completed" {
                    if run.conclusion == "success" {
                        try await downloadArtifact(runId: run.id, config: config)
                        return
                    } else {
                        throw APIError.requestFailed(reason: "Build Failed (Check GitHub Logs)")
                    }
                }
            }
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        }
        throw APIError.requestFailed(reason: "Timeout")
    }
    
    func downloadArtifact(runId: Int, config: GitHubConfig) async throws {
        statusMessage = "Downloading..."
        let url = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/actions/runs/\(runId)/artifacts")!
        var req = makeRequest(url: url, token: config.token, method: "GET")
        let (data, _) = try await URLSession.shared.data(for: req)
        
        struct ArtifactList: Decodable { var artifacts: [Artifact] }
        struct Artifact: Decodable { var id: Int; var archive_download_url: String }
        
        guard let list = try? JSONDecoder().decode(ArtifactList.self, from: data),
              let artifact = list.artifacts.first else { throw APIError.noArtifacts }
        
        let dlUrl = URL(string: artifact.archive_download_url)!
        var dlReq = makeRequest(url: dlUrl, token: config.token, method: "GET")
        let (temp, _) = try await URLSession.shared.download(for: dlReq)
        
        let finalUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(runId).zip")
        if FileManager.default.fileExists(atPath: finalUrl.path) { try FileManager.default.removeItem(at: finalUrl) }
        try FileManager.default.moveItem(at: temp, to: finalUrl)
        self.downloadedURL = finalUrl
        statusMessage = "Done!"
        isBusy = false
    }
    
    private func makeRequest(url: URL, token: String, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("iosflyapp", forHTTPHeaderField: "User-Agent")
        return req
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var client = GitHubClient()
    @State private var config = GitHubConfig()
    @State private var appName: String = "MyApp"
    @State private var codeText: String = "// Paste Swift Code Here"
    @State private var showSettings = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // STATUS BAR
                HStack {
                    Circle().fill(client.isBusy ? .yellow : (client.downloadedURL != nil ? .green : .gray)).frame(width: 8, height: 8)
                    Text(client.statusMessage).font(.caption.monospaced())
                    Spacer()
                }
                .padding().background(Color(uiColor: .systemGroupedBackground))
                
                // CONTROLS
                HStack {
                    TextField("App Name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    
                    if let url = client.downloadedURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title2).foregroundColor(.green)
                        }.frame(width: 44)
                    } else {
                        Button(action: startBuild) {
                            if client.isBusy { ProgressView() } else { Image(systemName: "play.fill").font(.title2) }
                        }
                        .disabled(client.isBusy)
                        .frame(width: 44)
                    }
                }.padding()
                
                Divider()
                
                TextEditor(text: $codeText)
                    .font(.custom("Menlo", size: 12))
                    .padding(4)
            }
            .navigationTitle("Cloud Compiler 2.1")
            .toolbar { Button(action: { showSettings = true }) { Image(systemName: "gear") } }
            .sheet(isPresented: $showSettings) {
                Form {
                    Section("GitHub Auth") {
                        TextField("User", text: $config.owner)
                        TextField("Repo", text: $config.repo)
                        SecureField("Token", text: $config.token)
                    }
                    Button("Save") { showSettings = false }
                }
            }
        }
    }
    
    func startBuild() {
        guard !config.token.isEmpty else { client.statusMessage = "No Token"; return }
        
        // 1. Generate Project.yml dynamically
        // Note: Removed 'xcodeVersion: 15.0' so it uses the latest version (16) on the new server
        let projectYml = """
        name: \(appName)
        options:
          bundleIdPrefix: neo.uniwalls
        targets:
          \(appName):
            type: application
            platform: iOS
            deploymentTarget: 17.0
            sources: [\(config.codePath)]
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
        
        Task {
            do {
                client.statusMessage = "Uploading Project Spec..."
                try await client.uploadFile(content: projectYml, path: config.projectPath, config: config)
                
                client.statusMessage = "Uploading Source Code..."
                try await client.uploadFile(content: codeText, path: config.codePath, config: config)
                
                try await client.triggerBuild(config: config)
                try await client.monitorAndDownload(config: config)
            } catch {
                if case let GitHubClient.APIError.requestFailed(reason) = error {
                    client.statusMessage = reason
                } else {
                    client.statusMessage = "Error: \(error.localizedDescription)"
                }
                client.isBusy = false
            }
        }
    }
}
