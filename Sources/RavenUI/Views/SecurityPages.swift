import SwiftUI

/// Security: `security.status` (`raven security`, read-only: this app doesn't resolve notices)
/// and Lock while running (Lock v2: `lock.state`, `lock.now`; the locked screen unlocks).
struct SecurityPage: View {
    @ObservedObject var net: NetworkModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(tr(.securityTitle), intro: tr(.securityIntro)) {
            Button(tr(.networkRefresh)) { Task { await load() } }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .keyboardShortcut("r", modifiers: .command)
        } content: {
            if let error = net.securityError { ErrorNote(error) }
            if let s = net.security {
                PageSection(tr(.securityTitle)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            StateChip(state: s.available ? (s.lab == true ? .lab : .on) : .preview)
                            if let counted = s.counted, s.available {
                                Text(tr(.securityCounted, ["n": String(counted)])).font(RFont.small).foregroundColor(p.textSecondary)
                            }
                        }
                        Text(s.available ? kept(s.kept) : tr(.securityPreview)).font(RFont.smallish)
                            .fixedSize(horizontal: false, vertical: true)
                        if let node = s.node {
                            Text(tr(.securityNodeTitle)).font(RFont.small.weight(.semibold)).padding(.top, 4)
                            counts(node, noticesNeedYou: !s.notices.isEmpty)
                        }
                    }
                    .padding(.vertical, 8)
                }
                PageSection(tr(.securityNotices)) {
                    VStack(alignment: .leading, spacing: 0) {
                        if s.notices.isEmpty {
                            Text(tr(.securityNoticesNone)).font(RFont.smallish).foregroundColor(p.textSecondary).padding(.vertical, 8)
                        }
                        ForEach(Array(s.notices.enumerated()), id: \.element.id) { i, notice in
                            if i > 0 { Rule() }
                            NoticeRow(notice: notice)
                        }
                        if !s.notices.isEmpty {
                            Text(tr(.securityResolve)).font(RFont.small).foregroundColor(p.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 8)
                        }
                    }
                }
            } else if net.securityError == nil {
                Spinner()
            }
            LockSection()
        }
        .task { await load() }
    }

    private func load() async {
        await net.loadSecurity()
        await model.refreshLock()
    }

    private func kept(_ word: String) -> String {
        switch word {
        case "live": return tr(.securityKeptLive)
        case "unsealed": return tr(.securityKeptUnsealed)
        default: return tr(.securityKeptOff)
        }
    }

    /// The background program's counts. Its open alerts are the smaller notices, only counted, while no
    /// notice needs you (E1: "Open alerts: 1" beside "No notices. Nothing needs you.").
    @ViewBuilder private func counts(_ node: SecurityNodeCounts, noticesNeedYou: Bool) -> some View {
        let lines: [(Str, Int?)] = [(.securityNodeStrangers, node.strangersRefused1h), (.securityNodeHandshakes, node.failedHandshakes1h),
                                    (.securityNodeBans, node.bansActive), (.securityNodeLinkTags, node.linkTagFailures24h),
                                    (Display.openNoticesKey(noticesNeedYou: noticesNeedYou), node.alertsOpen)]
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            if let n = line.1 {
                Text(tr(line.0, ["n": String(n)])).font(RFont.smallish).foregroundColor(p.textSecondary)
            }
        }
    }
}

/// One security notice: level, headline, when, what Raven did, what to do, and its details.
struct NoticeRow: View {
    let notice: SecurityNotice
    @Environment(\.palette) private var p
    @ViewState private var showDetails = false

    var body: some View {
        let alert = notice.level == "alert"
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Pill(text: alert ? tr(.securityAlert) : tr(.securityWarning), tone: alert ? .danger : .warning)
                Text(notice.headline).font(RFont.bodyBold).fixedSize(horizontal: false, vertical: true)
            }
            let who = [notice.name, notice.when].compactMap { $0 }.filter { !$0.isEmpty }.map { Sanitizer.line($0, maxLength: 80) }
            if !who.isEmpty {
                Text(who.joined(separator: " · ")).font(RFont.small).foregroundColor(p.textSecondary)
            }
            if let did = notice.whatRavenDid, !did.isEmpty {
                labelled(tr(.securityDidWhat), did)
            }
            if let todo = notice.whatToDo, !todo.isEmpty {
                labelled(tr(.securityToDo), todo)
            }
            if let details = notice.details, !details.isEmpty {
                Button(tr(.messageDetails)) { showDetails.toggle() }
                    .buttonStyle(RButtonStyle(.plain))
                    .font(RFont.small)
                if showDetails {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, d in
                        Text("\(d.label): \(d.value)").font(RFont.mono).foregroundColor(p.textSecondary).selectable()
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func labelled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(RFont.small.weight(.semibold)).foregroundColor(p.textSecondary)
            Text(text).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Lock while running (Lock v2): what it does, and Lock now where the running raven-node serves it.
struct LockSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let lock = model.lockV2
        PageSection(tr(.lockV2Title)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let lock {
                        StateChip(state: lock.available ? (lock.lab == true ? .lab : .on) : .preview)
                        if lock.supported {
                            Text(lock.locked ? tr(.lockV2Locked) : tr(.lockV2Unlocked)).font(RFont.small).foregroundColor(p.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if lock?.supported == true {
                        Button(tr(.lockNow)) { model.requestLock() }
                            .buttonStyle(RButtonStyle(.secondary, compact: true))
                    }
                }
                Text(tr(.lockV2Body)).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                if lock?.available != true {
                    Text(tr(.lockNotAvailable)).font(RFont.smallish).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else if lock?.supported != true {
                    Text(tr(.lockNotSupported)).font(RFont.smallish).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else if lock?.hasPassphrase == true {
                    Text(tr(.lockV2PassphraseNote)).font(RFont.small).foregroundColor(p.textSecondary)
                } else if lock?.hasPassphrase == false {
                    Text(tr(.lockNoPassphrase)).font(RFont.small).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.lockError { ErrorNote(error) }
            }
            .padding(.vertical, 8)
        }
    }
}

/// Updates: `updates.status` (`raven update status`), read-only; installing stays in the terminal.
struct UpdatesPage: View {
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(tr(.updatesTitle), intro: tr(.updatesIntro)) {
            Button(tr(.networkRefresh)) { Task { await net.loadUpdates() } }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .keyboardShortcut("r", modifiers: .command)
        } content: {
            if let error = net.updatesError { ErrorNote(error) }
            if let u = net.updates {
                PageSection(tr(.updatesStatus)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            StateChip(state: u.available ? (u.lab == true ? .lab : .on) : .preview)
                            if let summary = u.summary, !summary.isEmpty {
                                Text(summary).font(RFont.bodyBold).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(Array(u.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(RFont.mono).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                                .selectable()
                        }
                        HStack(spacing: 8) {
                            Text(tr(.updatesFromFriends)).font(RFont.smallish)
                            StateChip(state: u.fromFriends == true ? (u.lab == true ? .lab : .on) : .preview)
                        }
                        .padding(.top, 4)
                        if u.available != true {
                            Text(tr(.updatesNotAvailable)).font(RFont.smallish).foregroundColor(p.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 8)
                }
                if let offer = u.offer, !offer.isEmpty {
                    PageSection(tr(.updatesOffer)) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(offer.enumerated()), id: \.offset) { _, line in
                                Text(line).font(RFont.mono).fixedSize(horizontal: false, vertical: true).selectable()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(.updatesInstall)).font(RFont.bodyBold).fixedSize(horizontal: false, vertical: true)
                    // The terminal command: Technical details only (E1).
                    if let text = u.installText, !text.isEmpty { TechnicalDetails(lines: [text]) }
                }
            } else if net.updatesError == nil {
                Spinner()
            }
        }
        .task { await net.loadUpdates() }
    }
}
