import Foundation
import Testing
@testable import RavenUI

@Suite struct EnvelopeTests {
    @Test func successAndFailureRoundTrip() throws {
        let ok = try RavenEnvelope.parseResponse(#"{"v":1,"ok":true,"result":{"x":1},"extra":"ignored"}"#)
        #expect(ok["x"]?.int == 1)
        do {
            _ = try RavenEnvelope.parseResponse(RavenEnvelope.failure(RavenError(code: "NOT_A_CONTACT", message: "m", detail: "d")))
            Issue.record("expected a failure")
        } catch let e as RavenError {
            #expect(e == RavenError(code: "NOT_A_CONTACT", message: "m", detail: "d"))
        }
    }

    @Test func requestShape() throws {
        let req = try JSONValue.parse(RavenEnvelope.request(op: "contacts.list", args: [:]))
        #expect(req["v"]?.int == 1)
        #expect(req["op"]?.string == "contacts.list")
        #expect(req["args"]?.object?.isEmpty == true)
    }

    @Test func unknownOpAndNewerVersionFail() throws {
        let mock = readyMock()
        let unknown = try raw(mock, "no.such.op")
        #expect(unknown["ok"]?.bool == false)
        #expect(unknown["error"]?["code"]?.string == "BAD_REQUEST")
        #expect(unknown["error"]?["message"]?.string == "Raven didn't understand what this app asked. Update Raven; if it keeps happening, open Details.")
        let newer = try JSONValue.parse(mock.handle(#"{"v":2,"op":"app.info","args":{}}"#))
        #expect(newer["ok"]?.bool == false)
        #expect(newer["error"]?["code"]?.string == "BAD_REQUEST")
        let extra = try JSONValue.parse(mock.handle(#"{"v":1,"op":"app.info","args":{"unknown":true},"later":1}"#))
        #expect(extra["ok"]?.bool == true)
    }
}

@Suite struct MockNetworkTests {
    /// The mock answers the network ops as a release build: LAN direct on, the rest held, a held way
    /// never turned on, the help-friends flags and LAN kept as set.
    @Test func networkAnswersLikeARelease() async throws {
        let mock = readyMock()
        let net = try await mock.networkStatus()
        #expect(net.way("lan")?.state == .on)
        for w in net.carriers + (net.protections ?? []) where w.id != "lan" {
            #expect(w.state == .preview, "\(w.id)")
        }
        do {
            _ = try await mock.setNetwork(["p2p": true, "store": false])
            Issue.record("expected NOT_AVAILABLE_YET")
        } catch let e as RavenError {
            #expect(e.code == ErrorCode.notAvailableYet)
        }
        #expect(try await mock.networkStatus().help?.store == true)
        let set = try await mock.setNetwork(["store": false, "lan": false])
        #expect(set.changes.count == 2 && set.status.help?.store == false)
        #expect(set.status.way("lan")?.state == .off)
        let check = try await mock.checkNetwork(router: true)
        #expect(check.summary.contains { $0.key == "lan" } && check.router != nil)
        #expect(try await mock.securityStatus().available == false)
        #expect(try await mock.lockState().available == false)
        #expect(try await mock.updatesStatus().install == "cli_only")
    }

    /// The lab mode answers as a developer build with lab switches: open ways, CONSENT_NEEDED without
    /// `agreed`, `restart_needed` for a running raven-node, Lock v2 with a passphrase.
    @Test func labModeAnswersLikeADeveloperBuild() async throws {
        let mock = MockRaven(start: .ready, demo: false, clock: MockClock(fixed: testStart), identityDelay: 0, network: .lab)
        let net = try await mock.networkStatus()
        #expect(net.labSwitches == MockRaven.labSwitches && net.way("p2p")?.state == .lab && net.way("nearby")?.state == .notOnThisOs)
        let refused = try raw(mock, "network.set", ["carry_for_friends": true])
        #expect(refused["error"]?["code"]?.string == ErrorCode.consentNeeded)
        #expect(try await mock.networkStatus().carry?.carryForFriends?.on == false)
        let agreed = try await mock.setNetwork(["carry_for_friends": true, "agreed": true])
        #expect(agreed.status.carry?.carryForFriends?.on == true && !agreed.restartNeeded)
        let restart = try await mock.setNetwork(["internet": true])
        #expect(restart.restartNeeded && restart.changes.first?.applies == "restart")
        #expect(try await mock.lockState().supported)
        #expect(try raw(mock, "lock.unlock", ["passphrase": "bob"])["error"]?["code"]?.string == ErrorCode.passphraseWrong)
        #expect(try raw(mock, "node.stop")["result"]?["stop"]?.string == "stopped")
    }

    @Test func contactRoutesAndMailFriends() async throws {
        let mock = readyMock()
        let ali = try await mock.contactRoutes(address: MockRaven.aliAddress)
        #expect(ali.routes.first?.kind == "lan" && ali.routes.last?.kind == "nearby")
        let set = try await mock.setContactRoutes(address: MockRaven.aliAddress,
                                                  ["internet": "203.0.113.5:7422",
                                                   "custodians": [.string(MockRaven.minaAddress)]])
        #expect(set.routes.routes.contains { $0.kind == "internet" })
        #expect(set.routes.carriers?.listed?.first?.address == MockRaven.minaAddress)
        do {
            _ = try await mock.setContactRoutes(address: MockRaven.aliAddress, ["custodians": [.string(MockRaven.renaAddress)]])
            Issue.record("Rena is not verified")
        } catch let e as RavenError {
            #expect(e.code == ErrorCode.badRequest)
        }
    }
}

@Suite struct MockRavenTests {
    @Test func newProfileNeedsSetup() async throws {
        let mock = MockRaven(start: .new, demo: true, clock: MockClock(fixed: testStart), identityDelay: 0)
        #expect(try await mock.profileState().state == .new)
        await #expect(throws: RavenError.self) { _ = try await mock.contacts() }
        let created = try await mock.createIdentity(displayName: "Sam")
        #expect(created.words.count == 10)
        #expect(created.words.last == "wagon")
        #expect(try await mock.profileState().state == .ready)
        let me = try await mock.me()
        #expect(me.oldCode == MockRaven.myOldCode)
        #expect(me.displayName == "Sam")
        let contacts = try await mock.contacts()
        #expect(contacts.map(\.name) == ["Ali", "Mina", "Rena"])
    }

    @Test func demoFriends() async throws {
        let mock = readyMock()
        let contacts = try await mock.contacts()
        let ali = try #require(contacts.first { $0.name == "Ali" })
        let mina = try #require(contacts.first { $0.name == "Mina" })
        let rena = try #require(contacts.first { $0.name == "Rena" })
        #expect(ali.verified && ali.presence == .inTouch)
        #expect(mina.verified && mina.waiting?.count == 1)
        #expect(mina.waiting!.untilMs > testStart.ms)
        #expect(!rena.verified)
        #expect(contacts.map { $0.avatarIndex } == [0, 1, 2])
    }

    /// The demo stream follows the mockup, and every event kind is one of API.md's.
    @Test func demoEventStream() async throws {
        let mock = readyMock()
        var seq = 0
        var all: [RavenEvent] = []
        var at = 0.0
        for step in stride(from: 0.0, through: 13.0, by: 0.5) {
            mock.clock.advance(step - at)
            at = step
            let events = try await pollAll(mock, after: &seq)
            all += events
        }
        let allowed: Set<EventKind> = [.statusOk, .sendStarted, .receipt, .incoming, .retry, .presence, .state, .node, .unread,
                                       .groupMessage, .groupChanged]
        #expect(all.allSatisfy { allowed.contains($0.kind) })
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.seq < $1.seq })

        let story = all.filter { $0.kind != .statusOk }.map { e -> String in
            switch e.kind {
            case .incoming: return "incoming:\(e.message?.text ?? "")"
            case .presence: return "presence:\(e.address == MockRaven.minaAddress ? "Mina" : "Rena"):\(e.presence?.rawValue ?? "")"
            case .retry: return "retry:\(e.id ?? ""):\(e.attempts ?? 0)"
            case .sendStarted: return "send_started:\(e.id ?? "")"
            case .state: return "state:\(e.id ?? ""):\(e.state?.rawValue ?? "")"
            case .receipt: return "receipt:\(e.id ?? ""):\(e.path ?? "")"
            case .node: return "node"
            case .unread: return "unread:\(e.address == MockRaven.aliAddress ? "Ali" : "Rena"):\(e.unread ?? -1)"
            case .groupChanged: return "group_changed"
            case .groupMessage: return "group_message:\(e.groupMessage?.text ?? "")"
            default: return "?"
            }
        }
        #expect(story == [
            "node",
            "incoming:Great. Can you bring the charger?",
            "unread:Ali:1",
            "presence:Rena:in_touch",
            "incoming:Hi, it's Rena. Did my invite reach you?",
            "unread:Rena:1",
            "retry:m3:2",
            "send_started:demo-send",
            "state:demo-send:sent",
            "receipt:demo-send:LAN direct",
            "group_changed",
            "group_message:I'll bring the second book too.",
            "presence:Mina:in_touch",
            "send_started:m3",
            "receipt:m3:LAN direct",
        ])
        // A status check every 2 s (statusCheckInterval).
        let beats = all.filter { $0.kind == .statusOk }.map(\.atMs)
        #expect(beats.count == 7)
        #expect(zip(beats, beats.dropFirst()).allSatisfy { $1 - $0 == 2000 })

        // Mina's waiting message got through; nothing waits any more.
        let mina = try #require(try await mock.contacts().first { $0.name == "Mina" })
        #expect(mina.waiting == nil)
        #expect(try await mock.history(address: MockRaven.minaAddress).last?.state == .delivered)
    }

    /// After the demo, an idle profile produces nothing but the heartbeat.
    @Test func idleIsQuiet() async throws {
        let mock = readyMock()
        var seq = 0
        _ = try await pollAll(mock, after: &seq)
        mock.clock.advance(20)
        _ = try await pollAll(mock, after: &seq)
        mock.clock.advance(10)
        let later = try await pollAll(mock, after: &seq)
        #expect(later.map(\.kind) == [.statusOk])
        let none = try await pollAll(mock, after: &seq)
        #expect(none.isEmpty)
    }

    @Test func sendToFriendInTouch() async throws {
        let mock = readyMock(demo: false)
        var seq = 0
        _ = try await pollAll(mock, after: &seq)
        let sent = try await mock.send(address: MockRaven.aliAddress, text: "  hello  ")
        #expect(sent.state == .sending && sent.text == "hello")
        var events = try await pollAll(mock, after: &seq)
        #expect(events.contains { $0.kind == .sendStarted && $0.id == sent.id })
        mock.clock.advance(1.0)
        events = try await pollAll(mock, after: &seq)
        #expect(events.contains { $0.kind == .state && $0.id == sent.id && $0.state == .sent })
        #expect(!events.contains { $0.kind == .receipt })   // never delivered before the receipt
        mock.clock.advance(1.0)
        events = try await pollAll(mock, after: &seq)
        let receipt = try #require(events.first { $0.kind == .receipt && $0.id == sent.id })
        #expect(receipt.path == "LAN direct" && (receipt.ms ?? 0) > 0)
        #expect(try await mock.history(address: MockRaven.aliAddress).last?.state == .delivered)
    }

    @Test func sendToFriendAwayWaits() async throws {
        let mock = readyMock(demo: false)
        let sent = try await mock.send(address: MockRaven.renaAddress, text: "are you there?")
        mock.clock.advance(1)
        let after = try await mock.history(address: MockRaven.renaAddress).last
        #expect(after?.id == sent.id && after?.state == .waiting)
        let details = try await mock.details(id: sent.id)
        #expect(details.statusText.hasPrefix("Waiting for Rena until"))
        #expect(details.whyText == "Rena's Raven isn't reachable (Rena may be away or on another network).")
        let stopped = try await mock.stop(id: sent.id)
        #expect(stopped.state == .failed)
    }

    @Test func sendErrors() async throws {
        let mock = readyMock(demo: false)
        await #expect(throws: RavenError.self) { _ = try await mock.send(address: "rvn1qnobody", text: "x") }
        do {
            _ = try await mock.send(address: MockRaven.aliAddress, text: String(repeating: "a", count: 5000))
            Issue.record("expected MESSAGE_TOO_LONG")
        } catch let e as RavenError {
            #expect(e.code == "MESSAGE_TOO_LONG")
        }
    }

    // MARK: Security words

    @Test func checkWordAlgorithmMatchesReference() {
        let list = MockWordList.shared
        #expect(list.words.count == 256)
        // Reference vector "alice" from security_words.py.
        let mine = MockRaven.myWords.compactMap { list.resolve($0) }
        #expect(mine == [241, 80, 25, 253, 153, 114, 81, 125, 98, 248])
        #expect(MockWordList.checkOK(mine))
        #expect(MockWordList.checkIndex(Array(mine.prefix(9))) == 248)
    }

    /// The check word catches every single wrong word and every swap of two neighbours.
    @Test func checkWordCatchesSingleErrorsAndSwaps() {
        let list = MockWordList.shared
        let words = MockRaven.aliWords.compactMap { list.resolve($0) }
        for position in 0..<10 {
            for delta in [1, 7, 128, 255] {
                var wrong = words
                wrong[position] = (wrong[position] + delta) % 256
                #expect(!MockWordList.checkOK(wrong))
            }
        }
        for i in 0..<9 where words[i] != words[i + 1] {
            var swapped = words
            swapped.swapAt(i, i + 1)
            #expect(!MockWordList.checkOK(swapped))
        }
    }

    @Test func verifyMatchTypoMismatch() async throws {
        let mock = readyMock(demo: false)
        let rena = MockRaven.renaAddress
        // Mismatch: valid words (the check word fits) but not Rena's.
        #expect(try await mock.checkWords(address: rena, words: MockRaven.minaWords) == .mismatch)
        // Typo: one misheard word; the check word catches it.
        var misheard = MockRaven.renaWords
        misheard[4] = "beach"
        #expect(try await mock.checkWords(address: rena, words: misheard) == .typo)
        // Swapped words are a typo too.
        var swapped = MockRaven.renaWords
        swapped.swapAt(0, 1)
        #expect(try await mock.checkWords(address: rena, words: swapped) == .typo)
        #expect(try await mock.contacts().first { $0.address == rena }?.verified == false)
        // Match (prefixes, plurals and capitals are fine): Rena becomes verified.
        let spoken = ["AIRPORT", "balls", "ban", "batt", "bed", "belts", "baby", "bask", "anch", "eag"]
        #expect(try await mock.checkWords(address: rena, words: spoken) == .match)
        #expect(try await mock.contacts().first { $0.address == rena }?.verified == true)
    }

    @Test func verifyNeedsTenRavenWords() async throws {
        let mock = readyMock(demo: false)
        for words in [Array(MockRaven.aliWords.prefix(9)), MockRaven.aliWords.dropLast() + ["zebraxx"]] {
            do {
                _ = try await mock.checkWords(address: MockRaven.aliAddress, words: words)
                Issue.record("expected WORDS_INCOMPLETE")
            } catch let e as RavenError {
                #expect(e.code == "WORDS_INCOMPLETE")
            }
        }
    }

    @Test func wordHintCompletesAfterThreeLetters() async throws {
        let mock = readyMock(demo: false)
        #expect(try await mock.wordHint(prefix: "tu") == nil)
        #expect(try await mock.wordHint(prefix: "tur") == "turtle")
        #expect(try await mock.wordHint(prefix: "TURT") == "turtle")
        #expect(try await mock.wordHint(prefix: "\u{FF54}\u{FF55}\u{FF52}") == "turtle")   // full-width letters
        #expect(try await mock.wordHint(prefix: "xyz") == nil)
    }

    /// The friend's words never leave the engine.
    @Test func friendWordsAreNeverReturned() throws {
        let mock = readyMock()
        let secret = MockRaven.aliWords.joined(separator: " ")
        for op in ["contacts.list", "identity.me", "settings.get", "node.status", "events.poll"] {
            let text = try raw(mock, op, op == "events.poll" ? ["after_seq": 0] : [:]).text()
            #expect(!text.contains("kettle") && !text.contains(secret), "\(op) leaked a friend's word")
        }
        let parsed = try raw(mock, "card.parse", ["text": .string("raven-card/1 address=\(MockRaven.aliAddress) pub_hex=00 fingerprint=Ab3d-Ef56-Gh78 lan=10.0.0.2:7420")])
        #expect(!parsed.text().contains("Ab3d-Ef56-Gh78"))
        #expect(parsed["result"]?["has_address"]?.bool == true)
    }

    /// card.parse as a release engine answers it: internet and p2p addresses in a card are left out
    /// (`ignored_routes`, `note`), and the add-friend step then says so.
    @Test func cardAddressesNobodySignsAreLeftOut() async throws {
        let mock = readyMock(demo: false)
        let base = "raven-card/1 address=\(MockRaven.aliAddress) pub_hex=00 fingerprint=x"
        let routed = try await mock.parseCard(base + " inet=203.0.113.7:7420 p2p=/ip4/198.51.100.2/udp/7423")
        #expect(routed.ignoredRoutes == ["internet", "p2p"] && routed.note != nil)
        #expect(routed.leftOutAddresses && !routed.hasAddress)
        let lan = try await mock.parseCard(base + " lan=10.0.0.2:7420")
        #expect(!lan.leftOutAddresses && lan.hasAddress && lan.note == nil)
        // An older engine sends neither field.
        let old = try JSONValue.parse(#"{"short_address":"rvn1…","has_address":false,"routes":[]}"#).decode(CardSummary.self)
        #expect(!old.leftOutAddresses)
        #expect(!tr(.addPasteIgnoredRoutes).isEmpty)
    }

    // MARK: Contacts, settings, lock

    @Test func addContactAndNameClash() async throws {
        let mock = readyMock(demo: false)
        let card = "raven-card/1 address=rvn1qz8m4c7hj2kd9wl0a6vrsx5qtyn3pfe8gu7c2hla pub_hex=00 fingerprint=x"
        let summary = try await mock.parseCard(card)
        #expect(summary.shortAddress == "rvn1qz8m…c2hla" && !summary.hasAddress)
        do {
            _ = try await mock.addContact(text: card, name: "ali")
            Issue.record("expected NAME_CLASH")
        } catch let e as RavenError {
            #expect(e.code == "NAME_CLASH")
            #expect(e.message == "You already have a friend called ali. Pick another name.")
        }
        let added = try await mock.addContact(text: card, name: "Sam")
        #expect(!added.verified && added.presence == .noAddress)
        await #expect(throws: RavenError.self) { _ = try await mock.parseCard("hello there") }
        // Without an address, a message cannot leave: "Not sent: meet first".
        let m = try await mock.send(address: added.address, text: "hi")
        #expect(m.state == .notSentMeetFirst)
    }

    @Test func settingsRoundTrip() async throws {
        let mock = readyMock(demo: false)
        var s = try await mock.setSettings(["reduced_motion": true, "keep_chats_days": .null, "when_quit": "ask"])
        #expect(s.reducedMotion && s.keepChatsDays == nil && s.whenQuit == "ask")
        s = try await mock.setSettings(["keep_chats_days": 90, "when_quit": "bogus"])
        #expect(s.keepChatsDays == 90 && s.whenQuit == "ask")
        _ = try await mock.setSettings(["receive": false])
        #expect(try await mock.nodeStatus().listening == nil)
    }

    /// Until the privacy pack lands: state says not available, every action says NOT_AVAILABLE_YET.
    @Test func privacyIsNotAvailableYet() async throws {
        let mock = readyMock(demo: false)
        #expect(try await mock.privacyState() == PrivacyState(available: false, encrypted: false, locked: false))
        func expectNotAvailable(_ op: String, _ args: [String: JSONValue] = [:]) throws {
            let r = try raw(mock, op, args)
            #expect(r["ok"]?.bool == false, "\(op)")
            #expect(r["error"]?["code"]?.string == "NOT_AVAILABLE_YET", "\(op)")
            #expect(r["error"]?["message"]?.string == "This isn't in this release of Raven yet. Nothing was changed.")
        }
        try expectNotAvailable("privacy.lock")
        try expectNotAvailable("privacy.unlock")
        try expectNotAvailable("privacy.encrypt")
        try expectNotAvailable("privacy.erase", ["confirm": "erase"])
        #expect(try raw(mock, "privacy.erase", ["confirm": "yes"])["error"]?["code"]?.string == "BAD_REQUEST")
        #expect(try raw(mock, "privacy.erase")["error"]?["code"]?.string == "BAD_REQUEST")
        #expect(try await mock.contacts().count == 3)      // nothing changed
        await #expect(throws: RavenError.self) { try await mock.encrypt() }
    }

    /// A locked profile (reachable for review with RAVEN_MOCK_STATE=locked) refuses everything.
    @Test func lockedProfileRefusesEverything() async throws {
        let mock = MockRaven(start: .locked, demo: false, clock: MockClock(fixed: testStart), identityDelay: 0)
        #expect(try await mock.profileState().state == .locked)
        #expect(try await mock.privacyState().locked)
        do {
            _ = try await mock.contacts()
            Issue.record("expected PROFILE_LOCKED")
        } catch let e as RavenError {
            #expect(e.code == "PROFILE_LOCKED")
            #expect(e.message == "Raven is locked. Unlock it to continue.")
        }
    }

    // MARK: Old code

    @Test func oldCodeMatchAndMismatch() async throws {
        let mock = readyMock(demo: false)
        let rena = MockRaven.renaAddress
        // Wrong code, wrong case, or another friend's: mismatch, and nothing is pinned.
        #expect(try await mock.checkOldCode(address: rena, code: "Tq7m-29Xa-hKe5") == .mismatch)
        #expect(try await mock.checkOldCode(address: rena, code: "TQ7M-29XA-HKE4") == .mismatch)
        #expect(try await mock.checkOldCode(address: rena, code: MockRaven.myOldCode) == .mismatch)
        #expect(try await mock.checkOldCode(address: MockRaven.aliAddress, code: MockRaven.renaOldCode) == .mismatch)
        #expect(try await mock.contacts().first { $0.address == rena }?.verified == false)
        // Spaces, other separators and Persian or Arabic-Indic digits are fine.
        #expect(try await mock.checkOldCode(address: rena, code: " Tq\u{06F7}m 2\u{0669}Xa\u{2013}hKe4 ") == .match)
        #expect(try await mock.contacts().first { $0.address == rena }?.verified == true)
        // The result says only match or mismatch.
        let r = try raw(mock, "verify.check_old_code", ["address": .string(rena), "code": "Tq7mx"])
        #expect(r["result"]?.object?.keys.sorted() == ["result"])
        #expect(!r.text().contains("hKe4"))
    }

    @Test func oldCodeBadRequests() throws {
        let mock = readyMock(demo: false)
        #expect(try raw(mock, "verify.check_old_code", ["address": .string(MockRaven.renaAddress), "code": " - "])["error"]?["code"]?.string == "BAD_REQUEST")
        #expect(try raw(mock, "verify.check_old_code", ["code": "Tq7m"])["error"]?["code"]?.string == "BAD_REQUEST")
        #expect(try raw(mock, "verify.check_old_code", ["address": "rvn1qnobody", "code": "Tq7m"])["error"]?["code"]?.string == "NOT_A_CONTACT")
        #expect(WordInput.oldCodeKey("If4x 36FU\u{200B}-omFi") == "If4x36FUomFi")
        #expect(WordInput.oldCodeKey("\u{FF11}\u{0662}\u{06F3}") == "123")
    }
}
