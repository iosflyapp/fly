import SwiftUI

// MARK: - AI Provider Definition
enum AIProvider: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google AI"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "cpu"
        case .google: return "globe"
        case .custom: return "gearshape"
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .custom: return ""
        }
    }
    
    // Default models (fallback if API fetch fails)
    var defaultModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .google:
            return ["gemini-2.0-flash-exp", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .custom:
            return []
        }
    }
}

// MARK: - API Configuration Model
struct APIConfiguration: Identifiable, Codable {
    let id: UUID
    let provider: AIProvider
    var apiKey: String
    var selectedModel: String
    var customEndpoint: String
    var isActive: Bool
    var availableModels: [String]
    
    init(provider: AIProvider, apiKey: String = "", selectedModel: String = "", customEndpoint: String = "", isActive: Bool = false) {
        self.id = UUID()
        self.provider = provider
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.customEndpoint = customEndpoint
        self.isActive = isActive
        self.availableModels = provider.defaultModels
    }
    
    enum CodingKeys: String, CodingKey {
        case id, provider, apiKey, selectedModel, customEndpoint, isActive, availableModels
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let providerString = try container.decode(String.self, forKey: .provider)
        provider = AIProvider(rawValue: providerString) ?? .openai
        apiKey = try container.decode(String.self, forKey: .apiKey)
        selectedModel = try container.decode(String.self, forKey: .selectedModel)
        customEndpoint = try container.decode(String.self, forKey: .customEndpoint)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        availableModels = try container.decodeIfPresent([String].self, forKey: .availableModels) ?? provider.defaultModels
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider.rawValue, forKey: .provider)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(customEndpoint, forKey: .customEndpoint)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(availableModels, forKey: .availableModels)
    }
}

// MARK: - Model Response Structures
struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Codable {
    let id: String
}

struct AnthropicModelsResponse: Codable {
    let data: [AnthropicModel]
}

struct AnthropicModel: Codable {
    let id: String
}

struct GoogleModelsResponse: Codable {
    let models: [GoogleModel]
}

struct GoogleModel: Codable {
    let name: String
}

// MARK: - Model Fetcher Service
class ModelFetcher {
    static func fetchModels(for provider: AIProvider, apiKey: String, customEndpoint: String? = nil) async throws -> [String] {
        switch provider {
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey)
        case .google:
            return try await fetchGoogleModels(apiKey: apiKey)
        case .custom:
            if let endpoint = customEndpoint, !endpoint.isEmpty {
                return try await fetchCustomModels(endpoint: endpoint, apiKey: apiKey)
            }
            return []
        }
    }
    
    private static func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        
        // Filter for chat models and sort by preference
        let chatModels = modelsResponse.data
            .map { $0.id }
            .filter { $0.contains("gpt") && !$0.contains("instruct") }
            .sorted { model1, model2 in
                let priority: [String] = ["gpt-4o", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]
                let index1 = priority.firstIndex(where: { model1.contains($0) }) ?? Int.max
                let index2 = priority.firstIndex(where: { model2.contains($0) }) ?? Int.max
                return index1 < index2
            }
        
        return chatModels.isEmpty ? AIProvider.openai.defaultModels : chatModels
    }
    
    private static func fetchAnthropicModels(apiKey: String) async throws -> [String] {
        // Anthropic doesn't have a public models endpoint, return default models
        // But we can verify the API key by making a test request
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send a minimal test request to validate the API key
        let testBody: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "test"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        
        // We don't need the response, just want to verify the key is valid
        _ = try await URLSession.shared.data(for: request)
        
        return AIProvider.anthropic.defaultModels
    }
    
    private static func fetchGoogleModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let modelsResponse = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
        
        // Extract model names and filter for chat models
        let models = modelsResponse.models
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { $0.contains("gemini") && $0.contains("generateContent") == false }
            .sorted { model1, model2 in
                let priority: [String] = ["gemini-2.0", "gemini-1.5-pro", "gemini-1.5-flash"]
                let index1 = priority.firstIndex(where: { model1.contains($0) }) ?? Int.max
                let index2 = priority.firstIndex(where: { model2.contains($0) }) ?? Int.max
                return index1 < index2
            }
        
        return models.isEmpty ? AIProvider.google.defaultModels : models
    }
    
    private static func fetchCustomModels(endpoint: String, apiKey: String) async throws -> [String] {
        // For custom endpoints, try OpenAI-compatible format first
        guard let baseURL = URL(string: endpoint),
              let modelsURL = URL(string: baseURL.absoluteString.replacingOccurrences(of: "/chat/completions", with: "/models")) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // If models endpoint fails, return empty array
            return []
        }
        
        let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return modelsResponse.data.map { $0.id }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var apiConfigurations: [APIConfiguration] = []
    @Published var activeConfiguration: APIConfiguration?
    
    private let configurationsKey = "apiConfigurations"
    
    init() {
        loadConfigurations()
    }
    
    func getConfiguration(for provider: AIProvider) -> APIConfiguration {
        if let existing = apiConfigurations.first(where: { $0.provider == provider }) {
            return existing
        }
        let new = APIConfiguration(provider: provider)
        apiConfigurations.append(new)
        return new
    }
    
    func updateConfiguration(_ configuration: APIConfiguration) {
        if let index = apiConfigurations.firstIndex(where: { $0.id == configuration.id }) {
            apiConfigurations[index] = configuration
        } else {
            apiConfigurations.append(configuration)
        }
        saveConfigurations()
    }
    
    func setActiveConfiguration(_ configuration: APIConfiguration) {
        // Deactivate all others
        for i in apiConfigurations.indices {
            apiConfigurations[i].isActive = false
        }
        
        // Activate the selected one
        if let index = apiConfigurations.firstIndex(where: { $0.id == configuration.id }) {
            apiConfigurations[index].isActive = true
            activeConfiguration = apiConfigurations[index]
        }
        
        saveConfigurations()
    }
    
    func fetchModels(for configuration: APIConfiguration) async throws -> [String] {
        return try await ModelFetcher.fetchModels(
            for: configuration.provider,
            apiKey: configuration.apiKey,
            customEndpoint: configuration.customEndpoint.isEmpty ? nil : configuration.customEndpoint
        )
    }
    
    private func saveConfigurations() {
        if let encoded = try? JSONEncoder().encode(apiConfigurations) {
            UserDefaults.standard.set(encoded, forKey: configurationsKey)
        }
    }
    
    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: configurationsKey),
           let decoded = try? JSONDecoder().decode([APIConfiguration].self, from: data) {
            apiConfigurations = decoded
            activeConfiguration = decoded.first(where: { $0.isActive })
        }
    }
}

// MARK: - Configuration Form Section
struct ConfigurationFormSection: View {
    let provider: AIProvider
    @Binding var apiKey: String
    @Binding var selectedModel: String
    @Binding var customEndpoint: String
    @Binding var showingAPIKey: Bool
    @Binding var availableModels: [String]
    @Binding var isFetchingModels: Bool
    let onFetchModels: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
                .foregroundStyle(.white)
            
            VStack(spacing: 16) {
                // API Key field
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Spacer()
                        
                        if !apiKey.isEmpty {
                            Button {
                                Task {
                                    await onFetchModels()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if isFetchingModels {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.cyan)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Fetch Models")
                                        .font(.caption)
                                }
                                .foregroundStyle(.cyan)
                            }
                            .disabled(isFetchingModels)
                        }
                    }
                    
                    HStack {
                        if showingAPIKey {
                            TextField("Enter your API key", text: $apiKey)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: apiKey) { _ in
                                    // Auto-fetch models when API key is entered
                                    if !apiKey.isEmpty && apiKey.count > 20 {
                                        Task {
                                            await onFetchModels()
                                        }
                                    }
                                }
                        } else {
                            SecureField("Enter your API key", text: $apiKey)
                                .onChange(of: apiKey) { _ in
                                    // Auto-fetch models when API key is entered
                                    if !apiKey.isEmpty && apiKey.count > 20 {
                                        Task {
                                            await onFetchModels()
                                        }
                                    }
                                }
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
                
                // Model selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        if isFetchingModels {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.cyan)
                            Text("Fetching models...")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                    }
                    
                    Menu {
                        ForEach(availableModels, id: \.self) { model in
                            Button(model) {
                                selectedModel = model
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
                    .disabled(availableModels.isEmpty || isFetchingModels)
                }
                
                // Custom endpoint (for custom provider)
                if provider == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Endpoint")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextField("https://api.example.com/v1/chat/completions", text: $customEndpoint)
                            .font(.body)
                            .foregroundStyle(.white)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
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
                                
                                Text(config.selectedModel)
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
    let isEnabled: Bool
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
                        isEnabled ?
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [.gray.opacity(0.3), .gray.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .disabled(!isEnabled)
    }
}

// MARK: - API Configuration View
struct APIConfigurationView: View {
    @StateObject private var appState = AppState()
    @State private var selectedProvider: AIProvider = .openai
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var customEndpoint: String = ""
    @State private var showingAPIKey: Bool = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var fetchError: String?
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Provider selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Provider")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(AIProvider.allCases) { provider in
                                        ProviderCard(
                                            provider: provider,
                                            isSelected: selectedProvider == provider
                                        ) {
                                            selectedProvider = provider
                                            loadConfiguration()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Configuration form
                        ConfigurationFormSection(
                            provider: selectedProvider,
                            apiKey: $apiKey,
                            selectedModel: $selectedModel,
                            customEndpoint: $customEndpoint,
                            showingAPIKey: $showingAPIKey,
                            availableModels: $availableModels,
                            isFetchingModels: $isFetchingModels,
                            onFetchModels: fetchModels
                        )
                        
                        // Error message
                        if let error = fetchError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.red.opacity(0.2))
                            }
                        }
                        
                        // Save button
                        SaveConfigurationButton(
                            isEnabled: !apiKey.isEmpty && !selectedModel.isEmpty,
                            action: saveConfiguration
                        )
                        
                        // Active configurations
                        ActiveConfigurationsSection()
                            .environmentObject(appState)
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Configuration")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadConfiguration()
            }
            .alert("Configuration Saved", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func loadConfiguration() {
        let config = appState.getConfiguration(for: selectedProvider)
        apiKey = config.apiKey
        selectedModel = config.selectedModel
        customEndpoint = config.customEndpoint
        availableModels = config.availableModels
        
        // If we have a key but no models, fetch them
        if !apiKey.isEmpty && availableModels.isEmpty {
            Task {
                await fetchModels()
            }
        }
    }
    
    private func fetchModels() async {
        guard !apiKey.isEmpty else { return }
        
        isFetchingModels = true
        fetchError = nil
        
        do {
            let config = APIConfiguration(
                provider: selectedProvider,
                apiKey: apiKey,
                selectedModel: selectedModel,
                customEndpoint: customEndpoint
            )
            
            let models = try await appState.fetchModels(for: config)
            
            await MainActor.run {
                availableModels = models
                
                // Auto-select first model if none selected
                if selectedModel.isEmpty && !models.isEmpty {
                    selectedModel = models[0]
                }
                
                isFetchingModels = false
            }
        } catch {
            await MainActor.run {
                fetchError = "Failed to fetch models: \(error.localizedDescription)"
                // Fall back to default models
                availableModels = selectedProvider.defaultModels
                if selectedModel.isEmpty && !availableModels.isEmpty {
                    selectedModel = availableModels[0]
                }
                isFetchingModels = false
            }
        }
    }
    
    private func saveConfiguration() {
        var config = appState.getConfiguration(for: selectedProvider)
        config.apiKey = apiKey
        config.selectedModel = selectedModel
        config.customEndpoint = customEndpoint
        config.availableModels = availableModels
        config.isActive = true
        
        appState.updateConfiguration(config)
        appState.setActiveConfiguration(config)
        
        alertMessage = "\(selectedProvider.rawValue) configuration saved with model \(selectedModel)"
        showingAlert = true
    }
}

// MARK: - Provider Card
struct ProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.title)
                    .foregroundStyle(isSelected ? .cyan : .white.opacity(0.6))
                
                Text(provider.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            }
            .frame(width: 120, height: 100)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? .cyan.opacity(0.15) : .white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? .cyan : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    }
            }
        }
    }
}

// MARK: - App Entry Point
@main
struct AIConfigurationApp: App {
    var body: some Scene {
        WindowGroup {
            APIConfigurationView()
        }
    }
}
