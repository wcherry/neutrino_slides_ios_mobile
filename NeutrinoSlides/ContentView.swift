import SwiftUI
import NeutrinoCore
import NeutrinoUI

// MARK: - ContentView

/// The signed-in app shell: a tab per browse section, plus Offline and Settings (Epic 1 — "Tabs").
///
/// Each tab keeps its own `NavigationStack` so pushing into a folder or a deck in one tab does not
/// disturb the others.
struct ContentView: View {

    @EnvironmentObject private var driveService: SlidesDriveService
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @State private var selectedTab: Tab = .home
    /// Home's navigation stack, owned here rather than by ``SlideBrowserView`` so a Universal Link
    /// can push an editor onto it from outside the browser.
    @State private var homePath = NavigationPath()
    @State private var linkError: String?

    enum Tab: Hashable {
        case home, recent, favorites, shared, offline, settings
    }

    var body: some View {
        tabs
            // Slides queues no edits made offline; an offline copy opens read-only. The strip says
            // so rather than promising a sync.
            .connectivityBanner(isOnline: networkMonitor.isOnline, keepsChangesOffline: false)
            // A presentation link has to land on Home whatever the user was last looking at: that
            // is the stack the editor is pushed onto.
            .onChange(of: deepLinkRouter.pending?.id) { pendingID in
                if pendingID != nil { selectedTab = .home }
            }
            .task(id: deepLinkRouter.pending?.id) { await openPendingLink() }
            .alert("Couldn\u{2019}t Open Presentation", isPresented: Binding(
                get: { linkError != nil },
                set: { if !$0 { linkError = nil } }
            )) {
                Button("OK") { linkError = nil }
            } message: {
                Text(linkError ?? "")
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                SlideBrowserView(section: .home)
                    // Only the deep link pushes by value; the browser's own rows push their
                    // destination view directly.
                    .navigationDestination(for: SlideItem.self) { item in
                        DeckEditorView(item: item)
                    }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                SlideBrowserView(section: .recent)
            }
            .tabItem { Label("Recent", systemImage: "clock") }
            .tag(Tab.recent)

            NavigationStack {
                SlideBrowserView(section: .favorites)
            }
            .tabItem { Label("Favorites", systemImage: "star") }
            .tag(Tab.favorites)

            NavigationStack {
                SlideBrowserView(section: .shared)
            }
            .tabItem { Label("Shared", systemImage: "person.2") }
            .tag(Tab.shared)

            NavigationStack {
                OfflineView()
            }
            .tabItem { Label("Offline", systemImage: "arrow.down.circle") }
            .tag(Tab.offline)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Tab.settings)
        }
    }

    // MARK: - Universal Links

    /// Opens the presentation an inbound `…/open/slide/<id>` link named.
    ///
    /// The stack is reset before the push so a link followed while three folders deep does not bury
    /// the editor under a back trail the user never walked.
    private func openPendingLink() async {
        guard FeatureFlags.appLinks, FeatureFlags.driveIntegration else { return }
        guard deepLinkRouter.pending != nil, let destination = deepLinkRouter.consume() else { return }

        // A link can name a deck in a folder this session never opened, or one shared by another
        // account, so the cache is an optimisation and the server is the fallback.
        if let cached = driveService.item(id: destination.fileID), cached.type == .file {
            push(cached)
            return
        }
        do {
            push(try await driveService.fetchItem(id: destination.fileID))
        } catch {
            linkError = error.localizedDescription
        }
    }

    private func push(_ item: SlideItem) {
        homePath = NavigationPath()
        homePath.append(item)
    }
}

// MARK: - OfflineView

/// The presentations this device keeps a copy of — every one opened recently — which open
/// read-only without a connection.
///
/// The copies are made by ``SlideContentService`` when a deck opens and refreshed when it saves;
/// nothing is downloaded on purpose here. Editing offline, with a queue that syncs later, is a
/// later release.
struct OfflineView: View {

    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var contentService: SlideContentService

    @State private var copies: [SlideContentService.OfflineCopy] = []

    var body: some View {
        Group {
            if copies.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(copies) { copy in
                            NavigationLink {
                                DeckEditorView(item: copy.item)
                            } label: {
                                row(copy)
                            }
                        }
                        .onDelete(perform: remove)
                    } footer: {
                        Text("Presentations you open are kept here, encrypted, and open read-only when you're offline.")
                    }
                }
            }
        }
        .navigationTitle("Offline")
        .onAppear(perform: reload)
    }

    private func row(_ copy: SlideContentService.OfflineCopy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(copy.item.displayName)
                .lineLimit(1)
            Text("Kept \(copy.storedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: networkMonitor.isOnline ? "arrow.down.circle" : "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No offline presentations")
                .font(.headline)
            Text("Presentations you open are kept on this device, so you can read them without a connection.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        copies = contentService.offlineCopies
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            contentService.offlineCache?.remove(fileID: copies[index].id)
        }
        reload()
    }
}
