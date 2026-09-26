import Foundation
import Testing

@testable import EarshotKit

@Suite struct SpokenLanguagesSummaryTests {
    private let english = Locale(identifier: "en")

    @Test func namesLeaveOutTheirRegionUnlessTwoShareAName() {
        #expect(Languages.summary([], locale: english) == "Any language")
        #expect(Languages.summary(["de-DE"], locale: english) == "German")
        #expect(Languages.summary(["de-DE", "en-US"], locale: english) == "German, English")
        #expect(Languages.summary(["en-US", "en-GB"], locale: english) == "English (US, GB)")
        #expect(
            Languages.summary(["en-US", "de-DE", "en-GB"], locale: english)
                == "English (US, GB) + 1")
    }

    @Test func pastTwoTheFirstAndACount() {
        #expect(
            Languages.summary(["de-DE", "en-US", "fr-FR"], locale: english) == "German + 2")
    }
}
