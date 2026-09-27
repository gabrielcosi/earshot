import SwiftUI

// MARK: 5. Languages

/// A speech bubble flips like a card from what was said to its translation.
struct LanguagesScene: View {
    @Environment(\.setupAnimates) private var animates
    @State private var pair = 0
    @State private var turned = false

    private struct Pair {
        let language: LocalizedStringKey
        let said: String
        let meant: LocalizedStringKey
    }

    private static let pairs = [
        Pair(language: "German", said: "Hallo! Wie geht's?", meant: "Hi! How are you?"),
        Pair(language: "Spanish", said: "¿Vamos a la playa?", meant: "Shall we go to the beach?"),
        Pair(language: "German", said: "Bis morgen!", meant: "See you tomorrow!"),
    ]

    var body: some View {
        let pair = Self.pairs[pair]
        FlipCard(
            angle: turned ? 180 : 0,
            front: side(pair.language, Text(verbatim: pair.said), colour: SetupColor.first),
            back: side("English", Text(pair.meant), colour: SetupColor.third)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animates) {
            guard animates else {
                (self.pair, turned) = (0, true)
                return
            }
            try? await play()
        }
    }

    private func play() async throws {
        var next = 0
        while true {
            withAnimation(.setupSpring(0.8)) { turned = false }
            try await beat(700)
            pair = next
            try await beat(1500)
            withAnimation(.setupSpring(0.8)) { turned = true }
            try await beat(2200)
            next = (next + 1) % Self.pairs.count
        }
    }

    private func side(_ language: LocalizedStringKey, _ text: Text, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language)
                .font(.system(size: 12, weight: .heavy))
                .textCase(.uppercase)
                .tracking(0.7)
                .opacity(0.7)
            text.font(.system(size: 22, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(width: 250, height: 110, alignment: .leading)
        .background(
            colour,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 26, bottomLeadingRadius: 8, bottomTrailingRadius: 26,
                topTrailingRadius: 26))
    }

    /// Turns about its vertical axis, showing whichever face is towards the viewer: SwiftUI has
    /// no back-face hiding, so each face shows only on its half of the turn.
    private struct FlipCard<Front: View, Back: View>: View, Animatable {
        var angle: Double
        let front: Front
        let back: Back

        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }

        var body: some View {
            ZStack {
                front.opacity(angle < 90 ? 1 : 0)
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(angle < 90 ? 0 : 1)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
    }
}

// MARK: 6. Transcripts

/// Lines write themselves into a notebook, and the audio clips on when Keep audio is on.
struct TranscriptsScene: View {
    let keepsAudio: Bool
    let megabytesPerHour: Int
    @Environment(\.setupAnimates) private var animates
    /// Bars drawn so far, across all rows.
    @State private var drawn = 0
    @State private var finished = false

    private static let rows: [(speaker: Int, widths: [Double])] = [
        (1, [0.9, 0.6]), (2, [1, 0.8, 0.4]), (1, [0.7]), (2, [0.95, 0.55]),
    ]
    private static let bars = rows.map(\.widths.count).reduce(0, +)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                let first = Self.rows.prefix(index).map(\.widths.count).reduce(0, +)
                if drawn > first {
                    HStack(alignment: .top, spacing: 8) {
                        SpeakerBadge(number: row.speaker)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(row.widths.enumerated()), id: \.offset) { bar, width in
                                Bar(width: drawn > first + bar ? width : 0)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 300, height: 200, alignment: .topLeading)
        .setupCard()
        .overlay(alignment: .bottomTrailing) {
            voice
                .rotationEffect(.degrees(-4))
                .reveal(keepsAudio && finished, scale: 0.001, angle: -4)
                .offset(x: 16, y: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animates) {
            guard animates else {
                (drawn, finished) = (Self.bars, true)
                return
            }
            try? await play()
        }
    }

    private func play() async throws {
        while true {
            (drawn, finished) = (0, false)
            for bar in 1...Self.bars {
                try await beat(60)
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)) { drawn = bar }
                try await beat(420)
            }
            try await beat(500)
            finished = true
            try await beat(2800)
        }
    }

    private var voice: some View {
        HStack(spacing: 8) {
            VoiceBars()
            Text("Audio · \(megabytesPerHour) MB an hour")
        }
        .font(.system(size: 12, weight: .heavy))
        .foregroundStyle(SetupColor.ground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SetupColor.ink, in: .capsule)
        .fixedSize()
    }

    private struct Bar: View {
        let width: Double

        var body: some View {
            GeometryReader { space in
                Capsule()
                    .fill(SetupColor.line)
                    .frame(width: space.size.width * width)
            }
            .frame(height: 9)
        }
    }

    /// Four level bars bouncing out of step.
    private struct VoiceBars: View {
        @Environment(\.setupAnimates) private var animates

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach([0, -0.3, -0.6, -0.15], id: \.self) { offset in
                        let phase = (time + offset).truncatingRemainder(dividingBy: 1)
                        Capsule()
                            .frame(width: 3, height: 14 * (0.4 + 0.6 * sin(.pi * phase)))
                    }
                }
                .frame(height: 14)
            }
        }
    }
}

// MARK: 7. Captions

/// Subtitles over a video call, there when the captions overlay is on.
struct CaptionsScene: View {
    let showsCaptions: Bool
    @Environment(\.setupAnimates) private var animates
    @State private var line = 1
    @State private var lineShown = true

    private static let lines: [(said: String, meant: LocalizedStringKey)] = [
        ("¿Tenemos todo para mañana?", "Do we have everything for tomorrow?"),
        ("Sí, solo falta la tarta.", "Yes, we just need the cake."),
    ]

    var body: some View {
        let colours = SetupColor.speakers
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                tile(colours[0])
                tile(colours[1])
            }
            GridRow {
                tile(colours[2])
                tile(colours[3])
            }
        }
        .padding(8)
        .frame(width: 330, height: 200)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x4A3530), Color(hex: 0x243048)], startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 18)
        )
        .overlay(alignment: .bottom) {
            subtitles
                .offset(y: -14)
                .reveal(showsCaptions, offset: CGSize(width: 0, height: 20))
        }
        .clipShape(.rect(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animates) {
            guard animates else { return }
            lineShown = true
            while !Task.isCancelled {
                try? await beat(2600)
                withAnimation(.easeIn(duration: 0.2)) { lineShown = false }
                try? await beat(200)
                guard !Task.isCancelled else { break }
                line = (line + 1) % Self.lines.count
                withAnimation(.easeOut(duration: 0.2)) { lineShown = true }
            }
            lineShown = true
        }
    }

    private func tile(_ colour: Color) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.07))
            .overlay { Circle().fill(colour).frame(width: 40, height: 40) }
    }

    private var subtitles: some View {
        let line = Self.lines[line]
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(Text("Speaker 1").bold().foregroundStyle(Color(hex: 0xFFB38A))) \(line.said)")
            Text(line.meant).foregroundStyle(Color(hex: 0x7FE3C8))
        }
        // The old line fades out before the new one fades in: the two never overlap.
        .opacity(lineShown ? 1 : 0)
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 330 * 0.86, alignment: .leading)
        .background(Color(hex: 0x0F0F12, alpha: 0.78), in: .rect(cornerRadius: 12))
    }
}
