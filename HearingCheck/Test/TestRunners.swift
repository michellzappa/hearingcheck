import Foundation
import Observation

struct TestStep: Hashable {
    var ear: Ear
    var frequency: Double
}

/// Runs the pure-tone threshold test: random onset, pulsed tone, response window,
/// silent catch trials to count false alarms.
@MainActor
@Observable
final class ThresholdRunner {
    enum Phase: Equatable {
        case ready, running, stopped(String), finished
    }

    static let responseGrace = 1.0
    static let catchTrialChance = 0.12

    private(set) var phase: Phase = .ready
    private(set) var current: TestStep?
    private(set) var stepIndex = 0
    private(set) var results: [ThresholdResult] = []
    private(set) var tapPulse = 0

    let plan: [TestStep]
    @ObservationIgnored private let audio: AudioController
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var windowOpen = false
    @ObservationIgnored private var heard = false
    @ObservationIgnored private var falseAlarms = 0

    init(audio: AudioController, ears: [Ear], frequencies: [Double]) {
        self.audio = audio
        plan = ears.flatMap { ear in frequencies.map { TestStep(ear: ear, frequency: $0) } }
    }

    var progress: Double { plan.isEmpty ? 0 : Double(stepIndex) / Double(plan.count) }

    func start() {
        guard phase == .ready else { return }
        phase = .running
        audio.start()
        task = Task { await run() }
    }

    func tap() {
        guard phase == .running else { return }
        tapPulse += 1
        if windowOpen { heard = true } else { falseAlarms += 1 }
    }

    func stop(_ reason: String) {
        guard phase == .running else { return }
        task?.cancel()
        audio.stopSound()
        phase = .stopped(reason)
    }

    private func run() async {
        for (index, step) in plan.enumerated() {
            stepIndex = index
            current = step
            falseAlarms = 0
            var procedure = ThresholdProcedure()

            while !Task.isCancelled {
                // A false alarm during the wait extends the wait, so tapping on rhythm does not pay off.
                let alarmsBefore = falseAlarms
                try? await Task.sleep(for: .seconds(Double.random(in: 1.2...3.2)))
                if falseAlarms > alarmsBefore {
                    try? await Task.sleep(for: .seconds(1.5))
                }
                guard !Task.isCancelled else { return }
                guard audio.headphonesConnected else { stop("Headphones disconnected."); return }

                let isCatch = procedure.trials > 2 && Double.random(in: 0..<1) < Self.catchTrialChance
                heard = false
                windowOpen = true
                if !isCatch {
                    audio.playTone(frequency: step.frequency, levelDBFS: procedure.level, channel: step.ear.channel)
                }
                try? await Task.sleep(for: .seconds(AudioController.stimulusDuration + Self.responseGrace))
                windowOpen = false
                guard !Task.isCancelled else { return }

                if isCatch {
                    if heard { falseAlarms += 1 }
                    continue
                }
                if let outcome = procedure.record(heard: heard) {
                    let level: Double?
                    switch outcome {
                    case .threshold(let l): level = l
                    case .noResponse: level = nil
                    }
                    results.append(ThresholdResult(
                        ear: step.ear, frequency: step.frequency, thresholdDBFS: level,
                        trials: procedure.trials, falseAlarms: falseAlarms))
                    break
                }
            }
        }
        stepIndex = plan.count
        current = nil
        phase = .finished
    }
}

/// Runs the spatial localization test: one stimulus per trial from one of 8 azimuths,
/// rendered with HRTF. Each azimuth appears `repeats` times in random order.
@MainActor
@Observable
final class LocalizationRunner {
    static let azimuths = [0, 45, 90, 135, 180, 225, 270, 315]

    private(set) var trialIndex = 0
    private(set) var trials: [LocalizationTrial] = []
    private(set) var lastAnswer: LocalizationTrial?
    private(set) var awaitingAnswer = false

    let stimulus: Stimulus
    @ObservationIgnored private let audio: AudioController
    @ObservationIgnored private let order: [Int]

    init(audio: AudioController, stimulus: Stimulus, repeats: Int = 2) {
        self.audio = audio
        self.stimulus = stimulus
        order = (0..<repeats).flatMap { _ in Self.azimuths }.shuffled()
    }

    var count: Int { order.count }
    var finished: Bool { trialIndex >= order.count }
    var result: LocalizationResult { LocalizationResult(stimulus: stimulus, trials: trials) }

    func play() {
        guard !finished else { return }
        // Small level jitter so loudness is not a cue.
        audio.playSpatial(stimulus, azimuth: Double(order[trialIndex]), levelDBFS: -22 + Double.random(in: -3...3))
        awaitingAnswer = true
    }

    func answer(_ azimuth: Int) {
        guard awaitingAnswer, !finished else { return }
        let trial = LocalizationTrial(target: order[trialIndex], response: azimuth)
        trials.append(trial)
        lastAnswer = trial
        awaitingAnswer = false
        trialIndex += 1
    }
}

/// Alternate binaural loudness balance: the same tone plays in the left ear, then the right,
/// in a loop. The user moves a slider until both sound equally loud.
/// The left ear stays at `referenceLevel`; the slider changes the right ear's level.
/// The slider centre is shifted by a hidden random amount per frequency, so "centre" is not a cue.
@MainActor
@Observable
final class BalanceRunner {
    nonisolated static let frequencies: [Double] = [500, 1000, 2000, 3000, 4000, 6000, 8000]
    static let referenceLevel = -35.0
    static let sliderRange = -25.0...25.0
    static let toneDuration = 0.45
    static let maxLevel = -3.0

    private(set) var index = 0
    private(set) var sounding: Ear?
    private(set) var results: [BalanceResult] = []
    var slider = 0.0

    let frequencies: [Double]
    @ObservationIgnored private let audio: AudioController
    @ObservationIgnored private var hiddenShift = 0.0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(audio: AudioController, frequencies: [Double] = BalanceRunner.frequencies) {
        self.audio = audio
        self.frequencies = frequencies
    }

    var finished: Bool { index >= frequencies.count }
    var currentFrequency: Double? { finished ? nil : frequencies[index] }
    var running: Bool { task != nil }

    /// Right level minus left level, in dB.
    var offset: Double { slider + hiddenShift }

    func start() {
        guard task == nil, !finished else { return }
        newTrial()
        audio.start()
        task = Task { await loop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        sounding = nil
        audio.stopSound()
    }

    /// Records the current setting as "equally loud" and moves to the next frequency.
    func confirm() {
        guard let f = currentFrequency else { return }
        results.append(BalanceResult(frequency: f, offsetDB: (offset * 2).rounded() / 2))
        index += 1
        if finished { stop() } else { newTrial() }
    }

    private func newTrial() {
        hiddenShift = Double.random(in: -10...10)
        slider = 0
    }

    private func loop() async {
        while !Task.isCancelled, let f = currentFrequency {
            sounding = .left
            audio.playBurst(frequency: f, levelDBFS: Self.referenceLevel, channel: .left, duration: Self.toneDuration)
            try? await Task.sleep(for: .seconds(Self.toneDuration + 0.15))
            guard !Task.isCancelled, let f2 = currentFrequency, f2 == f else { continue }

            sounding = .right
            let right = min(Self.maxLevel, Self.referenceLevel + offset)
            audio.playBurst(frequency: f, levelDBFS: right, channel: .right, duration: Self.toneDuration)
            try? await Task.sleep(for: .seconds(Self.toneDuration + 0.15))

            sounding = nil
            try? await Task.sleep(for: .seconds(0.35))
        }
    }
}
