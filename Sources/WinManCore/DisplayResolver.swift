import CoreGraphics

/// Resolves connected displays into `DisplayGeometry` values and answers
/// adjacency questions for multi-monitor cycling.
///
/// This is pure geometry over `DisplayGeometry`; the AppKit step of reading
/// `NSScreen` lives in the app module (`WinManEngine.currentDisplays()`).
/// Display frames use AppKit's global coordinate space (origin bottom-left).
/// A display is a "left neighbour" when its right edge is at (or just past) the
/// current display's left edge and their vertical spans overlap.
public enum DisplayResolver {

    /// The display that contains the largest portion of `frame`.
    /// Falls back to the display whose origin is closest to the frame centre
    /// when the window lies entirely off-screen (e.g. partially outside the
    /// visible desktop).
    public static func display(containing frame: CGRect,
                               from displays: [DisplayGeometry]) -> DisplayGeometry? {
        guard !displays.isEmpty else { return nil }

        var best: DisplayGeometry?
        var bestOverlap: CGFloat = 0
        for d in displays {
            let overlap = d.frame.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestOverlap {
                bestOverlap = area
                best = d
            }
        }
        if best != nil { return best }

        // No overlap at all: pick the display whose centre is closest to the
        // window's centre so we still have a sensible target.
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return displays.min { a, b in
            distanceSquared(a.frame, centre) < distanceSquared(b.frame, centre)
        }
    }

    /// The display immediately to the left of `current`, or nil.
    /// Prefers displays whose right edge is nearest to (and <=) current's left
    /// edge with vertical overlap; falls back to any vertically-overlapping
    /// display further left.
    public static func leftNeighbour(of current: DisplayGeometry,
                                     in displays: [DisplayGeometry]) -> DisplayGeometry? {
        neighbour(of: current, in: displays, direction: -1)
    }

    /// The display immediately to the right of `current`, or nil.
    public static func rightNeighbour(of current: DisplayGeometry,
                                      in displays: [DisplayGeometry]) -> DisplayGeometry? {
        neighbour(of: current, in: displays, direction: 1)
    }

    private static func neighbour(of current: DisplayGeometry,
                                  in displays: [DisplayGeometry],
                                  direction: Int) -> DisplayGeometry? {
        let currentFrame = current.frame
        let verticalOverlap = { (a: CGRect, b: CGRect) -> Bool in
            a.maxY > b.minY + 1 && a.minY < b.maxY - 1
        }

        // Candidates strictly on the requested side with vertical overlap.
        let candidates = displays.filter { d in
            guard d.frame != currentFrame else { return false }
            if direction < 0 {
                // d is to the left: its right edge is at or before current's left edge.
                return d.frame.maxX <= currentFrame.minX + 1 && verticalOverlap(d.frame, currentFrame)
            } else {
                return d.frame.minX >= currentFrame.maxX - 1 && verticalOverlap(d.frame, currentFrame)
            }
        }

        if direction < 0 {
            // Closest to the right among left-side candidates.
            return candidates.max { $0.frame.maxX < $1.frame.maxX }
        } else {
            // Closest to the left among right-side candidates.
            return candidates.min { $0.frame.minX < $1.frame.minX }
        }
    }

    /// The display to continue cycling on when there is no neighbour in
    /// `direction`: the far end of the horizontal row, so an outward press at
    /// a row end wraps around the arrangement instead of mirroring in place.
    /// With a single display that display comes back, which matches the
    /// wrap-to-self behaviour verified on Windows. Vertical keys never cycle.
    public static func wraparound(in displays: [DisplayGeometry],
                                  direction: Direction) -> DisplayGeometry? {
        guard !displays.isEmpty else { return nil }
        switch direction {
        case .left: return displays.max { $0.frame.maxX < $1.frame.maxX }   // far right end
        case .right: return displays.min { $0.frame.minX < $1.frame.minX }  // far left end
        case .up, .down: return nil
        }
    }

    /// Moves `frame` onto `target` as if the two displays were the same one:
    /// same offset from the usable area's origin, same size, clamped inside
    /// the target's usable area. Identity when the displays match.
    public static func relocate(_ frame: CGRect,
                                from origin: DisplayGeometry,
                                to target: DisplayGeometry) -> CGRect {
        guard origin.frame != target.frame else { return frame }

        let moved = CGRect(
            x: frame.minX + (target.availableFrame.minX - origin.availableFrame.minX),
            y: frame.minY + (target.availableFrame.minY - origin.availableFrame.minY),
            width: frame.width,
            height: frame.height
        )
        let a = target.availableFrame
        let x = min(max(moved.minX, a.minX), max(a.minX, a.maxX - moved.width))
        let y = min(max(moved.minY, a.minY), max(a.minY, a.maxY - moved.height))
        return CGRect(x: x, y: y, width: moved.width, height: moved.height)
    }

    private static func distanceSquared(_ a: CGRect, _ b: CGPoint) -> CGFloat {
        let dx = a.midX - b.x
        let dy = a.midY - b.y
        return dx * dx + dy * dy
    }
}
