import SwiftUI

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable, Equatable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google (Gemini)"
    case custom = "Custom (OpenAI-compatible)"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "a.circle"
        case .google: return "g.circle"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    /// Used as a fallback before network fetch succeeds.
    var fallbackModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o-mini", "gpt-4o", "o1-mini"]
        case .anthropic:
            return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"]
        case .google:
            return ["gemini-1.5-pro", "gemini-1.5-flash"]
        case .custom:
            return []
        }
    }
}

// MARK: - Data model

struct APIConfiguration: Identifiable, Equatable {
    let id: UUID
    var provider: AIProvider
    var apiKey: String
    var selectedModel: String
    var customEndpoint: String
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        provider: AIProvider,
        apiKey: String = "",
        selectedModel: String = "",
        customEndpoint: String = "",
        isActive: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.customEndpoint = customEndpoint
        self.isActive = isActive
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var apiConfigurations: [APIConfiguration] = [
        .init(provider: .openAI),
        .init(provider: .anthropic),
        .init(provider: .google),
        .init(provider: .custom)
    ]
    
    func setActiveConfiguration(_ config: APIConfiguration) {
        apiConfigurations = apiConfigurations.map { existing in
            var updated = existing
            updated.isActive = (existing.id == config.id)
            return updated
        }
    }
}

// MARK: - Model fetching

enum ModelFetchError: LocalizedError {
    case missingAPIKey
    case invalidCustomEndpoint
    case httpError(status: Int, body: String)
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key."
        case .invalidCustomEndpoint:
            return "Custom endpoint URL is invalid."
        case .httpError(let status, let body):
            if body.isEmpty { return "Request failed (HTTP \(status))." }
            return "Request failed (HTTP \(status)): \(body)"
        case .decodingFailed:
            return "Couldn’t decode models response."
        }
    }
}

struct ModelService {
    static func fetchModels(
        provider: AIProvider,
        apiKey: String,
        customEndpoint: String
    ) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ModelFetchError.missingAPIKey }
        
        let request = try makeRequest(provider: provider, apiKey: trimmedKey, customEndpoint: customEndpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ModelFetchError.httpError(status: http.statusCode, body: body)
        }
        
        if let decoded = decodeModelIDs(from: data, provider: provider), !decoded.isEmpty {
            return decoded
        }
        
        throw ModelFetchError.decodingFailed
    }
    
    // MARK: Requests
    
    private static func makeRequest(
        provider: AIProvider,
        apiKey: String,
        customEndpoint: String
    ) throws -> URLRequest {
        switch provider {
        case .openAI:
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return req
            
        case .anthropic:
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            // Required by Anthropic APIs (version string may need updating per your account/docs).
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return req
            
        case .google:
            // Gemini uses API key as query parameter.
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)")!
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            return req
            
        case .custom:
            let url = try customModelsURL(from: customEndpoint)
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            // Assume OpenAI-compatible auth.
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return req
        }
    }
    
    /// Accepts a user-entered endpoint like:
    /// - https://host/v1/chat
    /// - https://host/v1/chat/completions
    /// - https://host/v1
    /// and converts it to:
    /// - https://host/v1/models
    private static func customModelsURL(from customEndpoint: String) throws -> URL {
        let raw = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme != nil else {
            throw ModelFetchError.invalidCustomEndpoint
        }
        
        let absolute = url.absoluteString
        if let range = absolute.range(of: "/v1") {
            let base = String(absolute[..<range.upperBound])
            guard let modelsURL = URL(string: base + "/models") else {
                throw ModelFetchError.invalidCustomEndpoint
            }
            return modelsURL
        }
        
        // If the endpoint doesn't include /v1, fall back to appending /models.
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let currentPath = comps?.path ?? ""
        let newPath = (currentPath as NSString).appendingPathComponent("models")
        comps?.path = newPath.hasPrefix("/") ? newPath : "/" + newPath
        guard let modelsURL = comps?.url else { throw ModelFetchError.invalidCustomEndpoint }
        return modelsURL
    }
    
    // MARK: Decoding (supports multiple provider shapes)
    
    private struct OpenAIModelsResponse: Decodable {
        struct Item: Decodable { let id: String }
        let data: [Item]
    }
    
    private struct AnthropicModelsResponse: Decodable {
        struct Item: Decodable {
            let id: String?
            let name: String?
        }
        let data: [Item]?
        let models: [Item]?
    }
    
    private struct GoogleModelsResponse: Decodable {
        struct Item: Decodable { let name: String }
        let models: [Item]
    }
    
    private static func decodeModelIDs(from data: Data, provider: AIProvider) -> [String]? {
        let decoder = JSONDecoder()
        
        switch provider {
        case .openAI, .custom:
            if let res = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
                return res.data.map(\.id).sorted()
            }
            return nil
            
        case .anthropic:
            if let res = try? decoder.decode(AnthropicModelsResponse.self, from: data) {
                let items = (res.data ?? res.models ?? [])
                let ids = items.compactMap { $0.id ?? $0.name }.filter { !$0.isEmpty }
                return Array(Set(ids)).sorted()
            }
            return nil
            
        case .google:
            if let res = try? decoder.decode(GoogleModelsResponse.self, from: data) {
                // Google returns names like "models/gemini-1.5-pro"
                return res.models
                    .map(\.name)
                    .map { $0.split(separator: "/").last.map(String.init) ?? $0 }
                    .sorted()
            }
            return nil
        }
    }
}

// MARK: - Configuration Form Section (fixed: actually fetches models)

struct ConfigurationFormSection: View {
    let provider: AIProvider
    @Binding var apiKey: String
    @Binding var selectedModel: String
    @Binding var customEndpoint: String
    @Binding var showingAPIKey: Bool
    
    @State private var models: [String] = []
    @State private var isLoadingModels = false
    @State private var loadError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
                .foregroundStyle(.white)
            
            VStack(spacing: 16) {
                // API Key field
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    HStack {
                        if showingAPIKey {
                            TextField("Enter your API key", text: $apiKey)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Enter your API key", text: $apiKey)
                                .textContentType(.password)
                        }
                        
                        Button {
                            showingAPIKey.toggle()
                        } label: {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
                
                // Model selection (now backed by fetched models)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Spacer()
                        
                        if isLoadingModels {
                            ProgressView()
                                .tint(.cyan)
                                .scaleEffect(0.9)
                        }
                        
                        Button("Fetch") {
                            Task { await loadModels() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Menu {
                        let list = models.isEmpty ? provider.fallbackModels : models
                        if list.isEmpty {
                            Text("No models loaded")
                        } else {
                            ForEach(list, id: \.self) { model in
                                Button(model) { selectedModel = model }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedModel.isEmpty ? "Select a model" : selectedModel)
                                .foregroundStyle(selectedModel.isEmpty ? .white.opacity(0.4) : .white)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .font(.body)
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.08))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                }
                        }
                    }
                    
                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
                
                // Custom endpoint (for custom provider)
                if provider == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Endpoint")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextField("https://api.example.com/v1/chat", text: $customEndpoint)
                            .font(.body)
                            .foregroundStyle(.white)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                    }
                }
                
                // Help text
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.cyan)
                    
                    Text("Your API key is stored securely on your device and never shared.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.cyan.opacity(0.1))
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .onAppear {
            // Default to provider fallbacks until fetch succeeds.
            models = provider.fallbackModels
        }
        .onChange(of: provider) { _, _ in
            models = provider.fallbackModels
            loadError = nil
            selectedModel = ""
        }
        .onChange(of: apiKey) { _, _ in
            // Auto-refresh when the user pastes/changes key.
            Task { await loadModels() }
        }
        .onChange(of: customEndpoint) { _, _ in
            guard provider == .custom else { return }
            Task { await loadModels() }
        }
    }
    
    @MainActor
    private func loadModels() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            loadError = nil
            models = provider.fallbackModels
            return
        }
        
        isLoadingModels = true
        loadError = nil
        defer { isLoadingModels = false }
        
        do {
            let fetched = try await ModelService.fetchModels(provider: provider, apiKey: key, customEndpoint: customEndpoint)
            models = fetched
            
            // If the currently selected model isn't in the fetched list, clear it.
            if !selectedModel.isEmpty, !models.contains(selectedModel) {
                selectedModel = ""
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Keep whatever we already had (fallback or previous fetch).
        }
    }
}

// MARK: - Active Configurations Section

struct ActiveConfigurationsSection: View {
    @EnvironmentObject var appState: AppState
    
    var configuredProviders: [APIConfiguration] {
        appState.apiConfigurations.filter { !$0.apiKey.isEmpty }
    }
    
    var body: some View {
        if !configuredProviders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configured Providers")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                VStack(spacing: 8) {
                    ForEach(configuredProviders) { config in
                        HStack {
                            Image(systemName: config.provider.iconName)
                                .foregroundStyle(config.isActive ? .cyan : .white.opacity(0.6))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.provider.rawValue)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                
                                Text(config.selectedModel.isEmpty ? "No model selected" : config.selectedModel)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            if config.isActive {
                                Text("Active")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.cyan.opacity(0.2)))
                            }
                            
                            Button {
                                appState.setActiveConfiguration(config)
                            } label: {
                                Image(systemName: config.isActive ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(config.isActive ? .cyan : .white.opacity(0.4))
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(config.isActive ? .cyan.opacity(0.1) : .white.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(config.isActive ? .cyan.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
                                }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Save Configuration Button

struct SaveConfigurationButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save & Activate")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

// MARK: - Example container view (for previews / drop-in testing)

struct APIConfigurationView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var provider: AIProvider = .openAI
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var customEndpoint: String = "https://api.example.com/v1/chat"
    @State private var showingAPIKey: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                
                ConfigurationFormSection(
                    provider: provider,
                    apiKey: $apiKey,
                    selectedModel: $selectedModel,
                    customEndpoint: $customEndpoint,
                    showingAPIKey: $showingAPIKey
                )
                
                SaveConfigurationButton {
                    // Example "save": write into AppState list.
                    if let idx = appState.apiConfigurations.firstIndex(where: { $0.provider == provider }) {
                        appState.apiConfigurations[idx].apiKey = apiKey
                        appState.apiConfigurations[idx].selectedModel = selectedModel
                        appState.apiConfigurations[idx].customEndpoint = customEndpoint
                        appState.setActiveConfiguration(appState.apiConfigurations[idx])
                    }
                }
                
                ActiveConfigurationsSection()
                    .environmentObject(appState)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    APIConfigurationView()
        .environmentObject(AppState())
}

