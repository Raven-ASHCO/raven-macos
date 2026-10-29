#if RAVEN_ENGINE
import CRavenClient
import Foundation
import Testing
@testable import RavenUI

/// A throwaway profile for the real engine. raven-client reads its profile folder once, on the first
/// call in the process, so every engine test reaches the engine only after `EngineProfile.ready`:
/// a new temporary folder and the file-backed secret stores (never ~/.raven, never the Keychain).
/// Nothing here starts raven-node or listens: `receive` stays off.
enum EngineProfile {
    static let dataDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rvn-swift-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let env = [
            "RAVEN_DATA_DIR": dir.path,
            "RAVEN_IDENTITY_BACKEND": "locked-file",
            "RAVEN_SESSION_BACKEND": "locked-file",
            "RAVEN_PREKEY_BACKEND": "locked-file",
            "RAVEN_CHAT_HISTORY_BACKEND": "locked-file",
            "RAVEN_ALLOW_EPHEMERAL_DATA_DIR": "1",
        ]
        for (key, value) in env { setenv(key, value, 1) }
        unsetenv("ASH_DATA_DIR")
        // The privacy pack's lab switches (raven-core's PRIVACY_LAB_SWITCHES): a plain profile,
        // whatever the suite runs with (raven-client's own tests cover sealed ones).
        for key in ["RAVEN_LAB_AT_REST", "RAVEN_LAB_ERASE_ROOT", "RAVEN_LAB_AT_REST_KEY_FAULT",
                    "RAVEN_LAB_RETENTION_GRACE_MS", "RAVEN_LAB_LOGIN_ITEM_ROOT", "RAVEN_LAB_LOGIN_ITEM_TOOLS"] {
            unsetenv(key)
        }
        atexit { try? FileManager.default.removeItem(at: EngineProfile.dataDir) }
        return dir
    }()

    /// Call before the first engine call of a test.
    static func ready() -> URL {
        let dir = dataDir
        precondition(ProcessInfo.processInfo.environment["RAVEN_DATA_DIR"] == dir.path)
        return dir
    }

    /// One raw envelope through `RavenClientEngine.rawCall` (raven_call / raven_free), parsed.
    static func raw(_ op: String, _ args: [String: JSONValue] = [:]) throws -> JSONValue {
        _ = ready()
        return try JSONValue.parse(RavenClientEngine.rawCall(RavenEnvelope.request(op: op, args: args)))
    }

    /// The engine's debug build (`RAVEN_ENGINE=dev`, app.info says `dev`) accepts the file-backed
    /// stores; a release engine refuses them, so with it only the refusal is tested.
    static let isDevEngine: Bool = (try? raw("app.info"))?["result"]?["build"]?.string == "dev"
}

/// The real engine (raven-client) through the C module, on one temporary profile. Built and run only
/// when the engine is linked: `RAVEN_ENGINE=dev swift test` runs everything, `RAVEN_ENGINE=1 swift
/// test` (the release engine) checks that it refuses the test stores. The steps share the process's
/// one engine, so they run in order inside one test.
@MainActor
@Suite(.serialized) struct EngineTests {
    @Test(.enabled(if: EngineProfile.isDevEngine, "needs the engine's debug build (RAVEN_ENGINE=dev)"))
    func aNewProfileFromWelcomeToReady() async throws {
        let dir = EngineProfile.ready()
        let engine = RavenClientEngine()

        // profile.state: new, and the app shows the welcome screen.
        #expect(try await engine.profileState().state == .new)
        let welcome = AppModel(engine: engine)
        await welcome.bootstrap()
        #expect(welcome.phase == .welcome)

        // app.info
        let info = try await engine.appInfo()
        #expect(!info.version.isEmpty && ["release", "dev"].contains(info.build))
        #expect(info.platform == "macos")
        #expect(try EngineProfile.raw("app.info")["result"]?["api"]?.int == 1)

        // privacy.state: a plain profile (a debug engine without the lab switch), not locked; the
        // actions the app does not offer yet answer NOT_AVAILABLE_YET, and Unlock answers as
        // profile.state.
        #expect(try await engine.privacyState() == PrivacyState(available: false, encrypted: false, locked: false))
        #expect(try EngineProfile.raw("privacy.unlock")["result"]?["state"]?.string == "new")
        for op in ["privacy.lock", "privacy.encrypt"] {
            #expect(try EngineProfile.raw(op)["error"]?["code"]?.string == ErrorCode.notAvailableYet, "\(op)")
        }

        // Settings chosen during setup are kept in memory until the identity exists.
        let early = try await engine.setSettings(["receive": false, "display_name": "Tëst Mac ✓"])
        #expect(early.receive == false && early.displayName == "Tëst Mac ✓")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("desktop_settings.json").path))

        // identity.create: 10 words from Raven's list (the check word fits), the old code.
        let created = try await engine.createIdentity(displayName: "Tëst Mac ✓")
        #expect(created.address.hasPrefix("rvn1"))
        #expect(created.words.count == 10)
        let list = MockWordList.shared
        let indexes = created.words.compactMap { list.resolve($0) }
        #expect(indexes.count == 10 && MockWordList.checkOK(indexes), "words: \(created.words)")
        // Groups of four letters and digits (fewer when the base64 form had a + or /, which are dropped).
        #expect(created.oldCode.range(of: #"^[A-Za-z0-9]{4}(-[A-Za-z0-9]{1,4}){1,2}$"#, options: .regularExpression) != nil)
        #expect(try await engine.profileState().state == .ready)

        // identity.me: the same identity, with the card and the invite.
        let me = try await engine.me()
        #expect(me.address == created.address && me.words == created.words && me.oldCode == created.oldCode)
        #expect(me.card?.isEmpty == false && me.invite?.isEmpty == false)

        // card.make: without an address; asked for one while nothing listens, it says why not.
        let card = try await engine.makeCard(includeAddress: false)
        #expect(!card.card.isEmpty && !card.invite.isEmpty && card.addressIncluded == nil)
        let withAddress = try EngineProfile.raw("card.make", ["include_address": true])["result"]
        #expect(withAddress?["address_included"] == nil)
        #expect(withAddress?["address_missing"]?.string == "not_receiving")
        #expect(card.card == me.card && card.invite == me.invite)

        // Settings round-trip, written to the profile once the identity exists.
        var settings = try await engine.settings()
        #expect(settings.receive == false && settings.displayName == "Tëst Mac ✓")
        settings = try await engine.setSettings(["reduced_motion": true, "when_quit": "ask", "keep_chats_days": 7])
        #expect(settings.reducedMotion && settings.whenQuit == "ask" && settings.keepChatsDays == 7 && !settings.receive)
        settings = try await engine.setSettings(["keep_chats_days": nil])
        #expect(settings.keepChatsDays == nil)
        #expect(try await engine.settings() == settings)
        // The name has its own file (sealed once the profile is; plain JSON here), and the
        // chat-keeping time is the privacy pack's setting: desktop_settings.json names nobody.
        let file = try String(contentsOf: dir.appendingPathComponent("desktop_settings.json"), encoding: .utf8)
        #expect(!file.contains("Tëst Mac ✓") && !file.contains("keep_chats_days"))
        let named = try String(contentsOf: dir.appendingPathComponent("desktop_private.rms"), encoding: .utf8)
        #expect(named.contains("Tëst Mac ✓"))
        do {
            _ = try await engine.setSettings(["when_quit": "sometimes"])
            Issue.record("expected BAD_REQUEST")
        } catch let e as RavenError {
            #expect(e.code == ErrorCode.badRequest)
        }

        // node.status: nothing runs for this profile (and nothing was started).
        let node = try await engine.nodeStatus()
        #expect(!node.running && !node.receive && node.state == "not_running")

        // events.poll: never blocks; a seq from before this engine says reset.
        let batch = try await engine.poll(after: 0)
        #expect(batch.reset == false && batch.seq >= 0)
        let ahead = try await engine.poll(after: batch.seq + 1000)
        #expect(ahead.reset == true && ahead.seq == batch.seq)

        // The network ops (API.md, Network): every way decodes with its state; LAN direct is on, and
        // a debug engine without a lab switch holds the rest (preview) and refuses to turn one on.
        let net = try await engine.networkStatus()
        #expect(net.way("lan")?.state == .on)
        #expect(net.carriers.count >= 13 && (net.protections ?? []).count >= 6)
        #expect(net.help?.effects?.store.contains("changes nothing yet") == true)
        if net.way("p2p")?.state == .preview {
            do {
                _ = try await engine.setNetwork(["p2p": true])
                Issue.record("expected NOT_AVAILABLE_YET")
            } catch let e as RavenError {
                #expect(e.code == ErrorCode.notAvailableYet)
            }
        }
        let flags = try await engine.setNetwork(["store": false])
        #expect(flags.changes.count == 1 && flags.status.help?.store == false && flags.status.help?.automatic == false)
        _ = try await engine.setNetwork(["store": true])
        let check = try await engine.checkNetwork()
        #expect(check.summary.contains { $0.key == "identity" } && check.router == nil)
        _ = try await engine.securityStatus()
        _ = try await engine.lockState()
        #expect(try await engine.updatesStatus().install == "cli_only")

        // The app opens the ready profile on the engine: no friends yet.
        let ready = AppModel(engine: engine)
        await ready.bootstrap()
        #expect(ready.phase == .ready)
        #expect(ready.identity?.address == created.address && ready.contacts.isEmpty)
        #expect(ready.settings.reducedMotion && ready.node?.running == false)
        await ready.pollNow()
        #expect(ready.phase == .ready)
    }

    /// The Network page's model on the real engine and the throwaway profile (new or set up: the
    /// tests share one profile, in whatever order they run): `network.status` decodes, every way has
    /// a state and a name, LAN direct is there, the lab banner follows the switches the engine sees,
    /// and the read-only pages answer.
    @Test(.enabled(if: EngineProfile.isDevEngine, "needs the engine's debug build (RAVEN_ENGINE=dev)"))
    func theNetworkPageReadsTheEngine() async throws {
        _ = EngineProfile.ready()
        let engine = RavenClientEngine()
        let net = NetworkModel(engine: engine)
        await net.refresh()
        #expect(net.loadError == nil, "\(String(describing: net.loadError))")
        let status = try #require(net.status)
        #expect(status.build == "dev")
        #expect(status.carriers.count >= 13 && (status.protections ?? []).count >= 6)
        for way in status.carriers + (status.protections ?? []) {
            #expect(way.name?.isEmpty == false, "\(way.id)")
            #expect(!Display.wayState(way.state).text.isEmpty)
            _ = NetworkModel.toggle(for: way)
        }
        let lan = try #require(status.way("lan"))
        #expect([.on, .off].contains(lan.state) && NetworkModel.toggle(for: lan).enabled)
        let seen = ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("RAVEN_LAB_") }
        #expect(NetworkModel.labSwitches(status: status, node: nil).isEmpty == seen.isEmpty)
        #expect(status.texts?.carryForFriends.isEmpty == false)
        await net.loadUpdates()
        #expect(net.updates?.install == "cli_only")
        await net.loadSecurity()
        #expect(net.securityError == nil)
    }

    /// A release engine never runs on the file-backed stores (raven-core refuses them before it
    /// looks for an identity, so nothing reaches the Keychain): the app shows why.
    @Test(.enabled(if: !EngineProfile.isDevEngine, "needs the release engine (RAVEN_ENGINE=1)"))
    func aReleaseEngineRefusesTheTestStores() async throws {
        let dir = EngineProfile.ready()
        let engine = RavenClientEngine()
        #expect(try await engine.appInfo().build == "release")
        let state = try await engine.profileState()
        #expect(state.state == .unreadable)
        #expect(state.detail?.contains("forbidden in Release builds") == true, "\(String(describing: state.detail))")
        let model = AppModel(engine: engine)
        await model.bootstrap()
        guard case .failed(let error) = model.phase else {
            Issue.record("expected the failure screen, got \(model.phase)")
            return
        }
        #expect(error.code == ErrorCode.profileUnreadable && error.detail.contains("forbidden in Release builds"))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!files.contains { $0.hasPrefix("identity") || $0.hasSuffix(".seed") }, "\(files)")
    }

    @Test func wordHintsComeFromRavensList() async throws {
        _ = EngineProfile.ready()
        let engine = RavenClientEngine()
        #expect(try await engine.wordHint(prefix: "tur") == "turtle")
        #expect(try await engine.wordHint(prefix: "TURTLES") == "turtle")
        #expect(try await engine.wordHint(prefix: "tu") == nil)
        #expect(try await engine.wordHint(prefix: "xyz") == nil)
        #expect(try EngineProfile.raw("verify.word_hint", ["prefix": "tur"])["result"]?["known"]?.bool == true)
    }

    /// Groups follow the engine's gate, through the app's own wrappers: on since raven-core 0.1.0,
    /// in release and debug builds; a debug build closes them with `RAVEN_LAB_GROUPS=0`. Closed,
    /// `groups.list` says not available (the app shows no Groups section) and every other group op is
    /// NOT_AVAILABLE_YET; open, it lists this profile's groups (none yet) once the identity exists.
    @Test(.enabled(if: EngineProfile.isDevEngine, "needs the engine's debug build (RAVEN_ENGINE=dev)"))
    func groupsFollowTheEnginesGate() async throws {
        _ = EngineProfile.ready()
        let engine = RavenClientEngine()
        if ProcessInfo.processInfo.environment["RAVEN_LAB_GROUPS"] == "0" {
            let list = try await engine.groups()
            #expect(!list.available && list.groups.isEmpty)
            do {
                _ = try await engine.groupHistory("00000000000000000000000000000000")
                Issue.record("groups.history answered with groups closed")
            } catch let e as RavenError {
                #expect([ErrorCode.notAvailableYet, ErrorCode.notInitialized].contains(e.code), "\(e.code)")
            }
        } else {
            // The suite runs in order: aNewProfileFromWelcomeToReady made the identity before this.
            guard try await engine.profileState().state == .ready else { return }
            let list = try await engine.groups()
            #expect(list.available && list.groups.isEmpty)
        }
    }

    /// The C boundary itself: NULL and unknown operations are answered, never NULL, and every
    /// response goes back to raven_free.
    @Test func theCBoundaryAnswersEverything() throws {
        _ = EngineProfile.ready()
        let null = try #require(raven_call(nil))
        let nullText = String(cString: null)
        raven_free(null)
        #expect(try JSONValue.parse(nullText)["error"]?["code"]?.string == ErrorCode.badRequest)
        raven_free(nil)

        let unknown = try JSONValue.parse(RavenClientEngine.rawCall(#"{"v": 1, "op": "no.such.op", "args": {}}"#))
        #expect(unknown["ok"]?.bool == false && unknown["error"]?["code"]?.string == ErrorCode.badRequest)
        let broken = try JSONValue.parse(RavenClientEngine.rawCall("{not json"))
        #expect(broken["error"]?["code"]?.string == ErrorCode.badRequest)
        // (UTF-8 both ways: the display name "Tëst Mac ✓" in aNewProfileFromWelcomeToReady.)
    }
}
#endif
