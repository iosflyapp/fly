# Swift Playground Setup Guide

## Quick Start (iOS/iPadOS)

### 1. Install Swift Playgrounds
- Download from App Store: [Swift Playgrounds](https://apps.apple.com/app/swift-playgrounds/id908519492)
- Requires iOS 15.0 or later

### 2. Create New Playground
1. Open Swift Playgrounds
2. Tap the **+** button
3. Select **App**
4. Give it a name (e.g., "AI Configuration")

### 3. Add the Code
1. Delete the default code
2. Copy the entire contents of `AIConfigurationApp.swift`
3. Paste into the playground

### 4. Run the App
1. Tap the **Run** button (▶️)
2. The app will compile and launch
3. You should see the AI Configuration interface

## Quick Start (macOS)

### 1. Install Swift Playgrounds or Xcode
- **Swift Playgrounds**: Download from Mac App Store
- **Xcode**: Download from Mac App Store (larger, more features)

### 2. Create New Playground

**In Swift Playgrounds:**
1. Open Swift Playgrounds
2. Click **+** → **App**
3. Name your project

**In Xcode:**
1. Open Xcode
2. File → New → Playground
3. Choose **iOS** → **App** template
4. Save the playground

### 3. Add the Code
1. Replace all default code with `AIConfigurationApp.swift` contents
2. Save the file

### 4. Run the App
- **Swift Playgrounds**: Click Run button
- **Xcode**: Click ▶️ button or press ⌘R

## Troubleshooting

### "Cannot find type 'App' in scope"
**Solution**: Make sure you're using an **App** playground, not a blank playground

### "Failed to build module"
**Solution**: 
1. Clean build folder (if in Xcode: Shift+⌘K)
2. Restart Swift Playgrounds
3. Check for syntax errors

### "Network request failed"
**Solution**:
1. Check internet connection
2. Verify API key is correct
3. Make sure app has network permissions

### App doesn't appear when run
**Solution**:
1. Make sure `@main` attribute is present on `AIConfigurationApp`
2. Verify the code is complete (no truncation)
3. Check for compile errors

### "Cannot parse response" error
**Solution**:
1. Check if API provider is accessible
2. Verify API key is valid
3. Try manual "Fetch Models" button

## Features Available in Swift Playground

✅ **Full App Experience**
- Complete UI with navigation
- Forms and buttons
- Scroll views
- Alerts and error messages

✅ **Network Requests**
- URLSession works fully
- Async/await supported
- HTTPS requests allowed

✅ **Data Persistence**
- UserDefaults works
- Data saved between runs
- Configurations persist

✅ **Modern Swift Features**
- SwiftUI
- Async/await
- Actors
- Structured concurrency

❌ **Not Available**
- Push notifications
- Background tasks
- App Store deployment
- Advanced entitlements

## Testing the App

### 1. Test with OpenAI
```
1. Select "OpenAI" provider
2. Enter API key: sk-proj-... or sk-...
3. Wait for models to load (or click "Fetch Models")
4. Select a model (e.g., gpt-4o)
5. Click "Save & Activate"
6. Verify it appears in "Configured Providers"
```

### 2. Test with Anthropic
```
1. Select "Anthropic" provider
2. Enter API key: sk-ant-...
3. Models will load (default list)
4. Select a model (e.g., claude-3-5-sonnet-20241022)
5. Click "Save & Activate"
```

### 3. Test with Google AI
```
1. Select "Google AI" provider
2. Enter API key (alphanumeric)
3. Wait for models to load
4. Select a model (e.g., gemini-2.0-flash-exp)
5. Click "Save & Activate"
```

### 4. Test Multiple Providers
```
1. Configure OpenAI (save)
2. Switch to Anthropic tab
3. Configure Anthropic (save)
4. Go to "Configured Providers"
5. Toggle between them using the circle button
```

## Development Tips

### Viewing Console Output
**Swift Playgrounds iOS:**
- Swipe up from bottom to see console
- Look for print statements and errors

**Swift Playgrounds Mac:**
- View → Show Debug Area
- Console appears at bottom

**Xcode:**
- View → Debug Area → Show Debug Area
- Or press ⌘⇧Y

### Adding Debug Prints
Add print statements to track API calls:

```swift
private func fetchModels() async {
    print("🔄 Fetching models for \(selectedProvider.rawValue)...")
    
    // ... existing code ...
    
    do {
        let models = try await appState.fetchModels(for: config)
        print("✅ Fetched \(models.count) models")
        // ... rest of code ...
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        // ... error handling ...
    }
}
```

### Testing Without Real API Keys
Replace the `fetchModels` function with a mock version:

```swift
private func fetchModels() async {
    print("🧪 Using mock data")
    isFetchingModels = true
    
    // Simulate network delay
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    
    availableModels = selectedProvider.defaultModels
    if selectedModel.isEmpty && !availableModels.isEmpty {
        selectedModel = availableModels[0]
    }
    
    isFetchingModels = false
}
```

### Clearing Saved Data
To reset the app and clear all saved configurations:

```swift
// Add this to saveConfiguration() temporarily:
UserDefaults.standard.removeObject(forKey: "apiConfigurations")
print("🗑️ Cleared all saved configurations")
```

## Customization Ideas

### 1. Change Color Scheme
```swift
// Replace .cyan with your preferred color
.foregroundStyle(.purple)  // or .green, .orange, etc.
```

### 2. Add More Providers
```swift
enum AIProvider: String, CaseIterable, Identifiable {
    // ... existing cases ...
    case cohere = "Cohere"
    case huggingface = "Hugging Face"
}
```

### 3. Custom Model Names
```swift
var defaultModels: [String] {
    switch self {
    case .custom:
        return ["my-custom-model-v1", "my-custom-model-v2"]
    // ... rest of cases ...
    }
}
```

### 4. Add Model Descriptions
```swift
var modelDescription: String {
    switch self {
    case "gpt-4o": return "Most capable GPT-4 model"
    case "claude-3-5-sonnet-20241022": return "Best Claude model"
    default: return ""
    }
}
```

## Performance Tips

### Reduce API Calls
```swift
// Only auto-fetch if no models cached
if availableModels.isEmpty {
    Task {
        await fetchModels()
    }
}
```

### Cache Models Longer
```swift
// Add timestamp to APIConfiguration
var lastFetched: Date?

// Only fetch if > 1 hour old
if let last = config.lastFetched, 
   Date().timeIntervalSince(last) < 3600 {
    // Use cached models
} else {
    await fetchModels()
}
```

## Deployment Options

### Swift Playground (Recommended for Testing)
- ✅ Quick iteration
- ✅ No certificates needed
- ✅ Works on iPad
- ❌ Can't distribute

### Xcode (For Real Apps)
1. Create new Xcode project
2. Copy the code
3. Configure signing
4. Build for device
5. Submit to App Store

## Getting Help

### Common Issues
1. **Build Errors**: Check syntax, ensure code is complete
2. **Network Errors**: Verify internet, check API keys
3. **UI Not Showing**: Ensure @main attribute exists
4. **Data Not Saving**: Check UserDefaults isn't full

### Resources
- [Swift Playgrounds User Guide](https://www.apple.com/swift/playgrounds/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [URLSession Guide](https://developer.apple.com/documentation/foundation/urlsession)

### Need More Help?
Check the main README.md and API_REFERENCE.md files for detailed information.
