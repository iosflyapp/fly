import SwiftUI

@main
struct ShortcutShelfApp: App {
  @StateObject private var library = ShortcutLibrary()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(library)
    }
  }
}

