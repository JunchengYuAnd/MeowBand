import SwiftUI
import SpriteKit

enum PreyChoice: String, CaseIterable, Identifiable {
    case fish = "小鱼"
    case shrimp = "小虾"
    case moth = "飞蛾"
    var id: Self { self }
    var icon: String { switch self { case .fish: "fish.fill"; case .shrimp: "water.waves"; case .moth: "sparkles" } }
}

enum MusicMode: String, CaseIterable, Identifiable {
    case drums = "鼓组"
    case guitar = "吉他"
    var id: Self { self }
}

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
    @Published var preyChoice: PreyChoice = .fish
    @Published var musicMode: MusicMode = .drums
    @Published var visualMode: VisualMode = .nightPond
    @Published var speed: Double = 1
    @Published var targetSize: Double = 1
    @Published var sessionMinutes = 3

    weak var scene: FishGameScene?
    private var timer: Timer?

    var isPlaying: Bool { phase == .playing }

    func begin() {
        score = 0; seconds = sessionMinutes * 60; phase = .playing
        scene?.configure(musicMode: musicMode, visualMode: visualMode, speed: speed, targetSize: targetSize)
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
            "prey": kind, "x": point.x, "y": point.y,
            "vx": velocity.dx, "vy": velocity.dy, "score": score,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func openOwnerMenu() {
        guard phase == .playing else { return }
        phase = .paused; scene?.isPaused = true
    }

    func resume() {
        scene?.configure(musicMode: musicMode, visualMode: visualMode, speed: speed, targetSize: targetSize)
        scene?.restartHunt(); phase = .playing; scene?.isPaused = false
    }
    func finish() { phase = .finished; scene?.isPaused = true; timer?.invalidate() }
    func backToSetup() { phase = .setup; scene?.isPaused = true; timer?.invalidate() }
}

extension Notification.Name {
    static let meowBandCatch = Notification.Name("meowband.catch")
    static let meowBandOwnerMenu = Notification.Name("meowband.ownerMenu")
}

struct ContentView: View {
    @StateObject private var state = GameState()
    @State private var scene: FishGameScene?

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
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: state.phase)
    }

    private var setupView: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            HStack(spacing: 44) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MEOWBAND").font(.caption.weight(.black)).tracking(4).foregroundStyle(.yellow)
                    Text(state.musicMode == .drums ? "让小猫来打鼓" : "让小猫弹吉他")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Text(state.musicMode == .drums ? "每种猎物都是一面鼓。\n抓到它，就敲响它。" : "每种猎物都是一根琴弦。\n抓到它，就拨响它。")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.72)).lineSpacing(5)
                    Label("游戏中双指按住 2 秒打开主人设置", systemImage: "hand.raised.fingers.spread")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.58)).padding(.top, 10)
                }.frame(maxWidth: 430, alignment: .leading)
                settingsPanel(buttonTitle: "开始捕猎", action: state.begin)
            }
            .padding(50)
        }
    }

    private var ownerMenu: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea().background(.ultraThinMaterial)
            settingsPanel(buttonTitle: "继续游戏", action: state.resume)
                .frame(maxWidth: 520)
        }
    }

    private func settingsPanel(buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 22) {
            Picker("乐器", selection: $state.musicMode) {
                ForEach(MusicMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            Picker("画面", selection: $state.visualMode) {
                ForEach(VisualMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                if state.musicMode == .drums {
                    instrumentLegend("fish.fill", "底鼓", .yellow)
                    instrumentLegend("circle.grid.cross", "军鼓", .cyan)
                    instrumentLegend("water.waves", "踩镲", .orange)
                    instrumentLegend("circle.hexagongrid", "嗵鼓", .purple)
                    instrumentLegend("sparkles", "镲片", .white)
                } else {
                    instrumentLegend("circle.fill", "低音 E", .orange)
                    instrumentLegend("circle.fill", "A", .yellow)
                    instrumentLegend("circle.fill", "D", .cyan)
                    instrumentLegend("circle.fill", "G", .blue)
                    instrumentLegend("sparkles", "高音 E", .purple)
                }
            }
            settingSlider("速度", value: $state.speed, range: 0.65...1.45, low: "悠闲", high: "敏捷")
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

    private func instrumentLegend(_ icon: String, _ name: String, _ color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(name).font(.caption.weight(.black))
        }
        .frame(maxWidth: .infinity).frame(height: 66)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
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
