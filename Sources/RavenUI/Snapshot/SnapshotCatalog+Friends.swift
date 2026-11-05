#if DEBUG || RAVEN_MOCK
import SwiftUI

/// Setup, your identity and friends: the states the main list above does not show (your words and
/// card, rename, the third step of Add a friend, a paste that is not a card, a name you already use,
/// no friends yet, long names, many friends, a search).
extension SnapshotCatalog {
    /// A card for a friend who is not in the demo yet (no address, so no network address shows).
    static let newFriendCard = "raven-card/1 address=rvn1qz8m4c7hj2kd9wl0a6vrsx5qtyn3pfe8gu7c2hla pub_hex=00 fingerprint=Ab3d-Ef56-Gh78"

    /// Nicknames, never a person's name: the long one fills the 64 characters a name may have.
    static let longName = "Neighbour from the third floor with the very loud green bicycle"
    static let longNotVerified = "Climbing partner from the Tuesday evening group at the old hall"
    static let manyNames = ["Bakery on the corner", "Book shop", "Choir", "Cousin", "Garden club", "Landlord",
                            "Old school friend", "Piano teacher", "Tea house", "Uncle", "Workshop"]

    static func friendsShots() async -> [Shot] {
        var shots: [Shot] = []

        // Setup: the background program could not start; Raven says so on the receive step.
        let failed = await newModel()
        failed.beginSetup()
        failed.setupStep = .receive
        failed.actionError = RavenError(code: ErrorCode.internalError, message: tr(.errorInternal),
                                        detail: "node.start: could not start the background program")
        shots.append(windowShot("70-setup-receive-error", failed))

        // You: your fingerprint, words and card.
        let (you, _) = await readyModel(after: 2)
        shots.append(sheetShot("71-you", you, width: 620, YouSheet()))

        // Rename a friend.
        let (rename, _) = await readyModel(after: 2)
        shots.append(sheetShot("72-rename-friend", rename, width: 420, RenameSheet(address: MockRaven.aliAddress)))

        // Add a friend as it opens: the switch is off, so the card holds no network address.
        let (share, shareMock) = await readyModel(after: 2)
        let plainCard = try? await shareMock.makeCard(includeAddress: false)
        shots.append(sheetShot("85-add-friend-share-default", share, width: 560,
                               AddFriendSheet(state: AddFriendState(step: 1, includeAddress: false, card: plainCard))))

        // Add a friend, step 2 before anything is pasted, a paste that is no card, and a name in use.
        let (empty, _) = await readyModel(after: 2)
        shots.append(sheetShot("73-add-friend-paste-empty", empty, width: 560, AddFriendSheet(state: AddFriendState(step: 2))))
        let (bad, _) = await readyModel(after: 2)
        let badState = AddFriendState(step: 2)
        badState.pasteText = "see you on Saturday"
        await badState.pasted(bad)
        shots.append(sheetShot("74-add-friend-paste-not-a-card", bad, width: 560, AddFriendSheet(state: badState)))
        let (clash, clashMock) = await readyModel(after: 2)
        let clashSummary = try? await clashMock.parseCard(newFriendCard)
        shots.append(sheetShot("75-add-friend-name-in-use", clash, width: 560,
                               AddFriendSheet(state: AddFriendState(step: 2, summary: clashSummary, name: "ali"))))

        // Add a friend, step 3: saved (not verified yet), now the words.
        let (added, _) = await readyModel(after: 2)
        if let contact = try? await added.addContact(text: newFriendCard, name: "Neighbour") {
            shots.append(sheetShot("76-add-friend-check-words", added, width: 560,
                                   AddFriendSheet(state: AddFriendState(step: 3, added: contact,
                                                                         check: CheckWordsState(address: contact.address)))))
        }

        // Check words, just opened, and after a word Raven does not know.
        let (fresh, _) = await readyModel(after: 2)
        shots.append(sheetShot("77-check-words-start", fresh, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress, highlight: 0)))
        let (unknown, _) = await readyModel(after: 2)
        let unknownState = CheckWordsState(address: MockRaven.renaAddress)
        unknownState.field = "airport bal banana "
        await unknownState.fieldChanged(unknown)
        shots.append(sheetShot("78-check-words-not-a-word", unknown, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress, state: unknownState, highlight: 0)))

        // No friends yet: a new profile set up without the demo friends.
        let clock = MockClock(fixed: baseDate)
        let lonely = AppModel(engine: MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0), now: { clock.now })
        await lonely.bootstrap()
        lonely.beginSetup()
        await lonely.chooseReceive(true)
        await lonely.finishSetup()
        await lonely.pollNow()
        shots.append(windowShot("79-main-no-friends", lonely))

        // Long names: in the list, in the chat header and in the not verified banner.
        let (long, _) = await readyModel(after: 12)
        await long.renameContact(MockRaven.aliAddress, to: longName)
        await long.renameContact(MockRaven.renaAddress, to: longNotVerified)
        long.select(MockRaven.renaAddress)
        shots.append(windowShot("80-main-long-names", long))
        shots.append(Shot(name: "81-main-long-names-smallest-window", width: Theme.shared.layout.minWidth,
                          height: Theme.shared.layout.minHeight, model: long, view: AnyView(RootView())))

        // A long name that is not verified, in the smallest window (found by a search).
        let (narrow, _) = await readyModel(after: 12)
        await narrow.renameContact(MockRaven.renaAddress, to: longNotVerified)
        narrow.searchText = "climbing"
        narrow.select(MockRaven.renaAddress)
        shots.append(Shot(name: "86-main-not-verified-smallest-window", width: Theme.shared.layout.minWidth,
                          height: Theme.shared.layout.minHeight, model: narrow, view: AnyView(RootView())))

        // Many friends: the list scrolls under the add buttons.
        let (many, _) = await readyModel(after: 12)
        for (i, name) in manyNames.enumerated() {
            let address = "rvn1q" + String(repeating: "m", count: 30) + String(format: "%06d", i)
            _ = try? await many.addContact(text: "raven-card/1 address=\(address) pub_hex=00 fingerprint=Ab3d-Ef56-Gh78",
                                           name: name)
        }
        many.select(MockRaven.aliAddress)
        shots.append(windowShot("82-main-many-friends", many))

        // A search: what matches, and a search with no match.
        let (search, _) = await readyModel(after: 12)
        search.searchText = "book"
        shots.append(windowShot("83-main-search", search))
        let (none, _) = await readyModel(after: 12)
        none.searchText = "zebra"
        shots.append(windowShot("84-main-search-no-match", none))
        return shots
    }
}
#endif
