import SwiftUI

struct LocalizationTestView: View {
    let stimulus: Stimulus

    @Environment(AudioController.self) private var audio
    @Environment(SessionStore.self) private var store
    @State private var runner: LocalizationRunner?
    @State private var savedSession: TestSession?

    var body: some View {
        Group {
            if let savedSession {
                SessionDetailView(session: savedSession)
            } else if let runner {
                content(runner)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard runner == nil else { return }
            runner = LocalizationRunner(audio: audio, stimulus: stimulus)
        }
    }

    @ViewBuilder
    private func content(_ runner: LocalizationRunner) -> some View {
        VStack(spacing: 20) {
            Text("Trial \(min(runner.trialIndex + 1, runner.count)) of \(runner.count)")
                .font(.headline)

            DirectionDial(
                enabled: runner.awaitingAnswer,
                feedback: runner.awaitingAnswer ? nil : runner.lastAnswer
            ) { runner.answer($0) }
            .frame(width: 320, height: 320)

            if let last = runner.lastAnswer, !runner.awaitingAnswer {
                Text(last.target == last.response
                     ? "Correct"
                     : "It came from \(DirectionDial.name(last.target))")
                    .foregroundStyle(last.target == last.response ? .green : .orange)
            }

            if runner.finished {
                Button("See results") { save(runner) }
                    .buttonStyle(.borderedProminent)
            } else if runner.awaitingAnswer {
                Button("Replay") { runner.play() }
                    .buttonStyle(.bordered)
            } else {
                Button(runner.trialIndex == 0 ? "Play first sound" : "Next sound") { runner.play() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!audio.headphonesConnected)
            }
        }
        .padding()
        .navigationTitle(stimulus.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ runner: LocalizationRunner) {
        guard savedSession == nil else { return }
        let session = TestSession(outputVolume: audio.outputVolume, route: audio.routeName, localization: runner.result)
        store.add(session)
        savedSession = session
    }
}

/// 8 direction buttons around a head, seen from above. Top = front.
struct DirectionDial: View {
    let enabled: Bool
    let feedback: LocalizationTrial?
    let onSelect: (Int) -> Void

    static func name(_ azimuth: Int) -> String {
        switch azimuth {
        case 0: "front"
        case 45: "front right"
        case 90: "right"
        case 135: "back right"
        case 180: "behind"
        case 225: "back left"
        case 270: "left"
        case 315: "front left"
        default: "\(azimuth)°"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - 32
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .position(center)
                Text("front").font(.caption2).foregroundStyle(.secondary)
                    .position(x: center.x, y: center.y - 42)

                ForEach(LocalizationRunner.azimuths, id: \.self) { az in
                    let rad = Double(az) * .pi / 180
                    Button {
                        onSelect(az)
                    } label: {
                        Circle()
                            .fill(color(for: az))
                            .frame(width: 52, height: 52)
                            .overlay { Image(systemName: "arrow.up").rotationEffect(.degrees(Double(az))).foregroundStyle(.white) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .accessibilityLabel(Self.name(az))
                    .position(x: center.x + radius * sin(rad), y: center.y - radius * cos(rad))
                }
            }
        }
    }

    private func color(for az: Int) -> Color {
        if let feedback {
            if az == feedback.target { return .green }
            if az == feedback.response { return .orange }
        }
        return enabled ? .accentColor : .gray.opacity(0.5)
    }
}
