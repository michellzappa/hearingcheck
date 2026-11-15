import SwiftUI

struct ThresholdTestView: View {
    let ears: [Ear]
    let frequencies: [Double]

    @Environment(AudioController.self) private var audio
    @Environment(SessionStore.self) private var store
    @State private var runner: ThresholdRunner?
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
        .navigationBarBackButtonHidden(runner?.phase == .running)
        .onAppear {
            guard runner == nil else { return }
            runner = ThresholdRunner(audio: audio, ears: ears, frequencies: frequencies)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            runner?.stop("Test left.")
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: audio.headphonesConnected) { _, connected in
            if !connected { runner?.stop("Headphones disconnected.") }
        }
        .onChange(of: runner?.phase) { _, phase in
            if phase == .finished, let runner { save(runner) }
        }
    }

    @ViewBuilder
    private func content(_ runner: ThresholdRunner) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: runner.progress)
                .padding(.horizontal)

            if let step = runner.current {
                VStack(spacing: 4) {
                    Text("\(step.ear.label) ear").font(.title2.bold())
                    Text("\(Frequencies.label(step.frequency)) Hz").foregroundStyle(.secondary)
                }
            }

            Spacer()

            switch runner.phase {
            case .ready:
                Text("Tap the button each time you hear a beep.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Begin") { runner.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .running:
                HearButton(pulse: runner.tapPulse) { runner.tap() }
                Button("Stop test", role: .destructive) { runner.stop("Stopped.") }
            case .stopped(let reason):
                Label(reason, systemImage: "stop.circle").font(.headline)
                if !runner.results.isEmpty {
                    Button("Save partial results") { save(runner) }
                        .buttonStyle(.borderedProminent)
                }
            case .finished:
                ProgressView("Saving…")
            }

            Spacer()
        }
        .padding(.vertical)
        .navigationTitle("Threshold test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ runner: ThresholdRunner) {
        guard savedSession == nil else { return }
        let session = TestSession(outputVolume: audio.outputVolume, route: audio.routeName, thresholds: runner.results)
        store.add(session)
        savedSession = session
    }
}

private struct HearButton: View {
    let pulse: Int
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor.gradient)
                .overlay {
                    Label("I hear it", systemImage: "ear")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 240, height: 240)
                .scaleEffect(pressed ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .onChange(of: pulse) {
            withAnimation(.easeOut(duration: 0.08)) { pressed = true }
            withAnimation(.easeOut(duration: 0.15).delay(0.08)) { pressed = false }
        }
    }
}
