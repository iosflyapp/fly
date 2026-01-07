import SwiftUI
import Foundation

// MARK: - Main App Entry Point
@main
struct AICodeStudioApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - AI Provider Enum
enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"
    case mistral = "Mistral"
    
    var id: String { rawValue }
    
    var models: [String] {
        switch self {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]
        case .google:
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.5-flash-8b", "gemini-2.0-flash-exp"]
        case .mistral:
            return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest", "open-mixtral-8x22b"]
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        }
    }
    
    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "sparkles"
        case .google: return "globe"
        case .mistral: return "wind"
        }
    }
    
    var color: Color {
        switch self {
        case .openai: return .green
        case .anthropic: return .orange
        case .google: return .blue
        case .mistral: return .purple
        }
    }
}

// MARK: - API Configuration
struct APIConfiguration: Codable, Identifiable, Equatable {
    var id: UUID
    var provider: AIProvider
    var apiKey: String
    var selectedModel: String
    var isActive: Bool
    
    init(id: UUID = UUID(), provider: AIProvider, apiKey: String = "", selectedModel: String? = nil, isActive: Bool = false) {
        self.id = id
        self.provider = provider
        self.apiKey = apiKey
        self.selectedModel = selectedModel ?? provider.models.first ?? ""
        self.isActive = isActive
    }
    
    static func == (lhs: APIConfiguration, rhs: APIConfiguration) -> Bool {
        return lhs.id == rhs.id &&
               lhs.provider == rhs.provider &&
               lhs.apiKey == rhs.apiKey &&
               lhs.selectedModel == rhs.selectedModel &&
               lhs.isActive == rhs.isActive
    }
}

// MARK: - Chat Message
struct ChatMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var content: String
    var isUser: Bool
    var timestamp: Date
    var codeBlocks: [CodeBlock]
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.codeBlocks = ChatMessage.extractCodeBlocks(from: content)
    }
    
    static func extractCodeBlocks(from content: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return blocks
        }
        
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        for match in matches {
            if let languageRange = Range(match.range(at: 1), in: content),
               let codeRange = Range(match.range(at: 2), in: content) {
                let language = String(content[languageRange])
                let code = String(content[codeRange])
                blocks.append(CodeBlock(language: language.isEmpty ? "plaintext" : language, code: code))
            }
        }
        
        return blocks
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Code Block
struct CodeBlock: Codable, Identifiable {
    var id: UUID = UUID()
    var language: String
    var code: String
}

// MARK: - Project File
struct ProjectFile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var content: String
    var language: String
    
    static func == (lhs: ProjectFile, rhs: ProjectFile) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Chat Session
struct ChatSession: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var messages: [ChatMessage]
    var createdAt: Date
    var lastModified: Date
    
    init(id: UUID = UUID(), name: String = "New Chat", messages: [ChatMessage] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
        self.lastModified = createdAt
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var apiConfigurations: [APIConfiguration] = []
    @Published var activeConfiguration: APIConfiguration?
    @Published var messages: [ChatMessage] = []
    @Published var chatSessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var projectFiles: [ProjectFile] = []
    @Published var selectedFile: ProjectFile?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    
    private let configurationsKey = "apiConfigurations"
    private let activeConfigKey = "activeConfiguration"
    private let sessionsKey = "chatSessions"
    private let filesKey = "projectFiles"
    
    init() {
        loadData()
    }
    
    // MARK: - Data Persistence
    func loadData() {
        // Load API configurations
        if let data = UserDefaults.standard.data(forKey: configurationsKey),
           let configs = try? JSONDecoder().decode([APIConfiguration].self, from: data) {
            self.apiConfigurations = configs
        }
        
        // Load active configuration
        if let data = UserDefaults.standard.data(forKey: activeConfigKey),
           let config = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            self.activeConfiguration = config
        }
        
        // Load chat sessions
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) {
            self.chatSessions = sessions
        }
        
        // Load project files
        if let data = UserDefaults.standard.data(forKey: filesKey),
           let files = try? JSONDecoder().decode([ProjectFile].self, from: data) {
            self.projectFiles = files
        }
    }
    
    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(apiConfigurations) {
            UserDefaults.standard.set(data, forKey: configurationsKey)
        }
        if let config = activeConfiguration,
           let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: activeConfigKey)
        }
    }
    
    func saveSessions() {
        if let data = try? JSONEncoder().encode(chatSessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    func saveFiles() {
        if let data = try? JSONEncoder().encode(projectFiles) {
            UserDefaults.standard.set(data, forKey: filesKey)
        }
    }
    
    // MARK: - Configuration Management
    func addConfiguration(_ config: APIConfiguration) {
        var newConfig = config
        newConfig.id = UUID() // Ensure unique ID
        apiConfigurations.append(newConfig)
        saveConfigurations()
    }
    
    func updateConfiguration(_ config: APIConfiguration) {
        if let index = apiConfigurations.firstIndex(where: { $0.id == config.id }) {
            apiConfigurations[index] = config
            
            // Update active configuration if it's the same one
            if activeConfiguration?.id == config.id {
                activeConfiguration = config
            }
            saveConfigurations()
        }
    }
    
    func setActiveConfiguration(_ config: APIConfiguration) {
        // First, deactivate all configurations
        for i in 0..<apiConfigurations.count {
            apiConfigurations[i].isActive = false
        }
        
        // Find and activate the selected configuration
        if let index = apiConfigurations.firstIndex(where: { $0.id == config.id }) {
            apiConfigurations[index].isActive = true
            activeConfiguration = apiConfigurations[index]
        } else {
            // If the config doesn't exist, add it
            var newConfig = config
            newConfig.isActive = true
            apiConfigurations.append(newConfig)
            activeConfiguration = newConfig
        }
        
        saveConfigurations()
    }
    
    func deleteConfiguration(_ config: APIConfiguration) {
        apiConfigurations.removeAll { $0.id == config.id }
        if activeConfiguration?.id == config.id {
            activeConfiguration = nil
        }
        saveConfigurations()
    }
    
    // MARK: - Chat Session Management
    func createNewSession() -> ChatSession {
        let session = ChatSession()
        chatSessions.insert(session, at: 0)
        currentSessionId = session.id
        messages = []
        saveSessions()
        return session
    }
    
    func loadSession(_ session: ChatSession) {
        currentSessionId = session.id
        messages = session.messages
    }
    
    func updateCurrentSession() {
        guard let currentId = currentSessionId,
              let index = chatSessions.firstIndex(where: { $0.id == currentId }) else { return }
        
        chatSessions[index].messages = messages
        chatSessions[index].lastModified = Date()
        
        // Update session name based on first message
        if let firstUserMessage = messages.first(where: { $0.isUser }) {
            let name = String(firstUserMessage.content.prefix(30))
            chatSessions[index].name = name.isEmpty ? "New Chat" : name
        }
        
        saveSessions()
    }
    
    func deleteSession(_ session: ChatSession) {
        chatSessions.removeAll { $0.id == session.id }
        if currentSessionId == session.id {
            currentSessionId = nil
            messages = []
        }
        saveSessions()
    }
    
    // MARK: - Send Message
    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Create user message
        let userMessage = ChatMessage(content: content, isUser: true)
        messages.append(userMessage)
        updateCurrentSession()
        
        // Check for active configuration
        guard let config = activeConfiguration, !config.apiKey.isEmpty else {
            let errorMsg = ChatMessage(content: "Please configure an API key in Settings to start chatting.", isUser: false)
            messages.append(errorMsg)
            updateCurrentSession()
            return
        }
        
        // Make API call
        isLoading = true
        
        Task {
            do {
                let response = try await callAPI(content: content, config: config)
                await MainActor.run {
                    let assistantMessage = ChatMessage(content: response, isUser: false)
                    self.messages.append(assistantMessage)
                    self.updateCurrentSession()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    let errorMsg = ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)
                    self.messages.append(errorMsg)
                    self.updateCurrentSession()
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    
    // MARK: - API Calls
    func callAPI(content: String, config: APIConfiguration) async throws -> String {
        switch config.provider {
        case .openai:
            return try await callOpenAI(content: content, config: config)
        case .anthropic:
            return try await callAnthropic(content: content, config: config)
        case .google:
            return try await callGoogle(content: content, config: config)
        case .mistral:
            return try await callMistral(content: content, config: config)
        }
    }
    
    private func callOpenAI(content: String, config: APIConfiguration) async throws -> String {
        guard let url = URL(string: config.provider.baseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": config.selectedModel,
            "messages": [
                ["role": "user", "content": content]
            ],
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let responseContent = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return responseContent
    }
    
    private func callAnthropic(content: String, config: APIConfiguration) async throws -> String {
        guard let url = URL(string: config.provider.baseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("messages-2024-09-04", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": config.selectedModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Anthropic", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let responseText = firstContent["text"] as? String else {
            throw NSError(domain: "Anthropic", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return responseText
    }
    
    private func callGoogle(content: String, config: APIConfiguration) async throws -> String {
        let urlString = "\(config.provider.baseURL)/\(config.selectedModel):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": content]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Google", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let contentDict = firstCandidate["content"] as? [String: Any],
              let parts = contentDict["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            throw NSError(domain: "Google", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return responseText
    }
    
    private func callMistral(content: String, config: APIConfiguration) async throws -> String {
        guard let url = URL(string: config.provider.baseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": config.selectedModel,
            "messages": [
                ["role": "user", "content": content]
            ],
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Mistral", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let responseContent = message["content"] as? String else {
            throw NSError(domain: "Mistral", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return responseContent
    }
    
    // MARK: - File Management
    func addFile(_ file: ProjectFile) {
        projectFiles.append(file)
        saveFiles()
    }
    
    func updateFile(_ file: ProjectFile) {
        if let index = projectFiles.firstIndex(where: { $0.id == file.id }) {
            projectFiles[index] = file
            if selectedFile?.id == file.id {
                selectedFile = file
            }
            saveFiles()
        }
    }
    
    func deleteFile(_ file: ProjectFile) {
        projectFiles.removeAll { $0.id == file.id }
        if selectedFile?.id == file.id {
            selectedFile = nil
        }
        saveFiles()
    }
}

// MARK: - Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)
            
            ProjectView()
                .tabItem {
                    Label("Projects", systemImage: "folder.fill")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .tint(.blue)
        .alert("Error", isPresented: $appState.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred")
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSessionList = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(appState.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                            
                            if appState.isLoading {
                                LoadingIndicatorView()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: appState.messages.count) { _, _ in
                        if let lastMessage = appState.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input area
                ChatInputArea()
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSessionList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        _ = appState.createNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showSessionList) {
                SessionListView()
            }
            .onAppear {
                if appState.currentSessionId == nil && appState.chatSessions.isEmpty {
                    _ = appState.createNewSession()
                }
            }
        }
    }
}

// MARK: - Chat Input Area (FIXED)
struct ChatInputArea: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Text input - FIXED: Removed problematic modifiers, added proper iPad support
            TextField("Type your message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .textInputAutocapitalization(.sentences)  // FIXED: Proper autocapitalization
                .autocorrectionDisabled(false)  // FIXED: Enable autocorrection for chat
                .submitLabel(.return)  // FIXED: Use return instead of send for multiline
            
            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isLoading
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        inputText = ""
        isInputFocused = false
        appState.sendMessage(text)
    }
}

// MARK: - Chat Bubble View
struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                // Main message content
                if !message.codeBlocks.isEmpty {
                    MessageWithCodeView(message: message)
                } else {
                    Text(message.content)
                        .padding(12)
                        .background(message.isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Message With Code View
struct MessageWithCodeView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text content before code blocks
            let textContent = extractTextContent(from: message.content)
            if !textContent.isEmpty {
                Text(textContent)
                    .padding(12)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
            }
            
            // Code blocks
            ForEach(message.codeBlocks) { block in
                CodeBlockView(block: block)
            }
        }
    }
    
    private func extractTextContent(from content: String) -> String {
        var text = content
        let pattern = "```\\w*\\n[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Code Block View
struct CodeBlockView: View {
    let block: CodeBlock
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(block.language)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = block.code
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray4))
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.code)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
            }
            .background(Color(.systemGray6))
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Loading Indicator View
struct LoadingIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(12)
            .background(Color(.systemGray5))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Session List View
struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.chatSessions) { session in
                    Button {
                        appState.loadSession(session)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(session.lastModified, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        appState.deleteSession(appState.chatSessions[index])
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Project View
struct ProjectView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewFileSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.projectFiles) { file in
                    NavigationLink {
                        FileEditorView(file: file)
                    } label: {
                        HStack {
                            Image(systemName: iconForLanguage(file.language))
                                .foregroundColor(colorForLanguage(file.language))
                            
                            VStack(alignment: .leading) {
                                Text(file.name)
                                    .font(.headline)
                                Text(file.language)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        appState.deleteFile(appState.projectFiles[index])
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewFileSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewFileSheet) {
                NewFileView()
            }
        }
    }
    
    private func iconForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python": return "chevron.left.forwardslash.chevron.right"
        case "javascript", "js": return "curlybraces"
        case "html": return "globe"
        case "css": return "paintbrush"
        default: return "doc.text"
        }
    }
    
    private func colorForLanguage(_ language: String) -> Color {
        switch language.lowercased() {
        case "swift": return .orange
        case "python": return .blue
        case "javascript", "js": return .yellow
        case "html": return .red
        case "css": return .purple
        default: return .gray
        }
    }
}

// MARK: - New File View
struct NewFileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var fileName: String = ""
    @State private var selectedLanguage: String = "Swift"
    
    let languages = ["Swift", "Python", "JavaScript", "HTML", "CSS", "JSON", "Markdown", "Plain Text"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("File Details") {
                    TextField("File name", text: $fileName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                }
            }
            .navigationTitle("New File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFile()
                    }
                    .disabled(fileName.isEmpty)
                }
            }
        }
    }
    
    private func createFile() {
        let file = ProjectFile(name: fileName, content: "", language: selectedLanguage)
        appState.addFile(file)
        dismiss()
    }
}

// MARK: - File Editor View
struct FileEditorView: View {
    @EnvironmentObject var appState: AppState
    @State var file: ProjectFile
    @State private var editedContent: String = ""
    
    var body: some View {
        TextEditor(text: $editedContent)
            .font(.system(.body, design: .monospaced))
            .padding()
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedFile = file
                        updatedFile.content = editedContent
                        appState.updateFile(updatedFile)
                        file = updatedFile
                    }
                }
            }
            .onAppear {
                editedContent = file.content
            }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddConfiguration = false
    
    var body: some View {
        NavigationStack {
            List {
                // Active Configuration Section
                Section {
                    if let active = appState.activeConfiguration {
                        HStack {
                            Image(systemName: active.provider.icon)
                                .foregroundColor(active.provider.color)
                            
                            VStack(alignment: .leading) {
                                Text(active.provider.rawValue)
                                    .font(.headline)
                                Text(active.selectedModel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("No API configured")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Active Configuration")
                }
                
                // All Configurations Section
                Section {
                    ForEach(appState.apiConfigurations) { config in
                        NavigationLink {
                            APIConfigurationView(configuration: config)
                        } label: {
                            HStack {
                                Image(systemName: config.provider.icon)
                                    .foregroundColor(config.provider.color)
                                
                                VStack(alignment: .leading) {
                                    Text(config.provider.rawValue)
                                        .font(.headline)
                                    Text(config.selectedModel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if config.isActive {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            appState.deleteConfiguration(appState.apiConfigurations[index])
                        }
                    }
                    
                    Button {
                        showAddConfiguration = true
                    } label: {
                        Label("Add Configuration", systemImage: "plus.circle")
                    }
                } header: {
                    Text("API Configurations")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddConfiguration) {
                AddConfigurationView()
            }
        }
    }
}

// MARK: - Add Configuration View
struct AddConfigurationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedProvider: AIProvider = .openai
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        let config = APIConfiguration(provider: provider)
                        appState.addConfiguration(config)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: provider.icon)
                                .foregroundColor(provider.color)
                                .frame(width: 30)
                            
                            Text(provider.rawValue)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - API Configuration View (FIXED)
struct APIConfigurationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State var configuration: APIConfiguration
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var showAPIKey = false
    
    var body: some View {
        Form {
            // Provider Info Section
            Section {
                HStack {
                    Image(systemName: configuration.provider.icon)
                        .foregroundColor(configuration.provider.color)
                        .font(.title2)
                    
                    Text(configuration.provider.rawValue)
                        .font(.headline)
                }
            } header: {
                Text("Provider")
            }
            
            // API Key Section - FIXED
            Section {
                HStack {
                    if showAPIKey {
                        // FIXED: Added proper modifiers for API key input
                        TextField("Enter API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)  // FIXED: Prevent autocapitalization
                            .autocorrectionDisabled(true)  // FIXED: Disable autocorrection
                            .font(.system(.body, design: .monospaced))
                    } else {
                        // FIXED: Added proper modifiers for secure field
                        SecureField("Enter API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)  // FIXED: Prevent autocapitalization
                            .autocorrectionDisabled(true)  // FIXED: Disable autocorrection
                    }
                    
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored locally on your device.")
            }
            
            // Model Selection Section
            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(configuration.provider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Model")
            }
            
            // Activate Section
            Section {
                Button {
                    saveAndActivate()
                } label: {
                    HStack {
                        Spacer()
                        Text(configuration.isActive ? "Active" : "Set as Active")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty)
                .foregroundColor(apiKey.isEmpty ? .gray : .blue)
            }
            
            // Save Section
            Section {
                Button {
                    saveConfiguration()
                } label: {
                    HStack {
                        Spacer()
                        Text("Save Changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty)
                .foregroundColor(apiKey.isEmpty ? .gray : .green)
            }
        }
        .navigationTitle("Configure")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = configuration.apiKey
            selectedModel = configuration.selectedModel.isEmpty ? 
                (configuration.provider.models.first ?? "") : configuration.selectedModel
        }
    }
    
    private func saveConfiguration() {
        configuration.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)  // FIXED: Trim whitespace
        configuration.selectedModel = selectedModel
        appState.updateConfiguration(configuration)
    }
    
    private func saveAndActivate() {
        configuration.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)  // FIXED: Trim whitespace
        configuration.selectedModel = selectedModel
        appState.updateConfiguration(configuration)
        appState.setActiveConfiguration(configuration)
        dismiss()
    }
}
