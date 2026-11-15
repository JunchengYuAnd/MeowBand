import AVFoundation
import Darwin

/// Pre-rendered PCM voices, scheduled against the hardware host clock.
/// The conductor remains independent of rendering and can be tested offline.
@MainActor
final class EnsembleAudio {
    private struct Voice {
        let node: AVAudioPlayerNode
        var until = 0.0
    }
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var pools: [EnsembleRole: [Voice]] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var conductor: EnsembleConductor?
    private var origin = 0.0, elapsed = 0.0
    private var running = false

    init() {
        for role in EnsembleRole.allCases {
            pools[role] = (0..<(role == .pad ? 16 : 6)).map { _ in
                let node = AVAudioPlayerNode()
                engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
                return Voice(node: node)
            }
        }
        engine.mainMixerNode.outputVolume = 0.65
    }

    func start(role: EnsembleRole) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        // Prepare likely first-response pitches before the game clock starts.
        for note in 60...78 { _ = render(EnsembleNote(role: .lead, time: 0, midi: note, duration: 1.45)) }
        for drum in 0...2 { _ = render(EnsembleNote(role: .drums, time: 0, drum: drum)) }
        try engine.start()
        let model = EnsembleConductor(role: role)
        model.output = { [weak self] note in self?.play(note) }
        conductor = model; elapsed = 0; origin = ProcessInfo.processInfo.systemUptime; running = true
        update()
    }

    func update() {
        guard running else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - origin
        conductor?.advance(to: elapsed + 0.08)
    }

    func touch(role: EnsembleRole, variant: Int) {
        guard running else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - origin
        conductor?.touch(role: role, at: elapsed, variant: variant)
    }

    func pause() {
        guard running else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - origin; running = false
        silence(); engine.pause()
    }

    func resume() throws {
        guard conductor != nil else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        origin = ProcessInfo.processInfo.systemUptime - elapsed; running = true
        update()
    }

    func stop() { running = false; silence(); engine.pause(); conductor = nil; elapsed = 0 }

    private func silence() {
        for role in EnsembleRole.allCases {
            guard var pool = pools[role] else { continue }
            for i in pool.indices { pool[i].node.stop(); pool[i].until = 0 }
            pools[role] = pool
        }
    }

    private func play(_ note: EnsembleNote) {
        let buffer = render(note)
        guard var pool = pools[note.role] else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(0.003, origin + note.time - now)
        let onset = now + delay
        if note.role == .lead || note.role == .bass {
            for i in pool.indices { pool[i].node.stop(); pool[i].until = 0 }
        }
        let index = pool.indices.first { pool[$0].until <= now } ?? pool.indices.min { pool[$0].until < pool[$1].until }!
        let node = pool[index].node
        node.stop(); node.volume = Float(min(1, max(0, note.strength)))
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay)))
        pool[index].until = onset + Double(buffer.frameLength) / format.sampleRate
        pools[note.role] = pool
    }

    private func render(_ note: EnsembleNote) -> AVAudioPCMBuffer {
        let duration: Double = note.role == .drums ? (note.drum == 0 ? 0.30 : 0.13) : note.duration
        let key = "\(note.role)-\(note.midi)-\(note.drum)-\(Int(duration * 100))"
        if let cached = buffers[key] { return cached }
        let count = Int(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        let frequency = 440 * pow(2, Double(note.midi - 69) / 12)
        var phase = 0.0, seed: UInt64 = 87231, previous = 0.0
        for i in 0..<count {
            let t = Double(i) / format.sampleRate
            let attack = note.role == .pad ? 0.035 : 0.006
            let fade = min(1, (duration - t) / 0.04)
            let envelope = min(1, t / attack) * fade
            let wave: Double
            switch note.role {
            case .pad:
                wave = sin(2 * .pi * frequency * t) * exp(-t / max(0.1, duration / 3)) * 0.028
            case .lead:
                let p = 2 * .pi * frequency * t
                wave = (sin(p) + sin(p * 2) * 0.23 + sin(p * 3.01) * 0.07) * exp(-t * 3.5) * 0.17
            case .bass:
                let p = 2 * .pi * frequency * t
                wave = (sin(p) + sin(p * 2) * 0.32) * exp(-t * 3) * 0.15
            case .drums:
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let noise = Double(Int64(bitPattern: seed) >> 32) / Double(Int32.max)
                if note.drum == 0 {
                    phase += 2 * .pi * (57 + 71 * exp(-t * 28)) / format.sampleRate
                    wave = sin(phase) * exp(-t * 24) * 0.22
                } else {
                    let filtered = note.drum == 1 ? (noise + previous) / 2 : noise - previous
                    previous = noise
                    wave = filtered * exp(-t * 60) * (note.drum == 1 ? 0.17 : 0.065)
                }
            }
            samples[i] = Float(tanh(wave * envelope))
        }
        // All pitches, roles and duration variants used by the conductor are finite.
        buffers[key] = buffer
        return buffer
    }
}
