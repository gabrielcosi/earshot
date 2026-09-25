import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranslationDisplayTests {
    @Test func eachModeShowsItsText() {
        let text = { (mode: TranslationDisplay) in
            mode.text(original: "Hallo", translation: "Hello")
        }
        #expect(text(.original) == ("Hallo", nil))
        #expect(text(.both) == ("Hallo", "Hello"))
        #expect(text(.translation) == ("Hello", nil))
    }

    /// A line already in the target language has no translation; it still shows.
    @Test func aLineWithNoTranslationShowsItsOriginalInEveryMode() {
        for mode in TranslationDisplay.allCases {
            #expect(mode.text(original: "Hello", translation: nil) == ("Hello", nil))
        }
    }
}

@Suite struct TranscriptTextSizeTests {
    @Test func stepsFollowDynamicTypeFromTheDefault() {
        #expect(TranscriptTextSize.larger(than: 17) == 19)
        #expect(TranscriptTextSize.larger(than: 23) == 28)
        #expect(TranscriptTextSize.smaller(than: 17) == 16)
        #expect(TranscriptTextSize.smaller(than: 14) == 13)
    }

    @Test func stepsStopAtTheEnds() {
        #expect(TranscriptTextSize.smaller(than: 13) == 13)
        #expect(TranscriptTextSize.larger(than: 53) == 53)
    }

    /// A stored size from elsewhere, such as a hand-edited default, lands on the nearest step.
    @Test func aSizeOffTheStepsIsClampedToTheNearest() {
        #expect(TranscriptTextSize.clamped(2) == 13)
        #expect(TranscriptTextSize.clamped(200) == 53)
        #expect(TranscriptTextSize.clamped(18.4) == 19)
        #expect(TranscriptTextSize.clamped(17) == 17)
    }

    @Test func steppingFromAnOffStepSizeGoesToTheNeighbouringSteps() {
        #expect(TranscriptTextSize.larger(than: 18) == 19)
        #expect(TranscriptTextSize.smaller(than: 18) == 17)
    }
}
