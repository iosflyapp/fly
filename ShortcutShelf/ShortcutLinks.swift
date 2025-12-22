import Foundation

enum ShortcutLinkKind: String, CaseIterable, Hashable {
  case run
  case open

  var label: String {
    switch self {
    case .run: return "Run"
    case .open: return "Open in Shortcuts"
    }
  }
}

enum ShortcutLinkBuilder {
  /// Builds a `shortcuts://…` deep link for a given shortcut name.
  ///
  /// Notes:
  /// - This works only if the user already has the shortcut installed.
  /// - `name` must match the Shortcut’s name exactly.
  static func link(for name: String, kind: ShortcutLinkKind) -> URL? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "shortcuts"

    switch kind {
    case .run:
      components.host = "run-shortcut"
    case .open:
      components.host = "open-shortcut"
    }

    components.queryItems = [
      URLQueryItem(name: "name", value: trimmed),
    ]

    return components.url
  }
}

