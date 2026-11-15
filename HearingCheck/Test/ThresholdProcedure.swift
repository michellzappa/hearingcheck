import Foundation

/// Modified Hughson-Westlake staircase (the clinical pure-tone method):
/// heard → 10 dB down, missed → 5 dB up.
/// A presentation after a miss is "ascending". Threshold = the lowest level heard on
/// at least 2 ascending presentations, with at least half of the ascending presentations heard.
struct ThresholdProcedure {
    static let startLevel: Double = -40
    static let floor: Double = -120
    static let ceiling: Double = -6
    static let maxTrials = 30

    private(set) var level: Double = startLevel
    private(set) var trials = 0
    private var previousMissed = false
    private var ascendingHeard: [Double: Int] = [:]
    private var ascendingCount: [Double: Int] = [:]
    private var missesAtCeiling = 0
    private var hitsAtFloor = 0

    enum Outcome: Equatable {
        case threshold(Double)
        case noResponse
    }

    /// Records the response to the presentation at `level`. Returns an outcome when done.
    mutating func record(heard: Bool) -> Outcome? {
        trials += 1
        if previousMissed {
            ascendingCount[level, default: 0] += 1
            if heard { ascendingHeard[level, default: 0] += 1 }
        }

        if let found = threshold() { return .threshold(found) }

        if heard {
            if level <= Self.floor {
                hitsAtFloor += 1
                if hitsAtFloor >= 2 { return .threshold(Self.floor) }
            }
            level = max(Self.floor, level - 10)
            previousMissed = false
        } else {
            if level >= Self.ceiling {
                missesAtCeiling += 1
                if missesAtCeiling >= 2 { return .noResponse }
            }
            level = min(Self.ceiling, level + 5)
            previousMissed = true
        }

        if trials >= Self.maxTrials {
            // Best estimate: lowest level heard on any ascending run.
            if let best = ascendingHeard.filter({ $0.value > 0 }).keys.min() { return .threshold(best) }
            return .noResponse
        }
        return nil
    }

    private func threshold() -> Double? {
        ascendingHeard
            .filter { lvl, hits in hits >= 2 && Double(hits) * 2 >= Double(ascendingCount[lvl] ?? 0) }
            .keys
            .min()
    }
}
