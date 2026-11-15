import Foundation

enum EnsembleRole: String, CaseIterable, Identifiable {
    case drums = "节奏", pad = "和声", bass = "低音", lead = "旋律"
    var id: Self { self }
    var title: String { switch self {
    case .drums: "节奏捕猎"; case .pad: "和声涟漪"; case .bass: "低音追踪"; case .lead: "旋律追光"
    } }
    var icon: String { switch self {
    case .drums: "waveform"; case .pad: "water.waves"; case .bass: "circle.bottomhalf.filled"; case .lead: "music.note"
    } }
    var detail: String { switch self {
    case .drums: "追逐小虾，拍出轻巧律动"; case .pad: "捕捉慢游的大鱼，铺开柔和和弦"
    case .bass: "追踪一条深水鱼，拨动低音重心"; case .lead: "追逐游鱼，让旋律继续生长"
    } }
    var preyCount: Int { switch self { case .drums: 4; case .pad: 2; case .bass: 1; case .lead: 3 } }
    var movement: Double { switch self { case .drums: 1; case .pad: 0.48; case .bass: 0.65; case .lead: 1.12 } }
    var size: Double { switch self { case .drums: 0.85; case .pad: 1.35; case .bass: 1.45; case .lead: 0.95 } }
}

struct EnsembleNote {
    let role: EnsembleRole
    let time: Double
    var midi: Int = 62
    var strength: Double = 1
    var duration: Double = 1
    var drum: Int = 0
    var direct = false
}

/// Pure musical state: a monotonic clock, two-bar motifs and four-bar phrases.
/// Touches change future arrangement without resetting the clock.
final class EnsembleConductor {
    static let beat = 60.0 / 72
    static let bar = beat * 4
    private(set) var tick = 0
    private(set) var activity = 0.3
    private(set) var sleeping = false
    private(set) var focus: EnsembleRole = .lead
    private(set) var voicing = [57, 62, 66, 71]
    private var time = 0.0, lastTouch = 0.0, lastImpulse = -100.0
    private var memory: [EnsembleRole: Double] = [:]
    private var lastHit: [EnsembleRole: Double] = [:]
    private var requestedFocus: EnsembleRole
    private var lastPitch = 66, lastBass = 38, hits = 0
    private var theme = 0, wantedTheme = 0, color = false, wantedColor = false
    private var settleBar: Int?, density = 1, touchWindow = -1, touchCount = 0
    private var budgets: [EnsembleRole: Int] = [:]
    var output: ((EnsembleNote) -> Void)?

    init(role: EnsembleRole) { requestedFocus = role; focus = role }

    private func evolve(_ t: Double) {
        let delta = max(0, t - time); time = max(time, t)
        activity *= exp(-delta / 8)
        for role in EnsembleRole.allCases { memory[role, default: 0] *= exp(-delta / 10) }
    }

    private func chord(_ t: Double) -> (root: Int, pcs: [Int]) {
        let plan = [0, 0, 1, 1, 2, 2, 3, 3, 2, 2, 3, 0]
        let index = plan[Int(max(0, t) / Self.bar) % plan.count]
        let roots = [38, 35, 31, 33]
        let plain = [[2, 6, 9, 11], [11, 2, 6, 9], [7, 11, 2, 4], [9, 2, 4, 7]]
        let colored = [[2, 6, 9, 4], [11, 2, 6, 1], [7, 11, 2, 6], [9, 2, 7, 11]]
        return (roots[index], color ? colored[index] : plain[index])
    }

    private func pitch(at t: Double, target: Int, strong: Bool, cadence: Bool = false) -> Int {
        let harmony = chord(t), scale = [1, 2, 4, 6, 7, 9, 11]
        func cost(_ n: Int) -> Double {
            let leap = abs(n - lastPitch)
            return Double(abs(n - target)) * 0.8 + Double(leap) * 0.3
                + Double(max(0, leap - 5)) * 1.9
                + (harmony.pcs.contains(n % 12) ? 0 : (strong ? 7 : 1.4))
                + (n == lastPitch ? 0.65 : 0)
                + (cadence && n % 12 != harmony.root % 12 ? 12 : 0)
        }
        return (60...78).filter { scale.contains($0 % 12) }.min { cost($0) < cost($1) } ?? 62
    }

    private func emit(_ note: EnsembleNote) {
        if !note.direct && note.role != .pad {
            guard note.time - (lastHit[note.role] ?? -100) >= (note.role == .lead ? 0.27 : 0.15) else { return }
            let limit = note.role == .drums ? 9 : (note.role == .bass ? 4 : 5)
            guard budgets[note.role, default: 0] < limit else { return }
            budgets[note.role, default: 0] += 1
        }
        if note.role == .lead { lastPitch = note.midi }
        if note.role == .bass { lastBass = note.midi }
        output?(note)
    }

    func touch(role: EnsembleRole, at t: Double, variant: Int) {
        evolve(t)
        let window = Int(t * 10)
        if window != touchWindow { touchWindow = window; touchCount = 0 }
        touchCount += 1
        lastTouch = t; sleeping = false; settleBar = nil; requestedFocus = role
        let crowded = t - (lastHit[role] ?? -100) < 0.2
        lastHit[role] = t
        if t - lastImpulse > 0.12 {
            activity = min(1, activity + 0.23); lastImpulse = t
            memory[role] = min(2, memory[role, default: 0] + 0.7)
        }
        guard touchCount <= 6 else { return }
        hits += 1
        if role == .pad { wantedColor = !color }
        if role == .lead && !crowded { wantedTheme = (wantedTheme + 1) % 3 }
        let strength = crowded ? 0.25 : 1.0
        let harmony = chord(t)
        switch role {
        case .drums:
            emit(EnsembleNote(role: role, time: t, strength: strength, drum: variant % 3, direct: true))
        case .pad:
            for note in voicing { emit(EnsembleNote(role: role, time: t, midi: note,
                strength: crowded ? 0.12 : 0.65, duration: crowded ? 0.25 : 2.6, direct: true)) }
        case .bass:
            emit(EnsembleNote(role: role, time: t, midi: harmony.root, strength: strength, duration: crowded ? 0.16 : 1.3, direct: true))
        case .lead:
            emit(EnsembleNote(role: role, time: t, midi: pitch(at: t, target: lastPitch + (hits % 2 == 0 ? -1 : 2), strong: true),
                strength: strength, duration: crowded ? 0.16 : 1.45, direct: true))
        }
    }

    private func voiceLead(_ pcs: [Int]) {
        var best = voicing, bestCost = Double.infinity
        func search(_ current: [Int], _ used: Set<Int>) {
            if current.count == 4 {
                let cost = zip(current, voicing).reduce(0.0) { sum, pair in
                    let distance = abs(pair.0 - pair.1)
                    return sum + Double(distance) + Double(max(0, distance - 5)) * 1.5
                }
                if cost < bestCost { best = current; bestCost = cost }; return
            }
            for note in 53...77 where pcs.contains(note % 12) && !used.contains(note % 12) {
                guard current.last.map({ note - $0 >= 3 }) ?? true,
                      current.first.map({ note - $0 <= 22 }) ?? true else { continue }
                search(current + [note], used.union([note % 12]))
            }
        }
        search([], []); voicing = best
    }

    func advance(to t: Double) {
        // Bounded catch-up; after a system suspension, preserve the musical position
        // without emitting a backlog of old notes.
        if t - Double(tick) * Self.beat / 2 > 0.5 { tick = Int(t / (Self.beat / 2)) }
        while Double(tick) * Self.beat / 2 <= t {
            let stamp = Double(tick) * Self.beat / 2
            evolve(stamp); score(at: stamp, index: tick); tick += 1
        }
    }

    private func score(at t: Double, index: Int) {
        let bar = index / 8, slot = index % 8
        if slot % 2 == 0 {
            if t - lastTouch < Self.beat * 2 { focus = requestedFocus }
            else if t - lastTouch > 8 { focus = .lead }
            else { focus = EnsembleRole.allCases.max { memory[$0, default: 0] < memory[$1, default: 0] } ?? .lead }
        }
        if slot == 0 {
            budgets = [:]
            if t - lastTouch > 10 && settleBar == nil { settleBar = ((bar + 4) / 4) * 4 }
            let wasSleeping = sleeping
            if let end = settleBar, bar >= end { sleeping = true }
            if bar % 2 == 0 { color = wantedColor; theme = wantedTheme }
            density = activity > 0.57 ? 2 : 1
            voiceLead(sleeping ? [2, 6, 9, 11] : chord(t).pcs)
            if !sleeping || !wasSleeping {
                for midi in voicing {
                    emit(EnsembleNote(role: .pad, time: t, midi: midi,
                        strength: sleeping ? 0.18 : (focus == .pad ? 0.48 : 0.32), duration: Self.bar + 0.42))
                }
            }
        }
        guard !sleeping else { return }
        let quiet = settleBar != nil, ending = bar % 12 == 11
        let energy = 0.55 + 0.32 * activity
        func gain(_ role: EnsembleRole) -> Double { 0.78 + min(0.16, memory[role, default: 0] * 0.1) + (focus == role ? 0.2 : 0) }
        if slot == 0 || (!quiet && slot == 5 && (density == 2 || focus == .drums)) {
            emit(EnsembleNote(role: .drums, time: t, strength: 0.42 * energy * gain(.drums)))
        }
        if slot == 4 && !ending { emit(EnsembleNote(role: .drums, time: t, strength: 0.29 * energy * gain(.drums), drum: 1)) }
        if !quiet && [2, 6].contains(slot) { emit(EnsembleNote(role: .drums, time: t + 0.012, strength: 0.32 * energy, drum: 2)) }
        let harmony = chord(t)
        if slot == 0 {
            emit(EnsembleNote(role: .bass, time: t, midi: harmony.root, strength: 0.53 * energy * gain(.bass), duration: 1.7))
        } else if slot == 5 && !quiet && !ending {
            let nextRoot = chord(Double(bar + 1) * Self.bar).root
            let note = [harmony.root, harmony.root + 7, harmony.root + 12].min {
                abs($0 - nextRoot) + abs($0 - lastBass) < abs($1 - nextRoot) + abs($1 - lastBass)
            } ?? harmony.root
            emit(EnsembleNote(role: .bass, time: t, midi: note, strength: 0.32 * energy * gain(.bass), duration: 0.8))
        }
        let grid = bar % 2 == 0 ? [0, 3, 5] : [2, 4, 7]
        guard let position = grid.firstIndex(of: slot), !(quiet && position == 1), !(ending && slot > 4) else { return }
        let motifs = [[0, 2, 1, 3, 2, 0], [0, 1, 3, 2, 1, 0], [2, 1, 0, 1, 2, 0]]
        var degree = motifs[theme][(bar % 2) * 3 + position]
        if bar % 4 >= 2 && !ending && bar % 2 == 0 { degree += 1 }
        let target = ending ? 62 : 62 + [0, 2, 4, 5, 7, 9, 11][degree % 7] + 12 * (degree / 7)
        let cadence = ending || (bar % 4 == 3 && slot == 7)
        emit(EnsembleNote(role: .lead, time: t, midi: pitch(at: t, target: target, strong: slot % 2 == 0, cadence: cadence),
            strength: (position == 0 ? 0.42 : 0.31) * energy * gain(.lead), duration: cadence ? 1.65 : 1.05))
    }
}
