import Charts
import SwiftUI

struct BalanceTestView: View {
    @Environment(AudioController.self) private var audio
    @Environment(SessionStore.self) private var store
    @State private var runner: BalanceRunner?
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
            runner = BalanceRunner(audio: audio)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            runner?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: audio.headphonesConnected) { _, connected in
            if !connected { runner?.stop() }
        }
    }

    @ViewBuilder
    private func content(_ runner: BalanceRunner) -> some View {
        @Bindable var runner = runner
        VStack(spacing: 28) {
            ProgressView(value: Double(runner.index), total: Double(runner.frequencies.count))
                .padding(.horizontal)

            if let f = runner.currentFrequency {
                Text("\(Frequencies.label(f)) Hz").font(.title2.bold())

                HStack(spacing: 60) {
                    earLamp("L", lit: runner.sounding == .left, color: .blue)
                    earLamp("R", lit: runner.sounding == .right, color: .red)
                }

                if runner.running {
                    VStack(spacing: 8) {
                        Slider(value: $runner.slider, in: BalanceRunner.sliderRange)
                        HStack {
                            Text("Right quieter")
                            Spacer()
                            Text("Right louder")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    Text("Move the slider until left and right sound equally loud.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Button("Equally loud") { runner.confirm() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Begin") { runner.start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!audio.headphonesConnected)
                }
            } else {
                Button("See results") { save(runner) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding(.vertical)
        .navigationTitle("Ear balance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func earLamp(_ label: String, lit: Bool, color: Color) -> some View {
        Circle()
            .fill(lit ? color : Color.gray.opacity(0.25))
            .frame(width: 64, height: 64)
            .overlay { Text(label).font(.title3.bold()).foregroundStyle(.white) }
            .animation(.easeOut(duration: 0.1), value: lit)
    }

    private func save(_ runner: BalanceRunner) {
        guard savedSession == nil else { return }
        let session = TestSession(outputVolume: audio.outputVolume, route: audio.routeName, balance: runner.results)
        store.add(session)
        savedSession = session
    }
}

struct BalanceSections: View {
    let session: TestSession
    @Environment(SessionStore.self) private var store

    static let flag = 10.0

    private var results: [BalanceResult] { (session.balance ?? []).sorted { $0.frequency < $1.frequency } }
    private var previous: TestSession? { store.previousBalance(before: session) }

    var body: some View {
        Section {
            Chart {
                RuleMark(y: .value("Equal", 0)).foregroundStyle(.secondary)
                ForEach(results, id: \.frequency) { r in
                    BarMark(x: .value("Hz", Frequencies.label(r.frequency)), y: .value("dB", r.offsetDB))
                        .foregroundStyle(r.offsetDB >= 0 ? Color.red : Color.blue)
                }
                if let prev = previous?.balance {
                    ForEach(prev.sorted { $0.frequency < $1.frequency }, id: \.frequency) { r in
                        PointMark(x: .value("Hz", Frequencies.label(r.frequency)), y: .value("dB", r.offsetDB))
                            .symbol(.diamond)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXScale(domain: results.map { Frequencies.label($0.frequency) })
            .chartYAxisLabel("dB more in right ear")
            .frame(height: 220)
        } footer: {
            Text("Red bar up = your right ear needed more level to sound as loud as the left. Blue bar down = the left ear needed more. Grey diamonds = your previous balance test. Repeat runs often differ by a few dB.")
        }

        Section("By frequency") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Hz").gridColumnAlignment(.leading)
                    Text("Now"); Text("Previous"); Text("Change")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                ForEach(results, id: \.frequency) { r in
                    let prev = previous?.balance?.first { $0.frequency == r.frequency }?.offsetDB
                    GridRow {
                        Text(Frequencies.label(r.frequency)).gridColumnAlignment(.leading)
                        Text(String(format: "%+.0f", r.offsetDB))
                            .foregroundStyle(abs(r.offsetDB) >= Self.flag ? .orange : .primary)
                        Text(prev.map { String(format: "%+.0f", $0) } ?? "-")
                        Text(prev.map { String(format: "%+.0f", r.offsetDB - $0) } ?? "-")
                    }
                    .monospacedDigit()
                }
            }
            if results.contains(where: { abs($0.offsetDB) >= Self.flag }) {
                Label("One ear needed \(Int(Self.flag)) dB or more extra at one or more frequencies.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        if store.balanceHistory.count >= 2 {
            Section {
                BalanceTrendChart(history: store.balanceHistory)
                    .frame(height: 220)
            } header: {
                Text("Over time")
            } footer: {
                Text("Each line is one frequency. A line moving toward 0 means the ears are getting closer.")
            }
        }
    }
}

struct BalanceTrendChart: View {
    let history: [TestSession]

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let frequency: String
        let offset: Double
    }

    private var points: [Point] {
        history.flatMap { s in
            (s.balance ?? []).map { Point(date: s.date, frequency: Frequencies.label($0.frequency), offset: $0.offsetDB) }
        }
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("dB", p.offset))
                .foregroundStyle(by: .value("Hz", p.frequency))
            PointMark(x: .value("Date", p.date), y: .value("dB", p.offset))
                .foregroundStyle(by: .value("Hz", p.frequency))
        }
        .chartForegroundStyleScale(domain: BalanceRunner.frequencies.map(Frequencies.label))
        .chartYAxisLabel("dB more in right ear")
    }
}
