import Foundation

enum SampleData {
  static let categories: [ShortcutCategory] = [
    ShortcutCategory(
      title: "Quick Actions",
      systemImage: "bolt.fill",
      summary: "Small shortcuts you run all the time.",
      shortcuts: [
        ShortcutItem(
          title: "Start Focus Session",
          subtitle: "Sets Focus, starts timer, plays ambient audio.",
          systemImage: "moon.stars.fill",
          installURL: URL(string: "https://www.icloud.com/shortcuts/EXAMPLE_ID_1"),
          shortcutName: "Start Focus Session",
          platforms: [.iOS, .macOS],
          tags: ["focus", "timer", "productivity"]
        ),
        ShortcutItem(
          title: "Clean Up Downloads",
          subtitle: "Moves old files into an archive folder.",
          systemImage: "folder.badge.gearshape",
          installURL: URL(string: "https://www.icloud.com/shortcuts/EXAMPLE_ID_2"),
          shortcutName: "Clean Up Downloads",
          platforms: [.macOS],
          tags: ["files", "mac", "automation"]
        ),
      ]
    ),
    ShortcutCategory(
      title: "Writing",
      systemImage: "text.book.closed.fill",
      summary: "Drafting, outlining, and publishing workflows.",
      shortcuts: [
        ShortcutItem(
          title: "Daily Journal Entry",
          subtitle: "Prompts you with questions and saves to Notes.",
          systemImage: "square.and.pencil",
          installURL: URL(string: "https://www.icloud.com/shortcuts/EXAMPLE_ID_3"),
          shortcutName: "Daily Journal Entry",
          platforms: [.iOS, .macOS],
          tags: ["notes", "journal", "writing"]
        ),
      ]
    ),
    ShortcutCategory(
      title: "Media",
      systemImage: "play.rectangle.fill",
      summary: "Audio/video helpers and share-sheet tools.",
      shortcuts: [
        ShortcutItem(
          title: "Download Video (Share Sheet)",
          subtitle: "Use from the share sheet to save a video.",
          systemImage: "square.and.arrow.down",
          installURL: URL(string: "https://www.icloud.com/shortcuts/EXAMPLE_ID_4"),
          shortcutName: nil,
          platforms: [.iOS],
          tags: ["share sheet", "video"]
        ),
      ]
    ),
  ]
}

