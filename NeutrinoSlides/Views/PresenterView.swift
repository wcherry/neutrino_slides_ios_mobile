import SwiftUI
import UIKit

// MARK: - PresenterView

/// Epic 12 — full-screen playback.
///
/// The whole screen, on black, with no chrome until it is asked for: a presentation is the one
/// place in the app where the *content* has to be the only thing on the display, because the
/// display is usually a projector by then.
///
/// Deliberately reads the deck it was handed rather than reloading it. The editor's copy is the one
/// with the edit made thirty seconds ago in it, and a presenter that fetched the server's copy
/// would show the version *before* whatever was just fixed.
struct PresenterView: View {

    // MARK: - Input

    let deck: SlideDeck
    let startIndex: Int
    /// `0` presents manually. From Settings.
    let advanceSeconds: TimeInterval
    let keepsScreenAwake: Bool

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var externalDisplay: ExternalDisplayService

    // MARK: - State

    @State private var index: Int
    @State private var showsChrome = true
    @State private var showsNotes = false
    /// Which way the last move went, so a transition that has a direction plays the right way when
    /// going *back*.
    @State private var isAdvancing = true
    @State private var showsExternalDisplayHelp = false
    /// When the presentation started, for the presenter console's clock.
    @State private var startedAt = Date()

    init(deck: SlideDeck, startIndex: Int, advanceSeconds: TimeInterval, keepsScreenAwake: Bool) {
        self.deck = deck
        self.startIndex = startIndex
        self.advanceSeconds = advanceSeconds
        self.keepsScreenAwake = keepsScreenAwake
        _index = State(initialValue: startIndex)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if externalDisplay.isConnected {
                // The room is looking at the other screen, so this one is the presenter's own.
                PresenterConsoleView(deck: deck, index: index, startedAt: startedAt,
                                     onPrevious: { go(to: index - 1) },
                                     onNext: { go(to: index + 1) },
                                     onDone: { dismiss() })
            } else {
                fullScreen
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < 0 { go(to: index + 1) }
                    else if value.translation.width > 0 { go(to: index - 1) }
                }
        )
        .task { await autoAdvanceLoop() }
        .onAppear {
            // Only while presenting, and put back on the way out — a global "never sleep" would
            // outlive the deck and flatten the battery of a phone left in a pocket.
            UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake
            startedAt = Date()
            // Sent whether or not a display is connected yet, so one plugged in mid-presentation
            // picks up at the current slide.
            externalDisplay.begin(deck: deck, at: index)
            updateOrientationLock(isConsole: externalDisplay.isConnected)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            externalDisplay.end()
            OrientationLock.unlock()
        }
        .onChange(of: index) { externalDisplay.show(index: $0) }
        .onChange(of: externalDisplay.isConnected) { updateOrientationLock(isConsole: $0) }
        .alert("Present on a TV or projector", isPresented: $showsExternalDisplayHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Control Center and choose Screen Mirroring to pick an AirPlay display, "
                 + "or connect a display with a cable. The slides then appear on that screen "
                 + "and this one shows the next slide, your notes and a timer.")
        }
        .preferredColorScheme(.dark)
    }

    /// The deck filling this screen — the only display there is.
    private var fullScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let size = SlideGeometry.canvasSize(fitting: proxy.size)
                ZStack {
                    if let slide = currentSlide {
                        SlideCanvasView(slide: slide, theme: deck.theme, size: size)
                            .id(slide.id)
                            .transition(SlideTransition(stored: slide.transition)
                                .presenterTransition(isAdvancing: isAdvancing))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()

            // The tap targets are the two halves of the screen, which is how every presenter
            // remote works. They sit above the slide and below the chrome, so a control still wins
            // where the two overlap.
            HStack(spacing: 0) {
                tapTarget(advance: false)
                tapTarget(advance: true)
            }
            .ignoresSafeArea()

            if showsChrome {
                chrome
            }
        }
    }

    /// Portrait while the presenter view is up, so the phone reads as a notes card. Released as soon
    /// as the display goes: presenting on the phone alone wants landscape, where a 16:9 slide fills
    /// the screen.
    private func updateOrientationLock(isConsole: Bool) {
        if isConsole {
            OrientationLock.lock(.portrait)
        } else {
            OrientationLock.unlock()
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
                .accessibilityLabel("End presentation")

                Spacer()

                // iOS gives apps no way to start AirPlay mirroring themselves, so this explains
                // where the system's own control is rather than pretending to be it.
                Button {
                    showsExternalDisplayHelp = true
                } label: {
                    Image(systemName: "airplayvideo")
                        .font(.title3)
                }
                .accessibilityLabel("Present on another display")

                if !(currentSlide?.notes.isEmpty ?? true) {
                    Button {
                        showsNotes.toggle()
                    } label: {
                        Image(systemName: showsNotes ? "note.text.badge.plus" : "note.text")
                            .font(.title3)
                    }
                    .accessibilityLabel(showsNotes ? "Hide speaker notes" : "Show speaker notes")
                }

                Text("\(index + 1) / \(deck.slides.count)")
                    .font(.footnote.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .foregroundStyle(.white)

            Spacer()

            if showsNotes, let notes = currentSlide?.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: 180)
                .background(.ultraThinMaterial)
            }
        }
        .transition(.opacity)
    }

    /// One half of the screen. A tap advances or goes back; the chrome comes and goes with a long
    /// press, so it can be dismissed without moving the deck on.
    private func tapTarget(advance: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                go(to: advance ? index + 1 : index - 1)
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                withAnimation { showsChrome.toggle() }
            }
            .accessibilityLabel(advance ? "Next slide" : "Previous slide")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Navigation

    private var currentSlide: Slide? {
        deck.slides.indices.contains(index) ? deck.slides[index] : nil
    }

    /// Moves to a slide, if it exists.
    ///
    /// Stopping at the ends rather than wrapping: a deck that jumps back to slide one when the
    /// presenter taps once too many at the end is a bad surprise in front of a room.
    private func go(to target: Int) {
        guard deck.slides.indices.contains(target), target != index else { return }
        isAdvancing = target > index
        let transition = SlideTransition(stored: deck.slides[target].transition)
        withAnimation(.easeInOut(duration: transition.duration)) {
            index = target
        }
    }

    /// Epic 12 — auto-advance, off by default.
    private func autoAdvanceLoop() async {
        guard advanceSeconds > 0 else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(advanceSeconds * 1_000_000_000))
            } catch {
                return
            }
            guard index + 1 < deck.slides.count else { return }
            go(to: index + 1)
        }
    }
}

// MARK: - Transitions

extension SlideTransition {

    /// The SwiftUI transition for a stored one, shared by this screen and the external display.
    ///
    /// Six of the twelve are played as written. The other six — flip, cube, gallery, pixelate,
    /// cover, wipe — are 3D or filter effects with no SwiftUI equivalent that is worth a Metal pass
    /// on a phone mid-presentation, so each falls back to the closest thing that keeps its
    /// *feel*: a directional one still moves, a textural one still dissolves. The stored value is
    /// untouched either way, so the deck still plays properly on the web.
    ///
    /// `isAdvancing` is which way the last move went, so a transition that has a direction plays
    /// the right way when going *back*.
    func presenterTransition(isAdvancing: Bool) -> AnyTransition {
        let insertionEdge: Edge = isAdvancing ? .trailing : .leading
        let removalEdge: Edge = isAdvancing ? .leading : .trailing

        switch self {
        case .none:
            return .identity
        case .fade, .dissolve, .pixelate:
            return .opacity
        case .slideRight, .gallery:
            return .asymmetric(insertion: .move(edge: insertionEdge),
                               removal: .move(edge: removalEdge))
        case .slideLeft:
            return .asymmetric(insertion: .move(edge: removalEdge),
                               removal: .move(edge: insertionEdge))
        case .cover, .wipe:
            // The incoming slide slides over the outgoing one, which stays put — that is what
            // "cover" means, and a wipe reads the same way at this size.
            return .asymmetric(insertion: .move(edge: insertionEdge), removal: .opacity)
        case .zoom, .cube, .flip:
            return .scale(scale: 0.85).combined(with: .opacity)
        }
    }
}

// MARK: - PresenterConsoleView

/// The phone's screen while the deck is on an external display: what the presenter needs and the
/// room does not — the next slide, the notes, the clock.
///
/// Takes its moves as closures so ``PresenterView`` stays the one owner of the index, the
/// transitions and the auto-advance loop.
private struct PresenterConsoleView: View {

    let deck: SlideDeck
    let index: Int
    let startedAt: Date
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            VStack(spacing: 12) {
                header

                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        currentSlidePanel
                            .frame(width: proxy.size.width * 0.58)
                        VStack(alignment: .leading, spacing: 12) {
                            nextSlidePanel
                            notesPanel
                        }
                    }
                } else {
                    // Portrait is the usual case — the phone is held to portrait while presenting
                    // to a display. The slide is a reminder of what the room sees, not the thing
                    // being read, so it is kept short and the notes get everything else.
                    currentSlidePanel
                        .frame(maxHeight: proxy.size.height * 0.28)
                    compactNextSlide
                    notesPanel
                }

                controls
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    // MARK: - Panels

    private var header: some View {
        HStack {
            Button(action: onDone) {
                Label("End", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .accessibilityLabel("End presentation")

            Label("On external display", systemImage: "tv")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(Self.elapsed(from: startedAt, to: context.date))
                    .font(.title3.monospacedDigit())
                    .accessibilityLabel("Elapsed time")
            }

            Text("\(index + 1) / \(deck.slides.count)")
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var currentSlidePanel: some View {
        slidePreview(at: index)
            .contentShape(Rectangle())
            .onTapGesture(perform: onNext)
            .accessibilityHint("Tap to advance")
    }

    @ViewBuilder
    private var nextSlidePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if deck.slides.indices.contains(index + 1) {
                slidePreview(at: index + 1)
            } else {
                Text("End of presentation")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    /// The next slide as one row — a thumbnail and a label — so it costs the notes as little
    /// height as possible.
    private var compactNextSlide: some View {
        HStack(spacing: 10) {
            if deck.slides.indices.contains(index + 1) {
                slidePreview(at: index + 1)
                    .frame(height: 108)
                Text("Next: slide \(index + 2)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("Last slide")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var notesPanel: some View {
        ScrollView {
            let notes = deck.slides.indices.contains(index) ? deck.slides[index].notes : ""
            Text(notes.isEmpty ? "No speaker notes" : notes)
                .font(.title3)
                .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(index == 0)

            Button(action: onNext) {
                Label("Next", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(index + 1 >= deck.slides.count)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }

    /// A slide at whatever size the panel allows, kept 16:9.
    private func slidePreview(at slideIndex: Int) -> some View {
        GeometryReader { proxy in
            let size = SlideGeometry.canvasSize(fitting: proxy.size)
            SlideCanvasView(slide: deck.slides[slideIndex], theme: deck.theme, size: size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(SlideGeometry.aspectRatio, contentMode: .fit)
    }

    /// `m:ss`, or `h:mm:ss` past the hour.
    static func elapsed(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
