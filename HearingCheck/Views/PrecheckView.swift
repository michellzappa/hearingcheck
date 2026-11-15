import MediaPlayer
import SwiftUI

struct PrecheckView: View {
    let kind: TestKind

    @Environment(AudioController.self) private var audio
    @Environment(SessionStore.self) private var store
    @State private var started = false

    private var baselineVolume: Float? { store.baseline?.outputVolume }

    var body: some View {
        List {
            Section {
                AudioStatusRow()
                SystemVolumeSlider()
                    .frame(height: 34)
                if let baselineVolume, abs(baselineVolume - audio.outputVolume) > 0.02 {
                    Label("Your baseline test used \(Int((baselineVolume * 100).rounded()))% volume. Set the same volume to compare results.", systemImage: "speaker.wave.2")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Output")
            } footer: {
                Text("Pick one volume (50% is a good start) and use it every time.")
            }

            Section("Channel check") {
                HStack {
                    Button("Play left") { audio.playTone(frequency: 1000, levelDBFS: -30, channel: .left) }
                    Spacer()
                    Button("Play right") { audio.playTone(frequency: 1000, levelDBFS: -30, channel: .right) }
                }
                .buttonStyle(.bordered)
                Text("Each button must play in that ear only. If not, swap the headphones or turn off Mono Audio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Before you start") {
                checklistItem("Sit in a quiet room.")
                checklistItem("Control Center → hold volume → turn Spatialize Stereo / head tracking off.")
                checklistItem("AirPods: use Noise Cancellation, not Transparency or Adaptive. Turn off Conversation Boost.")
                checklistItem("Settings → Accessibility → Audio & Visual: turn off Mono Audio, Headphone Accommodations, Balance at centre.")
                switch kind {
                case .threshold:
                    checklistItem("Tap the big button every time you hear a beep, even a faint one. Do not guess.")
                case .localization:
                    checklistItem("Keep your head still. Tap the direction the sound came from.")
                case .balance:
                    checklistItem("Judge loudness only. A tone can sound duller or brighter in one ear; ignore that.")
                }
            }

            Section {
                Button {
                    started = true
                } label: {
                    Text("Start").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!audio.headphonesConnected)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Setup")
        .onAppear { audio.start() }
        .navigationDestination(isPresented: $started) {
            switch kind {
            case .threshold(let ears, let frequencies):
                ThresholdTestView(ears: ears, frequencies: frequencies)
            case .localization(let stimulus):
                LocalizationTestView(stimulus: stimulus)
            case .balance:
                BalanceTestView()
            }
        }
    }

    private func checklistItem(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle").font(.subheadline)
    }
}

/// The system volume slider. Apps cannot set the output volume directly.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
