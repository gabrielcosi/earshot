import Foundation
import Testing

@testable import EarshotKit

@Suite struct SetupFlowTests {
    @Test func continueWalksTheStepsInOrderAndStopsAtTheLast() {
        var flow = SetupFlow()
        var visited = [flow.step]
        for _ in 0..<10 {
            flow.next()
            visited.append(flow.step)
        }
        #expect(
            visited.prefix(8) == [
                .welcome, .models, .permissions, .listening, .languages, .transcripts, .captions,
                .ready,
            ])
        #expect(flow.step == .ready)
    }

    @Test func backStopsAtTheFirstStep() {
        var flow = SetupFlow(from: .models)
        flow.back()
        #expect(flow.step == .welcome)
        #expect(flow.isFirst)
        flow.back()
        #expect(flow.step == .welcome)
    }

    @Test func skipGoesToTheLastStepFromAnywhere() {
        for step in SetupStep.allCases {
            var flow = SetupFlow(from: step)
            flow.skip()
            #expect(flow.step == .ready)
        }
    }

    /// VoiceOver reads "Step 3 of 8".
    @Test func positionCountsFromOne() {
        #expect(SetupFlow(from: .welcome).position == 1)
        #expect(SetupFlow(from: .permissions).position == 3)
        #expect(SetupFlow(from: .ready).position == 8)
        #expect(SetupFlow.count == 8)
    }
}

@Suite struct SetupLaunchTests {
    @Test func aFreshInstallShowsSetupFromTheStart() {
        let decision = SetupLaunch.atLaunch(
            done: false, started: false, hasModel: false, hasTranscripts: false)
        #expect(decision.show == .welcome)
        #expect(!decision.markDone)
    }

    /// Earshot 0.1 needed a model to do anything, so its users are done without seeing setup.
    @Test func anUpgradeWithAModelShowsNothingAndIsMarkedDone() {
        let decision = SetupLaunch.atLaunch(
            done: false, started: false, hasModel: true, hasTranscripts: false)
        #expect(decision.show == nil)
        #expect(decision.markDone)
    }

    /// Transcripts without a model: an earlier user who deleted it. Only the models step, as the
    /// launch without a model always did.
    @Test func anUpgradeWithTranscriptsButNoModelOpensAtTheModels() {
        let decision = SetupLaunch.atLaunch(
            done: false, started: false, hasModel: false, hasTranscripts: true)
        #expect(decision.show == .models)
        #expect(decision.markDone)
    }

    /// Quit midway after the download finished: the models are there, but this is no earlier
    /// user, and setup comes back.
    @Test func setupQuitMidwayComesBackEvenWithItsModels() {
        let decision = SetupLaunch.atLaunch(
            done: false, started: true, hasModel: true, hasTranscripts: false)
        #expect(decision.show == .welcome)
        #expect(!decision.markDone)
    }

    @Test func doneWithoutAModelOpensAtTheModels() {
        let decision = SetupLaunch.atLaunch(
            done: true, started: true, hasModel: false, hasTranscripts: false)
        #expect(decision.show == .models)
        #expect(!decision.markDone)
    }

    @Test func doneWithAModelShowsNothing() {
        for transcripts in [false, true] {
            let decision = SetupLaunch.atLaunch(
                done: true, started: true, hasModel: true, hasTranscripts: transcripts)
            #expect(decision.show == nil)
            #expect(!decision.markDone)
        }
    }
}

/// A process tap Earshot may not use delivers exact zeros, with no error anywhere.
@Suite struct SilenceTests {
    private func pcm(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { buffer in
            Data(buffer: UnsafeBufferPointer(start: buffer.baseAddress, count: buffer.count))
        }
    }

    @Test func exactZerosAreSilent() {
        #expect(PCM.isSilent(pcm(Array(repeating: 0, count: 16_000))))
        #expect(PCM.isSilent(Data()))
    }

    @Test func oneSampleAboveZeroIsHeard() {
        var samples = Array(repeating: Int16(0), count: 16_000)
        samples[12_345] = 1
        #expect(!PCM.isSilent(pcm(samples)))
        samples[12_345] = -1
        #expect(!PCM.isSilent(pcm(samples)))
    }
}
