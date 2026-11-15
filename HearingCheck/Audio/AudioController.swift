import AVFoundation
import Observation

/// Where a stimulus goes.
/// `.left` / `.right` are hard-panned: the other channel is digital silence.
/// Use these for threshold tests, because HRTF rendering leaks sound into both ears.
enum Channel {
    case left, right, both
}

enum Stimulus: String, Codable, CaseIterable, Identifiable {
    case noise, lowTone, highTone
    var id: String { rawValue }

    var label: String {
        switch self {
        case .noise: "Noise burst"
        case .lowTone: "Low tone (500 Hz)"
        case .highTone: "High tone (4 kHz)"
        }
    }
}

/// Owns the audio session, the engine and the headphone route state.
/// Two signal paths:
/// - `stereoPlayer` → main mixer: exact left/right isolation for audiometry.
/// - `spatialPlayer` → `AVAudioEnvironmentNode` (HRTF) → main mixer: positions a source
///   in 3D around the head for the localization test.
@MainActor
@Observable
final class AudioController {
    nonisolated static let pulseOn = 0.22
    nonisolated static let pulseOff = 0.18
    nonisolated static let pulseCount = 3
    nonisolated static let ramp = 0.02
    nonisolated static var stimulusDuration: Double {
        Double(pulseCount) * pulseOn + Double(pulseCount - 1) * pulseOff
    }

    private(set) var headphonesConnected = false
    private(set) var routeName = "None"
    private(set) var outputVolume: Float = 0
    private(set) var lastError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let stereoPlayer = AVAudioPlayerNode()
    @ObservationIgnored private let spatialPlayer = AVAudioPlayerNode()
    @ObservationIgnored private let environment = AVAudioEnvironmentNode()
    @ObservationIgnored private var sampleRate: Double = 48_000
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .measurement asks the system for the least signal processing.
            try session.setCategory(.playback, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
        }
        refreshRoute()
        outputVolume = session.outputVolume
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? 0
            Task { @MainActor in self?.outputVolume = value }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshRoute() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartAfterConfigurationChange() }
        })
    }

    // MARK: Route

    private func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let headphoneTypes: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio,
        ]
        headphonesConnected = outputs.contains { headphoneTypes.contains($0.portType) }
        routeName = outputs.map(\.portName).joined(separator: ", ")
        if routeName.isEmpty { routeName = "None" }
    }

    // MARK: Engine

    private func configureIfNeeded() {
        guard !configured else { return }
        let hwRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = hwRate > 0 ? hwRate : 48_000

        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        engine.attach(stereoPlayer)
        engine.attach(spatialPlayer)
        engine.attach(environment)

        engine.connect(stereoPlayer, to: engine.mainMixerNode, format: stereo)
        engine.connect(spatialPlayer, to: environment, format: mono)
        engine.connect(environment, to: engine.mainMixerNode, format: stereo)

        environment.outputType = .headphones
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.reverbParameters.enable = false
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 1
        environment.distanceAttenuationParameters.rolloffFactor = 0
        spatialPlayer.renderingAlgorithm = .HRTFHQ
        spatialPlayer.sourceMode = .pointSource

        engine.mainMixerNode.outputVolume = 1
        configured = true
    }

    func start() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            configureIfNeeded()
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            stereoPlayer.play()
            spatialPlayer.play()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopSound() {
        stereoPlayer.stop()
        spatialPlayer.stop()
        if engine.isRunning {
            stereoPlayer.play()
            spatialPlayer.play()
        }
    }

    private func restartAfterConfigurationChange() {
        guard configured else { return }
        start()
    }

    // MARK: Playback

    /// Plays a pulsed pure tone. `levelDBFS` is the peak level re digital full scale.
    func playTone(frequency: Double, levelDBFS: Double, channel: Channel) {
        start()
        let buffer = makeStereoBuffer(channel: channel) { t in
            sin(2 * .pi * frequency * t) * Self.amplitude(levelDBFS)
        }
        stereoPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Plays one steady tone of `duration` seconds with soft edges. Used by the balance test.
    func playBurst(frequency: Double, levelDBFS: Double, channel: Channel, duration: Double) {
        start()
        let buffer = makeStereoBuffer(channel: channel, duration: duration, envelope: { t in
            Self.singleToneEnvelope(t, length: duration)
        }) { t in
            sin(2 * .pi * frequency * t) * Self.amplitude(levelDBFS)
        }
        stereoPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Plays a stimulus from `azimuth` degrees (0 = front, 90 = right, 180 = behind, 270 = left)
    /// through the HRTF renderer.
    func playSpatial(_ stimulus: Stimulus, azimuth: Double, levelDBFS: Double = -20) {
        start()
        let rad = azimuth * .pi / 180
        // AVAudio3D: +x right, +y up, -z forward.
        spatialPlayer.position = AVAudio3DPoint(x: Float(sin(rad)), y: 0, z: Float(-cos(rad)))
        let buffer = makeMonoBuffer(stimulus: stimulus, levelDBFS: levelDBFS)
        spatialPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    // MARK: Synthesis

    nonisolated static func amplitude(_ dbfs: Double) -> Double { pow(10, dbfs / 20) }

    /// Envelope for the pulse train: cosine ramps on every pulse to avoid clicks
    /// (clicks are broadband and would let you "hear" a tone you cannot hear).
    nonisolated private static func envelope(_ t: Double) -> Double {
        let period = pulseOn + pulseOff
        let index = Int(t / period)
        guard index < pulseCount else { return 0 }
        let local = t - Double(index) * period
        guard local < pulseOn else { return 0 }
        if local < ramp { return 0.5 - 0.5 * cos(.pi * local / ramp) }
        if local > pulseOn - ramp { return 0.5 - 0.5 * cos(.pi * (pulseOn - local) / ramp) }
        return 1
    }

    /// Cosine ramp in and out over `ramp` seconds for a single tone of `length` seconds.
    nonisolated private static func singleToneEnvelope(_ t: Double, length: Double) -> Double {
        guard t >= 0, t <= length else { return 0 }
        if t < ramp { return 0.5 - 0.5 * cos(.pi * t / ramp) }
        if t > length - ramp { return 0.5 - 0.5 * cos(.pi * (length - t) / ramp) }
        return 1
    }

    private func makeStereoBuffer(
        channel: Channel,
        duration: Double = AudioController.stimulusDuration,
        envelope: (Double) -> Double = AudioController.envelope,
        sample: (Double) -> Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(duration * sampleRate) + 1
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let v = Float(sample(t) * envelope(t))
            left[i] = channel == .right ? 0 : v
            right[i] = channel == .left ? 0 : v
        }
        return buffer
    }

    private func makeMonoBuffer(stimulus: Stimulus, levelDBFS: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(Self.stimulusDuration * sampleRate) + 1
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        let amp = Self.amplitude(levelDBFS)
        // Uniform noise in [-1, 1] has RMS 1/√3; a sine has RMS 1/√2. Match RMS.
        let noiseScale = amp * sqrt(3.0) / sqrt(2.0)
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let raw: Double
            switch stimulus {
            case .noise: raw = Double.random(in: -1...1) * noiseScale
            case .lowTone: raw = sin(2 * .pi * 500 * t) * amp
            case .highTone: raw = sin(2 * .pi * 4000 * t) * amp
            }
            out[i] = Float(raw * Self.envelope(t))
        }
        return buffer
    }
}
