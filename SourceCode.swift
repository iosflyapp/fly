import SwiftUI
import WebKit

// MARK: - 1. APP ENTRY POINT
@main
struct SwiftIDEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 2. DATA MODELS
struct CodeFile: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var content: String
    var icon: String
}

enum OutputMode: String, CaseIterable {
    case terminal = "Terminal"
    case preview = "Preview"
}

// MARK: - 3. MAIN VIEW
struct ContentView: View {
    // Default Files
    @State private var files: [CodeFile] = [
        CodeFile(name: "main.swift", content: """
        import SwiftUI
        
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello from iPad!")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Button("Click Me") {
                        print("Button Tapped")
                    }
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
        }
        """, icon: "swift"),
        CodeFile(name: "Readme.md", content: "# Documentation\nUse the Preview tab to see your UI.", icon: "doc.text")
    ]
    
    @State private var selectedFileID: UUID?
    @State private var outputMode: OutputMode = .preview // Default to Preview for UI
    @StateObject private var runner = WasmRunner()
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            List(selection: $selectedFileID) {
                Section(header: Text("PROJECT")) {
                    ForEach($files) { file in
                        NavigationLink(value: file.id) {
                            Label(file.name, systemImage: file.icon)
                        }
                    }
                }
            }
            .navigationTitle("Explorer")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            
        } detail: {
            // EDITOR AREA
            ZStack(alignment: .bottom) {
                Color(red: 0.15, green: 0.15, blue: 0.18).ignoresSafeArea()
                
                if let index = files.firstIndex(where: { $0.id == selectedFileID }) {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text(files[index].name)
                                .font(.caption).bold().foregroundColor(.gray)
                            Spacer()
                            // Toggle between Terminal and Preview
                            Picker("Mode", selection: $outputMode) {
                                ForEach(OutputMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                            
                            Button(action: { runner.run(code: files[index].content) }) {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        
                        // Code Editor
                        TextEditor(text: $files[index].content)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .padding(.bottom, 250) // Space for bottom panel
                    
                    // BOTTOM PANEL (Terminal OR Preview)
                    VStack {
                        if outputMode == .terminal {
                            ConsoleView(output: runner.logs)
                        } else {
                            LivePreviewView(code: files[index].content)
                        }
                    }
                    .frame(height: 250)
                    .background(Color.black)
                    .transition(.move(edge: .bottom))
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .padding()
                    
                } else {
                    Text("Select a file").foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { selectedFileID = files.first?.id }
    }
}

// MARK: - 4. LIVE PREVIEW ENGINE (THE NEW PART)
// This simulates SwiftUI rendering by parsing the text
struct LivePreviewView: View {
    var code: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CANVAS (PREVIEW)").font(.caption).bold().foregroundColor(.gray)
                Spacer()
                Image(systemName: "iphone").foregroundColor(.gray)
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            
            // The Simulator
            ZStack {
                Color.white.ignoresSafeArea() // Canvas background
                
                // We use a simplified parser to render common UI elements
                VStack(spacing: 20) {
                    if code.contains("Text(") {
                        // Parse simple text
                        let extracted = extractString(from: code, keyword: "Text")
                        Text(extracted)
                            .font(.title) // Default styling for demo
                            .foregroundColor(.black)
                    }
                    
                    if code.contains("Button(") {
                        let btnText = extractString(from: code, keyword: "Button")
                        Button(action: {}) {
                            Text(btnText)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    if code.contains("Image(") {
                         Image(systemName: "photo")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray, lineWidth: 1))
    }
    
    // Helper to pull text out of code: Text("Hello") -> Hello
    func extractString(from code: String, keyword: String) -> String {
        let lines = code.components(separatedBy: "\n")
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(keyword) {
                if let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\"") {
                    if start < end {
                        let startIndex = line.index(after: start)
                        return String(line[startIndex..<end])
                    }
                }
            }
        }
        return "Placeholder"
    }
}

// MARK: - 5. TERMINAL & LOGIC RUNNER
struct ConsoleView: View {
    var output: String
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("TERMINAL").font(.caption).bold().foregroundColor(.gray); Spacer() }
                .padding(10).background(Color.white.opacity(0.1))
            ScrollView {
                Text(output)
                    .font(.custom("Menlo", size: 12))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.5), lineWidth: 1))
    }
}

class WasmRunner: ObservableObject {
    @Published var logs: String = "Ready to compile...\n"
    
    func run(code: String) {
        logs = ""
        logs += "Compiling \(code.count) bytes...\n"
        
        // Simulating logic execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.logs += "Build Success!\n"
            if code.contains("print") {
                self.logs += "> Hello from iPad!\n"
            }
            self.logs += "Program exited with code 0."
        }
    }
}
