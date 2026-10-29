import Foundation
import SwiftUI
import Testing
@testable import RavenUI

/// The Calm design's state and decisions: the status words, the motion triggers (lift-out, check
/// pop), the app's own preferences, Settings in the main window, and groups (API.md "Groups").
@MainActor
@Suite struct CalmTests {
    func readyModel(_ mock: MockRaven) async -> AppModel {
        let model = AppModel(engine: mock, now: { mock.clock.now })
        await model.bootstrap()
        await model.pollNow()
        return model
    }

    /// Advances the mock's clock in steps, polling after each (as the app does).
    func advance(_ model: AppModel, _ mock: MockRaven, seconds: Double) async {
        var left = seconds
        while left > 0 {
            mock.clock.advance(min(0.5, left))
            left -= 0.5
            model.tick()
            await model.pollNow()
        }
    }

    // MARK: Status words and icons

    @Test func statusDropsTheGlyphsTheIconShows() {
        func message(_ state: MessageState, until: Int64? = nil) -> Message {
            Message(id: "x", address: MockRaven.aliAddress, direction: .outgoing, text: "hi", atMs: testStart.ms,
                    state: state, untilMs: until)
        }
        let delivered = Display.status(message(.delivered), name: "Ali", now: testStart)
        #expect(delivered.text == tr(.tickDelivered) && delivered.icon == .delivered && delivered.tone == .success)
        let sent = Display.status(message(.sent), name: "Ali", now: testStart)
        #expect(sent.text == tr(.tickSent) && sent.icon == .sent && sent.tone == .secondary)
        let waiting = Display.status(message(.waiting), name: "Ali", now: testStart)
        #expect(waiting.text == tr(.tickWaitingNoTime, ["name": "Ali"]) && waiting.icon == .waiting && waiting.tone == .warning)
        #expect(Display.status(message(.failed), name: "Ali", now: testStart).icon == .problem)
        #expect(Display.status(message(.sending), name: "Ali", now: testStart).icon == .sending)
    }

    @Test func theSidebarLineDoesNotRepeatNotVerified() {
        let rena = Contact(address: MockRaven.renaAddress, name: "Rena", shortAddress: "rvn1…", verified: false,
                           presence: .none, lastContactMs: nil)
        #expect(Display.statusLine(rena, now: testStart).text == tr(.homeNotVerified))
        #expect(Display.statusLine(rena, now: testStart, verifiedShown: true).text == tr(.homeNoRecent))
    }

    // MARK: Motion triggers

    /// Your bubble lifts out of the composer once (only with motion on); the receipt pops the check.
    @Test func liftOutAndCheckPopFollowRealEvents() async throws {
        let mock = readyMock(demo: false)
        let model = await readyModel(mock)
        model.select(MockRaven.aliAddress)
        await model.send("Hello", to: MockRaven.aliAddress)
        let sent = try #require(model.messages[MockRaven.aliAddress]?.last)
        #expect(model.liftIDs.contains(sent.id))
        model.liftDone(sent.id)
        #expect(!model.liftIDs.contains(sent.id))
        #expect(model.deliveredPops[sent.id] == nil)
        await advance(model, mock, seconds: 3)
        #expect(model.message(sent.id)?.state == .delivered)
        #expect(model.deliveredPops[sent.id] == 1)

        // Reduced motion: nothing lifts (texts still change).
        model.settings.reducedMotion = true
        await model.send("Again", to: MockRaven.aliAddress)
        let second = try #require(model.messages[MockRaven.aliAddress]?.last)
        #expect(second.text == "Again" && !model.liftIDs.contains(second.id))
    }

    // MARK: Preferences and Settings

    @Test func themeAndTechnicalDetailsAreKeptByTheApp() async throws {
        let suite = "calm-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = readyMock(demo: false)
        let model = AppModel(engine: mock, preferences: defaults)
        #expect(model.themeChoice == .system && model.themeChoice.scheme == nil && !model.showTechnical)
        model.themeChoice = .dark
        model.showTechnical = true
        let again = AppModel(engine: mock, preferences: defaults)
        #expect(again.themeChoice == .dark && again.themeChoice.scheme == .dark && again.showTechnical)
        // Tests and snapshots keep nothing.
        let none = AppModel(engine: mock)
        none.themeChoice = .light
        #expect(AppModel(engine: mock).themeChoice == .system)
    }

    @Test func settingsOpenInTheMainWindow() async {
        let mock = readyMock(demo: false)
        let model = await readyModel(mock)
        model.openSettings(.lock)
        #expect(model.page == .settings && model.settingsSection == .lock)
        #expect(model.windowTitle == tr(.settingsTitle))
        model.openSettings()
        #expect(model.settingsSection == .lock)
        #expect(AppModel.SettingsSection.allCases.count == 7)
        #expect(AppModel.SettingsSection.allCases.map { SettingsView.info($0).title }
            == [tr(.settingsGeneral), tr(.settingsAppearance), tr(.settingsPrivacy), tr(.lockSection),
                tr(.settingsNetwork), tr(.updatesTitle), tr(.netAbout)])
    }

    // MARK: Groups

    @Test func aGroupMessageEventKeepsTheBatchReadable() throws {
        let json = """
        {"seq": 7, "events": [
          {"seq": 6, "kind": "group_message", "at_ms": 1, "group": "g1",
           "message": {"id": "m9", "group": "g1", "from_address": "rvn1q", "from_name": "Ali", "mine": false,
                       "text": "hi", "at_ms": 1, "delivered": 0, "total": 0}},
          {"seq": 7, "kind": "group_changed", "at_ms": 2, "group": "g1"},
          {"seq": 8, "kind": "incoming", "at_ms": 3, "message": {"id": "z", "bad": true}}
        ]}
        """
        let batch = try JSONValue.parse(json).decode(EventBatch.self)
        #expect(batch.events.count == 3)
        #expect(batch.events[0].kind == .groupMessage && batch.events[0].groupMessage?.text == "hi"
                && batch.events[0].message == nil && batch.events[0].group == "g1")
        #expect(batch.events[1].kind == .groupChanged && batch.events[1].group == "g1")
        // A message that fits no shape is dropped, not the whole poll.
        #expect(batch.events[2].kind == .incoming && batch.events[2].message == nil)
    }

    @Test func groupsLoadSendAndConfirm() async throws {
        let mock = readyMock(demo: false)
        let model = await readyModel(mock)
        #expect(model.groupsAvailable)
        let club = try #require(model.groups.first { $0.id == MockRaven.bookClubID })
        #expect(club.name == "Book club" && club.admin && club.members == 4)
        let members = try #require(model.groupMembers[club.id])
        #expect(members.contains { $0.address == MockRaven.samAddress && !$0.friend })
        #expect(members.contains { $0.me && $0.admin })
        let mine = try #require(model.groupMessages[club.id]?.last)
        #expect(Display.groupStatus(mine).text == "Delivered to 2 of 3")
        #expect(Display.groupStatus(mine).note == tr(.groupsNoteSent, ["n": "1"]))
        #expect(Display.receiptLine(mine.receipts![2]).text == tr(.tickSent) + " · " + tr(.groupsReceiptRelay))

        // Opening the group reads it; sending lifts the bubble and the receipts come in.
        #expect(club.unread == 1)
        model.selectGroup(club.id)
        #expect(model.page == .group && model.selectedGroup?.unread == 0)
        model.composerText = "See you Friday"
        await model.sendGroupComposer()
        let sent = try #require(model.groupMessages[club.id]?.last)
        #expect(sent.mine && sent.text == "See you Friday" && model.liftIDs.contains(sent.id) && model.composerText.isEmpty)
        #expect(Display.groupStatus(sent).text == "Delivered to 0 of 3")
        await advance(model, mock, seconds: 3)
        let after = try #require(model.groupMessages[club.id]?.first { $0.id == sent.id })
        // Ali is in touch: delivered. Mina waits (not reachable), Sam's copy goes through a member.
        #expect(after.receipts?.first { $0.address == MockRaven.aliAddress }?.state == "delivered")
        #expect(after.receipts?.first { $0.address == MockRaven.minaAddress }?.state == "sent")
        #expect((model.deliveredPops[sent.id] ?? 0) >= 1)
    }

    @Test func groupRulesComeFromTheEngine() async throws {
        let mock = readyMock(demo: false)
        let model = await readyModel(mock)
        // Only friends; a name is needed; 16 people at most, you included.
        #expect(await model.createGroup(name: "Trip", members: [MockRaven.samAddress])?.code == ErrorCode.notAContact)
        #expect(await model.createGroup(name: " ", members: [MockRaven.aliAddress])?.code == ErrorCode.groupBadName)
        #expect(await model.createGroup(name: "Trip", members: [MockRaven.aliAddress, MockRaven.renaAddress]) == nil)
        let trip = try #require(model.selectedGroup)
        #expect(trip.name == "Trip" && trip.admin && model.page == .group)
        #expect(model.groupMembers[trip.id]?.count == 3)
        // The admin can't leave.
        #expect(await model.leaveGroup(trip.id)?.code == ErrorCode.groupAdminCannotLeave)
        #expect(await model.removeGroupMember(trip.id, member: MockRaven.renaAddress) == nil)
        #expect(model.groupMembers[trip.id]?.count == 2)
        #expect(MockRavenLimits.groupMaxMembers == MockRaven.groupMaxMembers)
    }

    @Test func noGroupsInABuildWithout() async {
        let mock = readyMock(demo: false)
        mock.groupsOn = false
        let model = await readyModel(mock)
        #expect(!model.groupsAvailable && model.groups.isEmpty)
        #expect(await model.createGroup(name: "Trip", members: [MockRaven.aliAddress])?.code == ErrorCode.notAvailableYet)
    }

    @Test func membersLineCountsFriendsInTouch() {
        let g = RavenGroup(id: "g", name: "G", shortId: "g", admin: true, adminAddress: "a", adminName: "You", members: 3)
        let members = [GroupMember(address: "me", shortAddress: "", name: "You", friend: false, admin: true, me: true),
                       GroupMember(address: "a1", shortAddress: "", name: "A", friend: true),
                       GroupMember(address: "b1", shortAddress: "", name: "B", friend: false)]
        let contacts = [Contact(address: "a1", name: "A", shortAddress: "", verified: true, presence: .inTouch)]
        #expect(Display.groupMembersLine(g, members: members, contacts: contacts) == tr(.groupsMembersInTouch, ["n": "3", "m": "1"]))
        #expect(Display.groupMembersLine(g, members: members, contacts: []) == tr(.groupsMembers, ["n": "3"]))
    }
}
