import Foundation

/// Whether a live transcript follows new lines to the bottom, as a chat or a terminal does: pinned
/// until the reader scrolls up, pinned again at the bottom or on "Jump to latest".
///
/// A move up is the reader's. The view's own scrolls only go down, and growing content or a
/// growing live bar moves the bottom away without moving the offset, so the direction tells a
/// reader's scroll from everything else, whatever did the scrolling: trackpad, wheel, scroller,
/// or keyboard. The one move up that is not the reader's, the scroll view pulling the offset back
/// when the view grows, happens only at the bottom, within the tolerance.
public struct ScrollFollow: Sendable, Equatable {
    public private(set) var pinned = true
    private var offset: Double?

    public init() {}

    /// Takes the scroll view's latest geometry; true when the view should scroll to the bottom.
    /// Within `tolerance` of the bottom counts as at the bottom.
    public mutating func update(
        offset: Double, distanceFromBottom distance: Double, tolerance: Double
    )
        -> Bool
    {
        let movedUp = self.offset.map { offset < $0 } ?? false
        self.offset = offset
        if distance <= tolerance {
            pinned = true
        } else if movedUp {
            pinned = false
        }
        // Less than a point hidden is nothing to scroll for.
        return pinned && !movedUp && distance >= 1
    }

    /// "Jump to latest".
    public mutating func jumpToLatest() {
        pinned = true
    }
}
