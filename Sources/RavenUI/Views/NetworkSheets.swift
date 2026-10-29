import SwiftUI

/// The person's yes before a setting that lends this computer to friends, or hands friends their
/// mail, is turned on: what it does, what it costs, what others can and can't see, and Raven's own
/// text where the engine has one. `agreed: true` goes to the engine only from "I agree".
public struct ConsentSheet: View {
    let setting: String
    @EnvironmentObject private var model: AppModel

    public init(setting: String) { self.setting = setting }

    public var body: some View {
        ConsentBody(setting: setting, net: model.network)
    }
}

struct ConsentBody: View {
    let setting: String
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p
    @ViewState private var working = false

    var body: some View {
        let texts = Display.consent(setting)
        SheetFrame(texts?.title ?? setting, width: 520) {
            VStack(alignment: .leading, spacing: 12) {
                if let texts {
                    part(tr(.networkConsentDoes), texts.does)
                    part(tr(.networkConsentCosts), texts.costs)
                    part(tr(.networkConsentSees), texts.sees)
                    part(tr(.networkConsentHidden), texts.hidden)
                }
                if let full = Display.engineConsentText(setting, net.status?.texts), !full.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(tr(.networkConsentEngine))
                        Text(full)
                            .font(RFont.smallish)
                            .foregroundColor(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .selectable()
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted))
                    }
                }
                if let error = net.consentError { ErrorNote(error) }
            }
        } footer: {
            Button(tr(.networkConsentNotNow)) { net.decline() }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.networkConsentAgree)) {
                working = true
                Task {
                    await net.agree()
                    working = false
                }
            }
            .buttonStyle(RButtonStyle(.primary))
            .disabled(working)
        }
        .task { if net.status == nil { await net.refresh() } }
    }

    private func part(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Restart the background program": `network.set` said some changes apply only when raven-node
/// starts again. Restart is `node.stop` then `node.start`; a raven-node a login service runs is left
/// running and the engine's note says how to restart it.
public struct RestartSheet: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        RestartBody(net: model.network)
    }
}

struct RestartBody: View {
    @ObservedObject var net: NetworkModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let state = net.restart ?? .asking
        SheetFrame(tr(.networkRestartTitle), width: 480) {
            VStack(alignment: .leading, spacing: 10) {
                switch state {
                case .asking:
                    Text(tr(.networkRestartBody)).fixedSize(horizontal: false, vertical: true)
                    if model.node?.startedByApp != true {
                        Text(tr(.networkRestartNotOurs)).font(RFont.smallish).foregroundColor(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .working:
                    HStack(spacing: 8) {
                        Spinner()
                        Text(tr(.networkRestartWorking))
                    }
                case .restarted:
                    Text(tr(.networkRestartDone)).foregroundColor(p.success)
                case .managed(let note):
                    Text(tr(.networkRestartManaged)).fixedSize(horizontal: false, vertical: true)
                    if !note.isEmpty { noteText(note) }
                case .notStopped(let note):
                    Text(tr(.networkRestartNotStopped)).fixedSize(horizontal: false, vertical: true)
                    if !note.isEmpty { noteText(note) }
                case .failed(let error):
                    ErrorNote(error)
                }
            }
        } footer: {
            switch state {
            case .asking:
                Button(tr(.networkRestartLater)) { net.dismissRestart() }
                    .buttonStyle(RButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(tr(.networkRestartNow)) { Task { await net.restartNode() } }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            case .working:
                Button(tr(.commonClose)) {}
                    .buttonStyle(RButtonStyle(.secondary))
                    .disabled(true)
            default:
                Button(tr(.commonClose)) { net.dismissRestart() }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func noteText(_ note: String) -> some View {
        Text(note).font(RFont.mono).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true).selectable()
    }
}
