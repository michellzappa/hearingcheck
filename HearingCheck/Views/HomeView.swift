import SwiftUI

enum EarSelection: String, CaseIterable, Identifiable {
    case both, right, left
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var ears: [Ear] {
        switch self {
        case .both: [.right, .left]
        case .right: [.right]
        case .left: [.left]
        }
    }
}

enum TestKind: Hashable {
    case threshold(ears: [Ear], frequencies: [Double])
    case localization(Stimulus)
    case balance
}

struct HomeView: View {
    @Environment(AudioController.self) private var audio
    @Environment(SessionStore.self) private var store

    @State private var earSelection: EarSelection = .both
    @State private var extendedHigh = false
    @State private var stimulus: Stimulus = .noise

    private var frequencies: [Double] {
        extendedHigh ? Frequencies.standard + Frequencies.extendedHigh : Frequencies.standard
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AudioStatusRow()
                }

                Section {
                    Picker("Ears", selection: $earSelection) {
                        ForEach(EarSelection.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Extended high (10 to 16 kHz)", isOn: $extendedHigh)
                    NavigationLink("Start threshold test", value: TestKind.threshold(ears: earSelection.ears, frequencies: frequencies))
                } header: {
                    Text("Pure-tone threshold")
                } footer: {
                    Text("Finds the quietest tone you hear at each frequency, one ear at a time. Each tone plays in one ear only.")
                }

                Section {
                    NavigationLink("Start balance test", value: TestKind.balance)
                } header: {
                    Text("Ear balance")
                } footer: {
                    Text("Plays the same tone in your left ear, then your right, again and again. You move a slider until both sound equally loud. The result shows how much more level one ear needs at each frequency. Repeat it daily to follow a temporary change.")
                }

                Section {
                    Picker("Sound", selection: $stimulus) {
                        ForEach(Stimulus.allCases) { Text($0.label).tag($0) }
                    }
                    NavigationLink("Start spatial test", value: TestKind.localization(stimulus))
                } header: {
                    Text("Spatial localization")
                } footer: {
                    Text("Plays a sound from one of 8 directions with spatial audio (HRTF). You tap where it came from. Low tones test timing cues between ears; high tones test level cues.")
                }

                Section("History") {
                    if store.sessions.isEmpty {
                        Text("No tests yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session) { SessionRow(session: session) }
                    }
                    .onDelete { store.delete(at: $0) }
                }

                Section {
                    Text("This is a self-check, not a medical test. Levels are relative to your phone and headphones, not calibrated dB HL. Use the same headphones and volume each time and compare results over time. See an audiologist for a diagnosis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hearing Check")
            .navigationDestination(for: TestKind.self) { PrecheckView(kind: $0) }
            .navigationDestination(for: TestSession.self) { SessionDetailView(session: $0) }
        }
    }
}

struct AudioStatusRow: View {
    @Environment(AudioController.self) private var audio

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                audio.headphonesConnected ? "Headphones: \(audio.routeName)" : "No headphones connected",
                systemImage: audio.headphonesConnected ? "headphones" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(audio.headphonesConnected ? Color.primary : Color.orange)
            Text("Volume \(Int((audio.outputVolume * 100).rounded()))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = audio.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct SessionRow: View {
    let session: TestSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.kindLabel)
                if let feeling = session.feeling { FeelingChip(feeling: feeling) }
            }
            Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.route) · vol \(Int((session.outputVolume * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FeelingChip: View {
    let feeling: EarFeeling

    var body: some View {
        Text(feeling.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(feeling.isClogged ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
            .foregroundStyle(feeling.isClogged ? Color.orange : Color.green)
    }
}
