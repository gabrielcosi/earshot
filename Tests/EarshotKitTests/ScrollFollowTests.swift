import Foundation
import Testing

@testable import EarshotKit

@Suite struct ScrollFollowTests {
    /// One line of transcript text at the default size.
    private let line = 17.0

    /// The view's geometry: its offset, and the offset at the bottom, which moves only when the
    /// content or the view changes size.
    private func scroll(_ follow: inout ScrollFollow, _ offset: Double, bottom: Double) -> Bool {
        follow.update(offset: offset, distanceFromBottom: bottom - offset, tolerance: line)
    }

    @Test func pinnedItFollowsContentThatGrowsBelowTheView() {
        var follow = ScrollFollow()
        let followsAtRest = scroll(&follow, 0, bottom: 0)
        #expect(!followsAtRest)
        // A card arrives, or the live bar grows: the offset stays, the bottom moves away.
        let followsGrowth = scroll(&follow, 0, bottom: 120)
        #expect(followsGrowth)
        #expect(follow.pinned)
    }

    @Test func scrollingUpUnpinsAndNewLinesThenLeaveTheViewAlone() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        let followsUp = scroll(&follow, 300, bottom: 500)
        #expect(!followsUp)
        #expect(!follow.pinned)
        let followsNewLine = scroll(&follow, 300, bottom: 620)
        #expect(!followsNewLine)
    }

    /// The first few points of a scroll up stay within the tolerance; following then would pull
    /// the reader back before they could get away.
    @Test func theStartOfAScrollUpIsNotPulledBack() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        let followsFirstPoints = scroll(&follow, 495, bottom: 500)
        #expect(!followsFirstPoints)
        let followsFurtherUp = scroll(&follow, 470, bottom: 500)
        #expect(!followsFurtherUp)
        #expect(!follow.pinned)
    }

    @Test func scrollingBackToTheBottomRepins() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        _ = scroll(&follow, 300, bottom: 500)
        _ = scroll(&follow, 490, bottom: 500)
        #expect(follow.pinned)
        let followsGrowth = scroll(&follow, 490, bottom: 580)
        #expect(followsGrowth)
    }

    @Test func scrollingDownShortOfTheBottomStaysUnpinned() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        _ = scroll(&follow, 100, bottom: 500)
        let follows = scroll(&follow, 250, bottom: 500)
        #expect(!follows)
        #expect(!follow.pinned)
    }

    @Test func jumpingToTheLatestRepinsAndFollows() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        _ = scroll(&follow, 100, bottom: 500)
        follow.jumpToLatest()
        #expect(follow.pinned)
        let followsAfterJump = scroll(&follow, 100, bottom: 500)
        #expect(followsAfterJump)
    }

    /// When the live bar goes away the view grows, and the scroll view pulls the offset back
    /// to stay within the content: a move up that is not the reader's.
    @Test func theOffsetClampedAtTheBottomKeepsItPinned() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        let followsClamp = scroll(&follow, 440, bottom: 440)
        #expect(!followsClamp)
        #expect(follow.pinned)
    }

    /// A new card arrives in the same pass as a row above is measured shorter than estimated:
    /// the scroll view moves the offset up with the content, which is not the reader's doing.
    @Test func aCardArrivingAsRowsAboveAreMeasuredIsFollowed() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        let followsCard = scroll(&follow, 460, bottom: 560)
        #expect(followsCard)
        #expect(follow.pinned)
    }

    /// After "Jump to latest", rows measured on the way move the offset up before it reaches the
    /// bottom; the jump still holds.
    @Test func rowsMeasuredBeforeAJumpLandsDoNotUnpin() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        _ = scroll(&follow, 100, bottom: 500)
        follow.jumpToLatest()
        let followsCorrection = scroll(&follow, 60, bottom: 480)
        #expect(followsCorrection)
        #expect(follow.pinned)
    }

    /// The same correction without a jump leaves a reader who scrolled up where they are.
    @Test func rowsMeasuredWhileUnpinnedLeaveTheViewAlone() {
        var follow = ScrollFollow()
        _ = scroll(&follow, 500, bottom: 500)
        _ = scroll(&follow, 100, bottom: 500)
        let followsCorrection = scroll(&follow, 60, bottom: 480)
        #expect(!followsCorrection)
        #expect(!follow.pinned)
    }
}
