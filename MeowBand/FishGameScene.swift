import SpriteKit
import UIKit

final class FishGameScene: SKScene {
    enum Instrument: String, CaseIterable { case kick = "底鼓", snare = "军鼓", hiHat = "踩镲", highTom = "高嗵鼓", floorTom = "低嗵鼓", crash = "镲片" }
    private enum HuntState { case entering, roaming, frozen, dashing, hiding, captured }
    private final class PreyAgent {
        let node: SKSpriteNode
        let instrument: Instrument
        var state: HuntState = .entering
        var velocity = CGVector.zero
        var stateUntil: TimeInterval = 0
        var speedPulse = 1.0
        init(node: SKSpriteNode, instrument: Instrument) { self.node = node; self.instrument = instrument }
    }

    weak var gameState: GameState?
    private let world = SKNode()
    private var agents: [PreyAgent] = []
    private var game: EnsembleRole = .drums
    private var visualMode: VisualMode = .nightPond
    private var lastUpdate: TimeInterval = 0
    private var lastInteraction = Date()
    private var skillLevel = 0.0
    private var speedSetting = 1.0
    private var sizeSetting = 1.0
    private var activeTouches: Set<ObjectIdentifier> = []
    private var ownerHoldWork: DispatchWorkItem?
    private let music = EnsembleAudio()
    private var musicGame: EnsembleRole?
    private var desiredPreyCount: Int { game.preyCount }

    func startMusic(game: EnsembleRole) throws { try music.start(role: game); musicGame = game }
    func pauseMusic() { music.pause(); ownerHoldWork?.cancel(); activeTouches.removeAll() }
    func stopMusic() { music.stop(); musicGame = nil }
    func resumeMusic(game: EnsembleRole) throws {
        if musicGame == game { try music.resume() } else { try startMusic(game: game) }
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.01, green: 0.06, blue: 0.13, alpha: 1)
        addChild(world); buildEnvironment(); refillPrey(after: 0)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard oldSize != .zero, view != nil else { return }
        buildEnvironment(); refillPrey(after: 0.1)
    }

    func configure(game: EnsembleRole, visualMode: VisualMode, speed: Double, targetSize: Double) {
        self.game = game; self.visualMode = visualMode
        speedSetting = speed; sizeSetting = targetSize
        buildEnvironment()
    }

    func restartHunt() {
        skillLevel = 0; lastInteraction = Date()
        agents.forEach { $0.node.removeFromParent() }; agents.removeAll()
        refillPrey(after: 0.12)
    }

    private func buildEnvironment() {
        world.removeAllChildren(); agents.removeAll()
        if visualMode == .blackAndWhite {
            backgroundColor = .white
            return
        }
        backgroundColor = UIColor(red: 0.01, green: 0.06, blue: 0.13, alpha: 1)
        let backdrop = SKSpriteNode(imageNamed: "UnderwaterBackground")
        backdrop.anchorPoint = .zero
        let textureSize = backdrop.texture?.size() ?? size
        let scale = max(size.width / textureSize.width, size.height / textureSize.height)
        backdrop.size = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
        backdrop.position = CGPoint(x: (size.width - backdrop.size.width) / 2, y: 0)
        backdrop.color = UIColor(red: 0.0, green: 0.05, blue: 0.13, alpha: 1)
        backdrop.colorBlendFactor = 0.72
        backdrop.alpha = 0.78
        backdrop.zPosition = -20; world.addChild(backdrop)
        for index in 0..<4 { addBubble(index: index) }
    }

    private func addBubble(index: Int) {
        let bubble = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...7))
        bubble.strokeColor = UIColor(red: 0.46, green: 0.86, blue: 1, alpha: 0.16)
        bubble.lineWidth = 1.3; bubble.fillColor = .clear
        bubble.position = CGPoint(x: CGFloat.random(in: 20...max(21, size.width - 20)), y: CGFloat.random(in: 0...max(1, size.height)))
        bubble.zPosition = -4; world.addChild(bubble)
        let rise = SKAction.moveBy(x: CGFloat.random(in: -22...22), y: size.height + 80, duration: Double.random(in: 8...14))
        bubble.run(.repeatForever(.sequence([.wait(forDuration: Double(index) * 0.16), rise, .moveBy(x: 0, y: -(size.height + 80), duration: 0)])))
    }

    private func assetName(for instrument: Instrument) -> String {
        switch instrument {
        case .kick: return "FishSunshine"
        case .snare: return "FishBlue"
        case .hiHat: return "PreyShrimp"
        case .highTom: return "FishLilac"
        case .floorTom: return "FishCoral"
        case .crash: return "PreyMoth"
        }
    }

    private func refillPrey(after delay: TimeInterval) {
        let missing = desiredPreyCount - agents.count
        guard missing > 0 else { return }
        for index in 0..<missing { spawnPrey(after: delay + Double(index) * 0.28) }
    }

    private func spawnPrey(after delay: TimeInterval) {
        let choices: [Instrument] = switch game {
        case .drums: [.hiHat, .crash, .hiHat, .crash]
        case .pad: [.kick, .snare]
        case .bass: [.floorTom]
        case .lead: [.highTom, .snare, .kick]
        }
        let instrument = choices.first { item in !agents.contains { $0.instrument == item } } ?? choices.randomElement()!
        let node = SKSpriteNode(imageNamed: assetName(for: instrument))
        let textureSize = node.texture?.size() ?? CGSize(width: 2, height: 1)
        let adaptiveEase = max(0.86, 1 - skillLevel * 0.018)
        let width = CGFloat(Double.random(in: 154...198) * sizeSetting * game.size * adaptiveEase)
        node.size = CGSize(width: width, height: width * textureSize.height / textureSize.width)
        node.zPosition = CGFloat.random(in: 3...7); node.alpha = 0; node.setScale(0.72)
        if visualMode == .blackAndWhite {
            node.color = .black
            node.colorBlendFactor = 1
        } else {
            addHighContrastHalo(to: node, instrument: instrument)
        }
        let fromLeft = Bool.random()
        node.position = CGPoint(x: fromLeft ? -width : size.width + width, y: freeY())
        node.xScale = fromLeft ? abs(node.xScale) : -abs(node.xScale)
        world.addChild(node)
        let agent = PreyAgent(node: node, instrument: instrument); agents.append(agent)
        let destination = CGPoint(x: CGFloat.random(in: size.width * 0.18...size.width * 0.82), y: freeY())
        let reveal: SKAction = visualMode == .blackAndWhite ? .fadeAlpha(to: 1, duration: 0) : .fadeIn(withDuration: 0.18)
        node.run(.sequence([.wait(forDuration: delay), .group([reveal, .scale(to: 1, duration: 0.22), .move(to: destination, duration: Double.random(in: 0.65...1.15) / speedSetting)])])) { [weak self, weak agent] in
            guard let self, let agent else { return }; self.beginRoaming(agent)
        }
    }

    private func freeY() -> CGFloat {
        if game == .bass { return CGFloat.random(in: 90...max(91, size.height * 0.42)) }
        return CGFloat.random(in: 90...max(91, size.height - 105))
    }

    private func addHighContrastHalo(to node: SKSpriteNode, instrument: Instrument) {
        guard let texture = node.texture else { return }
        let haloColor: UIColor = switch instrument {
        case .kick, .hiHat, .crash: UIColor(red: 1.0, green: 0.93, blue: 0.25, alpha: 1)
        case .snare, .highTom, .floorTom: UIColor(red: 0.76, green: 0.95, blue: 1.0, alpha: 1)
        }

        let outer = SKSpriteNode(texture: texture)
        outer.size = node.size
        outer.color = haloColor
        outer.colorBlendFactor = 1
        outer.alpha = 0.33
        outer.setScale(1.13)
        outer.zPosition = -2
        outer.blendMode = .add
        node.addChild(outer)

        let rim = SKSpriteNode(texture: texture)
        rim.size = node.size
        rim.color = .white
        rim.colorBlendFactor = 1
        rim.alpha = 0.34
        rim.setScale(1.055)
        rim.zPosition = -1
        rim.blendMode = .screen
        node.addChild(rim)
    }

    private func beginRoaming(_ agent: PreyAgent) {
        guard agent.node.parent != nil else { return }
        agent.state = .roaming
        let base = Double.random(in: 42...82) * speedSetting * game.movement * (1 + skillLevel * 0.025)
        agent.speedPulse = Double.random(in: 0.72...1.25)
        agent.velocity = CGVector(dx: (Bool.random() ? 1 : -1) * base, dy: Double.random(in: -24...24))
        agent.stateUntil = lastUpdate + Double.random(in: 0.65...2.25)
    }

    override func update(_ currentTime: TimeInterval) {
        guard gameState?.isPlaying == true else { lastUpdate = currentTime; return }
        music.update()
        let dt = min(currentTime - lastUpdate, 1.0 / 30.0); lastUpdate = currentTime
        guard dt > 0 else { return }
        for agent in agents where agent.node.parent != nil {
            update(agent, time: currentTime, dt: dt)
        }
        if Date().timeIntervalSince(lastInteraction) > 18 {
            lastInteraction = Date(); lureAttention()
        }
    }

    private func update(_ agent: PreyAgent, time: TimeInterval, dt: TimeInterval) {
        let node = agent.node
        switch agent.state {
        case .roaming, .dashing:
            // Independent sine pulses continuously accelerate and relax every prey.
            let pulse = 0.72 + 0.42 * (sin(time * agent.speedPulse * 2.4 + Double(node.hashValue % 17)) + 1) / 2
            node.position.x += agent.velocity.dx * pulse * dt
            node.position.y += agent.velocity.dy * dt + sin(time * 3.1 + Double(node.hashValue % 11)) * 8 * dt
            face(agent); keepInArea(agent)
            if time >= agent.stateUntil { chooseNextBehavior(agent, at: time) }
        case .frozen:
            node.zRotation = sin(time * 22 + Double(node.hashValue % 9)) * 0.028
            if time >= agent.stateUntil { dash(agent, at: time) }
        case .hiding:
            if time >= agent.stateUntil { reappear(agent) }
        case .entering, .captured: break
        }
    }

    private func chooseNextBehavior(_ agent: PreyAgent, at time: TimeInterval) {
        if game == .pad { beginRoaming(agent); return }
        let roll = Double.random(in: 0...1)
        if roll < 0.34 {
            agent.state = .frozen; agent.velocity = .zero
            agent.stateUntil = time + Double.random(in: 0.35...1.25)
        } else if roll < 0.78 {
            dash(agent, at: time)
        } else {
            hide(agent)
        }
    }

    private func dash(_ agent: PreyAgent, at time: TimeInterval) {
        agent.state = .dashing
        let magnitude = Double.random(in: 120...210) * speedSetting * game.movement * (1 + skillLevel * 0.025)
        agent.velocity = CGVector(dx: (Bool.random() ? 1 : -1) * magnitude, dy: Double.random(in: -90...90))
        agent.stateUntil = time + Double.random(in: 0.28...0.82)
        agent.node.run(.sequence([.scale(to: 1.08, duration: 0.07), .scale(to: 1, duration: 0.13)]))
    }

    private func hide(_ agent: PreyAgent) {
        agent.state = .hiding
        let edgeX: CGFloat = agent.node.position.x < size.width / 2 ? 18 : size.width - 18
        let hiddenAlpha: CGFloat = visualMode == .blackAndWhite ? 1 : 0.12
        agent.node.run(.group([.moveTo(x: edgeX, duration: 0.38), .fadeAlpha(to: hiddenAlpha, duration: 0.38), .scale(to: 0.78, duration: 0.38)]))
        agent.stateUntil = lastUpdate + Double.random(in: 0.55...1.45)
    }

    private func reappear(_ agent: PreyAgent) {
        agent.state = .entering
        let destination = CGPoint(x: CGFloat.random(in: size.width * 0.18...size.width * 0.82), y: freeY())
        let reveal: SKAction = visualMode == .blackAndWhite ? .fadeAlpha(to: 1, duration: 0) : .fadeIn(withDuration: 0.18)
        agent.node.run(.group([reveal, .scale(to: 1, duration: 0.2), .move(to: destination, duration: 0.55)])) { [weak self, weak agent] in
            guard let self, let agent else { return }; self.beginRoaming(agent)
        }
    }

    private func lureAttention() {
        for agent in agents.filter({ $0.state != .captured }).shuffled().prefix(2) {
            let node = agent.node, original = node.position
            node.run(.sequence([.moveBy(x: -18, y: 9, duration: 0.08), .moveBy(x: 36, y: -18, duration: 0.1), .move(to: original, duration: 0.1)]))
        }
    }

    private func face(_ agent: PreyAgent) {
        guard abs(agent.velocity.dx) > 1 else { return }
        agent.node.xScale = agent.velocity.dx < 0 ? -abs(agent.node.xScale) : abs(agent.node.xScale)
        agent.node.zRotation = CGFloat(agent.velocity.dy / 900)
    }

    private func keepInArea(_ agent: PreyAgent) {
        let node = agent.node, margin = max(52, node.size.width * 0.25)
        if node.position.x < margin { node.position.x = margin; agent.velocity.dx = abs(agent.velocity.dx) * Double.random(in: 0.75...1.2) }
        if node.position.x > size.width - margin { node.position.x = size.width - margin; agent.velocity.dx = -abs(agent.velocity.dx) * Double.random(in: 0.75...1.2) }
        if node.position.y < 70 { node.position.y = 70; agent.velocity.dy = abs(agent.velocity.dy) + 12 }
        let ceiling = game == .bass ? max(91, size.height * 0.42) : size.height - 75
        if node.position.y > ceiling { node.position.y = ceiling; agent.velocity.dy = -abs(agent.velocity.dy) - 12 }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.formUnion(touches.map { ObjectIdentifier($0) })
        if activeTouches.count >= 2 { beginOwnerHold() }
        guard gameState?.isPlaying == true else { return }
        for touch in touches { handlePounce(at: touch.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches.map { ObjectIdentifier($0) })
        if activeTouches.count < 2 { ownerHoldWork?.cancel() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }

    private func beginOwnerHold() {
        ownerHoldWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeTouches.count >= 2 else { return }
            NotificationCenter.default.post(name: .meowBandOwnerMenu, object: nil)
        }
        ownerHoldWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func handlePounce(at point: CGPoint) {
        lastInteraction = Date(); makeRipple(at: point)
        let available = agents.filter { $0.state != .captured && $0.node.alpha > 0.35 }
        guard let nearest = available.min(by: { $0.node.position.distance(to: point) < $1.node.position.distance(to: point) }) else { return }
        let hitRadius = max(68, nearest.node.size.width * 0.5)
        if nearest.node.position.distance(to: point) <= hitRadius {
            capture(nearest, at: point)
        } else {
            skillLevel = max(-2, skillLevel - 0.22)
            for agent in available where agent.node.position.distance(to: point) < 260 { flee(agent, from: point) }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func flee(_ agent: PreyAgent, from point: CGPoint) {
        agent.state = .dashing
        let dx = agent.node.position.x - point.x, dy = agent.node.position.y - point.y
        let length = max(1, hypot(dx, dy)), speed = Double.random(in: 155...225) * speedSetting * game.movement
        agent.velocity = CGVector(dx: dx / length * speed, dy: dy / length * speed)
        agent.stateUntil = lastUpdate + Double.random(in: 0.5...0.9)
    }

    private func capture(_ agent: PreyAgent, at point: CGPoint) {
        agent.state = .captured; let caughtVelocity = agent.velocity; agent.velocity = .zero
        skillLevel = min(8, skillLevel + 0.55)
        let variant = Instrument.allCases.firstIndex(of: agent.instrument) ?? 0
        gameState?.caught(kind: game.rawValue, at: point, velocity: caughtVelocity)
        music.touch(role: game, variant: variant)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        makeSplash(at: agent.node.position, instrument: agent.instrument)
        let wiggles: [SKAction] = [.rotate(toAngle: 0.12, duration: 0.06), .rotate(toAngle: -0.13, duration: 0.07), .rotate(toAngle: 0.08, duration: 0.06), .rotate(toAngle: 0, duration: 0.06)]
        agent.node.run(.sequence([.scale(to: 0.9, duration: 0.08), .sequence(wiggles), .wait(forDuration: 0.16), .group([.scale(to: 0.16, duration: 0.2), .fadeOut(withDuration: 0.2)])])) { [weak self, weak agent] in
            guard let self, let agent else { return }
            agent.node.removeFromParent(); self.agents.removeAll { $0 === agent }
            self.refillPrey(after: Double.random(in: 0.45...1.0))
        }
    }

    private func makeRipple(at point: CGPoint) {
        for delay in [0.0, 0.08, 0.16] {
            let ring = SKShapeNode(circleOfRadius: 12); ring.position = point
            ring.strokeColor = visualMode == .blackAndWhite ? .black : .white
            ring.lineWidth = 3; ring.alpha = 0.75; ring.zPosition = 12
            world.addChild(ring); ring.run(.sequence([.wait(forDuration: delay), .group([.scale(to: 5.5, duration: 0.46), .fadeOut(withDuration: 0.46)]), .removeFromParent()]))
        }
    }

    private func makeSplash(at point: CGPoint, instrument: Instrument) {
        let accent: UIColor
        if visualMode == .blackAndWhite {
            accent = .black
        } else {
            accent = switch instrument {
            case .kick: .systemYellow
            case .snare: .white
            case .hiHat: .systemOrange
            case .highTom: .systemPurple
            case .floorTom: .systemRed
            case .crash: .systemYellow
            }
        }
        for _ in 0..<18 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...7)); drop.position = point
            drop.fillColor = visualMode == .blackAndWhite ? (Bool.random() ? .black : .darkGray) : (Bool.random() ? .white : accent)
            drop.strokeColor = .clear; drop.zPosition = 14; world.addChild(drop)
            drop.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -105...105), y: CGFloat.random(in: -85...110), duration: 0.52), .fadeOut(withDuration: 0.52), .scale(to: 0.1, duration: 0.52)]), .removeFromParent()]))
        }
    }

}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat { hypot(x - point.x, y - point.y) }
}
