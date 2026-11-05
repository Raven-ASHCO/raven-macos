#if DEBUG || RAVEN_MOCK
import Network
import SwiftUI

extension SnapshotCatalog {
    /// The UI pass on Network, Settings, the lock and the menu bar: the states the other shots do not
    /// show (many friends in the menu, Technical details open, a lock without a passphrase).
    static func networkSettingsLockShots() async -> [Shot] {
        var shots: [Shot] = []

        // Many friends: the menu lists eight, the one with new messages first, and says how many more.
        let (menu, _) = await readyModel(after: 3)
        let roles = ["Neighbour", "Teacher", "Cousin", "Workshop", "Landlord", "Coach", "Gardener", "Baker",
                     "Tailor", "Choir", "Studio", "Pharmacy"]
        for (i, role) in roles.enumerated() {
            let address = "rvn1menu" + String(i)
            menu.contacts.append(Contact(address: address, name: role, shortAddress: address, verified: i % 3 != 0,
                                         presence: i % 4 == 0 ? .inTouch : .none,
                                         avatarIndex: Theme.avatarIndex(for: address)))
        }
        menu.unread["rvn1menu" + String(roles.count - 2)] = 2
        shots.append(sheetShot("22b-menu-bar-many-friends", menu, width: 310, MenuBarContent(openMain: {})))

        // Technical details open (Settings > Appearance): every port and address is there.
        let release = await pageModel(.network, network: .release)
        release.showTechnical = true
        shots.append(windowShot("31t-network-release-technical", release, height: 2300))
        let lab = await pageModel(.network, network: .lab)
        lab.showTechnical = true
        shots.append(windowShot("32t-network-lab-technical", lab, height: 2750))

        // The background program stopped: This computer offers Start, the menu says Raven is not receiving.
        let stopped = await pageModel(.network, network: .release)
        await stopped.stopNode()
        await stopped.network.refresh()
        shots.append(windowShot("31s-network-stopped", stopped))
        shots.append(sheetShot("22c-menu-bar-stopped", stopped, width: 310, MenuBarContent(openMain: {})))

        // Check network as the desktop engine words it for a program that listens on this computer
        // only: no address or port beside the rows or in the next step (the doctor's own lines keep
        // them under Technical details).
        let (engineCheck, engine) = await readyModel(after: 2)
        let loopback = "\(IPv4Address.loopback):7420"
        func row(_ key: String, _ label: String, _ value: String) -> CheckSummaryRow {
            CheckSummaryRow(key: key, label: label, value: value)
        }
        engine.checkSummary = [
            row("identity", "identity", "OK"),
            row("raven_node", "raven-node", "running; you can send, but friends cannot reach you (it listens on this computer only)"),
            row("lan", "LAN", "this computer only (\(loopback))"),
            row("lan_search", "LAN search", "on (answers only your contacts); last 10 min: 3 sent, 2 answered"),
            row("contacts", "contacts", "3"),
            row("disk", "disk", "OK \u{2014} 120 GB free"),
        ]
        engine.checkNextStep = "Friends cannot reach you: Raven's background program listens on this computer only (\(loopback))."
        engine.checkRows = [
            CheckRow(key: "receiving", value: "local_only " + loopback,
                     plain: "Raven listens on this computer only: friends on your network can't reach it."),
            CheckRow(key: "reach_class", value: "off (p2p host not running)",
                     plain: "Peer-to-peer isn't running, so only direct ways are used."),
        ]
        await engineCheck.network.refresh()
        await engineCheck.network.runCheck(router: true)
        engineCheck.open(.checkNetwork)
        shots.append(windowShot("35b-check-network-this-computer-only", engineCheck, height: 860))

        // Lock now without a Raven passphrase: waking asks for none.
        let (noPassphrase, _) = await readyModel(after: 2, network: .lab)
        await noPassphrase.refreshLock()
        noPassphrase.lockV2?.hasPassphrase = false
        shots.append(sheetShot("51d-lock-sheet-no-passphrase", noPassphrase, width: 460, ConfirmLockSheet()))
        // Settings > Lock where Lock while running works (a lab build), without a passphrase.
        let lockSettings = await settingsModel(.lock, network: .lab)
        lockSettings.lockV2?.hasPassphrase = false
        shots.append(windowShot("43b-settings-lock-no-passphrase", lockSettings))
        return shots
    }
}
#endif
