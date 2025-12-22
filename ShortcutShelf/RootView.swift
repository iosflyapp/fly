import SwiftUI

final class ShortcutLibrary: ObservableObject {
  @Published var categories: [ShortcutCategory] = SampleData.categories

  var allShortcuts: [ShortcutItem] {
    categories.flatMap(\.shortcuts)
  }

  func category(for id: ShortcutCategory.ID?) -> ShortcutCategory? {
    guard let id else { return nil }
    return categories.first(where: { $0.id == id })
  }
}

enum LibrarySection: Hashable, Identifiable {
  case all
  case favorites
  case category(ShortcutCategory.ID)

  var id: String {
    switch self {
    case .all: return "all"
    case .favorites: return "favorites"
    case .category(let id): return "category:\(id)"
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var library: ShortcutLibrary
  @Environment(\.openURL) private var openURL

  @AppStorage("favorites.shortcutIDs") private var favoritesRaw: String = ""

  @State private var selection: LibrarySection? = .all
  @State private var selectedShortcutID: ShortcutItem.ID?
  @State private var searchText: String = ""

  private var favoriteIDs: Set<String> {
    Set(
      favoritesRaw
        .split(separator: ",")
        .map { String($0) }
        .filter { !$0.isEmpty }
    )
  }

  private func setFavorite(_ id: ShortcutItem.ID, isFavorite: Bool) {
    var ids = favoriteIDs
    if isFavorite {
      ids.insert(id)
    } else {
      ids.remove(id)
    }
    favoritesRaw = ids.sorted().joined(separator: ",")
  }

  private func isFavorite(_ id: ShortcutItem.ID) -> Bool {
    favoriteIDs.contains(id)
  }

  private var visibleShortcuts: [ShortcutItem] {
    let base: [ShortcutItem] = {
      switch selection {
      case .favorites:
        return library.allShortcuts.filter { favoriteIDs.contains($0.id) }
      case .category(let categoryID):
        return library.category(for: categoryID)?.shortcuts ?? []
      case .all, .none:
        return library.allShortcuts
      }
    }()

    let filtered = base.filter { $0.matchesSearch(searchText) }
    return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  private var selectedShortcut: ShortcutItem? {
    guard let selectedShortcutID else { return nil }
    return library.allShortcuts.first(where: { $0.id == selectedShortcutID })
  }

  var body: some View {
    NavigationSplitView {
      sidebar
    } content: {
      shortcutList
    } detail: {
      ShortcutDetailView(
        shortcut: selectedShortcut,
        isFavorite: selectedShortcut.map { isFavorite($0.id) } ?? false,
        setFavorite: { id, favorite in setFavorite(id, isFavorite: favorite) }
      )
    }
    .searchable(text: $searchText, placement: .automatic, prompt: "Search shortcuts")
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section {
        Label("All", systemImage: "square.grid.2x2")
          .tag(LibrarySection.all as LibrarySection?)
        Label("Favorites", systemImage: "star.fill")
          .tag(LibrarySection.favorites as LibrarySection?)
      }

      Section("Categories") {
        ForEach(library.categories) { category in
          Label(category.title, systemImage: category.systemImage)
            .tag(LibrarySection.category(category.id) as LibrarySection?)
        }
      }
    }
    .navigationTitle("ShortcutShelf")
  }

  private var shortcutList: some View {
    List(selection: $selectedShortcutID) {
      if visibleShortcuts.isEmpty {
        ContentUnavailableView(
          "No Results",
          systemImage: "magnifyingglass",
          description: Text("Try a different search, or pick another category.")
        )
        .listRowBackground(Color.clear)
      } else {
        ForEach(visibleShortcuts) { shortcut in
          ShortcutRow(
            shortcut: shortcut,
            isFavorite: isFavorite(shortcut.id),
            toggleFavorite: { setFavorite(shortcut.id, isFavorite: !isFavorite(shortcut.id)) }
          )
          .tag(shortcut.id as ShortcutItem.ID?)
          .contextMenu {
            Button(isFavorite(shortcut.id) ? "Unfavorite" : "Favorite") {
              setFavorite(shortcut.id, isFavorite: !isFavorite(shortcut.id))
            }

            if let name = shortcut.shortcutName,
               let runURL = ShortcutLinkBuilder.link(for: name, kind: .run) {
              Button("Run") { openURL(runURL) }
            }

            if let name = shortcut.shortcutName,
               let openShortcutURL = ShortcutLinkBuilder.link(for: name, kind: .open) {
              Button("Open in Shortcuts") { openURL(openShortcutURL) }
            }

            if let installURL = shortcut.installURL {
              Button("Get Shortcut") { openURL(installURL) }
            }
          }
        }
      }
    }
    .navigationTitle(listTitle)
  }

  private var listTitle: String {
    switch selection {
    case .favorites:
      return "Favorites"
    case .category(let id):
      return library.category(for: id)?.title ?? "Category"
    case .all, .none:
      return "All Shortcuts"
    }
  }
}

private struct ShortcutRow: View {
  let shortcut: ShortcutItem
  let isFavorite: Bool
  let toggleFavorite: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(.thinMaterial)
        Image(systemName: shortcut.systemImage)
          .font(.system(size: 18, weight: .semibold))
          .symbolRenderingMode(.hierarchical)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(shortcut.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)

        if let subtitle = shortcut.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      HStack(spacing: 6) {
        ForEach(Array(shortcut.platforms).sorted(by: { $0.label < $1.label }), id: \.self) { platform in
          Text(platform.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        }
      }

      Button(action: toggleFavorite) {
        Image(systemName: isFavorite ? "star.fill" : "star")
          .symbolRenderingMode(.hierarchical)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
    }
    .padding(.vertical, 4)
  }
}

private struct ShortcutDetailView: View {
  @Environment(\.openURL) private var openURL

  let shortcut: ShortcutItem?
  let isFavorite: Bool
  let setFavorite: (ShortcutItem.ID, Bool) -> Void

  var body: some View {
    if let shortcut {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header(shortcut)
          actions(shortcut)
          info(shortcut)
        }
        .padding(20)
      }
      .navigationTitle(shortcut.title)
      .navigationBarTitleDisplayMode(.inline)
    } else {
      ContentUnavailableView(
        "Select a Shortcut",
        systemImage: "square.grid.2x2",
        description: Text("Pick a shortcut from the list to see details and actions.")
      )
    }
  }

  private func header(_ shortcut: ShortcutItem) -> some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(.thinMaterial)
        Image(systemName: shortcut.systemImage)
          .font(.system(size: 28, weight: .semibold))
          .symbolRenderingMode(.hierarchical)
      }
      .frame(width: 64, height: 64)

      VStack(alignment: .leading, spacing: 6) {
        Text(shortcut.title)
          .font(.title2.weight(.semibold))

        if let subtitle = shortcut.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.body)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
          ForEach(Array(shortcut.platforms).sorted(by: { $0.label < $1.label }), id: \.self) { platform in
            Label(platform.label, systemImage: platform == .iOS ? "iphone" : "macbook")
              .font(.caption)
              .foregroundStyle(.secondary)
              .labelStyle(.titleAndIcon)
          }
        }
      }

      Spacer(minLength: 0)

      Button {
        setFavorite(shortcut.id, !isFavorite)
      } label: {
        Image(systemName: isFavorite ? "star.fill" : "star")
          .font(.title3)
          .symbolRenderingMode(.hierarchical)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
    }
  }

  private func actions(_ shortcut: ShortcutItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let name = shortcut.shortcutName,
         let runURL = ShortcutLinkBuilder.link(for: name, kind: .run) {
        Button {
          openURL(runURL)
        } label: {
          Label("Run", systemImage: "play.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
      }

      HStack(spacing: 10) {
        if let name = shortcut.shortcutName,
           let openShortcutURL = ShortcutLinkBuilder.link(for: name, kind: .open) {
          Button {
            openURL(openShortcutURL)
          } label: {
            Label("Open", systemImage: "arrow.up.right.square")
          }
          .buttonStyle(.bordered)
        }

        if let installURL = shortcut.installURL {
          Button {
            openURL(installURL)
          } label: {
            Label("Get", systemImage: "arrow.down.circle")
          }
          .buttonStyle(.bordered)
        }

        if let shareURL = shortcut.installURL ?? shortcut.shortcutName.flatMap({ ShortcutLinkBuilder.link(for: $0, kind: .open) }) {
          ShareLink(item: shareURL) {
            Label("Share", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func info(_ shortcut: ShortcutItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let name = shortcut.shortcutName, !name.isEmpty {
        LabeledContent("Shortcut name") {
          Text(name).textSelection(.enabled)
        }
      }

      if let installURL = shortcut.installURL {
        LabeledContent("Install link") {
          Text(installURL.absoluteString)
            .textSelection(.enabled)
            .lineLimit(2)
        }
      }
    }
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

