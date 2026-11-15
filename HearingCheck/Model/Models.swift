import Foundation

enum Ear: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var label: String { self == .left ? "Left" : "Right" }
    var channel: Channel { self == .left ? .left : .right }
}

enum Frequencies {
    /// Clinical audiogram order: 1 kHz first, up, then down.
    static let standard: [Double] = [1000, 2000, 3000, 4000, 6000, 8000, 500, 250]
    static let extendedHigh: [Double] = [10000, 12000, 14000, 16000]

    static func label(_ hz: Double) -> String {
        hz >= 1000 ? String(format: hz.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0fk" : "%.1fk", hz / 1000) : String(format: "%.0f", hz)
    }
}

struct ThresholdResult: Codable, Identifiable, Hashable {
    var id = UUID()
    var ear: Ear
    var frequency: Double
    /// Lowest level heard, in dB re digital full scale. `nil` = no response at the maximum level.
    var thresholdDBFS: Double?
    var trials: Int
    var falseAlarms: Int
}

struct LocalizationTrial: Codable, Hashable {
    var target: Int
    var response: Int
}

struct LocalizationResult: Codable, Hashable {
    var stimulus: Stimulus
    var trials: [LocalizationTrial]

    var exactHits: Int { trials.filter { $0.target == $0.response }.count }

    var meanErrorDegrees: Double {
        guard !trials.isEmpty else { return 0 }
        return trials.map { Double(Self.angularDistance($0.target, $0.response)) }.reduce(0, +) / Double(trials.count)
    }

    /// Target and response on opposite sides (left vs right). Midline targets are excluded.
    var leftRightErrors: Int {
        trials.filter { t in
            let a = Self.side(t.target), b = Self.side(t.response)
            return a != 0 && b != 0 && a != b
        }.count
    }

    /// Response mirrored across the left-right axis (front heard as back or back as front).
    var frontBackConfusions: Int {
        trials.filter { t in
            t.target != t.response && (180 - t.target + 360) % 360 == t.response
        }.count
    }

    static func angularDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % 360
        return min(d, 360 - d)
    }

    /// -1 left, 1 right, 0 midline.
    static func side(_ azimuth: Int) -> Int {
        let a = (azimuth % 360 + 360) % 360
        if a == 0 || a == 180 { return 0 }
        return a < 180 ? 1 : -1
    }
}

/// Interaural loudness balance at one frequency.
/// `offsetDB` = right level minus left level when both sound equally loud.
/// Positive = the right ear needs more level = the right ear is less sensitive.
struct BalanceResult: Codable, Hashable {
    var frequency: Double
    var offsetDB: Double
}

struct TestSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var outputVolume: Float
    var route: String
    var thresholds: [ThresholdResult] = []
    var localization: LocalizationResult?
    var balance: [BalanceResult]?

    var isThresholdSession: Bool { !thresholds.isEmpty }
    var isBalanceSession: Bool { !(balance ?? []).isEmpty }

    var kindLabel: String {
        if isThresholdSession { return "Threshold test" }
        if isBalanceSession { return "Balance test" }
        return "Spatial test"
    }

    var resultTitle: String {
        if isThresholdSession { return "Audiogram" }
        if isBalanceSession { return "Ear balance" }
        return "Spatial result"
    }

    func threshold(_ ear: Ear, _ frequency: Double) -> ThresholdResult? {
        thresholds.first { $0.ear == ear && $0.frequency == frequency }
    }

    var frequencies: [Double] { Array(Set(thresholds.map(\.frequency))).sorted() }
}
