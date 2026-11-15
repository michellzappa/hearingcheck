import Foundation
import Observation

/// Sessions persist as plain JSON in Documents/sessions.json.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [TestSession] = []

    @ObservationIgnored private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sessions.json")
    }()

    init() { load() }

    /// The oldest threshold session is the baseline for change tracking.
    var baseline: TestSession? {
        sessions.filter(\.isThresholdSession).min { $0.date < $1.date }
    }

    /// The newest balance session older than `session`, for day-to-day comparison.
    func previousBalance(before session: TestSession) -> TestSession? {
        sessions.filter { $0.isBalanceSession && $0.date < session.date }.max { $0.date < $1.date }
    }

    /// All balance sessions, oldest first.
    var balanceHistory: [TestSession] {
        sessions.filter(\.isBalanceSession).sorted { $0.date < $1.date }
    }

    func add(_ session: TestSession) {
        sessions.insert(session, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([TestSession].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
