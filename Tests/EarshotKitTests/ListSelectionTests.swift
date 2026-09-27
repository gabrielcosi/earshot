import Testing

@testable import EarshotKit

@Suite struct ListSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func theRowAfterTheDeletedOnesIsSelected() {
        #expect(ListSelection.next(afterDeleting: ["b"], in: order) == "c")
        #expect(ListSelection.next(afterDeleting: ["b", "d"], in: order) == "e")
        #expect(ListSelection.next(afterDeleting: ["a", "b", "c"], in: order) == "d")
    }

    @Test func atTheEndTheRowBeforeIsSelected() {
        #expect(ListSelection.next(afterDeleting: ["e"], in: order) == "d")
        #expect(ListSelection.next(afterDeleting: ["b", "d", "e"], in: order) == "c")
    }

    @Test func nothingIsSelectedWhenNothingIsLeft() {
        #expect(ListSelection.next(afterDeleting: Set(order), in: order) == nil)
        #expect(ListSelection.next(afterDeleting: ["z"], in: order) == nil)
    }
}
