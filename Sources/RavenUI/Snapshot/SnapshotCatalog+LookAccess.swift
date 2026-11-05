#if DEBUG || RAVEN_MOCK
import SwiftUI

/// Look and access: the top screens in the smallest window (tokens.json `minWindow`) and in a large
/// one (a 16 inch laptop screen in full screen), where a layout runs out of room or spreads too far.
/// Light and dark, as every shot.
extension SnapshotCatalog {
    /// A full screen window on a 16 inch laptop screen (1728 by 1117 points at its default resolution,
    /// without the menu bar).
    static let fullScreen = CGSize(width: 1728, height: 1117)

    static func lookAccessShots() async -> [Shot] {
        let small = CGSize(width: Theme.shared.layout.minWidth, height: Theme.shared.layout.minHeight)
        func smallest(_ name: String, _ model: AppModel, _ view: AnyView = AnyView(RootView())) -> Shot {
            Shot(name: name, width: small.width, height: small.height, model: model, view: view)
        }
        func large(_ name: String, _ model: AppModel) -> Shot {
            Shot(name: name, width: fullScreen.width, height: fullScreen.height, model: model, view: AnyView(RootView()), scale: 1)
        }
        var shots: [Shot] = []

        // The smallest window: welcome, setup, the locked screens, the failure screen, Settings and
        // the Network page.
        shots.append(smallest("90-smallest-welcome", await newModel()))
        let name = await newModel()
        name.beginSetup()
        shots.append(smallest("90b-smallest-setup-name", name))
        let words = await newModel()
        words.beginSetup()
        await words.chooseReceive(true)
        shots.append(smallest("90c-smallest-setup-words", words))
        let (locked, _) = await readyModel(after: 0, start: .locked)
        shots.append(smallest("91-smallest-locked", locked))
        let (lockedV2, _) = await readyModel(after: 2, network: .lab)
        await lockedV2.lockNow()
        shots.append(smallest("91b-smallest-locked-passphrase", lockedV2))
        let missing = AppModel(engine: MissingEngine())
        await missing.bootstrap()
        shots.append(smallest("92-smallest-without-engine", missing))
        for (shot, section) in [("93-smallest-settings-general", AppModel.SettingsSection.general),
                                ("93b-smallest-settings-appearance", .appearance), ("93c-smallest-settings-privacy", .privacy)] {
            shots.append(smallest(shot, await settingsModel(section)))
        }
        shots.append(smallest("94-smallest-network", await pageModel(.network, network: .release)))
        shots.append(smallest("94b-smallest-security", await pageModel(.security, network: .lab)))

        // A full screen window: the chat, Settings, the Network page and the welcome screen.
        let (chat, _) = await readyModel(after: 12)
        shots.append(large("95-full-screen-chat", chat))
        shots.append(large("95b-full-screen-settings", await settingsModel(.appearance)))
        shots.append(large("95c-full-screen-network", await pageModel(.network, network: .release)))
        shots.append(large("95d-full-screen-welcome", await newModel()))
        return shots
    }
}
#endif
