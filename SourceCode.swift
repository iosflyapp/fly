import SwiftUI
import WebKit

// MARK: - 1. The Missing Entry Point (FIXED)
// This tells the compiler: "Start the App Here"
@main
struct SwiftWasmIDEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 2. The Embedded HTML/JS Runner
struct EmbeddedResources {
    static let runnerHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>SwiftWasm Runner</title>
        <style> body { background-color: #1a1a1e; color: white; font-family: monospace; } </style>
    </head>
    <body>
        <h1>Wasm Environment Active</h1>
        <script>
            var originalLog = console.log;
            console.log = function(message) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLog) {
                    window.webkit.messageHandlers.consoleLog.postMessage(message.toString());
                }
                originalLog(message);
            }

            function simulateWasmExecution(code) {
                console.log("Initializing Wasm Environment...");
                setTimeout(() => {
                    console.log("Analyzing: " + code);
                    console.log("Compiling to WASM (Simulated)...");
                    
                    setTimeout(() => {
                        console.log("Output:");
                        console.log("Hello from the Embedded Web Engine!");
                        console.log("Program exited with code 0.");
                    }, 800);
                }, 500);
            }
        </script>
    </body>
    </html>
    """
}

// MARK: - 3. The Engine (WasmRunner)
class WasmRunner: NSObject, ObservableObject, WKScriptMessageHandler {
    var webView: WKWebView!
    @Published var logs: String = "Ready to compile...\n"
    @Published var isRunning: Bool = false
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "consoleLog")
        config.userContentController = userContentController
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.loadHTMLString(EmbeddedResources.runnerHTML, baseURL: nil)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "consoleLog", let body = message.body as? String {
            DispatchQueue.main.async {
                self.logs += "> \(body)\n"
            }
        }
    }
    
    func run(code: String) {
        self.isRunning = true
        self.logs = "" 
        
        let sanitizedCode = code.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        let js = "simulateWasmExecution(\"\(sanitizedCode)\")"
        
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                DispatchQueue.main.async { self.logs += "Error: \(error.localizedDescription)\n" }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.isRunning = false
            }
        }
    }
}

// MARK: - 4. The Premium UI (ContentView)
struct ContentView: View {
    @StateObject private var runner = WasmRunner()
    @State private var codeText: String = """
    print("Hello World")
    // This is a premium Swift Editor
    """
    @State private var showConsole: Bool = true
    
    var body: some View {
        NavigationSplitView {
            List {
                Section(header: Text("PROJECT")) {
                    Label("main.swift", systemImage: "swift")
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                    Label("Package.swift", systemImage: "shippingbox")
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Explorer")
            .listStyle(.sidebar)
            .background(Color(red: 0.05, green: 0.05, blue: 0.07))
            .scrollContentBackground(.hidden)
            
        } detail: {
            ZStack(alignment: .bottom) {
                Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    EditorHeaderView(runAction: { runner.run(code: codeText) })
                    
                    TextEditor(text: $codeText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.bottom, showConsole ? 200 : 0)
                
                if showConsole {
                    ConsoleView(output: runner.logs, isRunning: runner.isRunning)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding()
                        .frame(height: 250)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 5. Subcomponents
struct EditorHeaderView: View {
    var runAction: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "chevron.right").foregroundColor(.gray)
            Text("main.swift").font(.caption).fontWeight(.bold).foregroundColor(.gray)
            Spacer()
            Button(action: runAction) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.caption)
                    Text("Run").font(.caption.bold())
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(LinearGradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.05)), alignment: .bottom)
    }
}

struct ConsoleView: View {
    var output: String
    var isRunning: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TERMINAL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                if isRunning { ProgressView().controlSize(.mini).tint(.white) }
            }
            .padding(12).background(Color.black.opacity(0.2))
            Divider().background(Color.white.opacity(0.1))
            ScrollView {
                Text(output).font(.custom("Menlo", size: 12)).foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .background(.ultraThinMaterial).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
}
