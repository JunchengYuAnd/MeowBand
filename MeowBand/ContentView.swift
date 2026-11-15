import SwiftUI
import SpriteKit
import AVFoundation

enum VisualMode: String, CaseIterable, Identifiable {
    case nightPond = "高对比夜池"
    case blackAndWhite = "黑白极简"
    var id: Self { self }
}

@MainActor
final class GameState: ObservableObject {
    enum Phase { case setup, playing, paused, finished }
    @Published var phase: Phase = .setup
    @Published var score = 0
    @Published var seconds = 180
    @Published var game: EnsembleRole = .drums
    @Published var audioError: String?
    @Published var visualMode: VisualMode = .nightPond
    @Published var speed: Double = 1
    @Published var targetSize: Double = 1
    @Published var sessionMinutes = 3

    weak var scene: FishGameScene?
    private var timer: Timer?

    var isPlaying: Bool { phase == .playing }

    func begin() {
        do { try scene?.startMusic(game: game) } catch { audioError = "声音暂时无法启动，请重试。"; return }
        audioError = nil
        score = 0; seconds = sessionMinutes * 60; phase = .playing
        scene?.configure(game: game, visualMode: visualMode, speed: speed, targetSize: targetSize)
        scene?.isPaused = false
        scene?.restartHunt()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard phase == .playing else { return }
        seconds -= 1
        if seconds <= 0 { finish() }
    }

    func caught(kind: String, at point: CGPoint, velocity: CGVector) {
        score += 1
        NotificationCenter.default.post(name: .meowBandCatch, object: nil, userInfo: [
            "prey": kind, "role": game.rawValue, "x": point.x, "y": point.y,
            "vx": velocity.dx, "vy": velocity.dy, "score": score,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func openOwnerMenu() {
        guard phase == .playing else { return }
        phase = .paused; scene?.isPaused = true; scene?.pauseMusic()
    }

    func resume() {
        do { try scene?.resumeMusic(game: game) } catch { audioError = "声音暂时无法恢复，请重试。"; return }
        audioError = nil
        scene?.configure(game: game, visualMode: visualMode, speed: speed, targetSize: targetSize)
        scene?.restartHunt(); phase = .playing; scene?.isPaused = false
    }
    func finish() { phase = .finished; scene?.isPaused = true; scene?.stopMusic(); timer?.invalidate() }
    func backToSetup() { phase = .setup; scene?.isPaused = true; scene?.stopMusic(); timer?.invalidate() }
}

extension Notification.Name {
    static let meowBandCatch = Notification.Name("meowband.catch")
    static let meowBandOwnerMenu = Notification.Name("meowband.ownerMenu")
}

struct ContentView: View {
    @StateObject private var state = GameState()
    @State private var scene: FishGameScene?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.02, green: 0.31, blue: 0.39).ignoresSafeArea()
                if let scene {
                    SpriteView(scene: scene, options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes])
                        .ignoresSafeArea()
                }
                if state.phase == .setup { setupView }
                if state.phase == .paused { ownerMenu }
                if state.phase == .finished { finishView }
            }
            .onAppear {
                guard scene == nil else { return }
                let newScene = FishGameScene(size: proxy.size)
                newScene.scaleMode = .resizeFill; newScene.gameState = state; newScene.isPaused = true
                state.scene = newScene; scene = newScene
            }
            .onReceive(NotificationCenter.default.publisher(for: .meowBandOwnerMenu)) { _ in state.openOwnerMenu() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { state.openOwnerMenu() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { state.openOwnerMenu() }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: state.phase)
    }

    private var setupView: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("MEOWBAND").font(.caption.weight(.black)).tracking(4).foregroundStyle(.yellow)
                    Text("小猫的四人乐队").font(.system(size: 40, weight: .black, design: .rounded))
                    Text("选一个游戏，让小猫带领一个声部。\n随意拍，乐队会接着演奏。")
                        .font(.title3).foregroundStyle(.white.opacity(0.75))
                    settingsPanel(buttonTitle: "开始游戏", action: state.begin)
                    Label("游戏中双指按住 2 秒打开主人设置", systemImage: "hand.raised.fingers.spread")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }.frame(maxWidth: 620).padding(32).frame(maxWidth: .infinity)
            }
        }
    }

    private var ownerMenu: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea().background(.ultraThinMaterial)
            ScrollView { settingsPanel(buttonTitle: "继续游戏", action: state.resume).frame(maxWidth: 620).padding(24).frame(maxWidth: .infinity) }
        }
    }

    private func settingsPanel(buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 22) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(EnsembleRole.allCases) { game in
                    Button { state.game = game } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(game.title, systemImage: game.icon).font(.headline)
                            Text(game.detail).font(.caption).multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(state.game == game ? Color.black : .white)
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading).padding(12)
                        .background(state.game == game ? Color.yellow : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityAddTraits(state.game == game ? .isSelected : [])
                }
            }
            Picker("画面", selection: $state.visualMode) {
                ForEach(VisualMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented)
            if let error = state.audioError { Text(error).foregroundStyle(.yellow).font(.subheadline) }
            settingSlider("猎物速度", value: $state.speed, range: 0.65...1.45, low: "悠闲", high: "敏捷")
            settingSlider("猎物大小", value: $state.targetSize, range: 0.8...1.35, low: "小", high: "大")
            Picker("时长", selection: $state.sessionMinutes) {
                Text("2 分钟").tag(2); Text("3 分钟").tag(3); Text("5 分钟").tag(5)
            }.pickerStyle(.segmented)
            Button(buttonTitle, action: action)
                .font(.title3.weight(.black)).foregroundStyle(Color(red: 0.04, green: 0.25, blue: 0.28))
                .frame(maxWidth: .infinity).frame(height: 58).background(.yellow, in: Capsule())
        }
        .padding(28)
        .background(Color(red: 0.03, green: 0.28, blue: 0.35).opacity(0.94), in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.3), radius: 35, y: 18)
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, low: String, high: String) -> some View {
        VStack(spacing: 7) {
            HStack { Text(title).fontWeight(.bold); Spacer(); Text(low); Text("—"); Text(high) }.font(.subheadline).foregroundStyle(.white.opacity(0.75))
            Slider(value: value, in: range).tint(.yellow)
        }
    }

    private var finishView: some View {
        ZStack {
            Color.black.opacity(0.46).ignoresSafeArea().background(.ultraThinMaterial)
            VStack(spacing: 18) {
                Image(systemName: "pawprint.fill").font(.system(size: 58)).foregroundStyle(.yellow)
                Text("捕猎结束").font(.system(size: 42, weight: .black, design: .rounded))
                Text("抓到了 \(state.score) 次").font(.title2.weight(.bold)).foregroundStyle(.white.opacity(0.72))
                Text("现在给小猫一个真实玩具或小零食，\n让捕猎有一个满足的结尾。")
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.66))
                HStack {
                    Button("调整设置", action: state.backToSetup).buttonStyle(.bordered)
                    Button("再玩一轮", action: state.begin).buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                }.controlSize(.large)
            }
            .padding(44).background(Color(red: 0.03, green: 0.28, blue: 0.35), in: RoundedRectangle(cornerRadius: 34))
        }
    }
}
