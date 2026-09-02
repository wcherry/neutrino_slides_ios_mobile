import SwiftUI

// MARK: - AppTheme

/// Settings — "Theme". The *app's* appearance, which is not the deck's theme; see ``SlideTheme``.
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// What to hand SwiftUI's `.preferredColorScheme`. `nil` follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - AppSettings

/// The user's preferences, persisted in `UserDefaults`.
///
/// `@Published` rather than `@AppStorage` so that a single observable object can be injected into
/// the view tree and, more importantly, constructed against a throwaway `UserDefaults` suite in
/// tests — `@AppStorage` reads `.standard` unconditionally.
@MainActor
final class AppSettings: ObservableObject {

    // MARK: - Keys

    enum Keys {
        static let theme            = "settings.theme"
        static let autoSaveInterval = "settings.autoSaveIntervalSeconds"
        static let snapStep         = "settings.snapStep"
        static let showSnapGuides   = "settings.showSnapGuides"
        static let showNotes        = "settings.showNotes"
        static let showThumbnails   = "settings.showThumbnails"
        static let advanceSeconds   = "settings.advanceSeconds"
        static let keepScreenAwake  = "settings.keepScreenAwake"
    }

    // MARK: - Allowed values

    /// Selectable auto-save intervals, in seconds. The web editor debounces at 2 seconds
    /// (`SlideEditor`'s autosave), which is the default here too.
    static let autoSaveIntervalOptions: [TimeInterval] = [2, 3, 5, 10, 30]
    static let defaultAutoSaveInterval: TimeInterval = 2

    /// How far a dragged element snaps, as a percentage of the canvas — element geometry is stored
    /// in percentages, so the snap grid is too and a deck laid out on a phone lines up with the
    /// same deck on a laptop. `0` means no snapping.
    static let snapStepOptions: [Double] = [0, 0.5, 1, 2.5, 5]
    static let defaultSnapStep: Double = 1

    /// Selectable auto-advance intervals for presenter mode, in seconds. `0` is manual, and is the
    /// default: a deck that advances itself while somebody is talking over it is the wrong default
    /// on a device that is also the remote.
    static let advanceSecondsOptions: [TimeInterval] = [0, 5, 10, 15, 30, 60]

    // MARK: - Published settings

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Epic 7 — "Autosave on an interval from Settings".
    @Published var autoSaveInterval: TimeInterval {
        didSet { defaults.set(autoSaveInterval, forKey: Keys.autoSaveInterval) }
    }

    /// Epic 6 — the drag/resize snap grid, in canvas percent.
    @Published var snapStep: Double {
        didSet {
            // Clamped on write rather than trusted from the caller: the value also arrives from
            // `UserDefaults`, where a stale build or a synced preference could have left anything,
            // and a negative step would make ``SlideGeometry/snap(_:step:)`` place elements at
            // random.
            let clamped = snapStep.clamped(to: 0...25)
            if clamped != snapStep {
                snapStep = clamped
                return
            }
            defaults.set(snapStep, forKey: Keys.snapStep)
        }
    }

    /// Whether the canvas draws its centre and edge guides while an element is being dragged.
    @Published var showSnapGuides: Bool {
        didSet { defaults.set(showSnapGuides, forKey: Keys.showSnapGuides) }
    }

    /// Whether the editor shows the speaker-notes pane under the canvas.
    @Published var showNotes: Bool {
        didSet { defaults.set(showNotes, forKey: Keys.showNotes) }
    }

    /// Whether the editor shows the slide thumbnail rail. On by default; it is the only way to
    /// reorder slides, so switching it off loses reach as well as orientation — which is why it is
    /// a setting rather than something the layout decides.
    @Published var showThumbnails: Bool {
        didSet { defaults.set(showThumbnails, forKey: Keys.showThumbnails) }
    }

    /// Epic 12 — seconds each slide is held in presenter mode before advancing. `0` is manual.
    @Published var advanceSeconds: TimeInterval {
        didSet { defaults.set(advanceSeconds, forKey: Keys.advanceSeconds) }
    }

    /// Whether presenter mode holds the idle timer off. On by default: a phone that dims halfway
    /// through a deck is the failure this setting exists to prevent, and it applies *only* while
    /// presenting, so the cost when the presentation ends is nothing.
    @Published var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Keys.keepScreenAwake) }
    }

    // MARK: - Private

    private let defaults: UserDefaults

    // MARK: - Init

    /// - Parameter defaults: injected in tests so a run cannot disturb the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        let storedInterval = defaults.object(forKey: Keys.autoSaveInterval) as? Double
        self.autoSaveInterval = storedInterval ?? Self.defaultAutoSaveInterval
        let storedSnap = defaults.object(forKey: Keys.snapStep) as? Double
        self.snapStep = (storedSnap ?? Self.defaultSnapStep).clamped(to: 0...25)
        self.showSnapGuides = defaults.object(forKey: Keys.showSnapGuides) as? Bool ?? true
        self.showNotes = defaults.object(forKey: Keys.showNotes) as? Bool ?? false
        self.showThumbnails = defaults.object(forKey: Keys.showThumbnails) as? Bool ?? true
        let storedAdvance = defaults.object(forKey: Keys.advanceSeconds) as? Double
        self.advanceSeconds = storedAdvance ?? 0
        self.keepScreenAwake = defaults.object(forKey: Keys.keepScreenAwake) as? Bool ?? true
    }

    // MARK: - Derived

    /// Label for an auto-save interval, e.g. "Every 3 seconds".
    static func autoSaveLabel(for seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return whole == 1 ? "Every second" : "Every \(whole) seconds"
    }

    /// Label for a snap step, e.g. "1%".
    static func snapLabel(for step: Double) -> String {
        guard step > 0 else { return "Off" }
        return step == step.rounded() ? "\(Int(step))%" : String(format: "%.1f%%", step)
    }

    /// Label for an auto-advance interval.
    static func advanceLabel(for seconds: TimeInterval) -> String {
        seconds == 0 ? "Manual" : "Every \(Int(seconds)) seconds"
    }

    // MARK: - Reset

    /// Restores every setting to its default. Used by Settings' "Reset to Defaults".
    func resetToDefaults() {
        theme = .system
        autoSaveInterval = Self.defaultAutoSaveInterval
        snapStep = Self.defaultSnapStep
        showSnapGuides = true
        showNotes = false
        showThumbnails = true
        advanceSeconds = 0
        keepScreenAwake = true
    }
}

// MARK: - Comparable + clamped

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
