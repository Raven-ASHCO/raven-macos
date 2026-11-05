import SwiftUI

/// The lock scene (owner choice D, "Night curtain"), as the iPhone draws it (raven-ios
/// NightCurtain.swift, 2ecbdab), sized for the Lock sheet and the locked screen: by day the raven
/// perches on its branch under the sun, two leaves on a twig. On Lock a starry night with a crescent
/// moon and a scalloped lower edge is pulled down over the day like a blanket (`curtainDown`, 2 s);
/// the raven turns its head back under its wing, the eye shut, the wing puffed, the breath slower, and
/// a small "z" floats up now and then. On Unlock the curtain rises (`curtainUp`) and the raven wakes
/// with a stretch (`RavenMotion.wake`). Every frame is drawn from the time since the real event (Lock,
/// Unlock). Reduce Motion: still frames. Decorative: hidden from VoiceOver, the text beside it says
/// what happens.
struct LockScene: View {
    enum Moment: Equatable {
        /// Awake on its branch (Lock's question).
        case day
        /// Raven locked at this time: the night comes down, the raven falls asleep.
        case fallingAsleep(Date)
        /// Locked: night, the raven asleep.
        case asleep
        /// Unlock worked at this time: the night rises, the raven wakes.
        case waking(Date)
    }

    var moment: Moment
    /// Draws one frame at this moment (snapshots of the motion).
    var frozen: Date?
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot

    static let curtainDown = 2.0
    static let curtainUp = 1.2
    /// Snapshots without a frozen moment draw this one: by day the raven still between its head tilts
    /// and breaths, asleep a "z" halfway up.
    static let snapshotDate = Date(timeIntervalSinceReferenceDate: 4.49)

    var body: some View {
        Group {
            if frozen != nil || motionOff || snapshot {
                Canvas { ctx, size in draw(ctx, size, now: frozen ?? Self.snapshotDate, still: motionOff) }
            } else {
                TimelineView(Frames(moment: moment)) { timeline in
                    Canvas { ctx, size in draw(ctx, size, now: timeline.date, still: false) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.shared.radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    /// 30 frames a second, as on the iPhone; 15 once the raven sleeps (a slow breath, a drifting "z",
    /// the stars twinkling), since the locked screen may stay up for hours.
    private struct Frames: TimelineSchedule {
        let moment: Moment

        func entries(from start: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
            let slowFrom: Date?
            switch moment {
            case .day, .waking: slowFrom = nil
            case .fallingAsleep(let at): slowFrom = at.addingTimeInterval(LockScene.curtainDown)
            case .asleep: slowFrom = .distantPast
            }
            return sequence(first: start) { date in
                if mode == .lowFrequency { return date.addingTimeInterval(1) }
                if let slowFrom, !(date < slowFrom) { return date.addingTimeInterval(1.0 / 15) }
                return date.addingTimeInterval(1.0 / 30)
            }
        }
    }

    // MARK: State at a moment

    /// How far the night is down (0 day, 1 night), the raven's pose, whether it sleeps, and the clock
    /// of the "z"s (seconds asleep).
    ///
    /// Two seams of the iPhone's timeline are smoothed here so nothing jumps between frames: in the
    /// first 0.6 s after Lock the idle tilt and breath fade out (the iPhone cuts from mid-tilt to the
    /// settling pose), and once asleep the slow breath and the "z"s count from the moment it fell
    /// asleep (on the iPhone from the wall clock, so the breath stepped and a "z" could flash in half
    /// faded).
    static func picture(_ moment: Moment, now: Date, still: Bool)
        -> (curtain: Double, pose: RavenFigure.Pose, asleep: Bool, zClock: Double) {
        let t = now.timeIntervalSinceReferenceDate
        switch moment {
        case .day:
            return (0, still ? .perched : RavenMotion.idle(t), false, 0)
        case .asleep:
            return (1, still ? .sleeping : RavenMotion.asleep(t), true, t)
        case .fallingAsleep(let since):
            let x = now.timeIntervalSince(since)
            if still { return (1, .sleeping, true, 0) }
            if x >= curtainDown { return (1, RavenMotion.asleep(x - curtainDown), true, x - curtainDown) }
            let c = ease(x / curtainDown)
            let s = max(0, min(1, (x - 0.6) / (curtainDown - 0.6)))
            if s > 0 { return (c, RavenMotion.settling(s), false, 0) }
            var pose = RavenMotion.idle(t)
            let fade = 1 - smooth(x / 0.6)
            pose.head *= fade
            pose.breath = 1 + (pose.breath - 1) * fade
            return (c, pose, false, 0)
        case .waking(let since):
            let x = now.timeIntervalSince(since)
            if still || x >= RavenMotion.wake { return (0, still ? .perched : RavenMotion.idle(t), false, 0) }
            return (1 - ease(x / curtainUp), RavenMotion.waking(x), false, 0)
        }
    }

    /// The scene's own colours (the iPhone's): the day sky, the sun, the night, the moon, the wood
    /// and the leaves. The day sky in light mode is accentSoft.
    enum Colors {
        static let skyLight = hex("#E6F1FB"), skyDark = hex("#1E2A36")
        static let sun = hex("#F2C14E"), sunDark = hex("#E0B04A")
        static let nightTop = hex("#0E1530"), nightBottom = hex("#1B2647")
        static let moon = hex("#F4E9C8")
        static let wood = hex("#8A877F"), woodNight = hex("#6A6E7A")
        static let leaf = hex("#5FA85A")

        private static func hex(_ s: String) -> Color { (try? Theme.color(hex: s)) ?? .gray }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, now: Date, still: Bool) {
        let w = size.width, h = size.height
        let dark = p.isDark
        let (c, pose, asleep, zClock) = Self.picture(moment, now: now, still: still)
        let t = now.timeIntervalSinceReferenceDate
        let scale = min(1.0, h / 190)
        let perch = CGPoint(x: w * 0.4, y: h - 30)

        // The day: a soft sky and the sun.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? Colors.skyDark : Colors.skyLight))
        let sun = CGPoint(x: w * 0.8, y: h * 0.3)
        let r = 17 * scale
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 1.9, y: sun.y - r * 1.9, width: r * 3.8, height: r * 3.8)),
                 with: .color(Colors.sun.opacity(dark ? 0.12 : 0.18)))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                 with: .color(dark ? Colors.sunDark : Colors.sun))

        // The night, pulled down over the day: stars, a crescent moon, a scalloped lower edge.
        if c > 0.001 {
            let scallop = 11.0 * scale
            let edge = c * (h + scallop * 1.4) - scallop * 1.4
            var night = Path()
            night.move(to: .zero)
            night.addLine(to: CGPoint(x: w, y: 0))
            night.addLine(to: CGPoint(x: w, y: edge))
            var x = w
            while x > 0 {
                night.addQuadCurve(to: CGPoint(x: x - scallop * 2, y: edge), control: CGPoint(x: x - scallop, y: edge + scallop * 1.4))
                x -= scallop * 2
            }
            night.closeSubpath()
            ctx.fill(night, with: .linearGradient(Gradient(colors: [Colors.nightTop, Colors.nightBottom]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            var sky = ctx
            sky.clip(to: night)
            for i in 0..<22 {
                let sx = frac(Double(i) * 0.618 + 0.13) * w
                let sy = frac(Double(i) * 0.382 + 0.41) * h * 0.82
                let twinkle = still ? 0.8 : 0.55 + 0.45 * sin(t * 1.3 + Double(i) * 1.7)
                let d = (i % 4 == 0 ? 2.4 : 1.5) * scale
                sky.fill(Path(ellipseIn: CGRect(x: sx - d / 2, y: sy - d / 2, width: d, height: d)),
                         with: .color(.white.opacity(0.85 * twinkle)))
            }
            // The crescent: the moon less a circle up and to the right (Path.subtracting needs macOS 14).
            let moon = CGPoint(x: w * 0.8, y: h * 0.28)
            sky.drawLayer { layer in
                layer.fill(Path(ellipseIn: CGRect(x: moon.x - r, y: moon.y - r, width: r * 2, height: r * 2)), with: .color(Colors.moon))
                layer.blendMode = .destinationOut
                layer.fill(Path(ellipseIn: CGRect(x: moon.x - r * 0.45, y: moon.y - r * 1.2, width: r * 2, height: r * 2)), with: .color(.black))
            }
        }

        // The branch, a twig and two leaves (in front of day and night).
        let wood = dark || c > 0.6 ? Colors.woodNight : Colors.wood
        var branch = Path()
        branch.move(to: CGPoint(x: perch.x - 110 * scale, y: perch.y + 4))
        branch.addQuadCurve(to: CGPoint(x: perch.x + 150 * scale, y: perch.y - 6), control: CGPoint(x: perch.x + 20 * scale, y: perch.y + 8))
        ctx.stroke(branch, with: .color(wood), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        let twigFrom = CGPoint(x: perch.x + 96 * scale, y: perch.y - 1)
        let twigTo = CGPoint(x: perch.x + 122 * scale, y: perch.y - 24 * scale)
        var twig = Path()
        twig.move(to: twigFrom)
        twig.addQuadCurve(to: twigTo, control: CGPoint(x: perch.x + 116 * scale, y: perch.y - 4))
        ctx.stroke(twig, with: .color(wood), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for (dx, dy, angle) in [(0.0, 0.0, -35.0), (-9.0, 6.0, 25.0)] {
            var leaf = ctx
            leaf.translateBy(x: twigTo.x + dx * scale, y: twigTo.y + dy * scale)
            leaf.rotate(by: .degrees(angle))
            leaf.fill(Path(ellipseIn: CGRect(x: -8 * scale, y: -3.4 * scale, width: 16 * scale, height: 6.8 * scale)),
                      with: .color(Colors.leaf.opacity(c > 0.6 ? 0.55 : 0.85)))
        }

        // The raven: the one bird. In light mode, once the night covers it, its dark version (black
        // with the light outline) so it still reads against the night.
        let birdTop = perch.y - 90 * scale
        let cover = dark ? 0 : max(0, min(1, (c * h - birdTop) / (90 * scale)))
        if cover < 1 {
            ctx.drawLayer { l in
                l.opacity = 1 - cover
                RavenFigure.draw(l, feet: perch, scale: scale, pose: pose, colors: RavenLook(p).colors())
            }
        }
        if cover > 0 {
            ctx.drawLayer { l in
                l.opacity = cover
                RavenFigure.draw(l, feet: perch, scale: scale, pose: pose, colors: RavenLook.dark.colors())
            }
        }

        // A small "z" floats up now and then while it sleeps (one still z under Reduce Motion).
        if asleep {
            let head = CGPoint(x: perch.x + 4 * scale, y: perch.y - 70 * scale)
            let x = still ? 0.45 : max(0, zClock).truncatingRemainder(dividingBy: RavenMotion.zEvery) / RavenMotion.zRise
            if x < 1 {
                let at = CGPoint(x: head.x + 18 * scale * x, y: head.y - 30 * scale * x)
                let alpha = x < 0.2 ? x / 0.2 : (x > 0.7 ? (1 - x) / 0.3 : 1)
                ctx.draw(Text(verbatim: "z").font(.system(size: (11 + 6 * x) * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85 * alpha)), at: at)
            }
        }
    }

    private func frac(_ v: Double) -> Double { v - v.rounded(.down) }

    static func ease(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}
