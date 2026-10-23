import CoreGraphics
import Testing
import WinManCore

/// Display adjacency, wrap-around targeting, and cross-display relocation.
@Suite("Display resolver")
struct DisplayResolverTests {

    private let left = DisplayGeometry(
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1010)
    )
    private let middle = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: 0, y: 0, width: 1920, height: 1010)
    )
    private let right = DisplayGeometry(
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1010)
    )

    // MARK: - Wrap-around

    @Test func wraparoundGoesToTheFarEndOfTheRow() {
        let row = [left, middle, right]
        #expect(DisplayResolver.wraparound(in: row, direction: .right) == left)
        #expect(DisplayResolver.wraparound(in: row, direction: .left) == right)
    }

    @Test func wraparoundOnASingleDisplayReturnsItself() {
        #expect(DisplayResolver.wraparound(in: [middle], direction: .left) == middle)
        #expect(DisplayResolver.wraparound(in: [middle], direction: .right) == middle)
    }

    @Test func wraparoundNeverAppliesVertically() {
        #expect(DisplayResolver.wraparound(in: [left, right], direction: .up) == nil)
        #expect(DisplayResolver.wraparound(in: [left, right], direction: .down) == nil)
    }

    @Test func neighboursFollowTheRowOrder() {
        let row = [left, middle, right]
        #expect(DisplayResolver.leftNeighbour(of: middle, in: row) == left)
        #expect(DisplayResolver.rightNeighbour(of: middle, in: row) == right)
        #expect(DisplayResolver.leftNeighbour(of: left, in: row) == nil)
        #expect(DisplayResolver.rightNeighbour(of: right, in: row) == nil)
    }

    // MARK: - Relocation

    @Test func relocateKeepsRelativePlacementAndSize() {
        // Near the top-right of the middle display's usable area.
        let frame = CGRect(x: 1400, y: 700, width: 400, height: 300)
        let moved = DisplayResolver.relocate(frame, from: middle, to: right)
        #expect(moved.size == frame.size)
        #expect(abs(moved.minX - 3320) < 0.001)   // 1920 + 1400
        #expect(abs(moved.minY - frame.minY) < 0.001)
    }

    @Test func relocateClampsInsideTheUsableArea() {
        // Right edge would overflow the target by 300pt.
        let frame = CGRect(x: 1600, y: 700, width: 400, height: 300)
        let moved = DisplayResolver.relocate(frame, from: middle, to: right)
        #expect(moved.maxX <= right.availableFrame.maxX + 0.001)
        #expect(moved.size == frame.size)
    }

    @Test func relocateOnTheSameDisplayIsIdentity() {
        let frame = CGRect(x: 302, y: 190, width: 907, height: 569)
        #expect(DisplayResolver.relocate(frame, from: middle, to: middle) == frame)
    }
}
