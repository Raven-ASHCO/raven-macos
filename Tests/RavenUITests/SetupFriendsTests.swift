import Foundation
import Testing
@testable import RavenUI

/// An engine that fails the named operations once each, then answers as the mock does.
final class FailingOnce: RavenEngine, @unchecked Sendable {
    let inner: MockRaven
    private var failing: Set<String>

    init(_ inner: MockRaven, failing: Set<String>) {
        self.inner = inner
        self.failing = failing
    }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        if failing.remove(op) != nil {
            throw RavenError(code: ErrorCode.internalError, message: tr(.errorInternal), detail: "\(op) failed once")
        }
        return try await inner.call(op: op, args: args)
    }
}

/// An engine whose erase works (as with the privacy pack): Raven's data goes and the profile is new
/// again, as on a computer where Raven was never set up.
final class ErasableMock: RavenEngine, @unchecked Sendable {
    private let clock: MockClock
    private var inner: MockRaven

    init(clock: MockClock) {
        self.clock = clock
        self.inner = MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0)
    }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        if op == "privacy.erase" {
            inner = MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0)
            return [:]
        }
        return try await inner.call(op: op, args: args)
    }
}

/// An engine that notes what each `card.make` asked for (`include_address`, nil when not sent).
final class CardAsks: RavenEngine, @unchecked Sendable {
    let inner: MockRaven
    private(set) var includeAddress: [Bool?] = []

    init(_ inner: MockRaven) { self.inner = inner }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        if op == "card.make" { includeAddress.append(args["include_address"]?.bool) }
        return try await inner.call(op: op, args: args)
    }
}

/// Welcome and setup, your identity, adding and checking friends, the friends list.
@MainActor
@Suite struct SetupFriendsTests {
    func readyModel() async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    // MARK: Setup

    /// The background program failed to start after the identity was made: Try again on the same
    /// step went on to make a second identity, which the engine refuses, so setup could never finish.
    @Test func setupTriesAgainWithoutASecondIdentity() async {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0)
        let model = AppModel(engine: FailingOnce(mock, failing: ["node.start"]), now: { clock.now })
        await model.bootstrap()
        model.beginSetup()
        model.submitName()
        await model.chooseReceive(true)
        #expect(model.setupStep == .receive)
        #expect(model.actionError != nil)
        await model.chooseReceive(true)
        #expect(model.setupStep == .words)
        #expect(model.actionError == nil, "the error of the first try is gone")
        #expect(model.identity?.words.count == 10)
        #expect(model.node?.running == true)
    }

    /// Erase, then set up again: the new profile needs an identity of its own. Setup still
    /// remembered the erased one, skipped `identity.create` and could never finish.
    @Test func setupAfterAnEraseMakesANewIdentity() async {
        let clock = MockClock(fixed: testStart)
        let model = AppModel(engine: ErasableMock(clock: clock), now: { clock.now })
        await model.bootstrap()
        model.beginSetup()
        model.submitName()
        await model.chooseReceive(true)
        await model.finishSetup()
        #expect(model.phase == .ready)
        #expect(await model.erase() == nil)
        #expect(model.phase == .welcome)
        model.beginSetup()
        model.submitName()
        await model.chooseReceive(true)
        #expect(model.actionError == nil)
        #expect(model.setupStep == .words)
        #expect(model.identity?.words.count == 10)
    }

    // MARK: Add a friend

    /// Add a friend has no switch for the network address any more: the card it shows holds your
    /// key and your Tor address only, also while Raven receives on the network and the engine would
    /// put the address in if asked.
    @Test func addAFriendShowsACardWithoutTheNetworkAddress() async throws {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let asks = CardAsks(mock)
        let model = AppModel(engine: asks, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        let would = try await mock.call(op: "card.make", args: ["include_address": true])
        #expect(would["address_included"]?.string != nil, "the engine has an address it could put in")

        let state = AddFriendState()
        await state.loadCard(model)
        let card = try #require(state.card)
        #expect(card.addressIncluded == nil && card.addressMissing == nil)
        #expect(!card.card.contains("lan=") && !card.invite.contains("@"))
        #expect(!card.card.contains(model.node?.address ?? "?"))
        #expect(card.card.range(of: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#, options: .regularExpression) == nil)
        #expect(asks.includeAddress == [false], "card.make is asked with include_address false")
    }

    /// The Mac texts of this area are plain English: no apostrophes, hyphens or dashes, and never an
    /// address (the shared texts follow raven-core's file and are checked there).
    @Test func addAFriendTextsFollowTheTextRules() {
        let keys = Str.allCases.filter { $0.rawValue.hasPrefix("mac.add.") || $0.rawValue.hasPrefix("mac.check.")
            || $0.rawValue.hasPrefix("mac.friends.") || $0.rawValue.hasPrefix("mac.setup.") }
        #expect(!keys.isEmpty)
        let ipv4 = #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#
        for key in keys {
            let text = tr(key, ["n": "1", "name": "Book shop"])
            #expect(!text.contains("'") && !text.contains("\u{2019}"), "\(key.rawValue): \(text)")
            #expect(text.rangeOfCharacter(from: CharacterSet(charactersIn: "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}")) == nil,
                    "\(key.rawValue): \(text)")
            #expect(text.range(of: ipv4, options: .regularExpression) == nil, "\(key.rawValue): \(text)")
        }
    }

    // MARK: Friends list

    /// A search hid the friends it did not find, but every group stayed: "zebra" still listed the
    /// book club, under an empty Friends heading.
    @Test func aSearchFindsGroupsByNameToo() async {
        let (model, _) = await readyModel()
        #expect(!model.groups.isEmpty)
        model.searchText = "zebra"
        #expect(model.filteredContacts.isEmpty)
        #expect(model.filteredGroups.isEmpty)
        model.searchText = " book "
        #expect(model.filteredGroups.map(\.name) == ["Book club"])
        model.searchText = ""
        #expect(model.filteredGroups.count == model.groups.count)
    }

    // MARK: Check words

    /// Pasting the words with one that is not a Raven word kept that word but lost every word after
    /// it: "anchor basket zzzz candle eagle" left only "zzzz eagle" in the field.
    @Test func aPasteKeepsEveryWordAfterOneRavenDoesNotKnow() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.aliAddress)
        state.field = "anchor basket zzzz candle eagle"
        await state.fieldChanged(model)
        #expect(state.typed == ["anchor", "basket"])
        #expect(state.field == "zzzz candle eagle")
        #expect(state.note == .notAWord)
    }
}
