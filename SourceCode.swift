import SwiftUI
import Foundation

// MARK: - App Entry Point

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Tab Enum

enum Tab: String, CaseIterable {
    case compiler = "Compiler"
    case ai = "AI Assistant"
    
    var icon: String {
        switch self {
        case .compiler: return "hammer.fill"
        case .ai: return "sparkles"
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedTab: Tab = .compiler
    @StateObject private var buildEngine = BuildEngine()
    @StateObject private var claudeVM = ClaudeViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selectedTab {
                case .compiler:
                    CompilerView(buildEngine: buildEngine)
                case .ai:
                    AIAssistantView(viewModel: claudeVM)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Tab Bar at BOTTOM
            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Tab Bar (Bottom Position)

struct FloatingTabBar: View {
    @Binding var selectedTab: Tab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 5)
        )
    }
}

struct TabBarButton: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                
                if isSelected {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, isSelected ? 20 : 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isSelected ? LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            )
        }
    }
}

// MARK: - Build Engine (GitHub API)

class BuildEngine: ObservableObject {
    @Published var isBuilding = false
    @Published var buildOutput = ""
    @Published var buildSuccess: Bool?
    @Published var sourceCode = """
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
            .font(.largeTitle)
    }
}
"""
    
    func startBuild() {
        isBuilding = true
        buildOutput = "Starting build...\n"
        buildSuccess = nil
        
        // Simulate build process
        Task { @MainActor in
            buildOutput += "Compiling Swift sources...\n"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            buildOutput += "Linking...\n"
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            buildOutput += "Build completed successfully!\n"
            buildSuccess = true
            isBuilding = false
        }
    }
    
    func clearOutput() {
        buildOutput = ""
        buildSuccess = nil
    }
}

// MARK: - Compiler View

struct CompilerView: View {
    @ObservedObject var buildEngine: BuildEngine
    @State private var showOutput = false
    @FocusState private var isEditorFocused: Bool
    
    let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)
    let cardColor = Color(red: 0.10, green: 0.10, blue: 0.12)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Code Editor
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("main.swift")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        if buildEngine.isBuilding {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    TextEditor(text: $buildEngine.sourceCode)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.white)
                        .focused($isEditorFocused)
                        .padding(12)
                        .background(cardColor)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                // Build Output (when visible)
                if showOutput && !buildEngine.buildOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Build Output")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                            Spacer()
                            
                            if let success = buildEngine.buildSuccess {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(success ? .green : .red)
                            }
                            
                            Button {
                                withAnimation { showOutput = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            Text(buildEngine.buildOutput)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom padding for tab bar
                Color.clear.frame(height: 80)
            }
            .background(bgColor)
            .navigationTitle("Compiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        buildEngine.startBuild()
                        withAnimation { showOutput = true }
                    } label: {
                        Label("Build", systemImage: "play.fill")
                    }
                    .disabled(buildEngine.isBuilding)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
        }
    }
}

// MARK: - Claude View Model

class ClaudeViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isLoggedIn = false
    @Published var sessions: [ConversationSession] = []
    @Published var currentSessionId: UUID?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiKeyStorageKey = "claude_api_key_v1"
    private let sessionsStorageKey = "claude_sessions_v1"
    
    init() {
        loadApiKey()
        loadSessions()
        if sessions.isEmpty {
            createNewSession()
        } else if currentSessionId == nil {
            currentSessionId = sessions.first?.id
        }
    }
    
    var currentSession: ConversationSession? {
        get { sessions.first(where: { $0.id == currentSessionId }) }
        set {
            if let index = sessions.firstIndex(where: { $0.id == currentSessionId }), let newValue = newValue {
                sessions[index] = newValue
            }
        }
    }
    
    func login(with key: String) {
        apiKey = key
        isLoggedIn = true
        saveApiKey()
    }
    
    func logout() {
        apiKey = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: apiKeyStorageKey)
    }
    
    func createNewSession() {
        let newSession = ConversationSession(
            id: UUID(),
            date: Date(),
            title: "New Chat",
            messages: []
        )
        withAnimation {
            sessions.insert(newSession, at: 0)
            currentSessionId = newSession.id
        }
        saveSessions()
    }
    
    func switchSession(to id: UUID) {
        currentSessionId = id
    }
    
    func deleteSession(at offsets: IndexSet) {
        withAnimation {
            sessions.remove(atOffsets: offsets)
            if sessions.isEmpty {
                createNewSession()
            } else if currentSession == nil {
                currentSessionId = sessions.first?.id
            }
        }
        saveSessions()
    }
    
    func sendMessage(_ text: String, attachments: [Attachment] = []) {
        guard var session = currentSession else { return }
        
        if session.messages.isEmpty {
            session.title = String(text.prefix(30))
        }
        
        let userMessage = Message(
            id: UUID(),
            role: .user,
            content: text,
            attachments: attachments,
            timestamp: Date()
        )
        
        withAnimation {
            session.messages.append(userMessage)
        }
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        saveSessions()
        
        // Call Claude API
        callClaudeAPI(with: text, session: session)
    }
    
    private func callClaudeAPI(with text: String, session: ConversationSession) {
        isLoading = true
        errorMessage = nil
        
        guard !apiKey.isEmpty else {
            errorMessage = "Please enter your API key"
            isLoading = false
            return
        }
        
        Task { @MainActor in
            // Build messages for API
            var apiMessages: [[String: Any]] = []
            for msg in session.messages {
                apiMessages.append([
                    "role": msg.role == .user ? "user" : "assistant",
                    "content": msg.content
                ])
            }
            
            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 4096,
                "messages": apiMessages
            ]
            
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    self.errorMessage = "API Error: Status \(httpResponse.statusCode)"
                    self.isLoading = false
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let responseText = firstContent["text"] as? String {
                    
                    let assistantMessage = Message(
                        id: UUID(),
                        role: .assistant,
                        content: responseText,
                        attachments: [],
                        timestamp: Date()
                    )
                    
                    withAnimation {
                        if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                            self.sessions[idx].messages.append(assistantMessage)
                        }
                    }
                    self.saveSessions()
                } else {
                    self.errorMessage = "Failed to parse response"
                }
                
                self.isLoading = false
            } catch {
                self.errorMessage = "Network error: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func saveApiKey() {
        UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
    }
    
    private func loadApiKey() {
        if let key = UserDefaults.standard.string(forKey: apiKeyStorageKey), !key.isEmpty {
            apiKey = key
            isLoggedIn = true
        }
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsStorageKey)
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsStorageKey),
           let decoded = try? JSONDecoder().decode([ConversationSession].self, from: data) {
            sessions = decoded
            currentSessionId = sessions.first?.id
        }
    }
}

// MARK: - Data Models

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let attachments: [Attachment]
    let timestamp: Date
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    let type: AttachmentType
    let name: String
    let data: Data?
}

enum AttachmentType: String, Codable {
    case image
    case file
}

struct ConversationSession: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var title: String
    var messages: [Message]
}

struct GeneratedFile: Identifiable {
    let id = UUID()
    let name: String
    let content: String
    let language: String
}

// MARK: - AI Assistant View (iPhone Optimized)

struct AIAssistantView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    @State private var showSidebar = false
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color(red: 0.06, green: 0.06, blue: 0.08)
                        .ignoresSafeArea()
                    
                    if viewModel.isLoggedIn {
                        // Main Chat or iPad Split View
                        if isPhone {
                            // iPhone: Full screen chat with sheet sidebar
                            AIChatView(viewModel: viewModel, showSidebar: $showSidebar)
                        } else {
                            // iPad: Split view
                            HStack(spacing: 0) {
                                if showSidebar {
                                    AISidebarView(viewModel: viewModel, showSidebar: $showSidebar)
                                        .frame(width: min(320, geometry.size.width * 0.35))
                                        .transition(.move(edge: .leading))
                                }
                                
                                AIChatView(viewModel: viewModel, showSidebar: $showSidebar)
                            }
                        }
                    } else {
                        // Login View
                        AILoginView(viewModel: viewModel)
                    }
                }
            }
            .sheet(isPresented: $showSidebar) {
                if isPhone {
                    AISidebarView(viewModel: viewModel, showSidebar: $showSidebar)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
}

// MARK: - AI Login View

struct AILoginView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    @State private var apiKeyInput = ""
    @FocusState private var isInputFocused: Bool
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: isPhone ? 40 : 80)
                
                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: isPhone ? 80 : 100, height: isPhone ? 80 : 100)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: isPhone ? 36 : 44))
                        .foregroundColor(.white)
                }
                .shadow(color: .purple.opacity(0.5), radius: 20)
                
                // Title
                VStack(spacing: 8) {
                    Text("AI Assistant")
                        .font(.system(size: isPhone ? 28 : 34, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Enter your Claude API key to get started")
                        .font(isPhone ? .subheadline : .body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // API Key Input
                VStack(spacing: 16) {
                    SecureField("sk-ant-...", text: $apiKeyInput)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(white: 0.12))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .focused($isInputFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    Button {
                        if !apiKeyInput.isEmpty {
                            viewModel.login(with: apiKeyInput)
                        }
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: apiKeyInput.isEmpty ? [.gray] : [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .disabled(apiKeyInput.isEmpty)
                }
                .padding(.horizontal, isPhone ? 24 : 48)
                
                // Info text
                Text("Your API key is stored locally on this device")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                // Bottom padding for tab bar
                Color.clear.frame(height: 100)
            }
            .frame(maxWidth: isPhone ? .infinity : 500)
        }
        .onTapGesture {
            isInputFocused = false
        }
    }
}

// MARK: - AI Chat View (iPhone Optimized)

struct AIChatView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    @Binding var showSidebar: Bool
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)
    let cardColor = Color(red: 0.10, green: 0.10, blue: 0.12)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text(viewModel.currentSession?.title ?? "AI Assistant")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    viewModel.createNewSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(cardColor)
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let session = viewModel.currentSession {
                            if session.messages.isEmpty {
                                EmptyStateView()
                                    .padding(.top, 60)
                            } else {
                                ForEach(session.messages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                        }
                        
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Thinking...")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        }
                        
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                        }
                        
                        // Bottom spacing for input and tab bar
                        Color.clear.frame(height: isPhone ? 160 : 100)
                    }
                    .padding()
                }
                .onChange(of: viewModel.currentSession?.messages.count) { _, _ in
                    if let lastMessage = viewModel.currentSession?.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area (fixed at bottom)
            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack(alignment: .bottom, spacing: 12) {
                    // Text Input
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color(white: 0.15))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    // Send Button
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(inputText.isEmpty || viewModel.isLoading ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(cardColor)
                
                // Extra padding for tab bar
                Color(red: 0.10, green: 0.10, blue: 0.12)
                    .frame(height: 70)
            }
        }
        .background(bgColor)
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: isPhone ? 50 : 60))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("Start a conversation")
                .font(isPhone ? .headline : .title3)
                .foregroundColor(.gray)
            
            Text("Ask anything and I'll help you out")
                .font(isPhone ? .caption : .subheadline)
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: isPhone ? 50 : 100)
            } else {
                // AI Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        message.role == .user
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color(white: 0.18))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
                
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * (isPhone ? 0.75 : 0.65), alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer(minLength: isPhone ? 50 : 100)
            } else {
                // User Avatar
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - AI Sidebar View

struct AISidebarView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    @Binding var showSidebar: Bool
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    let bgColor = Color(red: 0.08, green: 0.08, blue: 0.10)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if isPhone {
                    Button {
                        showSidebar = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(bgColor)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // New Chat Button
            Button {
                viewModel.createNewSession()
                if isPhone {
                    showSidebar = false
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Chat")
                    Spacer()
                }
                .font(.body.weight(.medium))
                .foregroundColor(.white)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            .padding()
            
            // Session List
            List {
                ForEach(viewModel.sessions) { session in
                    SessionRowView(
                        session: session,
                        isSelected: session.id == viewModel.currentSessionId
                    ) {
                        viewModel.switchSession(to: session.id)
                        if isPhone {
                            showSidebar = false
                        }
                    }
                    .listRowBackground(
                        session.id == viewModel.currentSessionId
                        ? Color.white.opacity(0.1)
                        : Color.clear
                    )
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: viewModel.deleteSession)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Logout Button
            Button {
                viewModel.logout()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .font(.body)
                .foregroundColor(.red)
                .padding()
            }
        }
        .background(bgColor)
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: ConversationSession
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(session.date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Code Parser

class CodeParser {
    static func extractCodeBlocks(from text: String) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        
        let pattern = "```(\\w+)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return files
        }
        
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        
        for (index, match) in matches.enumerated() {
            var language = "text"
            if match.range(at: 1).location != NSNotFound {
                language = nsText.substring(with: match.range(at: 1))
            }
            
            let code = nsText.substring(with: match.range(at: 2))
            let fileName = "code_\(index + 1).\(fileExtension(for: language))"
            
            files.append(GeneratedFile(
                name: fileName,
                content: code,
                language: language
            ))
        }
        
        return files
    }
    
    static func fileExtension(for language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "yaml", "yml": return "yml"
        case "markdown", "md": return "md"
        default: return "txt"
        }
    }
}
