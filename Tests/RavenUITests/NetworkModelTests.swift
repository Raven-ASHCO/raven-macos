import Foundation
import Testing
@testable import RavenUI

/// The Network screens' view model against MockRaven: every way state, the switches, the consent
/// flow, the restart prompt, NOT_AVAILABLE_YET and CONSENT_NEEDED, Check network, a friend's routes,
/// Security, Lock v2 and Updates.
@MainActor
@Suite struct NetworkModelTests {
    func model(_ network: MockRaven.NetworkMode = .release, start: MockRaven.Start = .ready) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: start, demo: false, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        return (model, mock)
    }

    // MARK: Way states and switches

    /// The Tor way (API.md "The Tor way"): held in a release build; in the lab its state comes from
    /// raven-node's Tor line, with the phase chip, the why and the outage history; no switch.
    @Test func theTorWayShowsRavenNodesTorState() async throws {
        let (release, _) = await model(.release)
        await release.network.refresh()
        let held = try #require(release.network.status?.way("tor"))
        #expect(held.state == .preview && release.network.status?.tor == nil)
        let (app, _) = await model(.lab)
        await app.network.refresh()
        let status = try #require(app.network.status)
        let tor = try #require(status.way("tor"))
        #expect(tor.state == .lab && tor.canSet == false && NetworkModel.setting(forWay: "tor") == nil)
        #expect(PathFamily.of(way: tor.id) == .tor)
        let state = try #require(status.tor)
        #expect(Display.torPhase(state).text == "Ready" && Display.torPhase(state).tone == .success)
        #expect(Display.torLines(state) == ["Outage history: " + MockRaven.labTorOutages])
        let starting = TorState(phase: "starting", words: "starting (45 %)", percent: 45)
        #expect(Display.torPhase(starting).text == "Starting (45 %)")
        let blocked = TorState(phase: "blocked", why: "bridges needed", retry: "retrying in 2 min")
        #expect(Display.torPhase(blocked).text == "Blocked on this network" && Display.torPhase(blocked).tone == .warning)
        #expect(Display.torLines(blocked) == ["Why: bridges needed; retrying in 2 min"])
        #expect(Display.torPhase(TorState(phase: "could_not_start")).text == "Could not start")
        #expect(Display.torPhase(TorState(phase: "unreachable")).text == "Onion service unreachable")
        // A phase this app doesn't know: raven-node's own words.
        #expect(Display.torPhase(TorState(phase: "new", words: "something new")).text == "something new")
    }

    @Test func aReleaseBuildShowsLanOnAndEverythingElseHeld() async throws {
        let (app, _) = await model(.release)
        let net = app.network
        await net.refresh()
        let status = try #require(net.status)
        #expect(status.carriers.count == 14 && status.protections?.count == 6)
        #expect(status.way("lan")?.state == .on)
        for way in status.carriers + (status.protections ?? []) where way.id != "lan" {
            #expect(way.state == .preview, "\(way.id)")
            #expect(Display.wayState(way.state).text == "Preview, not in this release")
            // A held way that is off has its switch, but the switch can't be used.
            let toggle = NetworkModel.toggle(for: way)
            if NetworkModel.setting(forWay: way.id) != nil && way.id != "proxy" {
                #expect(toggle.shown && !toggle.enabled, "\(way.id)")
            } else {
                #expect(!toggle.shown, "\(way.id)")
            }
        }
        #expect(NetworkModel.toggle(for: try #require(status.way("lan"))) == (true, true))
        // No lab switches: no banner.
        #expect(NetworkModel.labSwitches(status: status, node: app.node).isEmpty)
    }

    @Test func aLabBuildShowsEveryState() async throws {
        let (app, _) = await model(.lab)
        await app.network.refresh()
        let status = try #require(app.network.status)
        var states: [String: WayState] = [:]
        for way in status.carriers + (status.protections ?? []) { states[way.id] = way.state }
        #expect(states["lan"] == .on)
        #expect(states["p2p"] == .lab)
        #expect(states["internet"] == .off && status.way("internet")?.lab == true)
        #expect(states["custody"] == .off)
        #expect(states["nearby"] == .notOnThisOs)
        #expect(states["websocket"] == .preview)
        #expect(states["lock_v2"] == .lab)
        #expect(Set(states.values) == [.on, .off, .preview, .lab, .notOnThisOs])
        #expect(Display.wayState(.lab).text == "Lab only")
        #expect(Display.wayState(.off).text == "Off")
        #expect(Display.wayState(.notOnThisOs).text == "Not on this computer")
        #expect(Display.wayState(.on).text == "On")
        // Switches: a lab way can be used; nearby on a computer without Bluetooth LE can't.
        #expect(NetworkModel.toggle(for: try #require(status.way("internet"))) == (true, true))
        #expect(NetworkModel.toggle(for: try #require(status.way("nearby"))) == (true, false))
        #expect(NetworkModel.toggle(for: try #require(status.way("lock_v2"))) == (false, false))
        #expect(NetworkModel.isOn(try #require(status.way("p2p"))))
        #expect(!NetworkModel.isOn(try #require(status.way("internet"))))
        // The lab banner: a developer build that sees lab switches.
        #expect(NetworkModel.labSwitches(status: status, node: app.node) == MockRaven.labSwitches)
        #expect(NetworkModel.labSwitches(status: nil, node: app.node) == MockRaven.labSwitches)
        // Relays in use and what the router said, with p2p running.
        #expect(status.relays?.first?.relay == MockRaven.relayAddress)
        #expect(Display.relaySource(try #require(status.relays?.first), name: { _ in nil }) == "added by you")
        #expect(status.portMapping?.router == "off")
    }

    /// A release engine never lists a lab switch, and a release build never shows the banner even if
    /// a list came along.
    @Test func theLabBannerNeedsADeveloperBuild() throws {
        let release = try JSONValue.object(["build": "release", "carriers": [], "lab_switches": ["RAVEN_LAB_TEST_A"]])
            .decode(NetworkStatus.self)
        #expect(NetworkModel.labSwitches(status: release, node: nil).isEmpty)
        let dev = try JSONValue.object(["build": "dev", "carriers": [], "lab_switches": ["RAVEN_LAB_TEST_A"]])
            .decode(NetworkStatus.self)
        #expect(NetworkModel.labSwitches(status: dev, node: nil) == ["RAVEN_LAB_TEST_A"])
    }

    @Test func turningAHeldWayOnIsRefusedAndChangesNothing() async throws {
        let (app, _) = await model(.release)
        let net = app.network
        await net.refresh()
        let before = net.status
        await net.toggle("p2p", on: true)
        #expect(net.rowError?.setting == "p2p")
        #expect(net.rowError?.error.code == ErrorCode.notAvailableYet)
        #expect(net.rowError?.error.message == "This isn't in this release of Raven yet. Nothing was changed.")
        #expect(net.status == before && net.changes.isEmpty && app.sheet == nil)
        #expect(net.busy.isEmpty)
        // A held consent setting is refused the same way, before any consent is asked for.
        await net.apply(["carry_for_friends": true, "agreed": true], setting: "carry_for_friends")
        #expect(net.rowError?.error.code == ErrorCode.notAvailableYet)
    }

    @Test func switchesShowTheEnginesAnswer() async throws {
        let (app, _) = await model(.release)
        let net = app.network
        await net.toggle("lan", on: false)
        #expect(net.status?.way("lan")?.state == .off && net.status?.way("lan")?.setting == false)
        #expect(net.changes.first?.setting == "lan" && net.changes.first?.applies == "now")
        #expect(net.rowError == nil && app.sheet == nil)
        await net.lanFor("1h")
        #expect(net.status?.way("lan")?.state == .on)
        #expect(net.status?.lanUntilMs == testStart.ms + 3600 * 1000)
        net.dismissChanges()
        #expect(net.changes.isEmpty)
        await net.toggle("store", on: false)
        #expect(net.status?.help?.store == false && net.status?.help?.automatic == false)
        await net.toggle("hide_ip", on: true)
        #expect(net.status?.hideIp == true)
    }

    // MARK: Consent

    @Test func consentIsAskedBeforeAnythingIsSent() async throws {
        let (app, mock) = await model(.lab)
        let net = app.network
        await net.refresh()
        await net.toggle("carry_for_friends", on: true)
        #expect(app.sheet == .consent("carry_for_friends"))
        #expect(net.consent == "carry_for_friends")
        // Nothing reached the engine: carrying for friends is still off there.
        #expect(try await mock.networkStatus().carry?.carryForFriends?.on == false)
        #expect(Display.consent("carry_for_friends")?.title == "Carry mail for your friends?")
        #expect(Display.engineConsentText("carry_for_friends", net.status?.texts) == "Hold sealed messages for your friends while they are offline?")

        // Not now: nothing changes.
        net.decline()
        #expect(app.sheet == nil && net.consent == nil)
        #expect(try await mock.networkStatus().carry?.carryForFriends?.on == false)

        // I agree: sent with agreed: true, and it is on.
        await net.toggle("carry_for_friends", on: true)
        await net.agree()
        #expect(app.sheet == nil && net.consent == nil && net.consentError == nil)
        #expect(net.status?.carry?.carryForFriends?.on == true)
        #expect(net.status?.carry?.carryForFriends?.heldMessages == 2)
        // Turning it off needs no yes.
        await net.toggle("carry_for_friends", on: false)
        #expect(app.sheet == nil && net.status?.carry?.carryForFriends?.on == false)
    }

    @Test func everyConsentSettingHasItsTexts() {
        for setting in NetworkModel.consentSettings {
            let texts = Display.consent(setting)
            #expect(texts != nil, "\(setting)")
            #expect([texts?.does, texts?.costs, texts?.sees, texts?.hidden].allSatisfy { ($0 ?? "").count > 20 }, "\(setting)")
        }
        // The consent rule: a sheet for exactly the engine's three, none for relay or bridge.
        #expect(NetworkModel.consentSettings == ["carry_for_friends", "friends_carry_mine", "handoff"])
        #expect(Display.consent("relay_for_friends") == nil && Display.consent("bridge") == nil)
    }

    /// The engine's CONSENT_NEEDED (a request without `agreed`) opens the consent sheet instead of an
    /// error; a refusal after agreeing is shown in the sheet.
    @Test func consentNeededFromTheEngineOpensTheSheet() async throws {
        let (app, _) = await model(.lab)
        let net = app.network
        await net.apply(["handoff": true], setting: "handoff")
        #expect(app.sheet == .consent("handoff") && net.consent == "handoff")
        #expect(net.rowError == nil)
        await net.agree()
        #expect(net.status?.way("handoff")?.setting == true && net.status?.way("handoff")?.state == .lab)
        #expect(app.sheet == nil)

        // In a release build the yes doesn't help: the way is held, and the sheet says so.
        let (release, _) = await model(.release)
        await release.network.toggle("friends_carry_mine", on: true)
        #expect(release.sheet == .consent("friends_carry_mine"))
        await release.network.agree()
        #expect(release.network.consentError?.code == ErrorCode.notAvailableYet)
        #expect(release.sheet == .consent("friends_carry_mine"))
        release.network.decline()
        #expect(release.sheet == nil && release.network.consentError == nil)
    }

    // MARK: Restart prompt

    @Test func aChangeThatNeedsARestartAsksForOne() async throws {
        let (app, mock) = await model(.lab)
        let net = app.network
        await net.toggle("internet", on: true)
        #expect(net.changes.first?.applies == "restart")
        #expect(app.sheet == .restartNode && net.restart == .asking)
        let pid = app.node?.pid
        await net.restartNode()
        #expect(net.restart == .restarted)
        #expect(app.node?.running == true && app.node?.startedByApp == true)
        #expect(pid != nil)
        #expect(try await mock.nodeStatus().running)
        net.dismissRestart()
        #expect(app.sheet == nil && net.restart == nil)

        // "Later": nothing is restarted.
        await net.toggle("port_mapping", on: true)
        #expect(app.sheet == .restartNode)
        net.dismissRestart()
        #expect(app.sheet == nil && net.restart == nil)
    }

    @Test func aChangeThatAppliesNowAsksForNoRestart() async throws {
        let (app, _) = await model(.lab)
        await app.network.toggle("hide_ip", on: true)
        #expect(app.sheet == nil && app.network.restart == nil)
    }

    /// A raven-node a login service runs is left running: the prompt says so and starts nothing.
    @Test func aLoginServiceNodeIsLeftRunning() async throws {
        let (app, mock) = await model(.lab)
        mock.runNodeAsLoginService()
        let net = app.network
        await net.toggle("p2p", on: false)
        #expect(app.sheet == .restartNode)
        await net.restartNode()
        guard case .managed(let note) = net.restart else {
            Issue.record("expected managed, got \(String(describing: net.restart))")
            return
        }
        #expect(note.contains("login service"))
        #expect(app.node?.running == true)
    }

    // MARK: Check network

    @Test func checkNetworkAndTheRouterQuestion() async throws {
        let (app, _) = await model(.release)
        let net = app.network
        await net.runCheck()
        let check = try #require(net.check)
        #expect(check.summary.contains { $0.key == "identity" } && check.nextStep == "All set: Raven can send and receive messages on this computer.")
        #expect(check.rows.contains { $0.key == "receiving" && $0.plain == "Raven receives messages on this network." })
        #expect(check.router == nil && !net.checking && !net.askingRouter)
        await net.runCheck(router: true)
        #expect(net.check?.router?.contains { $0.key == "router_upnp_igd" } == true)
        // Checking again keeps the router's answer.
        await net.runCheck()
        #expect(net.check?.router != nil)
    }

    // MARK: A friend's routes

    @Test func aFriendsRoutesAndMailFriends() async throws {
        let (app, _) = await model(.lab)
        let net = app.network
        await net.loadRoutes(MockRaven.aliAddress)
        let ali = try #require(net.routes[MockRaven.aliAddress])
        #expect(ali.routes.first?.kind == "lan" && ali.carriers?.hints == .lab)
        #expect(ali.learned?.peerIdProven == true && ali.carriers?.told?.first?.takesHandoffs == true)
        #expect(ali.carriers?.coverage?.kind == "mutual_friend")
        #expect(await net.setRoutes(MockRaven.aliAddress, ["internet": "203.0.113.5:7422", "hide_ip": true]))
        #expect(net.routes[MockRaven.aliAddress]?.routes.contains { $0.kind == "internet" && $0.state == .lab } == true)
        #expect(net.routes[MockRaven.aliAddress]?.hideIp == true)
        #expect(await net.setRoutes(MockRaven.aliAddress, ["custodians": [.string(MockRaven.minaAddress)]]))
        #expect(net.routes[MockRaven.aliAddress]?.carriers?.listed?.first?.address == MockRaven.minaAddress)
        #expect(await net.setRoutes(MockRaven.aliAddress, ["clear": ["internet"]]))
        #expect(net.routes[MockRaven.aliAddress]?.routes.contains { $0.kind == "internet" } == false)
        // Rena isn't verified: the engine refuses him as a mail friend, nothing is saved.
        #expect(!(await net.setRoutes(MockRaven.aliAddress, ["custodians": [.string(MockRaven.renaAddress)]])))
        #expect(net.routesError?.code == ErrorCode.badRequest)
        #expect(net.routes[MockRaven.aliAddress]?.carriers?.listed?.first?.address == MockRaven.minaAddress)
        app.presentRoutes(MockRaven.aliAddress)
        #expect(app.sheet == .friendRoutes(MockRaven.aliAddress))
    }

    // MARK: Path chips

    @Test func everyPathKindHasAChip() {
        // Calm's path words: "LAN direct", "Bluetooth", "Held by a friend", "via Tor" (the engine's `onion`).
        let expected = ["lan": "LAN direct", "internet": "Internet", "p2p": "p2p", "p2p_direct": "p2p direct",
                        "p2p_reversed": "p2p reversed", "p2p_relayed": "Relay", "p2p_hole_punched": "Hole punched",
                        "websocket": "Relay · 443", "nearby": "Bluetooth", "friend": "Held by a friend",
                        "handoff": "Passed on by a friend", "letter": "Letter", "onion": "via Tor"]
        for (kind, label) in expected {
            #expect(Display.pathChip(kind: kind, path: "x") == label, "\(kind)")
        }
        // Each kind's colour family (tokens.json color.pathRule).
        #expect(PathFamily.of(kind: "lan") == .lan && PathFamily.of(kind: "nearby") == .nearby)
        #expect(PathFamily.of(kind: "onion") == .tor && PathFamily.of(kind: "internet") == .direct)
        #expect(PathFamily.of(kind: "p2p_relayed") == .relay && PathFamily.of(kind: "websocket") == .relay)
        #expect(PathFamily.of(kind: "friend") == .friend && PathFamily.of(kind: "handoff") == .friend)
        #expect(PathFamily.of(kind: "future_way") == .other)
        // A kind this app doesn't know shows the engine's own words; no path, no chip.
        #expect(Display.pathChip(kind: "future_way", path: "Moon relay") == "Moon relay")
        #expect(Display.pathChip(kind: nil, path: nil) == nil)
        #expect(Display.pathChip(kind: nil, path: "") == nil)
        #expect(tr(.networkPathA11y, ["path": "Relay"]) == "Delivery path: Relay")
    }

    @Test func labMessagesCarryTheirPaths() async throws {
        let (app, _) = await model(.lab)
        let ali = try #require(app.messages[MockRaven.aliAddress])
        #expect(Display.pathChip(kind: ali.first?.pathKind, path: ali.first?.path) == "Relay")
        let mina = try #require(app.messages[MockRaven.minaAddress]?.first)
        #expect(mina.state == .waiting && Display.pathChip(kind: mina.pathKind, path: mina.path) == "Held by a friend")
    }

    @Test func sizesInPlainUnits() {
        #expect(Display.bytes(0) == "0 B")
        #expect(Display.bytes(512) == "512 B")
        #expect(Display.bytes(3072) == "3 KB")
        #expect(Display.bytes(1_258_291) == "1.2 MB")
    }

    // MARK: Pages

    @Test func pagesOpenAndAFriendBringsTheChatBack() async {
        let (app, _) = await model(.release)
        app.presentNetwork()
        app.open(.network)
        #expect(app.page == .network && app.sheet == nil)
        app.open(.security)
        #expect(app.page == .security)
        app.select(MockRaven.minaAddress)
        #expect(app.page == .chat && app.selectedAddress == MockRaven.minaAddress)
        app.open(.updates)
        app.select(MockRaven.minaAddress)
        #expect(app.page == .chat)
    }

    // MARK: Security, Lock v2, updates

    @Test func securityLockAndUpdatesInARelease() async throws {
        let (app, _) = await model(.release)
        let net = app.network
        await net.loadSecurity()
        #expect(net.security?.available == false && net.security?.notices.isEmpty == true)
        await net.loadUpdates()
        #expect(net.updates?.available == false && net.updates?.install == "cli_only")
        #expect(app.lockV2?.available == false && !app.canLock)
        // Lock now isn't offered; asked anyway, the engine says NOT_AVAILABLE_YET and nothing locks.
        await app.lockNow()
        #expect(app.lockError?.code == ErrorCode.notAvailableYet)
        #expect(app.phase == .ready)
    }

    @Test func securityNoticesInALabBuild() async throws {
        let (app, _) = await model(.lab)
        await app.network.loadSecurity()
        let s = try #require(app.network.security)
        #expect(s.available && s.lab == true && s.kept == "live")
        #expect(s.notices.first?.level == "warning" && s.notices.first?.whatRavenDid?.isEmpty == false)
        #expect(s.node?.strangersRefused1h == 3 && s.node?.bansActive == 1)
        await app.network.loadUpdates()
        #expect(app.network.updates?.lab == true && app.network.updates?.summary == "No update is waiting.")
    }

    @Test func lockWhileRunningAndUnlockWithThePassphrase() async throws {
        let (app, _) = await model(.lab)
        #expect(app.lockV2?.supported == true && app.lockV2?.locked == false && app.canLock)
        await app.lock()
        #expect(app.phase == .locked && app.lockV2?.locked == true)
        // No passphrase, then a wrong one: still locked, with the engine's words.
        await app.unlockLocked(passphrase: "")
        #expect(app.lockError?.code == ErrorCode.passphraseNeeded && app.phase == .locked)
        await app.unlockLocked(passphrase: "bob")
        #expect(app.lockError?.code == ErrorCode.passphraseWrong && app.phase == .locked)
        #expect(app.lockError?.message == "That isn't your Raven passphrase. Try again.")
        await app.unlockLocked(passphrase: MockRaven.labPassphrase)
        #expect(app.phase == .ready && app.lockV2?.locked == false && app.lockError == nil)
    }

    /// A profile whose raven-node is locked opens on the locked screen.
    @Test func aLockedNodeOpensOnTheLockedScreen() async throws {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: false, clock: clock, identityDelay: 0, network: .lab)
        _ = try await mock.lockNow()
        let app = AppModel(engine: mock, now: { clock.now })
        await app.bootstrap()
        #expect(app.phase == .locked && app.lockV2?.locked == true)
    }

    @Test func noNetworkCallRunsOnTheMainThread() async {
        let (app, mock) = await model(.lab)
        let net = app.network
        await net.refresh()
        await net.runCheck(router: true)
        await net.loadRoutes(MockRaven.aliAddress)
        await net.loadSecurity()
        await net.loadUpdates()
        await net.toggle("internet", on: true)
        await net.restartNode()
        #expect(mock.callsOnMainThread == 0)
    }
}
