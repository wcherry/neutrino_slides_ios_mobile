# Neutrino Slides for iOS

The iOS client for the presentations in [Neutrino Drive](../neutrino). It opens the same
end-to-end-encrypted decks the web app edits, in the same format, and saves them back where the web
app can read them.

Sibling to `neutrino_docs_ios_mobile`, `neutrino_notes_ios_mobile`, `neutrino_sheets_ios_mobile`,
`neutrino_photos_ios_mobile` and `neutrino_drive_mac_desktop`, and built on the same
`neutrino_shared_ios` package — account identity, the OAuth flow, the E2EE key lifecycle and the
sign-in screens are shared code, not copies.

## Running it

```bash
scripts/run_simulator.sh                       # iPhone 17 Pro, latest OS, Debug
scripts/run_simulator.sh --device "iPhone 17" --screenshot
scripts/run_simulator.sh --physical --console  # the paired device, attached to its output
```

The script regenerates the Xcode project from `project.yml` (XcodeGen), builds, installs and
launches. `neutrino_shared_ios` is referenced by relative path, so the two repositories have to sit
side by side.

Tests:

```bash
xcodebuild -project NeutrinoSlides.xcodeproj -scheme NeutrinoSlides \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## What is in it

Signed-in, the app is a Drive browser plus a deck editor:

- **Browse** — Home (with folders), Recent, Favorites, Shared and Trash, every listing filtered
  server-side to presentations. Create, rename, move, duplicate, star, trash and restore.
- **Edit** — a 16:9 canvas: tap to select, drag to move, pull one of eight handles to resize, with
  snapping and alignment guides. Text boxes, shapes from the same 35-shape catalog the web app uses,
  lines and arrows. Add, duplicate, delete and reorder slides; ten layouts; undo and redo.
- **Design** — the theme gallery (the account's own themes plus built-ins), per-slide backgrounds
  (colour, preset or custom gradient, image), transitions, and the slide master.
- **Present** — full screen, transitions, speaker notes, optional auto-advance, and the screen held
  awake for as long as the deck is playing.

Everything saves through Drive's autosave endpoint, encrypted on the device, guarded by
`expectedContentVersion` so an edit made on another device is reported rather than overwritten.

## Layout

```
NeutrinoSlides/
  Config/      FeatureFlags — one switch per shipped epic
  Models/      Drive rows, file info, roles, preferences
  Deck/        The presentation format and everything pure that acts on it:
               Presentation, SlideGeometry, ShapeCatalog, SlideLayouts,
               SlideThemes, TextStylePatch, EditHistory
  Services/    Drive, content (E2EE), themes, key vault, device sessions, deep links
  Views/       The browser, the editor and its model, the canvas renderer, presenter mode
NeutrinoSlidesTests/
agent_docs/road_map.md   What is shipped, what is next, and why
```

The split that matters: `Deck/` holds the format and the arithmetic and knows nothing about SwiftUI,
so "does dragging 32 points on a 320-point canvas move the element 10%?" is a unit test rather than a
UI test. `Views/` draws it.

## The one rule to know before editing the format

**A deck can hold things this app cannot draw.** Videos, diagram references, live spreadsheet embeds
and per-element animations all come from the web app, and a save made here must not lose them. Every
modelled type keeps its unknown fields; an element of an unmodelled kind is kept whole and drawn as a
labelled placeholder at its real position. `PresentationCodecTests` enforces it — if you add a field
to the format, add it to the round-trip fixture too.

## Status

Phase 1 is complete: the shell, the account, Drive integration, the canvas, editing, slide
management, text formatting, design and presenter mode. Sharing, search, offline, version history and
office mode (`.pptx`) are next; see `agent_docs/road_map.md` for the epic list and the reasoning.

Universal Links are implemented but switched off (`FeatureFlags.appLinks`): the deployed
`apple-app-site-association` still routes `/open/slide/*` to Neutrino Drive, and moving it has to be
sequenced with the App Store release.

The app icon is a placeholder in the brand's colours — replace it before shipping.
