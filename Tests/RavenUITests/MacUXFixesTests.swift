import Foundation
import Testing
@testable import RavenUI

/// The fixes from the macOS app review (0.1.1): one version everywhere, Check that stays off until the
/// words change, a confirmed Remove from group, no text that needs a terminal, a failure screen with a
/// way out, the card without an address, the network menu, the smallest window, and the Mac texts.
@MainActor
@Suite struct MacUXFixesTests {
    func readyModel(start: MockRaven.Start = .ready, engine: ((MockRaven) -> RavenEngine)? = nil) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: start, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: engine?(mock) ?? mock, now: { clock.now })
        await model.bootstrap()
        if model.phase == .ready { await model.pollNow() }
        return (model, mock)
    }

    func sources(_ folder: String) throws -> [(name: String, text: String)] {
        let root = packageRoot.appendingPathComponent(folder)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    // MARK: 3. One version

    /// The Network page and the Network sheet said the engine's "Version 0.1.0" while Settings said the
    /// app's 0.1.1: every screen shows the app's own version now, through one property.
    @Test func everyScreenShowsTheAppsOwnVersion() async throws {
        let (model, _) = await readyModel()
        #expect(model.appInfo?.version == "0.1.0")            // the engine's (MockRaven)
        model.bundleVersion = "0.1.1"
        #expect(model.shownVersion == "0.1.1")
        #expect(Display.versionLine(model.shownVersion) == "Raven · Version 0.1.1")
        model.bundleVersion = nil                             // `swift run`: no bundle, the engine's
        #expect(model.shownVersion == "0.1.0")
        #expect(Display.versionLine(nil) == nil)
        for file in try sources("Sources/RavenUI/Views") {
            #expect(!file.text.contains("appInfo?.version"), "\(file.name) reads the engine's version by itself")
        }
    }

    // MARK: 4. Check words

    /// Screen 17: after a mismatch Check stayed on, and pressing it again with the same words counted
    /// another try (three presses left only Later). Check is off until the words change, and an
    /// unchanged retry is never sent or counted.
    @Test func checkStaysOffUntilTheWordsChange() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.renaAddress, typed: MockRaven.minaWords)
        #expect(state.canCheck)
        await state.check(model)
        #expect(state.result == .mismatch && state.mismatches == 1)
        #expect(!state.canCheck)
        await state.check(model)                               // the same words: nothing is sent
        #expect(state.mismatches == 1 && !state.stopped)
        // A word taken out: no answer shown for 9 words, and no Check.
        state.remove(at: 9)
        #expect(state.result == nil && !state.canCheck)
        // Other words: Check comes back, and that try counts.
        state.typeAgain()
        state.field = MockRaven.aliWords.joined(separator: " ") + " "
        await state.fieldChanged(model)
        #expect(state.complete && state.canCheck)
        await state.check(model)
        #expect(state.result == .mismatch && state.mismatches == 2)
        // Back to words already checked: their answer again, Check stays off, nothing counted.
        state.typeAgain()
        #expect(state.result == nil && !state.canCheck)
        state.field = MockRaven.minaWords.joined(separator: " ") + " "
        await state.fieldChanged(model)
        #expect(state.typed == MockRaven.minaWords)
        #expect(state.result == .mismatch && !state.canCheck && state.mismatches == 2)
    }

    /// The old code the same way: the same code (spaces and dashes don't make it another) is not
    /// checked twice; a changed one is.
    @Test func anUnchangedOldCodeIsNotCheckedTwice() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.renaAddress, mode: .oldCode)
        state.oldCode = "Tq7m-29Xa-hKe5"
        await state.check(model)
        #expect(state.result == .mismatch && state.mismatches == 1 && !state.canCheck)
        await state.check(model)
        #expect(state.mismatches == 1)
        state.oldCode = "tq7m 29xa hke5"                       // another code (letter case matters)
        state.oldCodeChanged()
        #expect(state.result == nil && state.canCheck)
        state.oldCode = " Tq7m 29Xa hKe5 "                     // the first one again
        state.oldCodeChanged()
        #expect(state.result == .mismatch && !state.canCheck)
        state.oldCode = MockRaven.renaOldCode
        state.oldCodeChanged()
        #expect(state.canCheck)
        await state.check(model)
        #expect(state.result == .match && state.mismatches == 1)
    }

    // MARK: 5. Remove from group

    /// Screen 49: "Remove from group" removed at once, though a member who isn't your friend can't be
    /// added back. Remove asks first and says so; only the confirmation removes.
    @Test func removingAMemberAsksFirst() async throws {
        let (model, _) = await readyModel()
        let id = MockRaven.bookClubID
        let before = try #require(model.groupMembers[id])
        #expect(before.contains { $0.address == MockRaven.samAddress && !$0.friend })
        model.askRemoveGroupMember(id, member: MockRaven.samAddress)
        let ask = try #require(model.groupRemoval)
        #expect(model.groupMembers[id] == before)              // nothing removed yet
        let texts = Display.groupRemoval(ask, members: before, group: model.groups.first { $0.id == id })
        #expect(texts.title == "Remove Sam from Book club?")
        #expect(texts.body.contains("isn't your friend") && texts.body.contains("can't add"))
        model.cancelGroupRemoval()
        #expect(model.groupRemoval == nil && model.groupMembers[id] == before)
        // A friend can be added back, and the text says that instead.
        model.askRemoveGroupMember(id, member: MockRaven.aliAddress)
        let friend = Display.groupRemoval(try #require(model.groupRemoval), members: before, group: nil)
        #expect(!friend.body.contains("can't add"))
        model.askRemoveGroupMember(id, member: MockRaven.samAddress)
        let error = await model.confirmGroupRemoval()
        #expect(error == nil && model.groupRemoval == nil)
        #expect(model.groupMembers[id]?.contains { $0.address == MockRaven.samAddress } == false)
        #expect(model.groupMembers[id]?.contains { $0.address == MockRaven.aliAddress } == true)
    }

    // MARK: 6. No terminal

    /// A sentence that sends you to a terminal: it says "in a terminal" (or "the terminal"), or asks
    /// you to run or use a `raven`/`ash` command (in lower case: "with Raven" is not a command).
    static func namesATerminalStep(_ text: String) -> Bool {
        let patterns = [#"\b(?i:in|from|use) (?i:a|the) (?i:terminal)\b"#,
                        #"\b(?i:run|use|with):?\s+`?(raven|ash) [a-z]"#,
                        #"`(raven|ash) [a-z]"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// The DMG installs no `raven` command, so no text tells you to type one. raven-core took those
    /// steps out of the shared texts and of the engine's messages (b409d94), so the app shows both as
    /// they are: the app's own filter (AppText) is gone, and nothing it shows needs one.
    @Test func noTextSendsYouToATerminal() async throws {
        // The check still catches what the old texts said, and lets "the terminal app" be.
        #expect(Self.namesATerminalStep("Lock while running isn't in this version of Raven yet. In a terminal, raven lock stops Raven instead."))
        #expect(Self.namesATerminalStep("To mark a notice as resolved, use raven security resolve in a terminal."))
        #expect(Self.namesATerminalStep("Install updates with `raven update install` in a terminal."))
        #expect(Self.namesATerminalStep("Raven couldn't unlock. Run `raven unlock` in a terminal."))
        #expect(!Self.namesATerminalStep("Every way Raven reaches your friends. The terminal app shows the same."))
        #expect(!Self.namesATerminalStep("Something went wrong inside Raven. Try again; if it keeps happening, open Details."))

        // Every text the app uses, shared (strings.en.json) and its own (strings.macos.json).
        for key in Str.allCases {
            #expect(!Self.namesATerminalStep(tr(key)), "\(key.rawValue): \(tr(key))")
        }

        // Lock (screen 43), Security (37) and Updates (44), as shown.
        let locks = [LockState(available: false, supported: false, locked: false),
                     LockState(available: true, supported: false, locked: false),
                     LockState(available: true, supported: true, locked: false, hasPassphrase: false),
                     LockState(available: true, supported: true, locked: false, hasPassphrase: true)]
        var shown = locks.map { Display.lockNote($0) } + [Display.lockNote(nil), Display.passphraseLine]
        shown += ["live", "unsealed", "off"].map { Display.securityKept($0) }
        shown.append(Display.securityResolveLine)
        for text in shown {
            #expect(!text.lowercased().contains("terminal"), "\(text)")
            #expect(text.range(of: #"\braven [a-z]"#, options: .regularExpression) == nil, "\(text)")
        }
        #expect(Display.lockNote(locks[0]) == "Lock while running isn't in this version of Raven yet.")
        #expect(Display.lockNote(locks[1]) == "Raven's background program can't lock now: it isn't running, or it is an older version.")
        #expect(Display.securityKept("unsealed") == "This profile isn't encrypted, so Raven keeps no security notices for it.")
        #expect(Display.passphraseLine.hasSuffix(tr(.lockPassphraseNotInApp)))
        #expect(Display.securityResolveLine == "Marking a notice as resolved isn't in this app yet.")
        #expect(Display.updatesInstallDetail("The app shows what is ready; it doesn't install updates yet.")
                == "The app shows what is ready; it doesn't install updates yet.")
        #expect(Display.updatesInstallDetail(" ") == nil && Display.updatesInstallDetail(nil) == nil)

        // An engine error is shown as the engine wrote it: the message names no command, and the
        // CLI's command stays in Details (engine.rs, not_in_the_app).
        let failure = RavenEnvelope.failure(RavenError(
            code: ErrorCode.notAvailableYet,
            message: "This isn't in the Raven app yet. Nothing was changed.",
            detail: "privacy.encrypt: not in the desktop app yet (raven privacy seal-now)"))
        do {
            _ = try RavenEnvelope.parseResponse(failure)
            Issue.record("expected NOT_AVAILABLE_YET")
        } catch let error as RavenError {
            #expect(error.message == "This isn't in the Raven app yet. Nothing was changed.")
            #expect(error.detail == "privacy.encrypt: not in the desktop app yet (raven privacy seal-now)")
        }

        // MockRaven speaks as the engine does: no command in what the demo shows.
        let mock = MockRaven(start: .ready, demo: false, clock: MockClock(fixed: testStart), identityDelay: 0)
        let updates = try await mock.call(op: "updates.status", args: [:])
        #expect(!Self.namesATerminalStep(updates["install_text"]?.string ?? "terminal"))

        // The Updates chip said "In the terminal" and the passphrase row named a command: neither
        // comes back.
        for file in try sources("Sources/RavenUI/Views") {
            #expect(!file.text.contains("settingsUpdatesTerminal"), "\(file.name)")
            #expect(!file.text.contains("tr(.lockPassphraseTerminal)"), "\(file.name)")
        }
        #expect(!FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("Sources/RavenUI/Support/AppText.swift").path))
    }

    // MARK: 7. Failure screen

    /// Screen 25: the failure screen had only red text and Details. It has Try Again, which runs the
    /// start again, and Quit.
    @Test func theFailureScreenCanTryAgain() async {
        let (model, _) = await readyModel(engine: { FailingFirst(inner: $0, failures: 1) })
        guard case .failed(let error) = model.phase else {
            Issue.record("expected the failure screen, got \(model.phase)")
            return
        }
        #expect(error.code == ErrorCode.internalError)
        await model.retryStart()
        #expect(model.phase == .ready)
        #expect(model.contacts.map(\.name) == ["Ali", "Mina", "Rena"])
        #expect(tr(.macFailureTryAgain) == "Try Again")
        #expect(tr(.quitQuit) == "Quit")
        // Still missing: the same screen again, nothing else changes.
        let missing = AppModel(engine: MissingEngine())
        await missing.bootstrap()
        await missing.retryStart()
        guard case .failed = missing.phase else {
            Issue.record("a missing engine stays on the failure screen")
            return
        }
    }

    // MARK: 8. Card, menu, smallest window

    /// Add a friend showed the switch with "(–:7420)" while Raven wasn't receiving: the engine's
    /// `address_missing` says why there is no address, and the sheet says it.
    @Test func aCardWithoutAnAddressSaysWhy() async throws {
        let (model, mock) = await readyModel()
        _ = try await mock.call(op: "node.stop", args: [:])
        let card = try await model.makeCard(includeAddress: true)
        #expect(card.addressIncluded == nil && card.addressMissing == "not_receiving")
        #expect(!card.card.contains("lan="))
        let label = Display.includeAddressLabel(card: card, node: nil)
        #expect(!label.contains("–") && !label.contains("7420"))
        #expect(Display.noAddressReason(card) == tr(.macAddNoAddressNotReceiving))
        for why in ["this_computer_only", "no_network", "something_new"] {
            var other = card
            other.addressMissing = why
            #expect(Display.noAddressReason(other)?.isEmpty == false)
        }
        _ = try await mock.call(op: "node.start", args: [:])
        let with = try await model.makeCard(includeAddress: true)
        #expect(with.addressIncluded != nil && with.addressMissing == nil && Display.noAddressReason(with) == nil)
        #expect(Display.includeAddressLabel(card: with, node: nil).contains(with.addressIncluded ?? "?"))
    }

    /// ⌥⌘1–4 looked enabled on the Welcome and Locked screens and did nothing: they follow the screen.
    @Test func theNetworkMenuWaitsForTheMainScreen() async throws {
        let (welcome, _) = await readyModel(start: .new)
        #expect(welcome.phase == .welcome && !welcome.pagesAvailable)
        let (locked, _) = await readyModel(start: .locked)
        #expect(locked.phase == .locked && !locked.pagesAvailable)
        let (ready, _) = await readyModel()
        #expect(ready.pagesAvailable)
        let app = try String(contentsOf: packageRoot.appendingPathComponent("Sources/Raven/RavenApp.swift"), encoding: .utf8)
        let menu = try #require(app.range(of: "CommandMenu(tr(.networkTitle))"))
        let body = app[menu.lowerBound...].prefix(1200)
        #expect(body.components(separatedBy: ".disabled(!model.pagesAvailable)").count - 1 == 4)
    }

    /// Screen 41: in the smallest window the sidebar kept its full width and the chat truncated
    /// ("Ve…", "Deliv…"). The sidebar gives way down to its minimum first.
    @Test func theSidebarGivesWayInTheSmallestWindow() {
        let layout = Theme.shared.layout
        #expect(Display.sidebarWidth(window: layout.minWidth) == layout.sidebarMinWidth)
        #expect(Display.sidebarWidth(window: 1200) == layout.sidebarWidth)
        #expect(Display.sidebarWidth(window: layout.minWidth + 20) == layout.sidebarMinWidth + 20)
        #expect(Display.detailMinWidth + layout.sidebarMinWidth <= layout.minWidth)
        #expect(Display.detailMinWidth >= 320)
    }

    // MARK: Mac texts

    /// The texts this app needs that the shared strings.en.json doesn't have yet live in
    /// strings.macos.json: they only add keys (mac.*), never replace a shared one.
    @Test func macTextsOnlyAddToTheSharedTable() throws {
        let shared = try Strings(json: Data(contentsOf: designRoot.appendingPathComponent("strings.en.json")))
        let mac = try Strings(json: Data(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Resources/strings.macos.json")))
        #expect(!mac.texts.isEmpty)
        for key in mac.texts.keys {
            #expect(key.hasPrefix("mac."), "\(key)")
            #expect(!shared.has(key), "\(key) is in strings.en.json now: remove it from strings.macos.json")
            #expect(Str(rawValue: key) != nil, "\(key) is not used")
        }
        #expect(Strings.shared.text(.appName) == "Raven")
        #expect(Strings.shared.has("mac.failure.tryAgain"))
    }

    // MARK: Polish

    /// Screen 10: the chat header said "Not verified" twice; screen 45: "Your fingerprint" over
    /// "Fingerprint …"; screen 31: "On. Works without the internet." beside an "On" chip.
    @Test func nothingIsSaidTwice() async throws {
        let (model, _) = await readyModel()
        let rena = try #require(model.contact(MockRaven.renaAddress))
        #expect(!rena.verified)
        #expect(Display.headerStatus(rena, now: testStart).text != tr(.homeNotVerified))
        #expect(Display.wayReason("On. Works without the internet.", state: .on) == "Works without the internet.")
        #expect(Display.wayReason("Not in this version of Raven yet.", state: .preview) == "Not in this version of Raven yet.")
        #expect(Display.wayReason("On.", state: .on) == nil)
        #expect(tr(.macTrayQuitKeepReceiving) == "Quit Raven (keeps receiving)")
        #expect(!tr(.macLockPlainBody).isEmpty)
    }
}

/// An engine whose first `profile.state` calls fail (a start that didn't work), then answers as `inner`.
final class FailingFirst: RavenEngine, @unchecked Sendable {
    let inner: RavenEngine
    private var failures: Int
    private let lock = NSLock()

    init(inner: RavenEngine, failures: Int) {
        self.inner = inner
        self.failures = failures
    }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        if op == "profile.state" {
            let fail: Bool = lock.withLock {
                guard failures > 0 else { return false }
                failures -= 1
                return true
            }
            if fail { throw RavenError.internalError("profile.state: the first start failed (test)") }
        }
        return try await inner.call(op: op, args: args)
    }
}
