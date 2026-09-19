import SwiftUI
import NeutrinoCore

// MARK: - SlideBrowserView

/// Epic 3 — Drive Integration: browsing, and the operations on a presentation.
///
/// One view serves every section. Home navigates into folders; Recent, Favorites, Shared and Trash
/// are flat listings (see ``SlidesSection/supportsFolderNavigation``).
struct SlideBrowserView: View {

    // MARK: - Input

    let section: SlidesSection
    /// The folder being listed. Always nil outside Home.
    var parentID: String? = nil
    var title: String? = nil

    // MARK: - Environment

    @EnvironmentObject private var driveService: SlidesDriveService
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    // MARK: - State

    @State private var showCreatePresentation = false
    @State private var showCreateFolder = false
    @State private var renameTarget: SlideItem?
    @State private var moveTarget: SlideItem?
    @State private var isWorking = false
    @State private var actionError: String?

    // MARK: - Body

    var body: some View {
        List {
            if items.isEmpty && !driveService.isLoading {
                EmptySectionView(section: section)
                    .listRowSeparator(.hidden)
            }

            ForEach(items) { item in
                row(for: item)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title ?? section.rawValue)
        .navigationBarTitleDisplayMode(parentID == nil ? .large : .inline)
        .toolbar { toolbarContent }
        .refreshable { await driveService.load(section, parentID: parentID) }
        .task { await driveService.load(section, parentID: parentID) }
        .overlay {
            if driveService.isLoading && items.isEmpty {
                ProgressView()
            }
        }
        .sheet(isPresented: $showCreatePresentation) {
            CreatePresentationSheet(parentID: parentID)
        }
        .sheet(isPresented: $showCreateFolder) {
            CreateFolderSheet(parentID: parentID)
        }
        .sheet(item: $renameTarget) { item in
            RenameSheet(item: item)
        }
        .sheet(item: $moveTarget) { item in
            MoveSheet(item: item)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: SlideItem) -> some View {
        if item.type == .folder && section.supportsFolderNavigation {
            NavigationLink {
                SlideBrowserView(section: section, parentID: item.id, title: item.name)
            } label: {
                SlideRowView(item: item)
            }
            .contextMenu { contextMenu(for: item) }
        } else if item.type == .file && section != .trash {
            NavigationLink {
                DeckEditorView(item: item)
            } label: {
                SlideRowView(item: item)
            }
            .contextMenu { contextMenu(for: item) }
            .swipeActions(edge: .trailing) {
                if !item.isShared {
                    Button(role: .destructive) {
                        driveService.delete(itemID: item.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } else {
            SlideRowView(item: item)
                .contextMenu { contextMenu(for: item) }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: SlideItem) -> some View {
        if section == .trash {
            Button {
                driveService.restore(itemID: item.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                driveService.delete(itemID: item.id)
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        } else {
            // Drive scopes rename, move, star and trash to the owner; offering them on somebody
            // else's presentation would only produce a 403.
            if !item.isShared {
                Button {
                    driveService.setStarred(itemID: item.id, isStarred: !item.isStarred)
                } label: {
                    Label(item.isStarred ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: item.isStarred ? "star.slash" : "star")
                }

                Button {
                    renameTarget = item
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    moveTarget = item
                } label: {
                    Label("Move…", systemImage: "folder")
                }
            }

            // Duplicating a raw .pptx would mean reading the package, which is Epic 22's job.
            if item.isNativeDeck {
                Button {
                    duplicate(item)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(!networkMonitor.isOnline)
            }

            if !item.isShared {
                Divider()
                Button(role: .destructive) {
                    driveService.delete(itemID: item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if section == .trash {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Empty", role: .destructive) {
                    driveService.emptyTrash()
                }
                .disabled(driveService.trashItems.isEmpty)
            }
        } else if section == .home && FeatureFlags.driveIntegration {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCreatePresentation = true
                    } label: {
                        Label("New Presentation", systemImage: "rectangle.badge.plus")
                    }
                    .disabled(!networkMonitor.isOnline)

                    Button {
                        showCreateFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(!networkMonitor.isOnline)

                    Divider()

                    // Deliberately not disabled offline like the two above. Those need the Drive
                    // API; this one opens Safari — and the bug most worth reporting is often the
                    // one that just took the app off the network.
                    ReportBugButton()
                } label: {
                    Image(systemName: "plus")
                }
                // The menu is no longer only about creating things. VoiceOver reads this label
                // instead of the glyph, so leaving it at "Create" would hide the report from
                // exactly the people most likely to have something to file.
                .accessibilityLabel("Create and more")
            }
        }
    }

    // MARK: - Data

    private var items: [SlideItem] {
        // Folders before presentations, then by name — the ordering people expect from a file
        // browser, except in Recent, where the server's newest-first order is the point.
        let raw = driveService.items(in: section, parentID: parentID)
        guard section != .recent else { return raw }
        return raw.sorted { lhs, rhs in
            if lhs.type != rhs.type { return lhs.type == .folder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Actions

    private func duplicate(_ item: SlideItem) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await driveService.duplicate(itemID: item.id)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

// MARK: - EmptySectionView

/// Epic 1 — "Empty states".
struct EmptySectionView: View {
    let section: SlidesSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: section.emptyIcon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(section.emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }
}

// MARK: - SlideRowView

/// One row in a listing.
struct SlideRowView: View {
    let item: SlideItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .foregroundStyle(item.type == .folder ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
            if item.isShared {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared with you")
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        // A real .pptx is listed but cannot be opened yet, and saying so in the row is kinder
        // than letting the user tap into an error.
        if item.isOfficeDeck {
            return "PowerPoint file \u{00B7} not supported yet"
        }
        var parts = [Self.dateFormatter.localizedString(for: item.modifiedAt, relativeTo: Date())]
        if let size = item.size, item.type == .file {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
