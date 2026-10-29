import Foundation
import Testing
@testable import RavenUI

/// The model turns engine events into texts and motion triggers, and nothing else moves.
@MainActor
@Suite struct AppModelTests {
    func readyModel(reducedMotion: Bool = false) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        if reducedMotion { await model.updateSettings(["reduced_motion": true]) }
        await model.pollNow()
        return (model, mock)
    }

    /// One clock tick and one poll per second (the app polls more often; the events are the same).
    func advance(_ model: AppModel, _ mock: MockRaven, seconds: Int) async {
        for _ in 0..<seconds {
            mock.clock.advance(1)
            await step(model)
        }
    }

    func step(_ model: AppModel) async {
        model.tick()
        await model.pollNow()
    }

    @Test func bootstrapLoadsTheDemo() async {
        let (model, _) = await readyModel()
        #expect(model.phase == .ready)
        #expect(model.contacts.map(\.name) == ["Ali", "Mina", "Rena"])
        #expect(model.selectedAddress == MockRaven.aliAddress)
        #expect(model.messages[MockRaven.aliAddress]?.count == 2)
        #expect(model.lastPath[MockRaven.aliAddress] == "LAN direct")
    }

    @Test func heartbeatFollowsStatusEvents() async {
        let (model, mock) = await readyModel()
        let before = model.heartbeatPulse
        #expect(before >= 1)
        await advance(model, mock, seconds: 1)
        #expect(model.heartbeatPulse == before)       // no status check yet, no pulse
        await advance(model, mock, seconds: 1)
        #expect(model.heartbeatPulse == before + 1)   // the 2 s status check
        #expect(Display.heartbeat(node: model.node, lastOk: model.lastStatusOk, now: model.now).text == "your node: ok · now")
    }

    @Test func eventsDriveRouteMotionsForTheOpenChat() async {
        let (model, mock) = await readyModel()
        model.routeQueue = []
        await advance(model, mock, seconds: 2)        // Ali's message arrives at 1.2 s
        #expect(model.routeQueue.map(\.kind) == [.incoming])
        #expect(model.messages[MockRaven.aliAddress]?.last?.text == "Great. Can you bring the charger?")
        #expect(model.freshUntil.count == 1)
        #expect(model.toast?.text == "New message from Ali · LAN direct")
        model.routeQueue = []
        await advance(model, mock, seconds: 1)        // Rena writes while Ali is open: badge, no motion
        #expect(model.unread[MockRaven.renaAddress] == 1)
        #expect(model.routeQueue.isEmpty)
        await advance(model, mock, seconds: 2)        // retry at 4.0, demo send starts at 4.5
        #expect(model.retryPulses[MockRaven.minaAddress] == 1)
        #expect(model.routeQueue.map(\.kind) == [.out])
        #expect(model.messages[MockRaven.aliAddress]?.last?.state == .sending)
        #expect(!model.routeQueue.contains { $0.kind == .back })   // nothing comes back before the receipt
        mock.clock.advance(0.5)                       // state sent at 5.3
        await step(model)
        #expect(model.messages[MockRaven.aliAddress]?.last?.state == .sent)
        #expect(!model.routeQueue.contains { $0.kind == .back })
        mock.clock.advance(0.5)                       // receipt at 6.0
        await step(model)
        #expect(model.messages[MockRaven.aliAddress]?.last?.state == .delivered)
        #expect(model.routeQueue.last?.kind == .back)
        #expect(model.toast?.text.hasPrefix("Delivered to Ali via LAN direct in") == true)
        await advance(model, mock, seconds: 6)        // Mina returns at 10.5; her waiting message is delivered at 11.3
        #expect(model.contact(MockRaven.minaAddress)?.presence == .inTouch)
        #expect(model.contact(MockRaven.minaAddress)?.waiting == nil)
        #expect(model.presenceBlinks[MockRaven.minaAddress] == 1)
        #expect(model.toast?.text == "Mina is back · your waiting message was delivered")
    }

    @Test func reducedMotionUpdatesTextsButQueuesNoMotion() async {
        let (model, mock) = await readyModel(reducedMotion: true)
        #expect(model.motionOff)
        await advance(model, mock, seconds: 12)
        #expect(model.routeQueue.isEmpty)
        #expect(model.messages[MockRaven.aliAddress]?.last?.state == .delivered)
        #expect(model.toast?.text == "Mina is back · your waiting message was delivered")
    }

    @Test func idleWindowOnlyHearsTheHeartbeat() async {
        let (model, mock) = await readyModel()
        await advance(model, mock, seconds: 20)
        model.routeQueue = []
        let pulses = model.heartbeatPulse
        let retries = model.retryPulses
        let blinks = model.presenceBlinks
        await advance(model, mock, seconds: 10)
        #expect(model.routeQueue.isEmpty)
        #expect(model.retryPulses == retries && model.presenceBlinks == blinks)
        #expect(model.heartbeatPulse == pulses + 5)
        #expect(model.toast == nil)
        #expect(Display.quietTicker(node: model.node, friends: 3, wifi: true) == "Listening on your Wi-Fi · 3 friends · all quiet")
        #expect(Display.quietTicker(node: model.node, friends: 3, wifi: false) == "Listening on your network · 3 friends · all quiet")
    }

    @Test func toastExpiresWithTheClock() async {
        let (model, mock) = await readyModel()
        await advance(model, mock, seconds: 2)
        #expect(model.toast != nil)
        await advance(model, mock, seconds: 1)
        #expect(model.toast != nil)                    // Rena's message replaced it
        model.toast = AppModel.Toast(text: "x", tone: .accent, until: model.now.addingTimeInterval(2.6))
        mock.clock.advance(3)
        model.tick()
        #expect(model.toast?.text != "x")
    }

    @Test func sendingFromTheComposer() async {
        let (model, mock) = await readyModel()
        model.select(MockRaven.renaAddress)
        #expect(model.unread[MockRaven.renaAddress] == 0)
        model.composerText = "  hello Rena  "
        await model.sendComposer()
        #expect(model.composerText.isEmpty)
        #expect(model.messages[MockRaven.renaAddress]?.last?.text == "hello Rena")
        await advance(model, mock, seconds: 1)
        let line = Display.tick(model.messages[MockRaven.renaAddress]!.last!, name: "Rena", now: model.now)
        #expect(line.text.hasPrefix("Waiting for Rena"))
    }

    @Test func setupFlow() async {
        let clock = MockClock(fixed: testStart)
        let model = AppModel(engine: MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0), now: { clock.now })
        await model.bootstrap()
        #expect(model.phase == .welcome)
        model.beginSetup()
        model.setupName = "  Sam\u{202E} "
        model.submitName()
        #expect(model.setupStep == .receive)
        await model.chooseReceive(true)
        #expect(model.setupStep == .words)
        #expect(model.identity?.words.count == 10)
        #expect(model.settings.displayName == "Sam")
        #expect(model.node?.running == true)
        await model.finishSetup()
        #expect(model.phase == .ready)
    }

    @Test func checkWordsStateTypesAndChecks() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.aliAddress)
        state.field = "1. anchor 2. basket "
        await state.fieldChanged(model)
        #expect(state.typed == ["anchor", "basket"])
        #expect(state.field.isEmpty)
        state.field = "cand"
        await state.fieldChanged(model)
        #expect(state.hint == "candle")
        await state.submit(model)
        #expect(state.typed.last == "candle")
        state.field = "zzz"
        await state.fieldChanged(model)
        #expect(state.note == .notAWord)
        state.field = "\u{06A9}\u{062A}\u{0627}"                // not Latin letters
        await state.fieldChanged(model)
        #expect(state.note == .englishLetters)
        state.field = "ca"
        await state.submit(model)
        #expect(state.note == .tooShort(4))
        #expect(state.typed.count == 3)
        state.field = MockRaven.aliWords.dropFirst(3).joined(separator: " ") + " "
        await state.fieldChanged(model)
        #expect(state.complete)
        await state.check(model)
        #expect(state.result == .match)
    }

    @Test func quitFollowsTheSetting() async {
        let (model, _) = await readyModel()
        #expect(model.quitReply() == .terminateNow)    // "keep" (recommended) quits without asking
        await model.updateSettings(["when_quit": "ask"])
        #expect(model.quitReply() == .terminateLater)
        #expect(model.sheet == .quit)
    }

    @Test func engineMissingShowsOneNextStep() async {
        let model = AppModel(engine: MissingEngine())
        await model.bootstrap()
        guard case .failed(let error) = model.phase else {
            Issue.record("expected a failure screen")
            return
        }
        #expect(error.code == "NOT_INITIALIZED")
        #expect(error.message == "Part of Raven is missing from this installation. Install Raven again, then open it.")
        #expect(error.detail.contains("raven-client is not linked"))
    }

    // MARK: Old code, three mismatches, privacy, polling, threading

    @Test func oldCodeVerifiesLikeTheWords() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.renaAddress)
        #expect(!state.canCheck)
        state.switchMode(.oldCode)
        #expect(state.mode == .oldCode && !state.canCheck)
        state.oldCode = "Tq7m-29Xa-hKe5"
        #expect(state.canCheck)
        await state.check(model)
        #expect(state.result == .mismatch && state.mismatches == 1)
        state.oldCodeChanged()
        #expect(state.result == nil)
        state.oldCode = " tq7m 29xa hke4 "                          // wrong case: still a mismatch
        await state.check(model)
        #expect(state.result == .mismatch)
        #expect(model.contact(MockRaven.renaAddress)?.verified == false)
        state.oldCode = "Tq7m 29Xa hKe4"
        await state.check(model)
        #expect(state.result == .match)
        #expect(model.contact(MockRaven.renaAddress)?.verified == true)
        state.switchMode(.words)                                       // a match stays
        #expect(state.mode == .oldCode && !state.canCheck)
    }

    @Test func threeMismatchesWithdrawCheck() async {
        let (model, _) = await readyModel()
        let state = CheckWordsState(address: MockRaven.renaAddress, typed: MockRaven.minaWords)
        for n in 1...2 {
            await state.check(model)
            #expect(state.result == .mismatch && state.mismatches == n && !state.stopped)
        }
        state.switchMode(.oldCode)
        state.oldCode = "nope"
        await state.check(model)
        #expect(state.mismatches == 3 && state.stopped && !state.canCheck)
        state.oldCode = MockRaven.renaOldCode
        await state.check(model)                                       // withdrawn: nothing is sent
        #expect(state.result == .mismatch)
        #expect(model.contact(MockRaven.renaAddress)?.verified == false)
    }

    @Test func privacyActionsWaitForThePrivacyPack() async {
        let (model, _) = await readyModel()
        #expect(model.privacy == PrivacyState(available: false, encrypted: false, locked: false))
        await model.lock()                                             // not offered: nothing happens
        #expect(model.phase == .ready && model.actionError == nil)
        let error = await model.erase()
        #expect(error?.code == "NOT_AVAILABLE_YET")
        #expect(error?.message == "This isn't in this release of Raven yet. Nothing was changed.")
        #expect(model.phase == .ready && model.contacts.count == 3)
        #expect(EraseSheet.confirms(" Erase ") && !EraseSheet.confirms("erase it"))
    }

    @Test func pollingFollowsTheWindow() async {
        let (model, _) = await readyModel()
        model.windowVisible = true
        #expect(model.pollInterval == 0.5)
        model.windowVisible = false
        #expect(model.pollInterval == 5)
    }

    /// No engine call runs on the main thread, although the model lives there.
    @Test func engineCallsRunOffTheMainThread() async {
        MainActor.assertIsolated()                                     // the test runs where the UI runs
        let (model, mock) = await readyModel()
        model.composerText = "hello"
        await model.sendComposer()
        await advance(model, mock, seconds: 3)
        _ = await model.wordHint("tur")
        #expect(mock.callsOnMainThread == 0)
    }
}

@Suite struct DisplayTests {
    let now = testStart

    func message(_ state: MessageState, until: Date? = nil) -> Message {
        Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: now.ms, state: state, untilMs: until?.ms)
    }

    @Test func tickTexts() {
        #expect(Display.tick(message(.sending), name: "Ali", now: now).text == "Sending…")
        #expect(Display.tick(message(.sent), name: "Ali", now: now).text == "✓ Sent, not confirmed yet")
        #expect(Display.tick(message(.delivered), name: "Ali", now: now).text == "✓✓ Delivered")
        #expect(Display.tick(message(.timeRanOut), name: "Ali", now: now).text == "Time ran out")
        #expect(Display.tick(message(.notSentMeetFirst), name: "Ali", now: now).text
                == "Not sent: Ali isn't reachable. A first message needs you both online.")
        #expect(Display.tick(message(.failed), name: "Ali", now: now).text == "Not delivered")
        let soon = Display.tick(message(.waiting, until: now.addingTimeInterval(40 * 60)), name: "Mina", now: now)
        #expect(soon.text == "Waiting for Mina · about 40 min left")
        let later = Display.tick(message(.waiting, until: now.addingTimeInterval(22 * 3600)), name: "Mina", now: now)
        #expect(later.text == "Waiting for Mina · until " + TimeText.clock(now.addingTimeInterval(22 * 3600)))
    }

    @Test func statusLines() {
        var c = Contact(address: "a", name: "Ali", shortAddress: "a", verified: true, presence: .inTouch,
                        lastContactMs: now.addingTimeInterval(-300).ms)
        #expect(Display.statusLine(c, now: now).text == "In touch 5 min ago")
        c.verified = false
        #expect(Display.statusLine(c, now: now).text == "Not verified")
        c.waiting = Waiting(count: 2, untilMs: now.ms)
        #expect(Display.statusLine(c, now: now).text == "2 waiting · until " + TimeText.clock(now))
        c = Contact(address: "a", name: "R", shortAddress: "a", verified: true, presence: .noAddress)
        #expect(Display.statusLine(c, now: now).text == "No address to reach them")
        #expect(Display.menuLine(c, unread: 1, now: now) == "1 new from R")
    }

    @Test func heartbeatGoesStale() {
        let node = NodeStatus(running: true, startedByApp: true, receive: true, lastOkMs: now.ms, build: "dev",
                              carriers: Carriers(lan: "on", internet: "preview", p2p: "preview", custody: "preview"))
        #expect(Display.heartbeat(node: node, lastOk: now, now: now.addingTimeInterval(4)).text == "your node: ok · 4 s")
        #expect(Display.heartbeat(node: node, lastOk: now, now: now.addingTimeInterval(60)).ok == false)
        #expect(Display.heartbeat(node: nil, lastOk: now, now: now).text == "Raven's background program isn't responding")
    }
}
