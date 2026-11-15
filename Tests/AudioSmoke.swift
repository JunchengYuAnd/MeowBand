import Foundation
import AVFoundation

@main
struct AudioSmoke {
    @MainActor static func main() async throws {
        let audio = EnsembleAudio()
        for role in EnsembleRole.allCases {
            try audio.start(role: role)
            for i in 0..<40 {
                audio.update()
                if i % 8 == 0 { audio.touch(role: role, variant: i / 8) }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            audio.pause()
            try await Task.sleep(nanoseconds: 80_000_000)
            try audio.resume()
            for _ in 0..<10 { audio.update(); try await Task.sleep(nanoseconds: 30_000_000) }
            audio.stop()
            print("PASS audio render, touch, pause, resume, stop: \(role.rawValue)")
        }
    }
}
