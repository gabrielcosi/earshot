import EarshotCapture
import EarshotKit
import SwiftUI

/// The controls under each page's text: the same settings as in Settings and the menu.
struct SetupControls: View {
    let step: SetupStep
    @Environment(SetupModel.self) private var setup
    @Environment(SessionController.self) private var controller

    var body: some View {
        VStack(spacing: step == .permissions ? 14 : 10) {
            HStack(spacing: 10) { controls }
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .font(.system(size: 14, weight: .bold))
                .tint(SetupColor.ink)
            note
                .font(.system(size: 12))
                .foregroundStyle(SetupColor.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var controls: some View {
        @Bindable var preferences = controller.preferences
        switch step {
        case .welcome, .ready: EmptyView()
        case .models: modelControls
        case .permissions: permissionControls
        case .listening:
            PillPicker(
                title: String(localized: "Listening with"),
                options: [
                    (false, String(localized: "Headphones")), (true, String(localized: "Speakers")),
                ],
                selection: $preferences.cancelSpeakerEcho
            )
            .disabled(!preferences.useMicrophone || controller.state != .idle)
        case .languages:
            LabeledContent("They speak") { SpokenLanguagesMenu().fixedSize() }
            LabeledContent("Translate into") { TranslationMenu().fixedSize() }
        case .transcripts:
            Toggle("Keep audio", isOn: $preferences.keepAudio)
                .toggleStyle(PillSwitchStyle())
            PillPicker(
                title: String(localized: "Audio Quality"),
                options: [
                    (AudioQuality.low, String(localized: "Low")),
                    (.medium, String(localized: "Medium")), (.high, String(localized: "High")),
                ], selection: $preferences.keepAudioQuality
            )
            .disabled(!preferences.keepAudio)
        case .captions:
            Toggle("Floating captions", isOn: $preferences.showsCaptions)
                .toggleStyle(PillSwitchStyle())
        }
    }

    @ViewBuilder private var modelControls: some View {
        let library = controller.library
        switch setup.download(in: library) {
        case .notStarted:
            Button {
                setup.startDownload(in: library)
            } label: {
                pillTitle("Download")
            }
            .buttonStyle(.borderedProminent)
        case .downloading:
            Button {
                setup.cancelDownload(in: library)
            } label: {
                pillTitle("Cancel")
            }
            .buttonStyle(.bordered)
        case .verifying, .done:
            EmptyView()
        case .failed, .noSpace:
            Button {
                setup.startDownload(in: library)
            } label: {
                pillTitle("Try Again")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// The microphone above the Mac's sound, each centred like the other pages' controls. The
    /// microphone tile's check already says it is allowed, so the switch stands alone.
    private var permissionControls: some View {
        VStack(spacing: 14) {
            microphoneControl
            dingControl
        }
    }

    @ViewBuilder private var microphoneControl: some View {
        switch setup.microphone {
        case .undetermined:
            Button {
                Task { await setup.allowMicrophone(controller.preferences) }
            } label: {
                pillTitle("Allow Microphone")
            }
            .buttonStyle(.bordered)
        case .allowed:
            @Bindable var preferences = controller.preferences
            Toggle("Include my microphone", isOn: $preferences.useMicrophone)
                .toggleStyle(PillSwitchStyle())
                .disabled(controller.state != .idle)
        case .denied:
            Button {
                ProblemFix.openPrivacySettings(.microphone)
            } label: {
                pillTitle("Open Microphone Settings")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var dingControl: some View {
        switch setup.ding {
        case .idle:
            dingButton("Play the Ding")
        case .listening:
            Button {
            } label: {
                Label {
                    pillTitle("Listening…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .heard:
            status("Earshot Heard It")
        case .notHeard:
            HStack(spacing: 14) {
                dingButton("Try Again")
                Button("Open System Settings") { ProblemFix.openPrivacySettings(.systemAudio) }
                    .buttonStyle(.link)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(SetupColor.me)
            }
        }
    }

    private func dingButton(_ title: LocalizedStringKey) -> some View {
        Button {
            Task { await setup.playDing(controller) }
        } label: {
            pillTitle(title)
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.state != .idle)
    }

    /// Ink text, for contrast on the sky; green only on the check.
    private func status(_ title: LocalizedStringKey) -> some View {
        Label {
            Text(title).foregroundStyle(SetupColor.ink)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SetupColor.done)
        }
    }

    @ViewBuilder private var note: some View {
        let preferences = controller.preferences
        switch step {
        case .models: modelNote
        case .permissions: permissionNote
        case .listening where !preferences.useMicrophone:
            Text("Turn on Include my microphone on the previous step to use this.")
        case .listening where controller.state != .idle:
            Text("You can change this once Earshot stops listening.")
        case .transcripts where preferences.keepAudio:
            Text(
                "Keeps about \(preferences.keepAudioQuality.megabytesPerHour) MB of audio an hour with each transcript."
            )
        default: EmptyView()
        }
    }

    @ViewBuilder private var modelNote: some View {
        switch setup.download(in: controller.library) {
        case .downloading:
            Text("You can carry on while it downloads.")
        case .failed:
            Text("The download stopped. Check your internet connection and try again.")
        case .noSpace(let bytes):
            Text(
                "Earshot needs \(bytes.formatted(.byteCount(style: .file))) of free space. Free up some space, then try again."
            )
        default: EmptyView()
        }
    }

    @ViewBuilder private var permissionNote: some View {
        if setup.ding == .notHeard {
            Text(
                "Earshot didn't hear the ding. Check your Mac's sound is on and that Earshot is allowed in System Settings, then try again."
            )
        } else if controller.state != .idle, setup.ding != .heard {
            Text("Earshot can play the ding once it stops listening.")
        } else if setup.microphone == .denied {
            if setup.microphoneTurnedOff {
                Text(
                    "Earshot will write down only what your Mac plays. To use your microphone later, allow Earshot in System Settings, then turn on Include my microphone."
                )
            } else {
                Text("Your microphone is turned off for Earshot in System Settings.")
            }
        }
    }
}
