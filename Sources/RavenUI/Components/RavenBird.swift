import SwiftUI

// The one raven of Raven (owner rule): every raven in every Raven app is this bird. Ported from the
// iPhone app (raven-ios Shared/RavenFigure.swift, 2ecbdab); Resources/Design/raven-bird.json and
// raven-bird.svg carry the same geometry, colours, poses and timings, and `RavenBirdTests` checks this
// file against them.
//
// Light: an ink raven (textPrimary), the wing textSecondary, a white eye (surface). Dark: a black
// raven (#0B0B0B) with a thin light outline (textTertiary, 1 pt), the wing a step lighter (#3C3C3C), a
// light eye (textPrimary).

/// The raven's geometry in its own units: a 120 by 100 box facing right, the feet at (66, 90).
enum RavenGeometry {
    /// One drawing step; the same list makes the SwiftUI path and the SVG path data.
    enum Seg {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case close
    }

    static let tail: [Seg] = [.move(26, 82), .line(15, 95), .line(24, 98), .line(50, 80), .close]
    static let body: [Seg] = [.move(73, 19), .quad(52, 28, 44, 52), .quad(34, 70, 26, 82), .line(50, 80), .quad(60, 82, 68, 78),
                              .quad(84, 72, 87, 54), .line(89, 47), .line(86, 44), .line(90, 40), .line(87, 36),
                              .quad(90, 33, 88, 30), .close]
    static let head = CGRect(x: 69, y: 12, width: 22, height: 21)
    static let beak: [Seg] = [.move(86, 15), .quad(102, 15, 108, 27), .quad(99, 31, 88, 31), .close]
    static let eye = CGRect(x: 83, y: 19, width: 3.6, height: 3.6)
    /// The shut eye: a small curved line (asleep).
    static let eyeShut: [Seg] = [.move(82.4, 20.6), .quad(84.8, 23.4, 87.2, 20.6)]
    static let foldedWing: [Seg] = [.move(72, 35), .quad(42, 46, 21, 88), .line(29, 90), .quad(54, 78, 70, 62), .quad(80, 46, 72, 35), .close]
    static let feathers: [Seg] = [.move(52, 60), .line(30, 84), .move(58, 64), .line(36, 86), .move(64, 66), .line(44, 84)]
    static let legs: [Seg] = [.move(61, 76), .line(60, 90), .move(69, 74), .line(70, 90), .move(54, 91), .line(65, 91), .move(64, 91), .line(75, 91)]

    /// Pivots: the feet (lean, breath), the body centre (pitch), the neck (head), the shoulder (wing).
    static let feet = CGPoint(x: 66, y: 90)
    static let bodyCentre = CGPoint(x: 60, y: 56)
    static let neck = CGPoint(x: 76, y: 30)
    static let shoulder = CGPoint(x: 66, y: 40)
    static let beakTip = CGPoint(x: 107, y: 28)

    /// The open wing from the shoulder, swept back, with the raven's fingered tip; `k` scales its
    /// height (1 up, negative down).
    static func wing(_ k: Double) -> [Seg] {
        let s = shoulder
        func pt(_ dx: Double, _ dy: Double) -> (Double, Double) { (s.x + dx, s.y + dy * k) }
        var p: [Seg] = [.move(s.x, s.y)]
        let a = pt(-2, -30), b = pt(-16, -40), c = pt(-28, -52), d = pt(-44, -60)
        p.append(.quad(a.0, a.1, b.0, b.1))
        p.append(.quad(c.0, c.1, d.0, d.1))
        for (dx, dy) in [(-49.0, -55.0), (-48.0, -51.0), (-55.0, -48.0), (-53.0, -44.0), (-60.0, -41.0), (-56.0, -37.0), (-62.0, -33.0)] {
            let q = pt(dx, dy)
            p.append(.line(q.0, q.1))
        }
        let e = pt(-46, -8), f = pt(-24, 4), g = pt(-10, 6)
        p.append(.quad(e.0, e.1, f.0, f.1))
        p.append(.quad(g.0, g.1, s.x, s.y))
        p.append(.close)
        return p
    }

    static func path(_ segs: [Seg]) -> Path {
        var p = Path()
        for s in segs {
            switch s {
            case let .move(x, y): p.move(to: CGPoint(x: x, y: y))
            case let .line(x, y): p.addLine(to: CGPoint(x: x, y: y))
            case let .quad(cx, cy, x, y): p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case .close: p.closeSubpath()
            }
        }
        return p
    }

    /// SVG path data of the same steps (as in raven-bird.json).
    static func svg(_ segs: [Seg]) -> String {
        func n(_ v: Double) -> String {
            let r = (v * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        return segs.map { s -> String in
            switch s {
            case let .move(x, y): return "M\(n(x)) \(n(y))"
            case let .line(x, y): return "L\(n(x)) \(n(y))"
            case let .quad(cx, cy, x, y): return "Q\(n(cx)) \(n(cy)) \(n(x)) \(n(y))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
}

/// Draws the raven in a GraphicsContext.
enum RavenFigure {
    struct Pose: Equatable {
        /// Degrees about the feet; positive leans forward (down to the letter).
        var lean: Double = 0
        /// Degrees about the body; flying posture.
        var pitch: Double = 0
        /// Degrees about the neck; positive tips the beak down.
        var head: Double = 0
        /// 0 folded, 1 open.
        var spread: Double = 0
        /// Wing height while open: 1 up, about minus 0.6 down.
        var beat: Double = 1
        /// 0 tucked, 1 down.
        var legs: Double = 1
        /// Vertical scale about the feet (the breath).
        var breath: Double = 1
        /// 0 awake, 1 asleep: the head turned back onto the back, the beak under the puffed wing,
        /// the eye shut.
        var sleep: Double = 0
        var letterInBeak = false
        /// Your card in the beak, instead of a letter.
        var cardInBeak = false
    }

    struct Colors {
        var ink: Color
        var wing: Color
        var eye: Color
        /// A thin light outline around the bird (dark mode), drawn behind the fills.
        var outline: Color?
        var paper: Color
        var line: Color
        var seal: Color
        /// The visible outline width in points.
        var outlineWidth: CGFloat = 1
    }

    static let feetLocal = RavenGeometry.feet
    static let neck = RavenGeometry.neck
    static let beakTip = RavenGeometry.beakTip

    static let tailPath = RavenGeometry.path(RavenGeometry.tail)
    static let bodyPath = RavenGeometry.path(RavenGeometry.body)
    static let headPath = Path(ellipseIn: RavenGeometry.head)
    static let beakPath = RavenGeometry.path(RavenGeometry.beak)
    static let eyePath = Path(ellipseIn: RavenGeometry.eye)
    static let eyeShutPath = RavenGeometry.path(RavenGeometry.eyeShut)
    static let foldedWing = RavenGeometry.path(RavenGeometry.foldedWing)
    static let featherLines = RavenGeometry.path(RavenGeometry.feathers)
    static let legs = RavenGeometry.path(RavenGeometry.legs)
    static func wing(_ k: Double) -> Path { RavenGeometry.path(RavenGeometry.wing(k)) }

    /// How far the head moves when asleep: turned to face back (mirrored about the neck), lowered
    /// onto the back.
    static let sleepHeadShift = CGPoint(x: 0, y: 9)
    /// The folded wing puffs up while asleep (scale about the shoulder) and rises over the beak.
    static let sleepWingPuff = 0.1
    static let sleepWingRise = -3.0

    static func body(_ ctx: GraphicsContext, feet: CGPoint, scale: CGFloat, pose: Pose) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: feet.x, y: feet.y)
        c.scaleBy(x: scale, y: scale)
        c.rotate(by: .degrees(pose.lean))
        c.scaleBy(x: 1, y: pose.breath)
        c.translateBy(x: -feetLocal.x, y: -feetLocal.y)
        let b = RavenGeometry.bodyCentre
        c.translateBy(x: b.x, y: b.y)
        c.rotate(by: .degrees(pose.pitch))
        c.translateBy(x: -b.x, y: -b.y)
        return c
    }

    static func head(_ c: GraphicsContext, pose: Pose) -> GraphicsContext {
        var h = c
        h.translateBy(x: neck.x + sleepHeadShift.x * pose.sleep, y: neck.y + sleepHeadShift.y * pose.sleep)
        h.rotate(by: .degrees(pose.head))
        h.scaleBy(x: 1 - 2 * pose.sleep, y: 1)
        h.translateBy(x: -neck.x, y: -neck.y)
        return h
    }

    static func foldedWingContext(_ c: GraphicsContext, pose: Pose) -> GraphicsContext {
        guard pose.sleep > 0 else { return c }
        var w = c
        let s = RavenGeometry.shoulder
        let k = 1 + sleepWingPuff * pose.sleep
        w.translateBy(x: s.x, y: s.y + sleepWingRise * pose.sleep)
        w.scaleBy(x: k, y: k)
        w.translateBy(x: -s.x, y: -s.y)
        return w
    }

    /// Where the beak tip is on screen, for the letter and the call (awake poses).
    static func beakPoint(feet: CGPoint, scale: CGFloat, pose: Pose) -> CGPoint {
        var p = beakTip
        p = rotate(p, about: neck, degrees: pose.head)
        p = rotate(p, about: RavenGeometry.bodyCentre, degrees: pose.pitch)
        p = CGPoint(x: p.x - feetLocal.x, y: (p.y - feetLocal.y) * pose.breath)
        p = rotate(p, about: .zero, degrees: pose.lean)
        return CGPoint(x: feet.x + p.x * scale, y: feet.y + p.y * scale)
    }

    private static func rotate(_ p: CGPoint, about o: CGPoint, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = p.x - o.x, dy = p.y - o.y
        return CGPoint(x: o.x + dx * cos(a) - dy * sin(a), y: o.y + dx * sin(a) + dy * cos(a))
    }

    static func draw(_ ctx: GraphicsContext, feet: CGPoint, scale: CGFloat, pose: Pose, colors: Colors) {
        let c = body(ctx, feet: feet, scale: scale, pose: pose)
        let h = head(c, pose: pose)
        let asleep = pose.sleep > 0.5
        // The outline: twice its width, behind every fill, so only the outer half shows.
        let rim = 2 * colors.outlineWidth / max(scale, 0.01)
        if let outline = colors.outline {
            let style = StrokeStyle(lineWidth: rim, lineCap: .round, lineJoin: .round)
            c.stroke(tailPath, with: .color(outline), style: style)
            c.stroke(bodyPath, with: .color(outline), style: style)
            h.stroke(headPath, with: .color(outline), style: style)
            h.stroke(beakPath, with: .color(outline), style: style)
            if pose.spread > 0.01 {
                var far = c
                far.opacity = pose.spread
                far.translateBy(x: 5, y: -3)
                far.stroke(wing(pose.beat * 0.8), with: .color(outline), style: style)
            }
        }
        if pose.spread > 0.01 {
            var far = c
            far.opacity = 0.55 * pose.spread
            far.translateBy(x: 5, y: -3)
            far.fill(wing(pose.beat * 0.8), with: .color(colors.wing))
        }
        c.fill(tailPath, with: .color(colors.ink))
        c.fill(bodyPath, with: .color(colors.ink))
        if pose.legs > 0.01 {
            var l = c
            l.opacity = pose.legs
            l.stroke(legs, with: .color(colors.outline ?? colors.ink),
                     style: StrokeStyle(lineWidth: colors.outline == nil ? 2.6 : 2, lineCap: .round, lineJoin: .round))
        }
        func folded() {
            guard pose.spread < 0.99 else { return }
            var f = foldedWingContext(c, pose: pose)
            f.opacity = 1 - pose.spread
            f.fill(foldedWing, with: .color(colors.wing))
            f.stroke(featherLines, with: .color(colors.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        // Awake the head is in front of the wing; asleep the puffed wing covers the beak.
        if !asleep { folded() }
        h.fill(headPath, with: .color(colors.ink))
        h.fill(beakPath, with: .color(colors.ink))
        if asleep {
            h.stroke(eyeShutPath, with: .color(colors.eye), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        } else {
            h.fill(eyePath, with: .color(colors.eye))
        }
        if asleep { folded() }
        if pose.letterInBeak || pose.cardInBeak {
            var l = h
            l.translateBy(x: beakTip.x - 6, y: beakTip.y + 4)
            l.rotate(by: .degrees(14))
            if pose.cardInBeak {
                cardShape(l, size: CGSize(width: 22, height: 15), colors: colors)
            } else {
                letterShape(l, size: CGSize(width: 20, height: 13), colors: colors)
            }
        }
        if pose.spread > 0.01 {
            var near = c
            near.opacity = pose.spread
            if let outline = colors.outline {
                near.stroke(wing(pose.beat), with: .color(outline), style: StrokeStyle(lineWidth: rim, lineCap: .round, lineJoin: .round))
            }
            near.fill(wing(pose.beat), with: .color(colors.wing))
        }
    }

    /// The sealed letter, centred at `center`.
    static func letter(_ ctx: GraphicsContext, center: CGPoint, scale: CGFloat, colors: Colors) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: scale, y: scale)
        letterShape(c, size: CGSize(width: 30, height: 20), colors: colors)
    }

    static func letterShape(_ c: GraphicsContext, size: CGSize, colors: Colors) {
        let r = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let paper = Path(roundedRect: r, cornerRadius: size.height * 0.12)
        c.fill(paper, with: .color(colors.paper))
        c.stroke(paper, with: .color(colors.line), lineWidth: 1.2)
        var flap = Path()
        flap.move(to: CGPoint(x: r.minX + 1, y: r.minY + 1))
        flap.addLine(to: CGPoint(x: 0, y: r.minY + size.height * 0.56))
        flap.addLine(to: CGPoint(x: r.maxX - 1, y: r.minY + 1))
        c.stroke(flap, with: .color(colors.line), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
        let d = size.height * 0.42
        c.fill(Path(ellipseIn: CGRect(x: -d / 2, y: r.minY + size.height * 0.56 - d / 2, width: d, height: d)), with: .color(colors.seal))
    }

    /// Your card: a small rounded card with a seal dot and two lines (never a word on it).
    static func cardShape(_ c: GraphicsContext, size: CGSize, colors: Colors) {
        let r = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let card = Path(roundedRect: r, cornerRadius: size.height * 0.2)
        c.fill(card, with: .color(colors.paper))
        c.stroke(card, with: .color(colors.line), lineWidth: 1.2)
        let d = size.height * 0.36
        c.fill(Path(ellipseIn: CGRect(x: r.minX + size.width * 0.14, y: -d / 2, width: d, height: d)), with: .color(colors.seal))
        var lines = Path()
        for y in [-size.height * 0.14, size.height * 0.16] {
            lines.move(to: CGPoint(x: r.minX + size.width * 0.44, y: y))
            lines.addLine(to: CGPoint(x: r.maxX - size.width * 0.14, y: y))
        }
        c.stroke(lines, with: .color(colors.line), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }
}

/// The raven's colours, from this app's tokens (tokens.json; the same values as raven-bird.json).
enum RavenLook: String, CaseIterable {
    /// Light surfaces: ink, a grey wing.
    case light
    /// Dark surfaces (and the night): black with a thin light outline.
    case dark

    init(_ scheme: ColorScheme) { self = scheme == .dark ? .dark : .light }
    init(_ palette: Palette) { self = palette.isDark ? .dark : .light }

    /// The black raven of dark mode (#0B0B0B) and its wing, a step lighter (#3C3C3C).
    static let black = Color(.sRGB, white: 11 / 255)
    static let darkWing = Color(.sRGB, white: 60 / 255)

    func colors(seal: Color? = nil) -> RavenFigure.Colors {
        let p = Theme.shared.palette(self == .dark ? .dark : .light)
        switch self {
        case .light:
            return RavenFigure.Colors(ink: p.textPrimary, wing: p.textSecondary, eye: p.surface, outline: nil,
                                      paper: p.background, line: p.textSecondary, seal: seal ?? p.named("pathTor"))
        case .dark:
            return RavenFigure.Colors(ink: Self.black, wing: Self.darkWing, eye: p.textPrimary, outline: p.textTertiary,
                                      paper: p.background, line: p.textSecondary, seal: seal ?? p.named("pathTor"))
        }
    }
}

/// The raven in a frame of its own: scaled to fit and centred on the bird (open wings included).
struct RavenBird: View {
    var pose = RavenFigure.Pose()
    /// The look; by default the current appearance's.
    var look: RavenLook?
    var seal: Color?
    /// Faces left instead of right.
    var mirrored = false
    @Environment(\.palette) private var p

    var body: some View {
        let colors = (look ?? RavenLook(p)).colors(seal: seal)
        Canvas { ctx, size in
            // The bird's box in its own units: folded 10...100 high, with open wings from -24.
            let top: CGFloat = pose.spread > 0.01 ? -24 : 10
            let box = CGRect(x: 10, y: top, width: 106, height: 100 - top)
            let scale = min(size.width / box.width, size.height / box.height)
            let feet = CGPoint(x: size.width / 2 + (RavenFigure.feetLocal.x - box.midX) * scale,
                               y: size.height / 2 + (RavenFigure.feetLocal.y - box.midY) * scale)
            var c = ctx
            if mirrored {
                c.translateBy(x: size.width, y: 0)
                c.scaleBy(x: -1, y: 1)
            }
            RavenFigure.draw(c, feet: feet, scale: scale, pose: pose, colors: colors)
        }
        .accessibilityHidden(true)
    }
}

/// The named poses (the same names in Resources/Design/raven-bird.json).
extension RavenFigure.Pose {
    /// Perched and still.
    static let perched = RavenFigure.Pose()
    /// Perched, the head tilted (the top of the idle tilt).
    static var headTilt: Self { var p = Self(); p.head = 16; return p }
    /// Flying, wings up.
    static var flying: Self { var p = Self(); p.spread = 1; p.beat = 1; p.legs = 0; p.pitch = 22; p.head = -14; return p }
    /// Wings up, legs going, the letter in the beak: off the branch.
    static var takeoff: Self { var p = Self(); p.spread = 1; p.beat = 1; p.legs = 0.3; p.letterInBeak = true; p.pitch = 22; p.head = -14; return p }
    /// Flying level with the letter.
    static var carrying: Self { var p = Self(); p.spread = 1; p.beat = 0.35; p.legs = 0; p.letterInBeak = true; p.pitch = 28; p.head = -18; return p }
    /// Gliding with nothing, wings down.
    static var gliding: Self { var p = Self(); p.spread = 1; p.beat = -0.4; p.legs = 0; p.pitch = 30; p.head = -20; return p }
    /// Asleep: the head turned back under the puffed wing, the eye shut, the body settled.
    static var sleeping: Self { var p = Self(); p.sleep = 1; p.breath = 0.97; return p }
    /// Perched with your card in the beak.
    static var holdingCard: Self { var p = Self(); p.cardInBeak = true; p.head = -6; return p }
    /// Perched with the letter in the beak (it waits, ready to go).
    static var holdingLetter: Self { var p = Self(); p.letterInBeak = true; return p }

    /// The poses of the design asset, by name.
    static var named: [(String, RavenFigure.Pose)] {
        [("perched", .perched), ("head-tilt", .headTilt), ("flying", .flying), ("takeoff", .takeoff), ("carrying", .carrying),
         ("gliding", .gliding), ("sleeping", .sleeping), ("holding-letter", .holdingLetter), ("holding-card", .holdingCard)]
    }
}

/// The raven's motion: the same timings in every Raven app (Resources/Design/raven-bird.json).
/// Seconds unless named otherwise.
enum RavenMotion {
    /// Breathing while perched: a vertical scale of 1 plus or minus `breathDepth` every `breathPeriod`.
    static let breathPeriod = 3.0
    static let breathDepth = 0.018
    /// The head tilt: within each `tiltCycle`, a tilt down to 16 degrees and back, then up to 10.
    static let tiltCycle = 5.2
    static let tilts: [(start: Double, end: Double, degrees: Double)] = [(0.4, 1.4, 16), (2.8, 3.6, -10)]
    /// Try now: the raven calls once (head up 22 degrees, three arcs).
    static let call = 1.3
    static let callHead = -22.0
    /// Wing beats while flying (beats a second); the wing goes from 1 (up) to minus 0.6 (down).
    static let flapHz = 5.0
    /// Take off with the letter: lean and pick it up, open the wings, fly off (ease out), shrink and
    /// fade; the check draws at the letter's place.
    static let pickUp = 0.35
    static let wingsOpen = 0.55
    static let flight = 1.3
    static let flightEase = 2.4
    static let flightShrink = 0.62
    static let fadeAfter = 0.7
    static let checkAt = 1.0
    static let checkDraw = 0.6
    /// Asleep: a slower, shallower breath, a small "z" now and then.
    static let sleepBreathPeriod = 5.0
    static let sleepBreathDepth = 0.012
    static let zEvery = 3.5
    static let zRise = 2.2
    /// Falling asleep (the head turns back under the wing) and waking (it turns back and stretches
    /// with a few wing beats).
    static let fallAsleep = 1.2
    static let wake = 1.5
    static let wakeFlaps = 3.0

    /// Perched and idle at time `t`: the breath and the head tilt.
    static func idle(_ t: Double) -> RavenFigure.Pose {
        var pose = RavenFigure.Pose()
        pose.breath = 1 + breathDepth * sin(2 * .pi * t / breathPeriod)
        let c = t.truncatingRemainder(dividingBy: tiltCycle)
        for tilt in tilts where c > tilt.start && c < tilt.end {
            pose.head = tilt.degrees * sin(.pi * (c - tilt.start) / (tilt.end - tilt.start))
        }
        return pose
    }

    /// Asleep at time `t`: the slow breath.
    static func asleep(_ t: Double) -> RavenFigure.Pose {
        var pose = RavenFigure.Pose.sleeping
        pose.breath = 0.97 + sleepBreathDepth * sin(2 * .pi * t / sleepBreathPeriod)
        return pose
    }

    /// Between awake (0) and asleep (1): the head turns back, the wing puffs.
    static func settling(_ p: Double) -> RavenFigure.Pose {
        var pose = RavenFigure.Pose()
        let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        pose.sleep = e
        pose.breath = 1 - 0.03 * e
        pose.head = 12 * sin(.pi * e)
        return pose
    }

    /// Waking at `x` seconds after unlock: the head comes back, then a stretch with a few beats.
    static func waking(_ x: Double) -> RavenFigure.Pose {
        if x < 0.5 { return settling(1 - x / 0.5) }
        var pose = RavenFigure.Pose()
        let s = min(1, (x - 0.5) / (wake - 0.5))
        let open = sin(.pi * s)
        pose.spread = open
        pose.beat = 0.3 + 0.7 * cos(2 * .pi * wakeFlaps * s)
        pose.head = -10 * open
        pose.breath = 1 + 0.03 * open
        return pose
    }
}
