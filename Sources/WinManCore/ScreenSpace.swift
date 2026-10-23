import CoreGraphics

/// Converts frames between the two global coordinate spaces macOS uses.
///
/// AppKit (`NSScreen`, `NSWindow`) places the origin at the **bottom-left** of
/// the primary display; the Accessibility API (and CoreGraphics) place it at
/// the **top-left** of the same display. X is identical in both; Y is mirrored
/// about the primary display's height.
public enum ScreenSpace {

    /// Mirrors a frame vertically about the primary display's height.
    ///
    /// The transform is its own inverse, so the same function converts
    /// AppKit → AX and AX → AppKit.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }
}
