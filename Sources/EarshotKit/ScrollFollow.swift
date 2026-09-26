import Foundation

/// Whether a live transcript follows new lines to the bottom, as a chat or a terminal does: pinned
/// until the reader scrolls up, pinned again at the bottom or on "Jump to latest".
///
/// A move up is the reader's when the bottom stays where it was. Everything else that moves the
/// offset up also moves the bottom: a live bar that shrinks pulls the offset back to stay within
/// the content, and lazy rows measured taller or shorter than estimated shift the content and the
/// offset together. Telling them apart by the bottom works whatever did the scrolling: trackpad,
/// wheel, scroller, or keyboard.
public struct ScrollFollow: Sendable, Equatable {
    public private(set) var pinned = true
    private var offset: Double?
    private var bottom: Double?

    public init() {}

    /// Takes the scroll view's latest geometry; true when the view should scroll to the bottom.
    /// Within `tolerance` of the bottom counts as at the bottom.
    public mutating func update(
        offset: Double, distanceFromBottom distance: Double, tolerance: Double
    )
        -> Bool
    {
        let bottom = offset + distance
        let readerMovedUp = self.offset.map { offset < $0 } == true && bottom == self.bottom
        self.offset = offset
        self.bottom = bottom
        if readerMovedUp {
            if distance > tolerance { pinned = false }
        } else if distance <= tolerance {
            pinned = true
        }
        // Less than a point hidden is nothing to scroll for.
        return pinned && !readerMovedUp && distance >= 1
    }

    /// "Jump to latest".
    public mutating func jumpToLatest() {
        pinned = true
    }
}
