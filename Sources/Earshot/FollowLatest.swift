import EarshotKit
import SwiftUI

extension View {
    /// Keeps a live transcript at its latest line until the reader scrolls up, with a button
    /// back down meanwhile. `lineHeight` is the tolerance for being at the bottom: a reader who
    /// stops within one line of it meant the bottom.
    func followsLatest(_ active: Bool, startsAtBottom: Bool, lineHeight: Double) -> some View {
        modifier(
            FollowLatest(active: active, lineHeight: lineHeight, startsAtBottom: startsAtBottom))
    }
}

private struct FollowLatest: ViewModifier {
    let active: Bool
    let lineHeight: Double
    @State private var position: ScrollPosition
    @State private var follow = ScrollFollow()

    init(active: Bool, lineHeight: Double, startsAtBottom: Bool) {
        self.active = active
        self.lineHeight = lineHeight
        _position = State(initialValue: ScrollPosition(edge: startsAtBottom ? .bottom : .top))
    }

    /// The offset, and how far the content runs past the view. Content scrolls under the live
    /// bar, but SwiftUI's `containerSize` is already the height above it. Measured on a 400 pt
    /// view: 356 pt with a one-line bar and 336 pt with two, with `contentInsets.bottom` 44 and 64.
    /// So contentSize − (offset + containerSize) is 0 at the bottom (2720 − (2384 + 336)), and
    /// adding the inset as well would count the bar twice. A bar that grows shrinks
    /// `containerSize`, which moves the bottom away and re-scrolls.
    private struct Geometry: Equatable {
        let offset: Double
        let belowView: Double
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            // SwiftUI requests another layout pass whenever this value changes, even when the
            // action does nothing (ScrollActionDispatcher in AppKit's layout-loop log): a saved
            // page renamed while open looped through it until AppKit crashed the app. So a page
            // not listening reports nil, which never changes, and a listening one whole points.
            .onScrollGeometryChange(for: Geometry?.self) { geometry in
                guard active else { return nil }
                return Geometry(
                    offset: geometry.contentOffset.y.rounded(),
                    belowView: (geometry.contentSize.height
                        - (geometry.contentOffset.y + geometry.containerSize.height)).rounded())
            } action: { _, geometry in
                guard let geometry else { return }
                if follow.update(
                    offset: geometry.offset, distanceFromBottom: geometry.belowView,
                    tolerance: lineHeight)
                {
                    position.scrollTo(edge: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if active, !follow.pinned {
                    // Not animated: an animated scroll crosses lazy rows that are measured on the
                    // way, and their corrections move the offset up as a reader would.
                    Button("Jump to Latest", systemImage: "arrow.down") {
                        follow.jumpToLatest()
                        position.scrollTo(edge: .bottom)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .help("Jump to the latest line")
                    .padding(16)
                }
            }
    }
}
