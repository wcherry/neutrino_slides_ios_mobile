import Foundation

// MARK: - SlideGradients

/// The preset backgrounds the background picker offers.
///
/// Copied verbatim from `PRESET_GRADIENTS` in the web app's `slideEditorConstants.ts`, CSS strings
/// and all. Storing the same string is the point: the value goes into the deck as written, and a
/// gradient authored on a phone has to be one the browser can paint.
enum SlideGradients {

    static let presets: [String] = [
        "linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%)",
        "linear-gradient(160deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)",
        "linear-gradient(135deg, #0d0221 0%, #0d3b2e 50%, #064e3b 100%)",
        "linear-gradient(135deg, #1a0000 0%, #4a1010 50%, #7c2020 100%)",
        "linear-gradient(135deg, #2d1b2e 0%, #4a1942 50%, #3d0f26 100%)",
        "linear-gradient(135deg, #1a2f20 0%, #2d4a35 50%, #1f3d28 100%)",
        "linear-gradient(135deg, #1a0a00 0%, #7c2d12 45%, #c2410c 100%)",
        "linear-gradient(160deg, #0a1628 0%, #0f2744 50%, #1e3a5f 100%)",
        "linear-gradient(135deg, #050010 0%, #1a0533 45%, #0d001f 100%)",
        "linear-gradient(135deg, #160800 0%, #451a03 50%, #78350f 100%)",
        "linear-gradient(160deg, #e0f7ff 0%, #bae6fd 50%, #7dd3fc 100%)",
        "linear-gradient(135deg, #04000f 0%, #180033 35%, #0d0525 65%, #1a0040 100%)",
        "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
        "linear-gradient(135deg, #f093fb 0%, #f5576c 100%)",
        "linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)",
        "linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)",
        "linear-gradient(135deg, #fa709a 0%, #fee140 100%)",
        "linear-gradient(135deg, #a18cd1 0%, #fbc2eb 100%)",
    ]
}
