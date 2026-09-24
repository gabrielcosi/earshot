import Foundation
import Testing

@testable import EarshotCapture

@Suite struct AudioSourcesTests {
    private typealias Details = AudioSources.ProcessDetails

    private let processes: [pid_t: Details] = [
        100: Details(bundleID: "com.acme.Browser", name: "Acme Browser", isApp: true, parent: 1),
        101: Details(bundleID: "com.acme.Browser.helper", name: nil, isApp: false, parent: 100),
        102: Details(
            bundleID: "com.acme.Browser.helper", name: "Helper", isApp: false, parent: 101),
        200: Details(
            bundleID: "com.apple.WebKit.GPU", name: "Acme Mail Graphics and Media", isApp: false,
            parent: 1),
        201: Details(
            bundleID: "com.apple.WebKit.GPU", name: "Acme Reader Graphics and Media",
            isApp: false, parent: 1),
        202: Details(
            bundleID: "com.apple.WebKit.GPU", name: "Acme Mailroom Graphics and Media",
            isApp: false, parent: 1),
    ]

    private let apps = [
        AudioSource(id: "com.acme.Mail", name: "Acme Mail"),
        AudioSource(id: "com.acme.Browser", name: "Acme Browser"),
    ]

    private func source(_ pid: pid_t) -> AudioSource? {
        AudioSources.source(of: pid, apps: apps) { processes[$0] }
    }

    @Test func aHelperPlaysForTheAppThatLaunchedIt() {
        #expect(source(102) == AudioSource(id: "com.acme.Browser", name: "Acme Browser"))
        #expect(source(101) == source(100))
    }

    /// A media process launchd starts is named after the app it plays for.
    @Test func aMediaProcessPlaysForTheAppItIsNamedAfter() {
        #expect(source(200) == AudioSource(id: "com.acme.Mail", name: "Acme Mail"))
    }

    /// Without a running app whose whole name starts the process's name, the process stands
    /// for itself: a shorter app name that is only a prefix of a word does not count.
    @Test func aMediaProcessNoRunningAppIsNamedForStandsForItself() {
        #expect(source(201)?.name == "Acme Reader Graphics and Media")
        #expect(source(202)?.name == "Acme Mailroom Graphics and Media")
    }

    @Test func anUnknownProcessIsNoSource() {
        #expect(source(999) == nil)
    }

    @Test func earshotIsNeverASource() {
        #expect(AudioSources.source(of: getpid(), apps: apps) { _ in nil } == nil)
    }
}
