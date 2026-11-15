import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

for game in EnsembleRole.allCases {
    let conductor = EnsembleConductor(role: game)
    var notes: [EnsembleNote] = []
    conductor.output = { notes.append($0) }
    let hits = [1.2, 5.7, 10.8, 10.94, 11.06, 19.8, 29.3]
    var next = 0
    for frame in 0..<4000 {
        let time = Double(frame) / 100
        while next < hits.count && hits[next] <= time {
            let clock = conductor.tick
            conductor.touch(role: game, at: hits[next], variant: next)
            check(clock == conductor.tick, "A touch must not restart the clock")
            next += 1
        }
        conductor.advance(to: time)
    }
    check(Set(notes.map(\.role)).count == 4, "Every game retains the four-part ensemble")
    for time in hits {
        check(notes.contains { $0.direct && $0.role == game && $0.time == time }, "Every sparse hit responds immediately in the selected role")
    }
    let melody = notes.filter { $0.role == .lead }.map(\.midi)
    check(zip(melody, melody.dropFirst()).allSatisfy { abs($0 - $1) <= 9 }, "Melody must preserve nearby motion")
    check(notes.allSatisfy { $0.strength > 0 && $0.strength <= 1 && $0.duration > 0 }, "All voices have safe, finite levels")
    let score = notes.filter { !$0.direct }
    let bars = Dictionary(grouping: score.filter { $0.role != .pad }) { "\($0.role)-\(Int($0.time / EnsembleConductor.bar))" }
    for events in bars.values {
        let cap = events[0].role == .drums ? 9 : (events[0].role == .bass ? 4 : 5)
        check(events.count <= cap, "Automatic note budget exceeded")
    }
    print("PASS \(game.title): \(notes.count) notes, all four parts, immediate sparse-hit responses")
}

let quiet = EnsembleConductor(role: .pad)
var quietNotes: [EnsembleNote] = []
quiet.output = { quietNotes.append($0) }
for frame in 0..<4000 { quiet.advance(to: Double(frame) / 100) }
check(quiet.sleeping, "An idle ensemble must finish its phrase and settle")
check(!quietNotes.contains { $0.time > 31 }, "The idle ensemble must not play forever")
quiet.touch(role: .lead, at: 40, variant: 0)
quiet.advance(to: 41)
check(!quiet.sleeping, "A new touch wakes the ensemble")

let burst = EnsembleConductor(role: .lead)
var burstNotes: [EnsembleNote] = []
burst.output = { burstNotes.append($0) }
for _ in 0..<100 { burst.touch(role: .lead, at: 0, variant: 0) }
check(burstNotes.count == 6, "A simultaneous burst must be bounded")
check(burst.activity <= 1, "Activity is saturated")
let before = burstNotes.count
burst.advance(to: 120)
check(burstNotes.count - before < 12, "Suspension must not replay old notes")
check(EnsembleRole.allCases.map(\.preyCount) == [4, 2, 1, 3], "Four games have distinct prey populations")
print("PASS idle cadence, wake, burst limit and bounded suspension catch-up")
