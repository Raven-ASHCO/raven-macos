import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RavenUI

/// What the 0.1.1 release check of every snapshot found: the away card's "Held by a…", a lock-on-sleep
/// switch that promised a lock this version can't do, a menu bar mark at less than half strength, and
/// your avatar in another colour in a group's member list.
@MainActor
@Suite struct ReleaseCheckTests {
    func readyModel(network: MockRaven.NetworkMode) async -> AppModel {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return model
    }

    func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
    }

    /// Snapshot 50: the away card's path said "Held by a…": every node was 64 points wide.
    @Test func theAwayCardsPathShowsWholeLabels() {
        let held = tr(.chipFriend)
        #expect(held == "Held by a friend")
        #expect(textWidth(held, size: AwayTrio.labelSize) > AwayTrio.minNodeWidth)      // what was cut
        #expect(AwayTrio.nodeWidth(held) >= textWidth(held, size: AwayTrio.labelSize))
        #expect(AwayTrio.nodeWidth(tr(.youTitle)) == AwayTrio.minNodeWidth)
        #expect(AwayTrio.nodeWidth("Mina") == AwayTrio.minNodeWidth)
        // A very long name still ends in "…" instead of pushing the card's text aside.
        #expect(AwayTrio.nodeWidth(String(repeating: "Maximilian ", count: 4)) == AwayTrio.maxNodeWidth)
    }

    /// Snapshot 43: "Lock Raven when the computer sleeps" could be turned on while the page said Lock
    /// while running isn't in this version; sleep then locked nothing. The switch waits for a version
    /// that can lock.
    @Test func lockOnSleepWaitsForAVersionThatCanLock() async throws {
        let release = await readyModel(network: .release)
        await release.refreshLock()
        #expect(release.lockV2?.available == false && release.privacy.available == false)
        #expect(!release.lockOnSleepAvailable && !release.canLock)

        let lab = await readyModel(network: .lab)
        await lab.refreshLock()
        #expect(lab.lockV2?.available == true)
        #expect(lab.lockOnSleepAvailable)

        let settings = try String(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Views/SettingsView.swift"),
                                  encoding: .utf8)
        #expect(settings.contains(".disabled(!model.lockOnSleepAvailable)"))
    }

    /// Snapshot 22 and the menu bar: the design file's mark is a 40% grey and a template image keeps
    /// only its alpha, so the menu bar's Raven looked disabled. Its mark is solid now.
    @Test func theMenuBarMarkIsDrawnAtFullStrength() throws {
        func peakAlpha(_ image: NSImage) throws -> UInt8 {
            var rect = CGRect(origin: .zero, size: image.size)
            let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                          bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return true
            }
            #expect(drawn)
            return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
        }
        #expect(try peakAlpha(RavenResources.mark(size: 18, template: true)) < 128)    // the design file's grey
        let menuBar = RavenResources.menuBarMark()
        #expect(menuBar.isTemplate)
        #expect(menuBar.size == NSSize(width: 18, height: 18))
        #expect(try peakAlpha(menuBar) >= 250)
    }

    /// Snapshots 49 and 52: you were blue in the sidebar and the chat but pink in a group's member
    /// list (your address's colour). You are the accent everywhere.
    @Test func youHaveOneColourEverywhere() {
        let me = GroupMember(address: "rvn1me", shortAddress: "rvn1me", name: "You", friend: false, admin: true, me: true)
        let ali = GroupMember(address: MockRaven.aliAddress, shortAddress: "rvn1ali", name: "Ali", friend: true)
        for scheme in [ColorScheme.light, .dark] {
            let p = Theme.shared.palette(scheme)
            #expect(p.avatar(for: me).background == p.accentSoft && p.avatar(for: me).foreground == p.accent)
            #expect(p.youAvatar.background == p.accentSoft && p.youAvatar.foreground == p.accent)
            #expect(p.avatar(for: ali).background == p.avatar(for: MockRaven.aliAddress).background)
        }
    }
}
