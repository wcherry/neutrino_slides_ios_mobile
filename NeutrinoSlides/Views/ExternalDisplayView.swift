import SwiftUI

// MARK: - ExternalDisplayView

/// What the room sees on a projector or AirPlay receiver: the slide, on black, and nothing else.
///
/// Non-interactive — the external-display scene takes no touches — so every move comes from the
/// presenter on the phone through ``ExternalDisplayService``. Plays the slide's own transition
/// here rather than relying on the phone's animation: the two windows are separate view graphs, so
/// an animation started on the phone does not carry across.
struct ExternalDisplayView: View {

    @EnvironmentObject private var display: ExternalDisplayService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let deck = display.deck {
                ExternalSlideStage(deck: deck)
                    // A new presentation starts fresh, rather than animating from wherever the
                    // last one stopped.
                    .id(display.sessionID)
            } else {
                standby
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// Shown between presentations. Claiming the display means the system stops mirroring the
    /// phone, so the alternative to this is a blank screen that looks broken.
    private var standby: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 56, weight: .light))
            Text("Neutrino Slides")
                .font(.title2.weight(.semibold))
            Text("Start a presentation on your device to show it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white.opacity(0.8))
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

// MARK: - ExternalSlideStage

/// The slide itself, with the transition played locally.
private struct ExternalSlideStage: View {

    @EnvironmentObject private var display: ExternalDisplayService

    let deck: SlideDeck

    /// Trails ``ExternalDisplayService/index`` by one animation, so the change can be wrapped in
    /// `withAnimation` here.
    @State private var shownIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = SlideGeometry.canvasSize(fitting: proxy.size)
            ZStack {
                if let slide = currentSlide {
                    SlideCanvasView(slide: slide, theme: deck.theme, size: size)
                        .id(slide.id)
                        .transition(SlideTransition(stored: slide.transition)
                            .presenterTransition(isAdvancing: display.isAdvancing))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { shownIndex = display.index }
        .onChange(of: display.index) { target in
            guard deck.slides.indices.contains(target) else { return }
            let transition = SlideTransition(stored: deck.slides[target].transition)
            withAnimation(.easeInOut(duration: transition.duration)) {
                shownIndex = target
            }
        }
    }

    private var currentSlide: Slide? {
        let index = shownIndex ?? display.index
        return deck.slides.indices.contains(index) ? deck.slides[index] : nil
    }
}
