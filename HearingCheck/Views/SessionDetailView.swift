import Charts
import SwiftUI

struct SessionDetailView: View {
    let session: TestSession
    @Environment(SessionStore.self) private var store

    static let asymmetryFlag = 15.0
    static let shiftFlag = 10.0

    private var baseline: TestSession? {
        guard let b = store.baseline, b.id != session.id, session.isThresholdSession else { return nil }
        return b
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Output", value: session.route)
                LabeledContent("Volume", value: "\(Int((session.outputVolume * 100).rounded()))%")
            }

            if session.isThresholdSession { thresholdSections }
            if let loc = session.localization { localizationSections(loc) }
            if session.isBalanceSession { BalanceSections(session: session) }
        }
        .navigationTitle(session.resultTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Threshold

    @ViewBuilder
    private var thresholdSections: some View {
        Section {
            AudiogramChart(session: session, baseline: baseline)
                .frame(height: 260)
        } footer: {
            Text("Higher = you hear quieter tones. Red ○ right ear, blue ✕ left ear. Dashed = baseline. Values are dB below digital full scale at this volume, not dB HL.")
        }

        Section("Thresholds (dB below full scale)") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Hz").gridColumnAlignment(.leading)
                    Text("Right"); Text("Left"); Text("R−L")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                ForEach(session.frequencies, id: \.self) { f in
                    let r = session.threshold(.right, f)?.thresholdDBFS
                    let l = session.threshold(.left, f)?.thresholdDBFS
                    GridRow {
                        Text(Frequencies.label(f)).gridColumnAlignment(.leading)
                        Text(Self.format(r, present: session.threshold(.right, f) != nil))
                        Text(Self.format(l, present: session.threshold(.left, f) != nil))
                        if let r, let l {
                            // Positive = right ear hears quieter tones than left.
                            let diff = l - r
                            Text(String(format: "%+.0f", diff))
                                .foregroundStyle(abs(diff) >= Self.asymmetryFlag ? .orange : .primary)
                        } else {
                            Text("-")
                        }
                    }
                    .monospacedDigit()
                }
            }
            if asymmetric {
                Label("Ears differ by \(Int(Self.asymmetryFlag)) dB or more at one or more frequencies. Repeat the test. If it repeats, see an audiologist.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            let alarms = session.thresholds.map(\.falseAlarms).reduce(0, +)
            LabeledContent("False taps", value: "\(alarms)")
                .font(.footnote)
            if alarms > session.thresholds.count {
                Text("Many taps came with no tone. Results can be too optimistic. Tap only when you are sure.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        if let baseline {
            Section {
                if abs(baseline.outputVolume - session.outputVolume) > 0.02 || baseline.route != session.route {
                    Label("Baseline used different headphones or volume. The change is not reliable.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Hz").gridColumnAlignment(.leading)
                        Text("Δ Right"); Text("Δ Left")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    ForEach(session.frequencies, id: \.self) { f in
                        GridRow {
                            Text(Frequencies.label(f)).gridColumnAlignment(.leading)
                            shiftCell(.right, f)
                            shiftCell(.left, f)
                        }
                        .monospacedDigit()
                    }
                }
            } header: {
                Text("Change vs baseline (\(baseline.date.formatted(date: .abbreviated, time: .omitted)))")
            } footer: {
                Text("Negative = worse than baseline. Orange = \(Int(Self.shiftFlag)) dB or more worse.")
            }
        }
    }

    private var asymmetric: Bool {
        session.frequencies.contains { f in
            guard let r = session.threshold(.right, f)?.thresholdDBFS,
                  let l = session.threshold(.left, f)?.thresholdDBFS else { return false }
            return abs(r - l) >= Self.asymmetryFlag
        }
    }

    @ViewBuilder
    private func shiftCell(_ ear: Ear, _ f: Double) -> some View {
        if let now = session.threshold(ear, f)?.thresholdDBFS,
           let then = baseline?.threshold(ear, f)?.thresholdDBFS {
            // Threshold rising (less negative) = worse hearing.
            let change = then - now
            Text(String(format: "%+.0f", change))
                .foregroundStyle(change <= -Self.shiftFlag ? .orange : .primary)
        } else {
            Text("-")
        }
    }

    static func format(_ dbfs: Double?, present: Bool) -> String {
        guard present else { return "-" }
        guard let dbfs else { return "NR" }
        return String(format: "%.0f", -dbfs)
    }

    // MARK: Localization

    @ViewBuilder
    private func localizationSections(_ loc: LocalizationResult) -> some View {
        Section(loc.stimulus.label) {
            LabeledContent("Exact", value: "\(loc.exactHits) / \(loc.trials.count)")
            LabeledContent("Mean error", value: String(format: "%.0f°", loc.meanErrorDegrees))
            LabeledContent("Left/right errors", value: "\(loc.leftRightErrors)")
            LabeledContent("Front/back confusions", value: "\(loc.frontBackConfusions)")
        }
        Section {
            ForEach(LocalizationRunner.azimuths, id: \.self) { az in
                let answers = loc.trials.filter { $0.target == az }.map { DirectionDial.name($0.response) }
                LabeledContent(DirectionDial.name(az).capitalized, value: answers.joined(separator: ", "))
            }
        } header: {
            Text("Target → your answers")
        } footer: {
            Text("Front/back confusions are normal with generic spatial audio and a still head. Left/right errors are the ones to watch: they can point to a difference between your ears.")
        }
    }
}

struct AudiogramChart: View {
    let session: TestSession
    let baseline: TestSession?

    private struct Point: Identifiable {
        let id = UUID()
        let ear: Ear
        let frequency: String
        let sensitivity: Double
        let series: String
    }

    private var labels: [String] { session.frequencies.map(Frequencies.label) }

    var body: some View {
        let current = sortedPoints(session, suffix: "")
        let base = baseline.map { sortedPoints($0, suffix: " baseline") } ?? []

        Chart {
            ForEach(base) { p in
                LineMark(x: .value("Hz", p.frequency), y: .value("dB", p.sensitivity), series: .value("Series", p.series))
                    .foregroundStyle(p.ear == .right ? Color.red.opacity(0.4) : Color.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(current) { p in
                LineMark(x: .value("Hz", p.frequency), y: .value("dB", p.sensitivity), series: .value("Series", p.series))
                    .foregroundStyle(p.ear == .right ? Color.red : Color.blue)
                PointMark(x: .value("Hz", p.frequency), y: .value("dB", p.sensitivity))
                    .foregroundStyle(p.ear == .right ? Color.red : Color.blue)
                    .symbol(p.ear == .right ? .circle : .cross)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: labels)
        .chartYScale(domain: 0...120)
        .chartYAxisLabel("dB below full scale")
        .chartLegend(.hidden)
    }

    /// Points in frequency order, so lines connect left to right.
    private func sortedPoints(_ s: TestSession, suffix: String) -> [Point] {
        let order = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        return s.thresholds.compactMap { t -> Point? in
            guard let db = t.thresholdDBFS, session.frequencies.contains(t.frequency) else { return nil }
            return Point(ear: t.ear, frequency: Frequencies.label(t.frequency), sensitivity: -db, series: t.ear.label + suffix)
        }
        .sorted { (order[$0.frequency] ?? 0) < (order[$1.frequency] ?? 0) }
    }
}
