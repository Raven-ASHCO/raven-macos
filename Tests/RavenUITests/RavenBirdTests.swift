import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RavenUI

/// The one raven (owner rule): RavenBird.swift draws the bird of Resources/Design/raven-bird.json
/// (written by raven-ios), with the same geometry, colours, poses and timings; and the lock scene
/// (Night curtain) follows Lock and Unlock.
@MainActor
@Suite struct RavenBirdTests {
    func design() throws -> [String: Any] {
        let url = packageRoot.appendingPathComponent("Sources/RavenUI/Resources/Design/raven-bird.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

    /// A colour as "#RRGGBB" in sRGB.
    func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> String { String(format: "%02X", Int((v * 255).rounded())) }
        return "#" + byte(c.redComponent) + byte(c.greenComponent) + byte(c.blueComponent)
    }

    @Test func geometryIsTheDesignFile() throws {
        let parts = try #require(try design()["parts"] as? [String: Any])
        let g = RavenGeometry.self
        for (name, segs) in [("tail", g.tail), ("body", g.body), ("beak", g.beak), ("folded_wing", g.foldedWing),
                             ("feathers", g.feathers), ("legs", g.legs), ("eye_shut", g.eyeShut),
                             ("open_wing_up", g.wing(1)), ("open_wing_level", g.wing(0.35)), ("open_wing_down", g.wing(-0.4))] {
            #expect(parts[name] as? String == g.svg(segs), "\(name) differs from raven-bird.json")
        }
        let head = try #require(parts["head"] as? [String: Any])
        #expect(number(head["cx"]) == Double(g.head.midX) && number(head["cy"]) == Double(g.head.midY))
        #expect(number(head["rx"]) == Double(g.head.width / 2) && number(head["ry"]) == Double(g.head.height / 2))
        let eye = try #require(parts["eye"] as? [String: Any])
        #expect(abs((number(eye["cx"]) ?? 0) - Double(g.eye.midX)) < 1e-9 && abs((number(eye["cy"]) ?? 0) - Double(g.eye.midY)) < 1e-9)
        #expect(abs((number(eye["rx"]) ?? 0) - Double(g.eye.width / 2)) < 1e-9)
        let pivots = try #require(try design()["pivots"] as? [String: [Double]])
        for (name, point) in [("feet", g.feet), ("body_centre", g.bodyCentre), ("neck", g.neck), ("shoulder", g.shoulder),
                              ("beak_tip", g.beakTip)] {
            #expect(pivots[name] == [Double(point.x), Double(point.y)], "pivot \(name)")
        }
        let sleep = try #require(try design()["sleep"] as? [String: Any])
        #expect((sleep["head_shift"] as? [Double]) == [Double(RavenFigure.sleepHeadShift.x), Double(RavenFigure.sleepHeadShift.y)])
        #expect(number(sleep["wing_puff"]) == RavenFigure.sleepWingPuff && number(sleep["wing_rise"]) == RavenFigure.sleepWingRise)
    }

    @Test func posesAreTheDesignFile() throws {
        let poses = try #require(try design()["poses"] as? [String: [String: Any]])
        #expect(Set(poses.keys) == Set(RavenFigure.Pose.named.map(\.0)))
        for (name, pose) in RavenFigure.Pose.named {
            let p = try #require(poses[name])
            #expect(number(p["lean"]) == pose.lean && number(p["pitch"]) == pose.pitch && number(p["head"]) == pose.head, "\(name)")
            #expect(number(p["spread"]) == pose.spread && number(p["beat"]) == pose.beat && number(p["legs"]) == pose.legs, "\(name)")
            #expect(number(p["breath"]) == pose.breath && number(p["sleep"]) == pose.sleep, "\(name)")
            #expect(p["letter_in_beak"] as? Bool == pose.letterInBeak && p["card_in_beak"] as? Bool == pose.cardInBeak, "\(name)")
        }
    }

    @Test func timingsAreTheDesignFile() throws {
        let t = try #require(try design()["timings_s"] as? [String: [String: Any]])
        #expect(number(t["breathe"]?["period"]) == RavenMotion.breathPeriod && number(t["breathe"]?["depth"]) == RavenMotion.breathDepth)
        #expect(number(t["tilt"]?["cycle"]) == RavenMotion.tiltCycle)
        let tilts = try #require(t["tilt"]?["tilts"] as? [[String: Double]])
        #expect(tilts.map { [$0["start"], $0["end"], $0["degrees"]] } == RavenMotion.tilts.map { [$0.start, $0.end, $0.degrees] as [Double?] })
        #expect(number(t["call"]?["duration"]) == RavenMotion.call && number(t["call"]?["head"]) == RavenMotion.callHead)
        #expect(number(t["flap"]?["beats_per_s"]) == RavenMotion.flapHz)
        let sleep = try #require(t["sleep"])
        #expect(number(sleep["breath_base"]) == RavenFigure.Pose.sleeping.breath)
        #expect(number(sleep["breath_depth"]) == RavenMotion.sleepBreathDepth && number(sleep["breath_period"]) == RavenMotion.sleepBreathPeriod)
        #expect(number(sleep["fall_asleep"]) == RavenMotion.fallAsleep)
        #expect(number(sleep["z_every"]) == RavenMotion.zEvery && number(sleep["z_rise"]) == RavenMotion.zRise)
        #expect(number(t["wake"]?["duration"]) == RavenMotion.wake && number(t["wake"]?["stretch_flaps"]) == RavenMotion.wakeFlaps)
        let off = try #require(t["take_off"])
        #expect(number(off["pick_up"]) == RavenMotion.pickUp && number(off["wings_open"]) == RavenMotion.wingsOpen)
        #expect(number(off["flight"]) == RavenMotion.flight && number(off["ease_out_power"]) == RavenMotion.flightEase)
        #expect(number(off["shrink"]) == RavenMotion.flightShrink && number(off["fade_after"]) == RavenMotion.fadeAfter)
        #expect(number(off["check_at"]) == RavenMotion.checkAt && number(off["check_draw"]) == RavenMotion.checkDraw)
    }

    /// The colours come from this app's tokens and equal the design file's.
    @Test func coloursAreTheDesignFile() throws {
        let colors = try #require(try design()["colors"] as? [String: [String: String]])
        for look in RavenLook.allCases {
            let want = try #require(colors[look.rawValue])
            let c = look.colors()
            #expect(hex(c.ink) == want["ink"] && hex(c.wing) == want["wing"] && hex(c.eye) == want["eye"], "\(look)")
            #expect(hex(c.paper) == want["paper"] && hex(c.line) == want["line"] && hex(c.seal) == want["seal"], "\(look)")
            #expect(c.outline.map(hex) == want["outline"], "\(look) outline")
        }
    }

    // MARK: The lock scene

    @Test func theNightComesDownOnLockAndRisesOnUnlock() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        func at(_ s: Double) -> Date { start.addingTimeInterval(s) }
        // By day: no night, the raven awake.
        let day = LockScene.picture(.day, now: at(0), still: false)
        #expect(day.curtain == 0 && day.pose.sleep == 0 && !day.asleep)
        // Lock: the night starts at the top and is all the way down after 2 s; the raven then sleeps.
        let falling = LockScene.Moment.fallingAsleep(start)
        #expect(LockScene.picture(falling, now: at(0), still: false).curtain == 0)
        let half = LockScene.picture(falling, now: at(1), still: false)
        #expect(half.curtain > 0.3 && half.curtain < 0.7 && !half.asleep)
        let down = LockScene.picture(falling, now: at(LockScene.curtainDown), still: false)
        #expect(down.curtain == 1 && down.asleep && down.pose.sleep == 1)
        // Unlock: the night rises in 1.2 s, the raven stretches its wings, and is awake by 1.5 s.
        let waking = LockScene.Moment.waking(start)
        #expect(LockScene.picture(waking, now: at(0), still: false).curtain == 1)
        #expect(LockScene.picture(waking, now: at(LockScene.curtainUp), still: false).curtain == 0)
        #expect(LockScene.picture(waking, now: at(1.0), still: false).pose.spread > 0.5)
        let awake = LockScene.picture(waking, now: at(RavenMotion.wake), still: false)
        #expect(awake.curtain == 0 && awake.pose.sleep == 0 && awake.pose.spread == 0)
    }

    /// Frame by frame at 30 a second nothing jumps: the night only moves one way, and the head, the
    /// breath, the turn under the wing and the wings change by small steps, whenever Lock or Unlock
    /// happens on the wall clock (the idle tilt and breath are at different points).
    @Test func noFrameJumps() {
        for offset in stride(from: 0.0, to: 5.2, by: 0.65) {
            let start = Date(timeIntervalSinceReferenceDate: 1000 + offset)
            for (moment, seconds) in [(LockScene.Moment.fallingAsleep(start), 10.0), (.waking(start), RavenMotion.wake - 1 / 30)] {
                var last = LockScene.picture(moment, now: start, still: false)
                for i in 1...Int(seconds * 30) {
                    let now = LockScene.picture(moment, now: start.addingTimeInterval(Double(i) / 30), still: false)
                    let at = "\(moment) +\(i) frames"
                    if case .fallingAsleep = moment { #expect(now.curtain >= last.curtain, "\(at)") } else { #expect(now.curtain <= last.curtain, "\(at)") }
                    #expect(abs(now.pose.head - last.pose.head) < 6, "head \(at)")
                    #expect(abs(now.pose.breath - last.pose.breath) < 0.004, "breath \(at)")
                    #expect(abs(now.pose.sleep - last.pose.sleep) < 0.15, "sleep \(at)")
                    #expect(abs(now.pose.spread - last.pose.spread) < 0.15, "spread \(at)")
                    last = now
                }
            }
        }
    }

    /// Reduce Motion: still frames, by day perched, at night asleep (from the first moment of Lock).
    @Test func reduceMotionDrawsStillFrames() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let day = LockScene.picture(.day, now: now, still: true)
        #expect(day.curtain == 0 && day.pose == .perched)
        for moment in [LockScene.Moment.asleep, .fallingAsleep(now)] {
            let night = LockScene.picture(moment, now: now, still: true)
            #expect(night.curtain == 1 && night.pose == .sleeping && night.asleep)
        }
        #expect(LockScene.picture(.waking(now), now: now, still: true).pose == .perched)
    }

    /// Unlock opens the main window only after the night has risen (`beforeOpen`), and Lock notes
    /// when it locked so the locked screen pulls the night down then.
    @Test func unlockWaitsForTheNightBeforeTheWindowOpens() async {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: .lab)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        #expect(model.lockedAt == nil)
        await model.lock()
        #expect(model.phase == .locked)
        #expect(model.lockedAt.map { Date().timeIntervalSince($0) < 5 } == true)
        var phaseInHook: AppModel.Phase?
        await model.unlockLocked(passphrase: MockRaven.labPassphrase) { phaseInHook = model.phase }
        #expect(phaseInHook == .locked && model.phase == .ready)
    }
}
