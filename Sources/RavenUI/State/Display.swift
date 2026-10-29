import Foundation

/// Pure text decisions for the screens (so they can be unit-tested without views).
public enum Display {
    /// The sidebar's status line under a friend's name.
    /// `verifiedShown`: the row already says "Not verified" (the Calm sidebar), so the line doesn't.
    public static func statusLine(_ c: Contact, now: Date, verifiedShown: Bool = false) -> (text: String, tone: AppModel.Tone) {
        if let w = c.waiting, w.count > 0 {
            return (tr(.homeWaiting, ["n": String(w.count), "time": TimeText.deadline(ms: w.untilMs, now: now)]), .warning)
        }
        if !c.verified && !verifiedShown { return (tr(.homeNotVerified), .secondary) }
        switch c.presence {
        case .inTouch:
            let since = c.lastContactMs.map { now.timeIntervalSince(Date(ms: $0)) } ?? 0
            return (tr(.homeInTouch, ["when": TimeText.ago(since: since)]), .secondary)
        case .noAddress: return (tr(.homeNoAddress), .secondary)
        case .waiting, .none:
            // Their messages are in the chat: say when, not "No recent contact" (E1).
            if let ms = c.lastContactMs, ms > 0 {
                return (tr(.homeLastContact, ["when": TimeText.ago(since: now.timeIntervalSince(Date(ms: ms)))]), .secondary)
            }
            return (tr(.homeNoRecent), .secondary)
        }
    }

    /// The tick text under one of your messages.
    public static func tick(_ m: Message, name: String, now: Date) -> (text: String, tone: AppModel.Tone) {
        switch m.state {
        case .sending: return (tr(.tickSending), .secondary)
        case .sent: return ("✓ " + tr(.tickSent), .secondary)
        case .delivered:
            // A late delivery says when it came (E1: one that waited an hour said only "Delivered").
            if let at = m.deliveredAtMs, at > 0 {
                return ("✓✓ " + tr(.tickDeliveredAt, ["time": TimeText.bubble(ms: at, now: now)]), .accent)
            }
            return ("✓✓ " + tr(.tickDelivered), .accent)
        case .waiting:
            // No deadline known yet (raven-node's outbox hasn't listed it): no "until –".
            guard let until = m.untilMs, until > 0 else { return (tr(.tickWaitingNoTime, ["name": name]), .warning) }
            let left = Date(ms: until).timeIntervalSince(now)
            if left < 2 * 3600 {
                return (tr(.tickWaitingSoon, ["name": name, "left": TimeText.left(left)]), .warning)
            }
            return (tr(.tickWaiting, ["name": name, "time": TimeText.deadline(ms: until, now: now)]), .warning)
        case .timeRanOut: return (tr(.tickTimeRanOut), .danger)
        case .notSentMeetFirst: return (tr(.tickNotSentMeetFirst, ["name": name]), .danger)
        case .failed: return (tr(.tickFailed), .danger)
        }
    }

    /// The Calm status under one of your messages: the tick's words without their glyphs (the icon
    /// says it), the icon, and the tone: delivered in the success colour, waiting in warning.
    public static func status(_ m: Message, name: String, now: Date) -> (text: String, icon: StatusKind, tone: AppModel.Tone) {
        let t = tick(m, name: name, now: now)
        let text = t.text.hasPrefix("✓✓ ") ? String(t.text.dropFirst(3)) : t.text.hasPrefix("✓ ") ? String(t.text.dropFirst(2)) : t.text
        switch m.state {
        case .sending: return (text, .sending, .secondary)
        case .sent: return (text, .sent, .secondary)
        case .delivered: return (text, .delivered, .success)
        case .waiting: return (text, .waiting, .warning)
        case .timeRanOut, .notSentMeetFirst, .failed: return (text, .problem, .danger)
        }
    }

    public enum StatusKind: Equatable { case sending, sent, delivered, waiting, problem }

    /// "Delivered to 3 of 5" and the note after it ("1 waiting · 1 not confirmed yet · 1 not
    /// delivered"), from a group message's receipts.
    public static func groupStatus(_ m: GroupMessage) -> (text: String, note: String?) {
        let receipts = m.receipts ?? []
        let total = receipts.isEmpty ? m.total : receipts.count
        let delivered = receipts.isEmpty ? m.delivered : receipts.filter { $0.state == "delivered" }.count
        let waiting = receipts.filter { $0.state == "waiting" }.count
        let sent = receipts.filter { $0.state == "sent" }.count
        let failed = receipts.filter { $0.state == "failed" }.count
        var parts: [String] = []
        if waiting > 0 { parts.append(tr(.groupsNoteWaiting, ["n": String(waiting)])) }
        if sent > 0 { parts.append(tr(.groupsNoteSent, ["n": String(sent)])) }
        if failed > 0 { parts.append(tr(.groupsNoteFailed, ["n": String(failed)])) }
        return (tr(.groupsDeliveredOf, ["n": String(delivered), "total": String(total)]),
                parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    /// One member's line in a group message's Details: the state in words (and "passed on by another
    /// member" for a copy another member carried).
    public static func receiptLine(_ r: GroupReceipt) -> (text: String, icon: StatusKind, tone: AppModel.Tone) {
        let base: (String, StatusKind, AppModel.Tone)
        switch r.state {
        case "delivered": base = (tr(.tickDelivered), .delivered, .success)
        case "sent": base = (tr(.tickSent), .sent, .secondary)
        case "failed": base = (tr(.tickFailed), .problem, .danger)
        default: base = (tr(.groupsReceiptWaiting), .waiting, .warning)
        }
        let text = r.via == "relay" ? base.0 + " · " + tr(.groupsReceiptRelay) : base.0
        return (text, base.1, base.2)
    }

    /// The members line of a group: "4 members · 2 in touch now" (friends in touch), or "4 members".
    public static func groupMembersLine(_ g: RavenGroup, members: [GroupMember], contacts: [Contact]) -> String {
        let inTouch = members.filter { m in !m.me && contacts.contains { $0.address == m.address && $0.presence == .inTouch } }.count
        let n = members.isEmpty ? g.members : members.count
        return inTouch > 0 ? tr(.groupsMembersInTouch, ["n": String(n), "m": String(inTouch)]) : tr(.groupsMembers, ["n": String(n)])
    }

    /// Who you are, for the top of the sidebar: "You · Sam" (or "You") and "Fingerprint KLHQ-uLWW-5iB0".
    public static func you(_ identity: Identity?, name: String?) -> (title: String, fingerprint: String?) {
        let shown = (identity?.displayName ?? name).map { Sanitizer.line($0, maxLength: 40) } ?? ""
        let title = shown.isEmpty ? tr(.youTitle) : tr(.youRow, ["name": shown])
        let code = identity.map { Sanitizer.line($0.oldCode, maxLength: 32) } ?? ""
        return (title, code.isEmpty ? nil : tr(.youFingerprint, ["code": code]))
    }

    /// "node ok · now", or the "isn't responding" sentence when the last status check is too old.
    public static func heartbeat(node: NodeStatus?, lastOk: Date?, now: Date) -> (text: String, ok: Bool) {
        guard let node, node.running, let lastOk else { return (tr(.homeHeartbeatDown), false) }
        let since = now.timeIntervalSince(lastOk)
        if since > 4 * Theme.shared.motion.statusCheckInterval + 2 { return (tr(.homeHeartbeatDown), false) }
        return (tr(.homeHeartbeatOk, ["when": TimeText.heartbeat(since: since)]), true)
    }

    /// The toast line when nothing just happened. "Wi-Fi" only when this Mac's network really is
    /// Wi-Fi (a Mac on a cable listens "on your network", E1).
    public static func quietTicker(node: NodeStatus?, friends: Int, wifi: Bool = NetworkKind.shared.isWiFi) -> String? {
        guard let node, node.running, node.listening != nil, !node.localOnly else { return nil }
        return tr(wifi ? .tickerQuiet : .tickerQuietNetwork, ["n": String(friends)])
    }

    /// "New message from Ali · LAN direct", or without the separator when no path is known (E1:
    /// "New message from mac-a · ").
    public static func incomingTicker(name: String, path: String?) -> String {
        let path = path.map { Sanitizer.line($0, maxLength: 40) } ?? ""
        return path.isEmpty ? tr(.tickerIncomingNoPath, ["name": name]) : tr(.tickerIncoming, ["name": name, "path": path])
    }

    /// One state per row (E1: "Off" beside "In use now"): the state chip says it; a way that is on
    /// but not in use now says so under it. Nothing else.
    public static func runningNote(state: WayState, running: Bool?) -> String? {
        guard state == .on || state == .lab, running == false else { return nil }
        return tr(.networkRunningNo)
    }

    /// How many mail friends a friend told about: the list the Routes panel shows below the count, so
    /// the two never disagree (E1: "mail friends: 0" above "Mail friends ... told you about: mac-b").
    public static func mailFriendCount(_ routes: ContactRoutes) -> Int {
        guard let told = routes.carriers?.told else { return routes.learned?.mailFriends ?? 0 }
        return told.count + (routes.carriers?.toldUnknown ?? 0)
    }

    /// The path chip in the chat header: how the last message travelled, but not while messages to the
    /// friend wait (E1: "LAN direct" stayed there while the friend was away and every try failed).
    public static func headerPath(_ c: Contact, lastPath: String?) -> String? {
        if c.presence == .waiting || (c.waiting?.count ?? 0) > 0 { return nil }
        let path = lastPath.map { Sanitizer.line($0, maxLength: 40) } ?? ""
        return path.isEmpty ? nil : path
    }

    /// The Routes panel's lines about an away friend: how long a message written now could wait, by the
    /// rule the terminal app and `raven contact list` use (`carriers.away`; E1: the panel said "up to 7
    /// days" where the terminal app said "until tomorrow"), then how friends can carry it too (only when
    /// one can). A friend Raven hasn't connected with yet gets the terminal app's first-message rule, and
    /// "meet first" is only for a secure connection that ended. `now`: when it is read (a deadline a week
    /// away has its date).
    public static func awayLines(_ routes: ContactRoutes, name: String, now: Date) -> [String] {
        var lines: [String] = []
        if let away = routes.carriers?.away {
            if away.firstMessage == true {
                lines.append(tr(.networkRoutesAwayFirstMessage, ["name": name]))
            } else if away.meetFirst == true {
                lines.append(tr(.networkRoutesAwayMeetFirst, ["name": name]))
            } else if let until = away.untilMs, until > 0 {
                lines.append(tr(.networkRoutesAway, ["name": name, "time": TimeText.deadline(ms: until, now: now)]))
            }
        }
        if let c = routes.carriers?.coverage, ["mutual_friend", "two_friends"].contains(c.kind) {
            lines.append(tr(.networkRoutesCoverage, ["coverage": c.name, "until": c.until]))
        }
        return lines
    }

    /// Where Raven reaches the friend on the local network now (`lan_now`), and, when the saved LAN
    /// address is another one, that it is old (E1: Routes showed only the old address while every
    /// message went to the new one).
    public static func lanNow(_ routes: ContactRoutes, name: String, now: Date) -> (reached: String, stale: String?)? {
        guard let lan = routes.lanNow, !lan.addr.isEmpty else { return nil }
        let when = TimeText.ago(since: now.timeIntervalSince(Date(ms: lan.atMs)))
        let reached = tr(.networkRoutesLanNow, ["name": name, "addr": lan.addr, "when": when])
        let saved = routes.routes.first(where: { $0.kind == "lan" })?.value ?? ""
        let stale = lan.savedStale == true && !saved.isEmpty
            ? tr(.networkRoutesLanStale, ["addr": saved, "name": name]) : nil
        return (reached, stale)
    }

    /// The label of the background program's count of open alerts: they are the smaller notices, only
    /// counted, while no notice needs you, and "alerts" is never said then (E1).
    public static func openNoticesKey(noticesNeedYou: Bool) -> Str {
        noticesNeedYou ? .securityNodeAlerts : .securityCounted
    }

    /// The peer-to-peer addresses the Network page shows: those friends could use. Loopback,
    /// link-local and unspecified ones stay under Technical details (E1: six "Peer-to-peer address"
    /// rows, loopback ones among them).
    public static func p2pAddressesShown(_ addrs: [String]) -> [String] {
        addrs.filter { !p2pAddressIsLocalOnly($0) }
    }

    /// A multiaddr (`/ip4/127.0.0.1/tcp/7423/...`) whose IP only this computer or this link can reach.
    public static func p2pAddressIsLocalOnly(_ multiaddr: String) -> Bool {
        let parts = multiaddr.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return false }
        let ip = parts[1].lowercased()
        switch parts[0] {
        case "ip4":
            return ip.hasPrefix("127.") || ip.hasPrefix("169.254.") || ip == "0.0.0.0"
        case "ip6":
            let bare = ip.split(separator: "%").first.map(String.init) ?? ip
            return bare == "::1" || bare == "::" || bare.hasPrefix("fe8") || bare.hasPrefix("fe9")
                || bare.hasPrefix("fea") || bare.hasPrefix("feb")
        default:
            return false
        }
    }

    /// View menu: the sidebar item says what it will do.
    public static func sidebarMenuTitle(shown: Bool) -> String {
        tr(shown ? .viewHideSidebar : .viewShowSidebar)
    }

    /// Ended messages of yours: Send again and Delete are offered on the bubble.
    public static func canDelete(_ m: Message) -> Bool {
        m.direction == .outgoing && [.failed, .timeRanOut, .notSentMeetFirst].contains(m.state)
    }

    /// One friend line in the menu bar menu.
    public static func menuLine(_ c: Contact, unread: Int, now: Date) -> String {
        if unread > 0 { return tr(.homeNewFrom, ["n": String(unread), "name": c.name]) }
        return c.name + " · " + statusLine(c, now: now).text
    }

    /// The listening chip of the Network panel.
    public static func listening(_ node: NodeStatus?) -> (text: String, tone: AppModel.Tone, busy: Bool) {
        guard let node, node.running else { return (tr(.netProcessNone), .danger, false) }
        if !node.receive { return (tr(.netOff), .secondary, false) }
        if node.starting { return (tr(.netStarting), .secondary, true) }
        if node.localOnly { return (tr(.netLocalOnly), .warning, false) }
        return (tr(.netListening, ["port": node.port ?? "7420"]), .success, false)
    }

    public static func process(_ node: NodeStatus?) -> String {
        guard let node, node.running, let pid = node.pid else { return tr(.netProcessNone) }
        return node.startedByApp ? tr(.netProcessApp, ["pid": String(pid)]) : tr(.netProcessEarlier, ["pid": String(pid)])
    }

    // MARK: Network screens

    /// A way's state chip: On, Off, Preview, Lab only, Not on this computer.
    public static func wayState(_ state: WayState) -> (text: String, tone: AppModel.Tone) {
        switch state {
        case .on: return (tr(.netOn), .success)
        case .off: return (tr(.netWayOff), .secondary)
        case .preview: return (tr(.netPreview), .warning)
        case .lab: return (tr(.netLab), .accent)
        case .notOnThisOs: return (tr(.netNotOnThisOs), .secondary)
        }
    }

    /// The short label of a message's path chip (API.md, Message `path_kind`). An unknown kind
    /// falls back to the engine's own path words; nothing when the message has no path.
    public static func pathChip(kind: String?, path: String?) -> String? {
        let key: Str?
        switch kind {
        // Calm chip words (chip.*: "LAN direct", "Bluetooth", "Held by a friend"); the
        // network.path.* labels stay the short technical names the Windows and Linux apps show.
        case "lan": key = .chipLan
        case "internet": key = .networkPathInternet
        case "p2p": key = .networkPathP2p
        case "p2p_direct": key = .networkPathP2pDirect
        case "p2p_reversed": key = .networkPathP2pReversed
        case "p2p_relayed": key = .networkPathP2pRelayed
        case "p2p_hole_punched": key = .networkPathP2pHolePunched
        case "websocket": key = .networkPathWebsocket
        case "nearby": key = .chipNearby
        case "friend": key = .chipFriend
        case "handoff": key = .chipHandoff
        case "letter": key = .networkPathLetter
        // The engine's Tor path (`onion`, "via Tor").
        case "onion", "tor": key = .networkPathTor
        default: key = nil
        }
        if let key { return tr(key) }
        let words = path.map { Sanitizer.line($0, maxLength: 40) } ?? ""
        return words.isEmpty ? nil : words
    }

    /// The Tor way's phase chip (API.md "The Tor way"): its words and tone. Raven-node's own words
    /// stand in for a phase this app doesn't know.
    public static func torPhase(_ tor: TorState) -> (text: String, tone: AppModel.Tone) {
        switch tor.phase {
        case "ready": return (tr(.networkTorPhaseReady), .success)
        case "publishing": return (tr(.networkTorPhasePublishing), .accent)
        case "unreachable": return (tr(.networkTorPhaseUnreachable), .warning)
        case "starting":
            return (tr(.networkTorPhaseStarting, ["percent": String(max(0, min(100, tor.percent ?? 0)))]), .accent)
        case "restarting": return (tr(.networkTorPhaseRestarting), .accent)
        case "blocked": return (tr(.networkTorPhaseBlocked), .warning)
        case "could_not_start": return (tr(.networkTorPhaseCouldNotStart), .warning)
        case "not_built": return (tr(.networkTorPhaseNotBuilt), .secondary)
        case "off": return (tr(.networkTorPhaseOff), .secondary)
        default:
            let words = Sanitizer.line(tor.words ?? "", maxLength: 60)
            return (words.isEmpty ? tr(.networkTorPhaseOff) : words, .secondary)
        }
    }

    /// The lines under the Tor way: why (with when it retries) and the outage history.
    public static func torLines(_ tor: TorState) -> [String] {
        var lines: [String] = []
        let why = [tor.why, tor.retry].compactMap { $0 }.map { Sanitizer.line($0, maxLength: 160) }
            .filter { !$0.isEmpty }.joined(separator: "; ")
        if !why.isEmpty { lines.append(tr(.networkTorWhy, ["text": why])) }
        if let outages = tor.outages.map({ Sanitizer.line($0, maxLength: 200) }), !outages.isEmpty {
            lines.append(tr(.networkTorOutages, ["text": outages]))
        }
        return lines
    }

    /// A size in plain units: "512 B", "3 KB", "1.2 MB".
    public static func bytes(_ n: Int64) -> String {
        if n < 1024 { return "\(max(0, n)) B" }
        if n < 1024 * 1024 { return "\(Int((Double(n) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(n) / (1024 * 1024))
    }

    /// The consent sheet's texts for a setting: title, what it does, what it costs, what others
    /// can see, what stays hidden.
    public static func consent(_ setting: String) -> (title: String, does: String, costs: String, sees: String, hidden: String)? {
        switch setting {
        case "carry_for_friends":
            return (tr(.networkConsentCarryForFriendsTitle), tr(.networkConsentCarryForFriendsDoes),
                    tr(.networkConsentCarryForFriendsCosts), tr(.networkConsentCarryForFriendsSees),
                    tr(.networkConsentCarryForFriendsHidden))
        case "friends_carry_mine":
            return (tr(.networkConsentFriendsCarryMineTitle), tr(.networkConsentFriendsCarryMineDoes),
                    tr(.networkConsentFriendsCarryMineCosts), tr(.networkConsentFriendsCarryMineSees),
                    tr(.networkConsentFriendsCarryMineHidden))
        case "handoff":
            return (tr(.networkConsentHandoffTitle), tr(.networkConsentHandoffDoes), tr(.networkConsentHandoffCosts),
                    tr(.networkConsentHandoffSees), tr(.networkConsentHandoffHidden))
        default:
            return nil
        }
    }

    /// The engine's own text for a consent setting (`network.status` `texts`), where it has one.
    public static func engineConsentText(_ setting: String, _ texts: NetworkTexts?) -> String? {
        guard let texts else { return nil }
        switch setting {
        case "carry_for_friends": return texts.carryForFriends
        case "friends_carry_mine": return texts.friendsCarryMine
        case "handoff": return texts.handoff
        default: return nil
        }
    }

    /// Where a relay comes from: added by you, or lent by a friend.
    public static func relaySource(_ relay: RelayInUse, name: (String) -> String?) -> String {
        if relay.source == "offer" {
            let who = relay.friendAddress.flatMap(name) ?? relay.friendAddress.map(Fallback.short) ?? "–"
            return tr(.networkRelaysOffer, ["name": who])
        }
        return tr(.networkRelaysManual)
    }
}
