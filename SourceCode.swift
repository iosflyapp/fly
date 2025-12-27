import SwiftUI
import UIKit
import AVFoundation
import PDFKit
import WebKit
import Combine

// MARK: - 1. FREE AI ENGINE (Pollinations.ai)
// Features: Ad-Blocking, Auto-Save History, Swift 6 Concurrency.

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let isUser: Bool
    let text: String
    let date: Date
}

struct ChatSession: Identifiable, Equatable, Codable {
    var id = UUID()
    var date: Date
    var title: String
    var messages: [ChatMessage]
}

@MainActor
class FreeAIClient: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var isLoading = false
    
    private let saveKey = "saved_chat_sessions_v7_final"
    
    init() {
        loadHistory()
        if sessions.isEmpty {
            createNewSession()
        } else if currentSessionId == nil {
            currentSessionId = sessions.first?.id
        }
    }
    
    var currentSession: ChatSession? {
        get { sessions.first(where: { $0.id == currentSessionId }) }
        set {
            if let index = sessions.firstIndex(where: { $0.id == currentSessionId }), let newValue = newValue {
                sessions[index] = newValue
            }
        }
    }
    
    func createNewSession() {
        let newSession = ChatSession(date: Date(), title: "New Chat", messages: [])
        withAnimation {
            sessions.insert(newSession, at: 0)
            currentSessionId = newSession.id
        }
        saveHistory()
    }
    
    func switchSession(to id: UUID) {
        currentSessionId = id
    }
    
    func deleteSession(at offsets: IndexSet) {
        withAnimation {
            sessions.remove(atOffsets: offsets)
            if sessions.isEmpty { createNewSession() }
            else if currentSession == nil { currentSessionId = sessions.first?.id }
        }
        saveHistory()
    }
    
    func sendMessage(question: String, context: String) {
        guard var session = currentSession else { return }
        
        if session.messages.isEmpty { session.title = question }
        
        let userMsg = ChatMessage(isUser: true, text: question, date: Date())
        withAnimation { session.messages.append(userMsg) }
        
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
        saveHistory()
        
        guard !context.isEmpty else {
            let errorMsg = ChatMessage(isUser: false, text: "Please import some text first.", date: Date())
            withAnimation {
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx].messages.append(errorMsg)
                }
            }
            return
        }
        
        isLoading = true
        let safeContext = String(context.prefix(6000))
        let systemPrompt = "You are a helpful assistant. Answer strictly based on the text below.\n\n--- TEXT START ---\n\(safeContext)\n--- TEXT END ---\n\nQuestion: \(question)"
        
        guard let url = URL(string: "https://text.pollinations.ai/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "messages": [["role": "system", "content": systemPrompt]],
            "model": "openai"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let rawText = String(data: data, encoding: .utf8) {
                    let cleanText = self.cleanAds(from: rawText)
                    
                    let aiMsg = ChatMessage(isUser: false, text: cleanText, date: Date())
                    withAnimation {
                        if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                            self.sessions[idx].messages.append(aiMsg)
                        }
                        self.isLoading = false
                    }
                    self.saveHistory()
                }
            } catch {
                let errMsg = ChatMessage(isUser: false, text: "Error: \(error.localizedDescription)", date: Date())
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[idx].messages.append(errMsg)
                }
                self.isLoading = false
            }
        }
    }
    
    private func cleanAds(from text: String) -> String {
        let triggers = [
            "**Support Pollinations.AI:**",
            "Powered by Pollinations.AI",
            "🌸 **Ad** 🌸",
            "---"
        ]
        
        var clean = text
        
        for trigger in triggers {
            if let range = clean.range(of: trigger) {
                let dist = clean.distance(from: range.lowerBound, to: clean.endIndex)
                if dist < 600 {
                    clean = String(clean[..<range.lowerBound])
                }
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            self.sessions = decoded
        }
    }
    
    func clearCurrentSession() {
        if let idx = sessions.firstIndex(where: { $0.id == currentSessionId }) {
            sessions[idx].messages.removeAll()
            sessions[idx].title = "New Chat"
            saveHistory()
        }
    }
}

// MARK: - 2. STREAMING EDGE TTS ENGINE

@MainActor
class StreamingEdgeTTS: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    enum State { case stopped, buffering, playing, paused }
    @Published var state: State = .stopped
    @Published var errorMessage: String?
    
    let voices = [
        ("Adrian", "en-US-AndrewMultilingualNeural"),
        ("Serena", "en-US-AvaMultilingualNeural"),
        ("Julian", "en-US-BrianMultilingualNeural"),
        ("Sophie", "en-US-EmmaMultilingualNeural"),
        ("Max", "en-US-GuyNeural"),
        ("Luna", "en-US-AriaNeural"),
        ("Alice", "en-GB-SoniaNeural"),
        ("Charlie", "en-GB-RyanNeural")
    ]
    @Published var selectedVoice = "en-US-AndrewMultilingualNeural"
    
    private var webSocket: URLSessionWebSocketTask?
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }()
    
    private var player: AVQueuePlayer?
    private var bufferData = Data()
    private let chunkThreshold = 64 * 1024
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, d MMM yyyy HH:mm:ss 'GMT'"
        f.timeZone = TimeZone(abbreviation: "GMT")
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio Session Error: \(error)") }
    }
    
    func stop() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        player?.pause()
        player?.removeAllItems()
        bufferData.removeAll()
        withAnimation { self.state = .stopped }
    }
    
    func play(text: String) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation { self.state = .buffering; self.errorMessage = nil }
        player = AVQueuePlayer()
        connectAndSpeak(text: text)
    }
    
    func pauseResume() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing { player.pause(); state = .paused }
        else if player.currentItem != nil { player.play(); state = .playing }
    }
    
    func seek(by seconds: Double) {
        guard let player = player, let currentItem = player.currentItem else { return }
        let newTime = CMTimeAdd(currentItem.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: newTime)
    }
    
    private func connectAndSpeak(text: String) {
        let urlString = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4"
        guard let url = URL(string: urlString) else { return }
        
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        sendConfig()
        sendSSML(text: text, voice: self.selectedVoice)
        listen()
    }
    
    private func listen() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            Task {
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): if text.contains("turn.end") { self.processAudioChunk(force: true) } else { self.listen() }
                    case .data(let data): self.handleBinaryData(data); self.listen()
                    @unknown default: break
                    }
                case .failure(_):
                    self.errorMessage = "Connection interrupted"
                }
            }
        }
    }
    
    private func handleBinaryData(_ data: Data) {
        guard data.count > 2 else { return }
        let headerLen = (Int(data[0]) << 8) | Int(data[1])
        if data.count > headerLen + 2 {
            bufferData.append(data.subdata(in: (headerLen + 2)..<data.count))
            if bufferData.count >= chunkThreshold { processAudioChunk(force: false) }
        }
    }
    
    private func processAudioChunk(force: Bool) {
        guard !bufferData.isEmpty else { return }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("chunk_\(UUID().uuidString).mp3")
        do {
            try bufferData.write(to: tempFile)
            bufferData.removeAll()
            let item = AVPlayerItem(url: tempFile)
            
            self.player?.insert(item, after: nil)
            if self.state == .buffering { self.player?.play(); withAnimation { self.state = .playing } }
            
        } catch { print("Write Error: \(error)") }
    }
    
    private func sendConfig() {
        let msg = buildMessage(path: "speech.config", type: "application/json; charset=utf-8", body: """
        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}
        """)
        webSocket?.send(.string(msg)) { _ in }
    }
    
    private func sendSSML(text: String, voice: String) {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><voice name='\(voice)'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escaped)</prosody></voice></speak>"
        webSocket?.send(.string(buildMessage(path: "ssml", type: "application/ssml+xml", body: ssml))) { _ in }
    }
    
    private func buildMessage(path: String, type: String, body: String) -> String {
        let ts = dateFormatter.string(from: Date())
        let reqId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "X-Timestamp:\(ts)\r\nContent-Type:\(type)\r\nX-RequestId:\(reqId)\r\nPath:\(path)\r\n\r\n\(body)"
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let err = error {
            Task { @MainActor in
                self.errorMessage = "Network Error: \(err.localizedDescription)"
            }
        }
    }
}

// MARK: - 3. CONTENT EXTRACTOR

struct ContentExtractor {
    static func extractFromPDF(url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var txt = ""
        for i in 0..<doc.pageCount { if let p = doc.page(at: i)?.string { txt += p + "\n" } }
        return txt
    }
    
    static func extractFromWeb(url: URL) async -> String {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try await MainActor.run {
                let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
                let attr = try NSAttributedString(data: data, options: opts, documentAttributes: nil)
                return attr.string
            }
        } catch {
            return "Failed to parse text: \(error.localizedDescription)"
        }
    }
}

// MARK: - 4. MAIN VIEW & UI

@main
struct ProReaderApp: App {
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some Scene { WindowGroup { ProReaderView().preferredColorScheme(.dark) } }
}

struct ProReaderView: View {
    @StateObject private var tts = StreamingEdgeTTS()
    @StateObject private var aiClient = FreeAIClient()
    
    @State private var textContent: String = "Welcome to Pro Reader.\n\nImport a PDF or Web Article.\nThen tap the AI icon to ask questions about it."
    @State private var showPDFImporter = false
    @State private var showWebInput = false
    @State private var showAIChat = false
    @State private var webURLString = ""
    @FocusState private var isTextFocused: Bool
    
    let bgColor = Color(red: 0.08, green: 0.08, blue: 0.1)
    let cardColor = Color(red: 0.12, green: 0.12, blue: 0.14)
    let panelColor = Color(red: 0.14, green: 0.14, blue: 0.16)
    let accentGradient = LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. BACKGROUND
                bgColor.ignoresSafeArea()
                
                // 2. TEXT EDITOR
                VStack(spacing: 20) {
                    TextEditor(text: $textContent)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(8)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isTextFocused)
                        .padding()
                        .background(cardColor)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                        .padding(.horizontal)
                        .padding(.bottom, 130) // Space for player + AI tab height
                }.padding(.top)
                
                // 3. AI DRAWER (Layer 2 - Behind Player)
                if showAIChat {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { withAnimation { showAIChat = false } }
                        .zIndex(1)
                    
                    AIOverlayPanel(
                        client: aiClient,
                        contextText: textContent,
                        showAIChat: $showAIChat,
                        panelColor: panelColor
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(2) // Sits visually behind layer 3
                }
                
                // 4. PLAYER PANEL (Layer 3 - On Top)
                ProPlayerPanel(
                    tts: tts,
                    textContent: $textContent,
                    showAIChat: $showAIChat,
                    showWebInput: $showWebInput,
                    showPDFImporter: $showPDFImporter,
                    accentGradient: accentGradient,
                    panelColor: panelColor
                )
                .zIndex(3) // Topmost Z Index
                
            }
            .navigationTitle("Pro Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { isTextFocused = false } }
            }
            .alert("Web URL", isPresented: $showWebInput) {
                TextField("https://...", text: $webURLString).keyboardType(.URL)
                Button("Load") {
                    guard let url = URL(string: webURLString) else { return }
                    Task {
                        let extracted = await ContentExtractor.extractFromWeb(url: url)
                        await MainActor.run { textContent = extracted }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                    textContent = ContentExtractor.extractFromPDF(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
}

// MARK: - 5. UI COMPONENTS

struct ProPlayerPanel: View {
    @ObservedObject var tts: StreamingEdgeTTS
    @Binding var textContent: String
    @Binding var showAIChat: Bool
    @Binding var showWebInput: Bool
    @Binding var showPDFImporter: Bool
    var accentGradient: LinearGradient
    var panelColor: Color
    
    var body: some View {
        VStack(spacing: 20) {
            // --- CONTROL ROW ---
            HStack(spacing: 12) {
                Spacer()
                
                // 1. LEFT: AI BUTTON
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showAIChat.toggle()
                    }
                } label: {
                    ZStack {
                        // Background matches inactive state
                        Circle().fill(Color.white.opacity(0.1)).frame(width: 44, height: 44)
                        
                        // Icon changes based on state
                        if showAIChat {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("AI")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // 2. CENTER: VOICE NAME
                Menu {
                    ForEach(tts.voices, id: \.1) { name, id in
                        Button { tts.selectedVoice = id; if tts.state == .playing { tts.play(text: textContent) } }
                        label: { HStack { Text(name); if tts.selectedVoice == id { Image(systemName: "checkmark") } } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tts.voices.first(where: { $0.1 == tts.selectedVoice })?.0 ?? "Voice")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        // CHEVRON REMOVED HERE
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                }
                
                // 3. RIGHT: ADD/MENU BUTTON
                Menu {
                    Button(action: { showWebInput = true }) { Label("Web Article", systemImage: "safari") }
                    Button(action: { showPDFImporter = true }) { Label("PDF Document", systemImage: "doc.text") }
                    Button(action: { textContent = UIPasteboard.general.string ?? textContent }) { Label("Paste", systemImage: "doc.on.clipboard") }
                    Divider()
                    Button(role: .destructive, action: { textContent = "" }) { Label("Clear Text", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .rotationEffect(.degrees(90))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            // --- PLAYER CONTROLS ---
            HStack(spacing: 40) {
                Button { haptic(); tts.seek(by: -10) } label: { Image(systemName: "gobackward.10").font(.title2) }.disabled(tts.state == .stopped || tts.state == .buffering)
                Button {
                    haptic(); if tts.state == .stopped { tts.play(text: textContent) } else { tts.pauseResume() }
                } label: {
                    ZStack {
                        Circle().fill(accentGradient).frame(width: 64, height: 64).shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                        if tts.state == .buffering { ProgressView().tint(.white) }
                        else { Image(systemName: tts.state == .playing ? "pause.fill" : "play.fill").font(.title.bold()).foregroundColor(.white) }
                    }
                }
                Button { haptic(); tts.seek(by: 10) } label: { Image(systemName: "goforward.10").font(.title2) }.disabled(tts.state == .stopped || tts.state == .buffering)
            }.foregroundColor(.white)
        }
        .padding(.top, 24)
        .padding(.bottom, 10).frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 32)
                .fill(panelColor).ignoresSafeArea().shadow(color: .black.opacity(0.4), radius: 20, y: -5)
        )
    }
    func haptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - 6. AI DRAWER (BEHIND PLAYER)

struct AIOverlayPanel: View {
    @ObservedObject var client: FreeAIClient
    var contextText: String
    @Binding var showAIChat: Bool
    var panelColor: Color
    
    @State private var inputText = ""
    @State private var showHistory = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            // --- HANDLE & HEADER ---
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .onTapGesture { withAnimation { showAIChat = false } }
                
                HStack {
                    Button { client.createNewSession() } label: {
                        Image(systemName: "square.and.pencil").foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Text(client.currentSession?.title ?? "AI Assistant")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Button { showHistory = true } label: {
                        Image(systemName: "clock").foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            .background(panelColor)
            .gesture(DragGesture().onEnded { val in
                if val.translation.height > 50 { withAnimation { showAIChat = false } }
            })
            
            // --- CHAT CONTENT ---
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let session = client.currentSession {
                            if session.messages.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray.opacity(0.4))
                                    Text("Ask about the text").font(.subheadline).foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity).padding(.top, 40)
                            } else {
                                ForEach(session.messages) { msg in ChatBubble(message: msg) }
                            }
                        }
                        if client.isLoading {
                            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding()
                        }
                        Spacer().frame(height: 10)
                    }
                    .padding()
                }
                .onChange(of: client.currentSession?.messages.count) { _, _ in
                    if let last = client.currentSession?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .background(panelColor)
            
            // --- INPUT AREA ---
            HStack(spacing: 10) {
                TextField("Ask...", text: $inputText)
                    .padding(12)
                    .background(Color(white: 0.2))
                    .cornerRadius(20)
                    .foregroundColor(.white)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.blue)
                }
                .disabled(client.isLoading || inputText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 185) // Kept at 185 (Goldilocks zone)
            .background(panelColor)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
        .background(panelColor)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 32))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -5)
        .sheet(isPresented: $showHistory) { HistoryView(client: client) }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        let q = inputText; inputText = ""
        client.sendMessage(question: q, context: contextText)
    }
}

// MARK: - 7. HISTORY UI & BUBBLES

struct HistoryView: View {
    @ObservedObject var client: FreeAIClient
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(client.sessions) { session in
                    Button {
                        client.switchSession(to: session.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title.isEmpty ? "New Chat" : session.title)
                                    .font(.headline).foregroundColor(.white).lineLimit(1)
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            if session.id == client.currentSessionId {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color(white: 0.12))
                    .listRowSeparatorTint(Color.white.opacity(0.2))
                }
                .onDelete(perform: client.deleteSession)
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea())
            .navigationTitle("History")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer() }
            VStack(alignment: message.isUser ? .trailing : .leading) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(white: 0.22))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.70, alignment: message.isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled) // ENABLED WORD-BY-WORD SELECTION
                Text(message.date.formatted(.dateTime.hour().minute()))
                    .font(.caption2).foregroundColor(.gray).padding(.horizontal, 4)
            }
            if !message.isUser { Spacer() }
        }
    }
}
