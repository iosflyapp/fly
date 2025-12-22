import Foundation

enum ShortcutPlatform: String, Codable, CaseIterable, Hashable {
  case iOS
  case macOS

  var label: String {
    switch self {
    case .iOS: return "iOS"
    case .macOS: return "macOS"
    }
  }
}

struct ShortcutItem: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var subtitle: String?
  var systemImage: String

  /// If you have an iCloud share link, set this so users can install the shortcut.
  var installURL: URL?

  /// If you know the installed Shortcut name, set this to enable run/open deep links.
  /// (The same name should exist on both iOS and macOS if you want it to work everywhere.)
  var shortcutName: String?

  /// Optional: show which platforms it’s intended for (badges).
  var platforms: Set<ShortcutPlatform>

  /// Optional: extra keywords for search.
  var tags: [String]

  init(
    id: String = UUID().uuidString,
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    installURL: URL? = nil,
    shortcutName: String? = nil,
    platforms: Set<ShortcutPlatform> = Set(ShortcutPlatform.allCases),
    tags: [String] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.installURL = installURL
    self.shortcutName = shortcutName
    self.platforms = platforms
    self.tags = tags
  }

  func matchesSearch(_ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return true }

    if title.lowercased().contains(q) { return true }
    if (subtitle ?? "").lowercased().contains(q) { return true }
    if tags.joined(separator: " ").lowercased().contains(q) { return true }
    if (shortcutName ?? "").lowercased().contains(q) { return true }
    return false
  }
}

struct ShortcutCategory: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var systemImage: String
  var summary: String?
  var shortcuts: [ShortcutItem]

  init(
    id: String = UUID().uuidString,
    title: String,
    systemImage: String,
    summary: String? = nil,
    shortcuts: [ShortcutItem]
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.summary = summary
    self.shortcuts = shortcuts
  }
}

