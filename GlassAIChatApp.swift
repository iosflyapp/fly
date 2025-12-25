import SwiftUI
import Combine
import UniformTypeIdentifiers
import PhotosUI
import Photos

// MARK: - App Entry Point
@main
struct GlassAIChatApp: App {
    init() {
        UITextView.appearance().backgroundColor = .clear
        // Ensure text fields work with external keyboards
        UITextField.appearance().keyboardAppearance = .dark
        UITextView.appearance().keyboardAppearance = .dark
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Helper for File Saving
struct TextFile: FileDocument {
    var text: String
    
    init(text: String = "") {
        self.text = text
    }
    
    static var readableContentTypes: [UTType] {
        [
            .plainText,
            .html,
            UTType("public.swift-source") ?? .plainText,
            UTType("public.javascript") ?? .plainText,
            UTType("public.python-script") ?? .plainText,
            UTType("public.source-code") ?? .plainText
        ]
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Models

struct ChatSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var messages: [ChatMessage]
    
    var title: String {
        if let first = messages.first {
            let text = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count > 30 ? String(text.prefix(30)) + "..." : text
        }
        return "New Chat"
    }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    var attachments: [Attachment]
    
    init(content: String, isUser: Bool, attachments: [Attachment] = []) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.attachments = attachments
    }
}

struct Attachment: Identifiable, Equatable, Codable {
    var id = UUID()
    let name: String
    let type: AttachmentType
    let data: Data?
    
    enum AttachmentType: String, CaseIterable, Codable {
        case image = "photo"
        case document = "doc.text"
        case pdf = "doc.richtext"
        case code = "chevron.left.forwardslash.chevron.right"
        case audio = "waveform"
        case video = "video"
        case other = "paperclip"
        
        static func from(filename: String) -> AttachmentType {
            let lower = filename.lowercased()
            if lower.hasSuffix(".jpg") || lower.hasSuffix(".png") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".heic") { return .image }
            if lower.hasSuffix(".pdf") { return .pdf }
            if lower.hasSuffix(".swift") || lower.hasSuffix(".js") || lower.hasSuffix(".py") || lower.hasSuffix(".html") || lower.hasSuffix(".txt") { return .code }
            if lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".wav") { return .audio }
            if lower.hasSuffix(".mov") || lower.hasSuffix(".mp4") { return .video }
            return .document
        }
    }
}

struct AIProvider: Identifiable, Equatable, Hashable, Codable {
    var id = UUID()
    var name: String
    var apiKey: String
    var baseURL: String
    var model: String
    var isActive: Bool
    var knownModels: [String] = []
    
    static let presets: [AIProvider] = [
        AIProvider(name: "OpenAI", apiKey: "", baseURL: "https://api.openai.com/v1", model: "", isActive: false),
        AIProvider(name: "Anthropic", apiKey: "", baseURL: "https://api.anthropic.com/v1", model: "", isActive: false),
        AIProvider(name: "Google AI", apiKey: "", baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "", isActive: false),
        AIProvider(name: "Mistral", apiKey: "", baseURL: "https://api.mistral.ai/v1", model: "", isActive: false),
        AIProvider(name: "Groq", apiKey: "", baseURL: "https://api.groq.com/openai/v1", model: "", isActive: false),
        AIProvider(name: "Together AI", apiKey: "", baseURL: "https://api.together.xyz/v1", model: "", isActive: false),
        AIProvider(name: "Custom", apiKey: "", baseURL: "", model: "", isActive: false)
    ]
}

// MARK: - Persistence Manager
class PersistenceManager {
    static let shared = PersistenceManager()
    private let sessionsURL: URL
    private let providersURL: URL
    
    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionsURL = documents.appendingPathComponent("chat_sessions.json")
        providersURL = documents.appendingPathComponent("providers_config.json")
    }
    
    func saveSessions(_ sessions: [ChatSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: sessionsURL)
        } catch { print("Failed to save sessions: \(error)") }
    }
    
    func loadSessions() -> [ChatSession] {
        guard let data = try? Data(contentsOf: sessionsURL),
              let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else { return [] }
        return sessions
    }
    
    func saveProviders(_ providers: [AIProvider]) {
        do {
            let data = try JSONEncoder().encode(providers)
            try data.write(to: providersURL)
        } catch { print("Failed to save providers: \(error)") }
    }
    
    func loadProviders() -> [AIProvider] {
        guard let data = try? Data(contentsOf: providersURL),
              let providers = try? JSONDecoder().decode([AIProvider].self, from: data) else { return AIProvider.presets }
        return providers
    }
}

// MARK: - View Model

@MainActor
class ChatViewModel: ObservableObject {
    enum TabSelection { case chat, code }
    
    @Published var selectedTab: TabSelection = .chat
    
    // History
    @Published var sessions: [ChatSession] = [] {
        didSet { PersistenceManager.shared.saveSessions(sessions) }
    }
    @Published var currentSessionID: UUID = UUID()
    @Published var messages: [ChatMessage] = [] {
        didSet { updateCurrentSession() }
    }
    
    @Published var providers: [AIProvider] = [] {
        didSet { PersistenceManager.shared.saveProviders(providers) }
    }
    
    @Published var extractedCode: String = ""
    @Published var inputText: String = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var isLoading: Bool = false
    
    // UI States
    @Published var showSettings: Bool = false
    @Published var showHistory: Bool = false
    @Published var errorMessage: String?
    @Published var showFileImporter: Bool = false
    @Published var showPhotoPicker: Bool = false
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    
    // Code Diff Stats (Added, Removed)
    @Published var lastChangeStats: (added: Int, removed: Int) = (0, 0)
    
    init() {
        self.sessions = PersistenceManager.shared.loadSessions()
        self.providers = PersistenceManager.shared.loadProviders()
        if self.providers.isEmpty { self.providers = AIProvider.presets }
        startNewChat()
    }
    
    var activeProvider: AIProvider? { providers.first { $0.isActive } }
    
    // MARK: - Session Management
    
    func updateCurrentSession() {
        if let index = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            sessions[index].messages = messages
            if index != 0 {
                let session = sessions.remove(at: index)
                sessions.insert(session, at: 0)
            }
        } else if !messages.isEmpty {
            let newSession = ChatSession(id: currentSessionID, date: Date(), messages: messages)
            sessions.insert(newSession, at: 0)
        }
    }
    
    func startNewChat() {
        if !messages.isEmpty { updateCurrentSession() }
        currentSessionID = UUID()
        messages = []
        extractedCode = ""
        lastChangeStats = (0, 0)
        inputText = ""
        pendingAttachments = []
        selectedTab = .chat
    }
    
    func loadSession(_ session: ChatSession) {
        currentSessionID = session.id
        messages = session.messages
        extractedCode = ""
        lastChangeStats = (0, 0)
        inputText = ""
        if let lastMsgWithCode = messages.last(where: { !$0.isUser && $0.content.contains("```") }) {
            extractCode(from: lastMsgWithCode.content)
        }
        selectedTab = .chat
        showHistory = false
    }
    
    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSessionID == session.id { startNewChat() }
    }
    
    func clearChatHistory() {
        sessions = []
        startNewChat()
        PersistenceManager.shared.saveSessions([])
    }
    
    // MARK: - Messaging
    
    func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty else { return }
        guard let provider = activeProvider else { errorMessage = "No active provider selected."; return }
        guard !provider.apiKey.isEmpty, !provider.model.isEmpty else { errorMessage = "Provider configuration incomplete."; return }
        
        let attachmentsToSend = pendingAttachments
        let textToSend = inputText
        
        let userMessage = ChatMessage(content: textToSend, isUser: true, attachments: attachmentsToSend)
        messages.append(userMessage)
        
        inputText = ""
        pendingAttachments = []
        isLoading = true
        errorMessage = nil
        selectedTab = .chat
        
        let history = messages.dropLast()
        
        do {
            let response = try await callAPI(provider: provider, message: textToSend, attachments: attachmentsToSend, history: Array(history))
            messages.append(ChatMessage(content: response, isUser: false))
            
            if extractCode(from: response) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                withAnimation(.easeInOut(duration: 0.35)) {
                    selectedTab = .code
                }
            }
        } catch {
            if let nsError = error as NSError?, nsError.code == 429 {
                messages.append(ChatMessage(content: "⚠️ Rate Limit Exceeded (HTTP 429). Please wait a moment before sending another message.", isUser: false))
            } else {
                messages.append(ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false))
            }
        }
        
        isLoading = false
    }
    
    @discardableResult
    func extractCode(from text: String) -> Bool {
        let pattern = "```[\\s\\S]*?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        if results.isEmpty { return false }
        
        let oldLines = extractedCode.components(separatedBy: .newlines)
        
        var newCodeBlock = ""
        for result in results {
            let codeBlock = nsString.substring(with: result.range)
            var clean = codeBlock.replacingOccurrences(of: "```", with: "")
            if let firstLineBreak = clean.firstIndex(of: "\n") {
                let firstLine = clean[..<firstLineBreak]
                if firstLine.count < 20 && !firstLine.contains(" ") {
                    clean = String(clean[firstLineBreak...])
                }
            }
            newCodeBlock += clean.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }
        
        let cleanedNewCode = newCodeBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !cleanedNewCode.isEmpty && cleanedNewCode != extractedCode.trimmingCharacters(in: .whitespacesAndNewlines) {
            self.extractedCode = cleanedNewCode
            let newLines = self.extractedCode.components(separatedBy: .newlines)
            let difference = newLines.difference(from: oldLines)
            let added = difference.insertions.count
            let removed = difference.removals.count
            self.lastChangeStats = (added, removed)
        }
        return true
    }
    
    // MARK: - File & Photo Handling
    func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { errorMessage = "Permission denied."; return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                let type = Attachment.AttachmentType.from(filename: name)
                pendingAttachments.append(Attachment(name: name, type: type, data: data))
            } catch { errorMessage = "Failed to read file: \(error.localizedDescription)" }
        case .failure(let error): errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }
    
    func requestPhotoPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    if newStatus == .authorized || newStatus == .limited {
                        self.showPhotoPicker = true
                    } else {
                        self.errorMessage = "Permission denied. Please enable in Settings."
                    }
                }
            }
        case .authorized, .limited:
            showPhotoPicker = true
        case .denied, .restricted:
            errorMessage = "Photo access denied. Enable in Settings."
        @unknown default:
            break
        }
    }
    
    func loadPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        let name = "Photo \(Date().formatted(date: .numeric, time: .shortened)).jpg"
                        pendingAttachments.append(Attachment(name: name, type: .image, data: data))
                        self.selectedPhotoItem = nil
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load photo."
                    self.selectedPhotoItem = nil
                }
            }
        }
    }
    
    // MARK: - API Logic
    private func callAPI(provider: AIProvider, message: String, attachments: [Attachment], history: [ChatMessage]) async throws -> String {
        var endpoint = provider.baseURL
        if provider.name == "Google AI" {
            endpoint = "\(provider.baseURL)/models/\(provider.model):generateContent?key=\(provider.apiKey)"
        } else if provider.name == "Anthropic" {
            endpoint = "\(provider.baseURL)/messages"
        } else {
            endpoint = "\(provider.baseURL)/chat/completions"
        }
        
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let codeContext = extractedCode.isEmpty ? "" : "\n\n[CONTEXT] Current code in editor:\n```\n\(extractedCode)\n```\nIf the user asks to modify the code, return the FULL updated code block."
        let systemPrompt = "You are a helpful assistant. Use Markdown for formatting. \(codeContext)"
        
        var body: [String: Any] = [:]
        
        if provider.name == "Anthropic" {
            request.setValue(provider.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var apiMessages: [[String: Any]] = []
            for msg in history { apiMessages.append(["role": msg.isUser ? "user" : "assistant", "content": msg.content]) }
            var currentContent: [[String: Any]] = []
            for att in attachments where att.type == .image {
                if let data = att.data { currentContent.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]) }
            }
            var finalText = message
            for att in attachments where att.type == .code || att.type == .document {
                if let data = att.data, let str = String(data: data, encoding: .utf8) { finalText += "\n\n[File: \(att.name)]\n\(str)" }
            }
            currentContent.append(["type": "text", "text": finalText])
            apiMessages.append(["role": "user", "content": currentContent])
            body = ["model": provider.model, "max_tokens": 4096, "system": systemPrompt, "messages": apiMessages]
        } else if provider.name == "Google AI" {
            var contents: [[String: Any]] = []
            for msg in history { contents.append(["role": msg.isUser ? "user" : "model", "parts": [["text": msg.content]]]) }
            var parts: [[String: Any]] = []
            var finalText = "\(codeContext)\n\n\(message)"
            for att in attachments {
                if let data = att.data {
                    if att.type == .image { parts.append(["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]) }
                    else if let str = String(data: data, encoding: .utf8) { finalText += "\n\n[File: \(att.name)]\n\(str)" }
                }
            }
            parts.append(["text": finalText])
            contents.append(["role": "user", "parts": parts])
            body = ["contents": contents]
        } else {
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
            var apiMessages: [[String: Any]] = []
            apiMessages.append(["role": "system", "content": systemPrompt])
            for msg in history { apiMessages.append(["role": msg.isUser ? "user" : "assistant", "content": msg.content]) }
            var contentList: [[String: Any]] = []
            var finalText = message
            for att in attachments {
                if let data = att.data {
                    if att.type == .image { contentList.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]) }
                    else if let str = String(data: data, encoding: .utf8) { finalText += "\n\n[File: \(att.name)]\n\(str)" }
                }
            }
            contentList.append(["type": "text", "text": finalText])
            apiMessages.append(["role": "user", "content": contentList])
            body = ["model": provider.model, "messages": apiMessages, "max_tokens": 4096]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        if httpResponse.statusCode != 200 { throw NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]) }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch provider.name {
        case "Anthropic":
            if let c = json?["content"] as? [[String: Any]], let t = c.first?["text"] as? String { return t }
        case "Google AI":
            if let c = json?["candidates"] as? [[String: Any]], let p = c.first?["content"] as? [String: Any],
               let parts = p["parts"] as? [[String: Any]], let t = parts.first?["text"] as? String { return t }
        default:
            if let c = json?["choices"] as? [[String: Any]], let m = c.first?["message"] as? [String: Any], let t = m["content"] as? String { return t }
        }
        return "No content returned."
    }
    
    func fetchAvailableModels(for provider: AIProvider) async throws -> [String] {
        guard !provider.apiKey.isEmpty else { throw NSError(domain: "App", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key required"]) }
        let urlString = provider.baseURL.contains("anthropic") ? "\(provider.baseURL)/models" : (provider.name == "Google AI" ? "\(provider.baseURL)/models?key=\(provider.apiKey)" : "\(provider.baseURL)/models")
        var headers: [String: String] = [:]
        if provider.name == "Anthropic" { headers["x-api-key"] = provider.apiKey; headers["anthropic-version"] = "2023-06-01" }
        else if provider.name != "Google AI" { headers["Authorization"] = "Bearer \(provider.apiKey)" }
        
        var request = URLRequest(url: URL(string: urlString)!); request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if provider.name == "Google AI" {
            return (json?["models"] as? [[String: Any]])?.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }.sorted() ?? []
        }
        return (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String }.sorted() ?? []
    }
    
    func removeAttachment(_ attachment: Attachment) { pendingAttachments.removeAll { $0.id == attachment.id } }
    func setActiveProvider(_ provider: AIProvider) { for i in providers.indices { providers[i].isActive = providers[i].id == provider.id } }
    func updateProvider(_ provider: AIProvider) { if let index = providers.firstIndex(where: { $0.id == provider.id }) { providers[index] = provider } }
}

// MARK: - UI Components

struct PremiumGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var intense: Bool
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                if intense { Rectangle().fill(.regularMaterial).colorScheme(.dark) }
                else { Rectangle().fill(.ultraThinMaterial).colorScheme(.dark) }
                Rectangle().fill(Color(white: 0.1).opacity(0.4))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            // Clip the background itself so the glass shape is correct
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Apply shadow to the clipped background
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        )
    }
}
extension View { func premiumGlass(cornerRadius: CGFloat = 24, intense: Bool = false) -> some View { modifier(PremiumGlassModifier(cornerRadius: cornerRadius, intense: intense)) } }

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Namespace private var tabNamespace
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        ZStack {
            PremiumBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderView(viewModel: viewModel).zIndex(3)
                
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        MessagesScrollView(viewModel: viewModel).frame(width: geo.size.width)
                        CodeView(viewModel: viewModel).frame(width: geo.size.width)
                    }
                    .frame(width: geo.size.width * 2, alignment: .leading)
                    .offset(x: viewModel.selectedTab == .chat ? 0 : -geo.size.width)
                    .compositingGroup()
                    .animation(.easeInOut(duration: 0.35), value: viewModel.selectedTab)
                }.clipped().zIndex(1)
                
                InputAreaView(viewModel: viewModel).zIndex(2)
                
                // --- TAB SWITCHER ---
                HStack(spacing: 0) {
                    // Chat Tab
                    Button {
                        viewModel.selectedTab = .chat
                    } label: {
                        ZStack {
                            if viewModel.selectedTab == .chat {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "TabCursor", in: tabNamespace)
                            }
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(viewModel.selectedTab == .chat ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).frame(height: 42).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    
                    // Code Tab
                    Button {
                        viewModel.selectedTab = .code
                    } label: {
                        ZStack {
                            if viewModel.selectedTab == .code {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "TabCursor", in: tabNamespace)
                            }
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(viewModel.selectedTab == .code ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).frame(height: 42).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(4)
                .background {
                    ZStack {
                        Capsule().fill(.regularMaterial).colorScheme(.dark)
                        Capsule().fill(Color(white: 0.1).opacity(0.4))
                        Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                }
                .frame(maxWidth: isPad ? 400 : .infinity)
                .padding(.vertical, 8)
                .zIndex(2)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.selectedTab)
            }
            .padding(.top, isPad ? 10 : 0)
            .padding(.bottom, isPad ? 20 : 0)
            .padding(.horizontal, isPad ? 16 : 12)
            .frame(maxWidth: isPad ? 800 : .infinity)
        }
        .sheet(isPresented: $viewModel.showSettings) { SettingsSheet(viewModel: viewModel).preferredColorScheme(.dark) }
        .sheet(isPresented: $viewModel.showHistory) { HistorySheet(viewModel: viewModel).preferredColorScheme(.dark) }
        
        .fileImporter(isPresented: $viewModel.showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { viewModel.handleFileSelection($0) }
        .photosPicker(isPresented: $viewModel.showPhotoPicker, selection: $viewModel.selectedPhotoItem, matching: .images)
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in viewModel.loadPhoto(from: newItem) }
        
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(error).font(.caption.bold()).foregroundStyle(.white).padding(12).background(Color.red.opacity(0.8)).clipShape(Capsule())
                    .padding(.top, 60).transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { viewModel.errorMessage = nil } } }
            }
        }
    }
}

// MARK: - UPDATED CODE VIEW WITH CORRECT CLIPPING ORDER

struct CodeView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showFileExporter = false
    @State private var fileToExport: TextFile? = nil
    @State private var detectedExtension = "txt"
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    // Smart Language Detection
    func detectLanguage(for code: String) -> String {
        let c = code.lowercased()
        if c.contains("import swiftui") || c.contains("var body: some view") { return "swift" }
        if c.contains("<!doctype html>") || c.contains("<html>") { return "html" }
        if c.contains("def ") && c.contains(":") { return "py" }
        if c.contains("import react") || c.contains("classname=") { return "jsx" }
        if c.contains("function") || c.contains("const ") || c.contains("console.log") { return "js" }
        if c.contains("#include") { return "cpp" }
        if c.contains("body {") || c.contains("margin:") { return "css" }
        return "txt"
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Code Content
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 12) {
                    // Line Numbers
                    if !viewModel.extractedCode.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(0..<viewModel.extractedCode.components(separatedBy: "\n").count, id: \.self) { i in
                                Text("\(i + 1)").font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(height: 18)
                            }
                        }
                    }
                    
                    // Code Text
                    Text(viewModel.extractedCode.isEmpty ? "// No code generated yet.\n// Ask the AI to write some code." : viewModel.extractedCode)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .lineSpacing(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(16)
                .padding(.top, 20)
                .padding(.bottom, 60)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            // FIXED: Clip the content/background FIRST so it's rounded
            .clipShape(RoundedRectangle(cornerRadius: isPad ? 32 : 20, style: .continuous))
            // FIXED: Then add the glass modifier (which has shadow/border) on the outside
            .modifier(UniversalGlass(isPad: isPad))
            
            // Buttons Container (Top Right)
            if !viewModel.extractedCode.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = viewModel.extractedCode
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 38)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                    
                    Button {
                        detectedExtension = detectLanguage(for: viewModel.extractedCode)
                        fileToExport = TextFile(text: viewModel.extractedCode)
                        showFileExporter = true
                    } label: {
                        Image(systemName: "arrow.down").font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(16)
                .fileExporter(isPresented: $showFileExporter, document: fileToExport, contentType: .plainText, defaultFilename: "CodeSnippet.\(detectedExtension)") { result in
                    if case .failure(let error) = result { print(error.localizedDescription) }
                }
            }
            
            // DIFF STATS BUBBLE (Bottom Right)
            if viewModel.lastChangeStats.added > 0 || viewModel.lastChangeStats.removed > 0 {
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Text("+").font(.headline); Text("\(viewModel.lastChangeStats.added)") }.foregroundStyle(.green)
                    Divider().frame(height: 16).background(.white.opacity(0.3))
                    HStack(spacing: 4) { Text("-").font(.headline); Text("\(viewModel.lastChangeStats.removed)") }.foregroundStyle(.red)
                }
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - UPDATED HEADER VIEW
struct HeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        HStack {
            Menu {
                Button { viewModel.startNewChat() } label: { Label("New Chat", systemImage: "plus") }
                Button { viewModel.showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
            } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44).background(.white.opacity(0.1)).clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text("AI Model").font(.headline).foregroundStyle(.white)
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.activeProvider != nil ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(viewModel.activeProvider?.name ?? "Offline").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Button { viewModel.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44).background(.white.opacity(0.1)).clipShape(Circle())
            }
        }
        .padding(16).padding(.bottom, 0)
    }
}

struct HistorySheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.sessions.isEmpty { Text("No chat history").foregroundStyle(.gray) }
                ForEach(viewModel.sessions) { session in
                    Button { viewModel.loadSession(session); dismiss() } label: {
                        VStack(alignment: .leading) {
                            Text(session.title).font(.body.bold()).foregroundStyle(.white)
                            Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.gray)
                        }
                    }.listRowBackground(Color(white: 0.1))
                }.onDelete { indexSet in indexSet.forEach { viewModel.deleteSession(viewModel.sessions[$0]) } }
            }
            .scrollContentBackground(.hidden).background(Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { showClearConfirmation = true } label: { Image(systemName: "trash").foregroundStyle(.red) }.disabled(viewModel.sessions.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Delete All History", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { viewModel.clearChatHistory() }
            } message: { Text("This will permanently remove all saved chats.") }
        }
    }
}

struct MessagesScrollView: View {
    @ObservedObject var viewModel: ChatViewModel
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    Color.clear.frame(height: 10)
                    if viewModel.messages.isEmpty { EmptyStateView() }
                    ForEach(viewModel.messages) { message in MessageBubble(message: message).id(message.id) }
                    if viewModel.isLoading { HStack { TypingIndicator(); Spacer() }.padding(.leading, 12) }
                    Color.clear.frame(height: 10)
                }.padding(.horizontal, isPad ? 4 : 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in if let last = viewModel.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
            // FIXED: Clip the content FIRST
            .clipShape(RoundedRectangle(cornerRadius: isPad ? 32 : 20, style: .continuous))
            // FIXED: Then apply glass modifier
            .modifier(UniversalGlass(isPad: isPad))
        }
    }
}

struct UniversalGlass: ViewModifier { 
    let isPad: Bool
    func body(content: Content) -> some View { 
        content.premiumGlass(cornerRadius: isPad ? 32 : 20)
    } 
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile").font(.system(size: 60)).foregroundStyle(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            Text("How can I help you today?").font(.title2.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            Text("Your chats are saved automatically.").font(.subheadline).foregroundStyle(.white.opacity(0.4))
        }.padding(.top, 60).padding(.bottom, 40)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var hasCode: Bool { return message.content.contains("```") }
    func cleanText(_ text: String) -> String {
        let pattern = "```[\\s\\S]*?```"
        let noCode = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return noCode.replacingOccurrences(of: "### ", with: "").replacingOccurrences(of: "###", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var body: some View {
        let displayContent = cleanText(message.content)
        if !displayContent.isEmpty || message.isUser || hasCode {
            HStack(alignment: .bottom, spacing: 12) {
                if message.isUser { Spacer(minLength: 40) } else { Circle().fill(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)).frame(width: 32, height: 32).overlay(Text("AI").font(.caption2.bold()).foregroundStyle(.white)) }
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    if !message.attachments.isEmpty {
                        HStack { ForEach(message.attachments) { att in HStack(spacing: 6) { Image(systemName: att.type.rawValue); Text(att.name).lineLimit(1) }.font(.caption2).padding(6).background(.white.opacity(0.2)).clipShape(Capsule()) } }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if !displayContent.isEmpty { Text(LocalizedStringKey(displayContent)).font(.system(.body, design: .rounded)).foregroundStyle(.white).lineSpacing(5).textSelection(.enabled) }
                        if hasCode && !message.isUser { Button { } label: { HStack(spacing: 6) { Image(systemName: "chevron.left.forwardslash.chevron.right"); Text("Code moved to Code Tab") }.font(.caption.bold()).foregroundStyle(.white.opacity(0.8)).padding(8).background(Color.white.opacity(0.1)).clipShape(Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)) } }
                    }
                    .padding(14).background(message.isUser ? LinearGradient(colors: [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.1, green: 0.3, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color(white: 0.2), Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 20))
                }
                if !message.isUser { Spacer(minLength: 40) }
            }
        }
    }
}

// MARK: - FIXED INPUT AREA VIEW (External Keyboard Support)
struct InputAreaView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(viewModel.pendingAttachments) { att in
                            HStack { Image(systemName: att.type.rawValue); Text(att.name); Button { viewModel.removeAttachment(att) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.7)) } }
                                .font(.caption).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { viewModel.showFileImporter = true } label: { Label("Files", systemImage: "doc") }
                    Button { viewModel.requestPhotoPermission() } label: { Label("Photo Library", systemImage: "photo") }
                } label: { Image(systemName: "paperclip").font(.title3).foregroundStyle(.white.opacity(0.7)).frame(width: 40, height: 40).background(.white.opacity(0.1)).clipShape(Circle()) }
                
                // FIXED: Custom UITextView wrapper for external keyboard support
                ExternalKeyboardTextField(
                    text: $viewModel.inputText,
                    placeholder: "Type a message...",
                    onSubmit: {
                        if !viewModel.inputText.isEmpty || !viewModel.pendingAttachments.isEmpty {
                            Task { await viewModel.sendMessage() }
                        }
                    },
                    isFocused: $isFocused
                )
                .frame(minHeight: 40, maxHeight: 120)
                .frame(maxWidth: .infinity)
                
                Button { 
                    Task { await viewModel.sendMessage() } 
                } label: { 
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Circle())
                        .shadow(color: .cyan.opacity(0.3), radius: 5) 
                }
                .disabled(viewModel.inputText.isEmpty && viewModel.pendingAttachments.isEmpty || viewModel.isLoading)
                .opacity(viewModel.inputText.isEmpty && viewModel.pendingAttachments.isEmpty ? 0.5 : 1)
            }
            .padding(12)
            .premiumGlass(cornerRadius: isPad ? 40 : 32, intense: true)
            .onAppear {
                // Auto-focus on appear for external keyboard support
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 0)
        .padding(.bottom, isPad ? 0 : 8)
    }
}

struct SettingsSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingProvider: AIProvider?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()
                List {
                    Section { ForEach(viewModel.providers) { provider in ProviderRow(provider: provider, isActive: provider.isActive) { viewModel.setActiveProvider(provider) } onEdit: { editingProvider = provider } } } header: { Text("Available Providers").foregroundStyle(.gray) }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("AI Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(.white) } }
            .sheet(item: $editingProvider) { provider in ProviderEditSheet(viewModel: viewModel, provider: provider) { viewModel.updateProvider($0); editingProvider = nil }.preferredColorScheme(.dark) }
        }
    }
}

struct ProviderRow: View {
    let provider: AIProvider; let isActive: Bool; let onToggle: () -> Void; let onEdit: () -> Void
    var body: some View {
        HStack {
            Button(action: onToggle) { ZStack { Circle().stroke(isActive ? Color.cyan : Color.gray.opacity(0.5), lineWidth: 2).frame(width: 24, height: 24); if isActive { Circle().fill(Color.cyan).frame(width: 14, height: 14) } } }.buttonStyle(.plain).padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 4) { Text(provider.name).font(.body.weight(.medium)).foregroundStyle(.white); Text(provider.model.isEmpty ? "Not configured" : provider.model).font(.caption).foregroundStyle(provider.model.isEmpty ? .orange : .gray) }
            Spacer(); Button("Edit") { onEdit() }.font(.subheadline).foregroundStyle(.cyan).padding(.horizontal, 12).padding(.vertical, 6).background(Color.cyan.opacity(0.1)).clipShape(Capsule())
        }.padding(.vertical, 4).listRowBackground(Color(white: 0.1))
    }
}

struct ProviderEditSheet: View {
    @ObservedObject var viewModel: ChatViewModel; @State private var provider: AIProvider; @State private var availableModels: [String] = []; @State private var isFetching = false; @State private var errorMsg: String?; let onSave: (AIProvider) -> Void; @Environment(\.dismiss) private var dismiss
    init(viewModel: ChatViewModel, provider: AIProvider, onSave: @escaping (AIProvider) -> Void) { self.viewModel = viewModel; _provider = State(initialValue: provider); _availableModels = State(initialValue: provider.knownModels); self.onSave = onSave }
    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    HStack {
                        Text("API Key").frame(width: 100, alignment: .leading)
                        ExternalKeyboardUITextField(
                            text: $provider.apiKey,
                            placeholder: "Enter API Key",
                            isSecure: true,
                            keyboardType: .default,
                            autocapitalizationType: .none,
                            autocorrectionType: .no
                        )
                    }
                    
                    if provider.name == "Custom" {
                        HStack {
                            Text("Base URL").frame(width: 100, alignment: .leading)
                            ExternalKeyboardUITextField(
                                text: $provider.baseURL,
                                placeholder: "https://api.example.com",
                                keyboardType: .URL,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                        }
                    }
                }
                Section("Model") {
                    HStack { Button(isFetching ? "Fetching..." : "Load Models") { Task { await fetchModels() } }.disabled(provider.apiKey.isEmpty || isFetching).foregroundStyle(.cyan); if isFetching { ProgressView().padding(.leading) } }
                    if let err = errorMsg { Text(err).foregroundStyle(.red).font(.caption) }
                    if !availableModels.isEmpty { Picker("Select Model", selection: $provider.model) { Text("Select...").tag(""); ForEach(availableModels, id: \.self) { m in Text(m).tag(m) } } } else {
                        HStack {
                            Text("Model ID").frame(width: 100, alignment: .leading)
                            ExternalKeyboardUITextField(
                                text: $provider.model,
                                placeholder: "Enter Model ID",
                                keyboardType: .default,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                        }
                    }
                }
            }
            .navigationTitle("Edit \(provider.name)").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { provider.knownModels = availableModels; onSave(provider); dismiss() } } }
        }
    }
    private func fetchModels() async { isFetching = true; errorMsg = nil; do { let models = try await viewModel.fetchAvailableModels(for: provider); await MainActor.run { availableModels = models; if provider.model.isEmpty, let first = models.first { provider.model = first }; isFetching = false } } catch { await MainActor.run { errorMsg = error.localizedDescription; isFetching = false } } }
}

struct PremiumBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.3), .black]), center: .center, startRadius: 5, endRadius: 500)
            
            GeometryReader { geo in
                ZStack {
                    Circle().fill(Color.purple.opacity(0.2)).frame(width: min(geo.size.width, geo.size.height) * 0.8).blur(radius: 60).offset(x: animate ? -30 : 30, y: animate ? -20 : 20)
                    Circle().fill(Color.blue.opacity(0.15)).frame(width: min(geo.size.width, geo.size.height) * 0.6).blur(radius: 50).offset(x: animate ? 40 : -40, y: animate ? 30 : -30)
                }.frame(width: geo.size.width, height: geo.size.height).contentShape(Rectangle())
            }
        }
        .ignoresSafeArea().onAppear { withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { animate.toggle() } }
    }
}

struct TypingIndicator: View { @State private var p1 = false; @State private var p2 = false; @State private var p3 = false; var body: some View { HStack(spacing: 4) { dot(p1); dot(p2); dot(p3) }.padding(12).background(.ultraThinMaterial).clipShape(Capsule()).onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(0.0)) { p1.toggle() }; withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(0.2)) { p2.toggle() }; withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(0.4)) { p3.toggle() } } }
    func dot(_ active: Bool) -> some View { Circle().fill(active ? Color.white : Color.white.opacity(0.3)).frame(width: 6, height: 6) } }
extension View { func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> Content) -> some View { ZStack(alignment: alignment) { placeholder().opacity(shouldShow ? 1 : 0); self } } }

// MARK: - Custom Text Input Components for External Keyboard Support

// UITextField wrapper for single-line text input
struct ExternalKeyboardUITextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .yes
    var returnKeyType: UIReturnKeyType = .default
    var onSubmit: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        
        // Configure text field properties first
        textField.font = UIFont.systemFont(ofSize: 17)
        textField.textColor = .label
        textField.text = text
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecure
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType
        textField.returnKeyType = returnKeyType
        textField.enablesReturnKeyAutomatically = false
        textField.keyboardAppearance = .dark
        textField.clearButtonMode = .whileEditing
        
        // Set delegate and target after configuration
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
        
        return textField
    }
    
    func updateUIView(_ textField: UITextField, context: Context) {
        // Only update text if it changed externally and text field is not being edited
        // This prevents conflicts when user is typing
        if !textField.isFirstResponder {
            if textField.text != text {
                textField.text = text
            }
        }
        
        // Update other properties
        if textField.placeholder != placeholder {
            textField.placeholder = placeholder
        }
        if textField.isSecureTextEntry != isSecure {
            textField.isSecureTextEntry = isSecure
        }
        if textField.keyboardType != keyboardType {
            textField.keyboardType = keyboardType
        }
        if textField.autocapitalizationType != autocapitalizationType {
            textField.autocapitalizationType = autocapitalizationType
        }
        if textField.autocorrectionType != autocorrectionType {
            textField.autocorrectionType = autocorrectionType
        }
        if textField.returnKeyType != returnKeyType {
            textField.returnKeyType = returnKeyType
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ExternalKeyboardUITextField
        
        init(_ parent: ExternalKeyboardUITextField) {
            self.parent = parent
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            // Update binding - this is called on main thread by UIKit
            let newText = textField.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Always allow the change - textFieldDidChange will update the binding
            return true
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            textField.resignFirstResponder()
            return true
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Text field is ready for input
        }
    }
}

// UITextView wrapper for multi-line text input
struct ExternalKeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    @FocusState.Binding var isFocused: Bool
    
    func makeUIView(context: Context) -> UITextViewWrapper {
        let wrapper = UITextViewWrapper()
        context.coordinator.wrapper = wrapper
        wrapper.textView.delegate = context.coordinator
        wrapper.textView.font = UIFont.systemFont(ofSize: 17)
        wrapper.textView.textColor = .white
        wrapper.textView.backgroundColor = .clear
        wrapper.textView.tintColor = .cyan
        wrapper.textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        wrapper.textView.textContainer.lineFragmentPadding = 0
        wrapper.textView.isScrollEnabled = true
        wrapper.textView.returnKeyType = .send
        wrapper.textView.enablesReturnKeyAutomatically = false
        wrapper.textView.autocapitalizationType = .none
        wrapper.textView.autocorrectionType = .yes
        wrapper.textView.keyboardType = .default
        wrapper.textView.keyboardAppearance = .dark
        wrapper.placeholder = placeholder
        wrapper.placeholderColor = UIColor.white.withAlphaComponent(0.4)
        wrapper.textView.text = text
        wrapper.updatePlaceholder()
        
        return wrapper
    }
    
    func updateUIView(_ wrapper: UITextViewWrapper, context: Context) {
        context.coordinator.wrapper = wrapper
        
        // Only update text if it changed externally and text view is not being edited
        if !wrapper.textView.isFirstResponder && wrapper.textView.text != text {
            context.coordinator.isUpdatingFromBinding = true
            wrapper.textView.text = text
            wrapper.updatePlaceholder()
            DispatchQueue.main.async {
                context.coordinator.isUpdatingFromBinding = false
            }
        }
        
        wrapper.placeholder = placeholder
        
        // Handle focus
        if isFocused && !wrapper.textView.isFirstResponder {
            DispatchQueue.main.async {
                wrapper.textView.becomeFirstResponder()
            }
        } else if !isFocused && wrapper.textView.isFirstResponder {
            DispatchQueue.main.async {
                wrapper.textView.resignFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ExternalKeyboardTextField
        weak var wrapper: UITextViewWrapper?
        private var isUpdatingFromBinding = false
        
        init(_ parent: ExternalKeyboardTextField) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromBinding else { return }
            let newText = textView.text
            if parent.text != newText {
                if Thread.isMainThread {
                    parent.text = newText
                    wrapper?.updatePlaceholder()
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.parent.text = newText
                        self.wrapper?.updatePlaceholder()
                    }
                }
            }
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if Thread.isMainThread {
                parent.isFocused = true
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isFocused = true
                }
            }
            wrapper?.updatePlaceholder()
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if Thread.isMainThread {
                parent.isFocused = false
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isFocused = false
                }
            }
            wrapper?.updatePlaceholder()
        }
    }
}

class UITextViewWrapper: UIView {
    let textView = UITextView()
    private let placeholderLabel = UILabel()
    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
        }
    }
    var placeholderColor: UIColor = .gray {
        didSet {
            placeholderLabel.textColor = placeholderColor
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(textView)
        addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -12)
        ])
        
        placeholderLabel.font = UIFont.systemFont(ofSize: 17)
        placeholderLabel.textColor = placeholderColor
        placeholderLabel.numberOfLines = 0
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
    }
    
    @objc private func textDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updatePlaceholder()
        }
    }
    
    func updatePlaceholder() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePlaceholder()
            }
            return
        }
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - KEYBOARD HELPER EXTENSION
#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
