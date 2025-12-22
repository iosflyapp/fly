## ShortcutShelf (iOS/iPadOS + macOS)

A SwiftUI app template for browsing and launching **pre-made Shortcuts** (Apple Shortcuts app) across **iOS/iPadOS and macOS**.

This is designed around modern cross‑platform SwiftUI patterns:

- **NavigationSplitView** sidebar + list + detail
- **Searchable** content
- **Favorites** saved with `AppStorage`
- **SF Symbols** + material/grouped styling
- **Deep links** into Shortcuts via `shortcuts://…` URL schemes (run/open) and iCloud links (install)

### Use this in Swift Playgrounds (iPad)

1. Create a new **App** project in Swift Playgrounds.
2. Add these files to your project (copy/paste each file’s contents):
   - `ShortcutShelfApp.swift`
   - `RootView.swift`
   - `Models.swift`
   - `SampleData.swift`
   - `ShortcutLinks.swift`
3. Run.

### Use this in Xcode (Mac)

1. Create a new **App** (SwiftUI) project.
2. Replace the generated `App`/`ContentView` with these files (same list as above).

### Customizing your shortcut library

Edit `SampleData.swift` and add your shortcuts:

- **Install link**: iCloud share link like `https://www.icloud.com/shortcuts/<id>`
- **Run/Open**: if you know the Shortcut’s name, the app can run/open it using:
  - `shortcuts://run-shortcut?name=<url-encoded-name>`
  - `shortcuts://open-shortcut?name=<url-encoded-name>`

> Tip: use iCloud links for “install”, and `run/open` URLs for already-installed shortcuts.

