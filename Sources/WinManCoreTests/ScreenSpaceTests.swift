import CoreGraphics
import Testing
import WinManCore

/// The AX (top-left origin) ↔ AppKit (bottom-left origin) frame conversion.
/// A bug here shows up as vertical mirroring on screen, so the mapping is
/// pinned with concrete numbers against a 1080pt-tall primary display.
@Suite("Screen space conversion")
struct ScreenSpaceTests {

    private let primaryHeight: CGFloat = 1080

    @Test func flipIsItsOwnInverse() {
        let rects = [
            CGRect(x: 0, y: 0, width: 1512, height: 474.5),
            CGRect(x: 26, y: 74, width: 1481, height: 885),
            CGRect(x: -1920, y: 100, width: 800, height: 600),
        ]
        for rect in rects {
            let flipped = ScreenSpace.flip(rect, primaryHeight: primaryHeight)
            #expect(ScreenSpace.flip(flipped, primaryHeight: primaryHeight) == rect)
        }
    }

    /// An AppKit bottom half (flush with the Dock at the bottom) must map to a
    /// rect that ends at the Dock when measured from the top.
    @Test func flipKeepsBottomHalfAtTheBottom() {
        // Bottom half of the usable area: y = 70 (dock height), height = 492.5.
        let ns = CGRect(x: 0, y: 70, width: 1512, height: 492.5)
        let ax = ScreenSpace.flip(ns, primaryHeight: primaryHeight)
        #expect(abs(ax.minY - 517.5) < 0.001)       // top edge, measured from the screen top
        #expect(abs(ax.maxY - 1010) < 0.001)        // bottom edge rests on the dock (1080 - 70)
    }

    /// An AppKit top half (flush under the menu bar) must start just below the
    /// menu bar in AX coordinates.
    @Test func flipKeepsTopHalfAtTheTop() {
        // Top half: y = 70 + 492.5 = 562.5, height = 492.5.
        let ns = CGRect(x: 0, y: 562.5, width: 1512, height: 492.5)
        let ax = ScreenSpace.flip(ns, primaryHeight: primaryHeight)
        #expect(abs(ax.minY - 25) < 0.001)          // flush under a 25pt menu bar
        #expect(abs(ax.maxY - 517.5) < 0.001)       // meets the bottom half exactly
    }

    /// Size and X are untouched; only Y moves.
    @Test func flipPreservesSizeAndX() {
        let ns = CGRect(x: 42, y: 100, width: 800, height: 600)
        let ax = ScreenSpace.flip(ns, primaryHeight: primaryHeight)
        #expect(ax.minX == ns.minX)
        #expect(ax.width == ns.width)
        #expect(ax.height == ns.height)
    }
}
