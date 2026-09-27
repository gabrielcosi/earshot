import EarshotCapture
import EarshotKit
import SwiftUI

/// The first-run setup: one idea per page, each with its own small scene, over a sky that changes
/// colour with the page. Every choice it offers is the same setting as in Settings and the menu,
/// shown as it is now; the scenes only illustrate them. Closing the window finishes setup;
/// quitting midway brings it back at the next launch.
struct SetupWindow: View {
    @Environment(SetupModel.self) private var setup
    @Environment(SessionController.self) private var controller
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var headingFocused: Bool
    @FocusState private var primaryFocused: Bool

    /// The window: the design's 580-point width, and its heights for the title bar, stage,
    /// copy, and footer, plus room under the controls for the tallest page's: step 3 with its
    /// microphone switch and the note when the ding was not heard. The page is drawn from the
    /// window's top edge, with the traffic lights and Skip over its first 40 points.
    private static let size = CGSize(width: 580, height: 630)
    /// The toolbar's height. The window adds it to the page's, even with the page drawn under
    /// the toolbar, so the page declares that much less.
    @State private var titleBar: CGFloat = 0

    var body: some View {
        let step = setup.flow.step
        VStack(spacing: 0) {
            ZStack {
                scene(step)
                    .id(step)
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            }
            .frame(height: 270)
            .clipped()
            // Illustrations only; the download's progress is the one thing VoiceOver needs here.
            .accessibilityHidden(step != .models)
            copy(step)
            SetupControls(step: step)
                .frame(maxHeight: .infinity)
            footer(step)
        }
        .padding(.top, 40)
        .frame(width: Self.size.width, height: Self.size.height)
        .frame(height: Self.size.height - titleBar, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            Color.clear
                // Once the window has shrunk by it, the inset reads 0: the largest is the one.
                .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) {
                    titleBar = max(titleBar, $0)
                }
        }
        .fontDesign(.rounded)
        .foregroundStyle(SetupColor.ink)
        .environment(\.setupAnimates, animates)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .setupSpring(0.6), value: step)
        // The window's background is outside this view's environment: it is told directly.
        .containerBackground(for: .window) { SetupBackground(step: step, animates: animates) }
        .toolbar {
            ToolbarSpacer(.flexible)
            if step != .ready {
                ToolbarItem {
                    Button("Skip") { setup.flow.skip() }
                        .buttonStyle(.plain)
                        // At least 4.5:1 on the sky's palest and brightest corners.
                        .foregroundStyle(SetupColor.ink.opacity(contrast == .increased ? 1 : 0.7))
                        .font(.system(size: 13))
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .windowMinimizeBehavior(.disabled)
        .onAppear {
            controller.preferences.openWindows += 1
            SetupModel.markStarted()
            setup.refreshMicrophone()
            primaryFocused = true
        }
        .onDisappear {
            controller.preferences.openWindows -= 1
            if !setup.quitting { SetupModel.markDone() }
        }
        .defaultFocus($primaryFocused, true)
        .onChange(of: step) {
            headingFocused = true
            primaryFocused = true
            if step == .ready { SetupModel.markDone() }
        }
        .onChange(of: setup.download(in: controller.library)) { old, new in
            switch new {
            case .done where old != .done:
                AccessibilityNotification.Announcement("Speech models are ready").post()
            case .failed where old != .failed:
                AccessibilityNotification.Announcement("The download stopped").post()
            case .noSpace where old != new:
                AccessibilityNotification.Announcement(
                    "Not enough free space for the speech models."
                ).post()
            default: break
            }
        }
        // Permissions change in System Settings, and the page follows when the user comes back.
        .onChange(of: appearsActive) { if appearsActive { setup.refreshMicrophone() } }
    }

    /// Scenes loop only while the window is frontmost and Reduce Motion is off.
    private var animates: Bool { !reduceMotion && appearsActive }

    @ViewBuilder private func scene(_ step: SetupStep) -> some View {
        let preferences = controller.preferences
        switch step {
        case .welcome: WelcomeScene()
        case .models: ModelsScene(download: setup.download(in: controller.library))
        case .permissions:
            PermissionsScene(microphoneAllowed: setup.microphone == .allowed, ding: setup.ding)
        case .listening: ListeningScene(speakers: preferences.cancelSpeakerEcho)
        case .languages: LanguagesScene()
        case .transcripts:
            TranscriptsScene(
                keepsAudio: preferences.keepAudio,
                megabytesPerHour: preferences.keepAudioQuality.megabytesPerHour)
        case .captions: CaptionsScene(showsCaptions: preferences.showsCaptions)
        case .ready:
            if controller.library.selection == nil, !isDownloading {
                ReadyScene(
                    title: "Download Speech Models", systemImage: "arrow.down.circle",
                    enabled: true, status: nil
                ) { setup.flow = SetupFlow(from: .models) }
            } else {
                ReadyScene(
                    title: "Start Listening", systemImage: "record.circle", enabled: canStart,
                    status: readyStatus, action: startListening)
            }
        }
    }

    private func copy(_ step: SetupStep) -> some View {
        VStack(spacing: 8) {
            heading(step)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue("Step \(setup.flow.position) of \(SetupFlow.count)")
                .accessibilityFocused($headingFocused)
            message(step)
                .font(.system(size: 15))
                .foregroundStyle(SetupColor.mute)
                .lineSpacing(3)
                .frame(maxWidth: 360)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 44)
        .padding(.top, 6)
        .frame(height: 118, alignment: .top)
        .id(step)
        .transition(.opacity)
    }

    private func heading(_ step: SetupStep) -> Text {
        switch step {
        case .welcome: Text("Earshot writes down what you hear")
        case .models: Text("Teach Earshot to listen")
        case .permissions: Text("Let Earshot hear")
        case .listening: Text("Headphones or speakers?")
        case .languages: Text("Speaks your language")
        case .transcripts: Text("Every word, saved as you go")
        case .captions: Text("Subtitles for your calls")
        case .ready: Text("You're all set!")
        }
    }

    private func message(_ step: SetupStep) -> Text {
        switch step {
        case .welcome:
            Text(
                "Calls, videos, podcasts. Earshot turns the talking into text you can read and keep. What it hears stays on your Mac."
            )
        case .models:
            Text(
                "A one-time download of about \(SetupModel.roundedSize(in: controller.library).formatted(.byteCount(style: .file))) from Hugging Face. After that, Earshot understands speech right on your Mac, even without the internet."
            )
        case .permissions:
            Text(
                "Your Mac asks before Earshot can hear: once for your microphone, and once for the sound your Mac plays. Earshot plays a little ding to make sure it works."
            )
        case .listening:
            Text(
                "With speakers, your microphone also picks up the call. Earshot removes that echo, so nothing is written down twice."
            )
        case .languages:
            Text(
                "Tell Earshot which languages people speak. It can translate what they say into yours."
            )
        case .transcripts:
            Text(
                "Each line is saved the moment it's said, so nothing gets lost. Want to hear it again later? Keep the audio too."
            )
        case .captions:
            Text(
                "Turn on floating captions and read along during any call, even in full screen. People see them if you share your whole screen."
            )
        case .ready:
            Text(
                "Earshot lives up here in your menu bar. Click the ear and choose Start Listening, or press ⌘N in Earshot's window."
            )
        }
    }

    private func footer(_ step: SetupStep) -> some View {
        HStack(spacing: 8) {
            PageDots(position: setup.flow.position)
            Spacer()
            Button {
                setup.flow.back()
            } label: {
                pillTitle("Back")
            }
            .buttonStyle(.bordered)
            .disabled(setup.flow.isFirst)
            primary(step)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focused($primaryFocused)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .font(.system(size: 14, weight: .bold))
        .tint(SetupColor.ink)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    @ViewBuilder private func primary(_ step: SetupStep) -> some View {
        if step != .ready {
            Button {
                setup.flow.next()
            } label: {
                pillTitle("Continue")
            }
        } else {
            // Finishes setup without starting anything; the red button above starts.
            Button {
                SetupModel.markDone()
                dismissWindow(id: "setup")
            } label: {
                pillTitle("Close")
            }
        }
    }

    /// A model to listen with, nothing already running, and the ding not being checked: the
    /// ding would be transcribed.
    private var canStart: Bool {
        controller.library.selection != nil
            && StartListening(
                controller: controller, navigation: navigation, openWindow: openWindow
            ).isPossible
    }

    private var isDownloading: Bool {
        switch setup.download(in: controller.library) {
        case .downloading, .verifying: true
        default: false
        }
    }

    /// Why step 8's Start Listening is off: the models still downloading, a session running,
    /// or the ding being checked.
    private var readyStatus: Text? {
        switch setup.download(in: controller.library) {
        case .downloading(let fraction):
            Text(
                "Still downloading, \(fraction.formatted(.percent.precision(.fractionLength(0))))")
        case .verifying: Text("Almost ready…")
        default:
            if controller.state != .idle {
                Text("Earshot is already listening.")
            } else if controller.checkingSystemAudio {
                Text("Checking the ding…")
            } else {
                nil
            }
        }
    }

    /// Setup closes first: its window is done, and the session opens its own.
    private func startListening() {
        let start = StartListening(
            controller: controller, navigation: navigation, openWindow: openWindow,
            dismissWindow: dismissWindow)
        dismissWindow(id: "setup")
        Task { await start() }
    }
}

/// The design's buttons have bold titles; a bordered button's own font sets only the size.
func pillTitle(_ title: LocalizedStringKey) -> Text {
    Text(title).fontWeight(.bold)
}
