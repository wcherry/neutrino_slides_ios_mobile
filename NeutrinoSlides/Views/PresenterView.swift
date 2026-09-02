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

    // MARK: - State

    @State private var index: Int
    @State private var showsChrome = true
    @State private var showsNotes = false
    /// Which way the last move went, so a transition that has a direction plays the right way when
    /// going *back*.
    @State private var isAdvancing = true

    init(deck: SlideDeck, startIndex: Int, advanceSeconds: TimeInterval, keepsScreenAwake: Bool) {
        self.deck = deck
        self.startIndex = startIndex
        self.advanceSeconds = advanceSeconds
        self.keepsScreenAwake = keepsScreenAwake
        _index = State(initialValue: startIndex)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let size = SlideGeometry.canvasSize(fitting: proxy.size)
                ZStack {
                    if let slide = currentSlide {
                        SlideCanvasView(slide: slide, theme: deck.theme, size: size)
                            .id(slide.id)
                            .transition(transition(for: slide))
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
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .preferredColorScheme(.dark)
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

    // MARK: - Transitions

    /// The SwiftUI transition for a slide's stored one.
    ///
    /// Six of the twelve are played as written. The other six — flip, cube, gallery, pixelate,
    /// cover, wipe — are 3D or filter effects with no SwiftUI equivalent that is worth a Metal pass
    /// on a phone mid-presentation, so each falls back to the closest thing that keeps its
    /// *feel*: a directional one still moves, a textural one still dissolves. The stored value is
    /// untouched either way, so the deck still plays properly on the web.
    private func transition(for slide: Slide) -> AnyTransition {
        let insertionEdge: Edge = isAdvancing ? .trailing : .leading
        let removalEdge: Edge = isAdvancing ? .leading : .trailing

        switch SlideTransition(stored: slide.transition) {
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
