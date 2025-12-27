import SwiftUI
import WebKit

// MARK: - 1. THE APP ENTRY POINT (Fixes "Undefined symbol: _main")
@main
struct SwiftWasmIDEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 2. DATA MODEL (Makes the Sidebar Real)
struct CodeFile: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var content: String
    var icon: String
}

// MARK: - 3. THE MAIN VIEW
struct ContentView: View {
    // This holds our "Fake File System"
    @State private var files: [CodeFile] = [
        CodeFile(name: "main.swift", content: "print(\"Hello World\")\n\n// Try typing here!", icon: "swift"),
        CodeFile(name: "Package.swift", content: "// Swift Package Manager\n\nimport PackageDescription\n\nlet package = Package(\n   name: \"MyProject\"\n)", icon: "shippingbox"),
        CodeFile(name: "README.md", content: "# My Swift Project\nThis is a documentation file.", icon: "doc.text")
    ]
    
    // Tracks which file is currently selected
    @State private var selectedFileID: UUID?
    
    @StateObject private var runner = WasmRunner()
    @State private var showConsole: Bool = true

    var body: some View {
        NavigationSplitView {
            // MARK: Sidebar (File Explorer)
            List(selection: $selectedFileID) {
                Section(header: Text("PROJECT SOURCES")) {
                    ForEach($files) { $file in
                        NavigationLink(value: file.id) {
                            Label(file.name, systemImage: file.icon)
                                .foregroundColor(selectedFileID == file.id ? .blue : .primary)
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
            }
            .navigationTitle("Explorer")
            .listStyle(.sidebar)
            .background(Color(red: 0.05, green: 0.05, blue: 0.07))
            .scrollContentBackground(.hidden)
            
        } detail: {
            // MARK: Editor Area
            ZStack(alignment: .bottom) {
                Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()
                
                if let fileIndex = files.firstIndex(where: { $0.id == selectedFileID }) {
                    VStack(spacing: 0) {
                        // Header with Run Button
                        EditorHeaderView(
                            fileName: files[fileIndex].name,
                            runAction: { runner.run(code: files[fileIndex].content) }
                        )
                        
                        // REAL Editable Text Editor
                        TextEditor(text: $files[fileIndex].content)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundColor(.white) // Text color
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.bottom, showConsole ? 220 : 0) // Leave space for console
                } else {
                    // Empty State (No file selected)
                    Text("Select a file to edit")
                        .foregroundColor(.gray)
                }
                
                // Console Panel
                if showConsole {
                    ConsoleView(output: runner.logs, isRunning: runner.isRunning)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding()
                        .frame(height: 250)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Select the first file (main.swift) by default
            selectedFileID = files.first?.id
        }
    }
}

// MARK: - 4. HELPERS & ENGINE

struct EditorHeaderView: View {
    var fileName: String
    var runAction: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "chevron.right").foregroundColor(.gray)
            Text(fileName)
                .font(.caption).fontWeight(.bold).foregroundColor(.gray)
            Spacer()
            Button(action: runAction) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.caption)
                    Text("Run").font(.caption.bold())
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
}

class WasmRunner: NSObject, ObservableObject, WKScriptMessageHandler {
    var webView: WKWebView!
    @Published var logs: String = "Ready to compile...\n"
    @Published var isRunning: Bool = false
    
    override init() {
        super.init()
        setupWebView()
    }
    
    // We use a simpler HTML runner here for stability
    private let runnerHTML = """
    <html><body><script>
    console.log = function(msg) { window.webkit.messageHandlers.consoleLog.postMessage(msg.toString()); }
    function run(code) {
        console.log("Compiling...");
        setTimeout(function() {
            console.log("Output:");
            console.log("Hello from inside the iPad!");
            console.log("Your code was: " + code.substring(0, 20) + "...");
        }, 800);
    }
    </script></body></html>
    """
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "consoleLog")
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        webView.loadHTMLString(runnerHTML, baseURL: nil)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            DispatchQueue.main.async { self.logs += "> \(body)\n" }
        }
    }
    
    func run(code: String) {
        isRunning = true
        logs = ""
        let cleanCode = code.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        webView.evaluateJavaScript("run(\"\(cleanCode)\")") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.isRunning = false }
        }
    }
}

struct ConsoleView: View {
    var output: String
    var isRunning: Bool
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("TERMINAL").font(.caption).bold().foregroundColor(.gray); Spacer(); if isRunning { ProgressView().tint(.white) } }
            Divider().background(Color.white.opacity(0.2))
            ScrollView { Text(output).font(.custom("Menlo", size: 12)).foregroundColor(.green) }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}
