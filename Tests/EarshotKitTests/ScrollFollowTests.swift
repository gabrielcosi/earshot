import Foundation
import Testing

@testable import EarshotKit

@Suite struct ScrollFollowTests {
    /// One line of transcript text at the default size.
    private let line = 17.0

    private func scroll(_ follow: inout ScrollFollow, _ offset: Double, _ distance: Double) -> Bool
    {
        follow.update(offset: offset, distanceFromBottom: distance, tolerance: line)
    }

    @Test func pinnedItFollowsContentThatGrowsBelowTheView() {
        var follow = ScrollFollow()
        let followsAtRest = scroll(&follow, 0, 0)
        #expect(!followsAtRest)
        // A card arrives, or the live bar grows: the offset stays, the bottom moves away.
        let followsGrowth = scroll(&follow, 0, 120)
        #expect(followsGrowth)
        #expect(follow.pinned)
    }

    @Test func scrollingUpUnpinsAndNewLinesThenLeaveTheViewAlone() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        let followsUp = scroll(&follow, 300, 200)
        #expect(!followsUp)
        #expect(!follow.pinned)
        let followsNewLine = scroll(&follow, 300, 320)
        #expect(!followsNewLine)
    }

    /// The first few points of a scroll up stay within the tolerance; following then would pull
    /// the reader back before they could get away.
    @Test func theStartOfAScrollUpIsNotPulledBack() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        let followsFirstPoints = scroll(&follow, 495, 5)
        #expect(!followsFirstPoints)
        let followsFurtherUp = scroll(&follow, 470, 30)
        #expect(!followsFurtherUp)
        #expect(!follow.pinned)
    }

    @Test func scrollingBackToTheBottomRepins() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        _ = scroll(&follow, 300, 200)
        _ = scroll(&follow, 490, 10)
        #expect(follow.pinned)
        let followsGrowth = scroll(&follow, 490, 90)
        #expect(followsGrowth)
    }

    @Test func scrollingDownShortOfTheBottomStaysUnpinned() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        _ = scroll(&follow, 100, 400)
        let follows = scroll(&follow, 250, 250)
        #expect(!follows)
        #expect(!follow.pinned)
    }

    @Test func jumpingToTheLatestRepinsAndFollows() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        _ = scroll(&follow, 100, 400)
        follow.jumpToLatest()
        #expect(follow.pinned)
        let followsAfterJump = scroll(&follow, 100, 400)
        #expect(followsAfterJump)
    }

    /// When the live bar goes away the view grows, and the scroll view pulls the offset back
    /// to stay within the content: a move up that is not the reader's.
    @Test func theOffsetClampedAtTheBottomKeepsItPinned() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, 0)
        let followsClamp = scroll(&follow, 440, 0)
        #expect(!followsClamp)
        #expect(follow.pinned)
    }
}
