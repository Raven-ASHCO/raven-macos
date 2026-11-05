import Foundation

// MARK: - Network, Settings, Lock and the menu bar (the Mac app's UI pass)

extension Display {
    /// This computer's port, addresses and process number: Technical details only (owner rule:
    /// addresses and ports only under Details). The port is the one raven-node listens on, or the
    /// profile's while nothing runs.
    public static func thisComputerDetails(status: NetworkStatus?, node: NodeStatus?) -> [String] {
        var lines: [String] = []
        // The profile's port only while nothing runs (as `NetworkModel.profilePortLine`).
        let profilePort = node?.running != true && status?.node != "running" ? status?.port.map(String.init) : nil
        if let port = node?.running == true ? node?.port : profilePort {
            lines.append(tr(.macNetworkDetailPort, ["port": port]))
        }
        let listening = (status?.listening ?? []).map { Sanitizer.line($0, maxLength: 64) }.filter { !$0.isEmpty }
        if !listening.isEmpty {
            lines.append(tr(.networkThisComputerListening, ["addr": listening.joined(separator: ", ")]))
        } else if status != nil {
            lines.append(tr(.networkThisComputerNotListening))
        }
        if let addr = node?.address, !addr.isEmpty { lines.append(tr(.macNetworkDetailAddress, ["addr": addr])) }
        if node?.running == true, let pid = node?.pid { lines.append(tr(.macNetworkDetailProcess, ["pid": String(pid)])) }
        return lines
    }

    /// A way's own addresses and ports for its Technical details: where Internet direct and peer to
    /// peer listen, the relays in use, every peer to peer address, and the router's answers.
    public static func wayAddressDetails(_ way: NetworkWay, _ status: NetworkStatus) -> [String] {
        var lines: [String] = []
        switch way.id {
        case "internet":
            if let at = status.internetListen, !at.isEmpty { lines.append(tr(.networkThisComputerInternet, ["addr": at])) }
        case "port_mapping":
            guard let pm = status.portMapping else { break }
            if let router = pm.router, !router.isEmpty { lines.append(tr(.macNetworkDetailRouter, ["result": router])) }
            // v4 and v6 are raven-node's words (upnp, none, open, ...); v4_port is the port the router forwards.
            if let v4 = pm.v4, !v4.isEmpty {
                if let port = pm.v4Port, port > 0 {
                    lines.append(tr(.networkPortMappingV4Port, ["how": v4, "port": String(port)]))
                } else {
                    lines.append(tr(.networkPortMappingV4, ["how": v4]))
                }
            }
            if let v6 = pm.v6, !v6.isEmpty { lines.append(tr(.networkPortMappingV6, ["how": v6])) }
        case "p2p":
            if let at = status.p2pListen, !at.isEmpty { lines.append(tr(.macNetworkDetailP2pListen, ["addr": at])) }
            lines += (status.relays ?? []).map { tr(.macNetworkDetailRelay, ["relay": $0.relay]) }
            lines += (status.p2pAddresses ?? []).map { tr(.macNetworkDetailP2pAddress, ["addr": $0]) }
        default:
            break
        }
        return lines
    }

    // MARK: Raven-node's words, plain

    /// Raven-node's phrases with an apostrophe or a hyphen, and the app's plain words for them;
    /// longest first. Every other "n't" becomes " not" in `plainWords`.
    static let plainPhrases: [(String, String)] = [
        ("a developer build's lab switch", "a lab switch in a developer build"),
        ("Raven's background program", "the Raven background program"),
        ("Raven's own links", "Raven links"),
        ("this computer's HTTPS proxy setting", "the HTTPS proxy setting of this computer"),
        ("this computer's IP address", "the IP address of this computer"),
        ("this computer's router", "the router of this computer"),
        ("this computer's network", "the network of this computer"),
        ("the profile's port", "the port of this profile"),
        ("a friend's address", "the address of a friend"),
        ("Wi-Fi", "WiFi"),
        ("Peer-to-peer", "Peer to peer"), ("peer-to-peer", "peer to peer"),
        ("NAT-PMP", "NAT\u{00A0}PMP"),   // kept on one line
        ("self-check", "self check"),
        ("carrier-grade", "carrier grade"),
        ("End-to-end", "End to end"), ("end-to-end", "end to end"),
        ("read-only", "read only"),
        ("built-in", "built in"),
        ("can't", "cannot"), ("Can't", "Cannot"),
        ("won't", "will not"), ("Won't", "Will not"),
        ("it's", "it is"), ("It's", "It is"),
        ("that's", "that is"), ("That's", "That is"),
        ("there's", "there is"), ("There's", "There is"),
        ("what's", "what is"), ("What's", "What is"),
        ("you're", "you are"), ("You're", "You are"),
        ("you'll", "you will"), ("You'll", "You will"),
        ("you've", "you have"), ("You've", "You have"),
        ("they're", "they are"), ("we're", "we are"), ("I'm", "I am"),
    ]

    /// Raven-node's own sentences (a way's name and reason, what a change does, the check's lines, a
    /// security notice) in the app's plain words: no apostrophes, hyphens or dashes (owner rule for
    /// visible texts). Technical details keep raven-node's words as they are.
    public static func plainWords(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\u{2019}", with: "'")
        for (from, to) in plainPhrases { s = s.replacingOccurrences(of: from, with: to) }
        // isn't, doesn't, didn't, don't, hasn't, couldn't, aren't ...
        s = s.replacingOccurrences(of: #"\b(\w+)n't\b"#, with: "$1 not", options: .regularExpression)
        // A sentence that now starts with "the Raven background program".
        s = s.replacingOccurrences(of: #"(^|[.!?]\s+)the Raven"#, with: "$1The Raven", options: .regularExpression)
        s = s.replacingOccurrences(of: " \u{2014} ", with: ": ").replacingOccurrences(of: " \u{2013} ", with: ": ")
        return s
    }

    /// A way's name: raven-node's, in plain words ("Same network (WiFi, cable or hotspot)", "Peer to
    /// peer and relays", "Router port opening (UPnP, NAT PMP, PCP)").
    public static func wayName(_ way: NetworkWay) -> String {
        if way.id == "tor" { return tr(.networkTorName) }
        let name = way.name.map { Sanitizer.line($0, maxLength: 80) } ?? ""
        return name.isEmpty ? way.id : plainWords(name)
    }

    /// Check network's name for a row of the doctor's summary: the app's where it has one, else the
    /// doctor's own label with a capital letter (it said "identity", "raven-node", "contacts").
    public static func checkLabel(_ row: CheckSummaryRow) -> String {
        switch row.key {
        case "identity": return tr(.macNetworkCheckLabelIdentity)
        case "raven_node": return tr(.macNetworkCheckLabelNode)
        case "lan": return tr(.macNetworkCheckLabelLan)
        case "contacts": return tr(.macNetworkCheckLabelContacts)
        case "disk": return tr(.macNetworkCheckLabelDisk)
        default: return capitalFirst(plainWords(Sanitizer.line(row.label, maxLength: 40)))
        }
    }

    /// A summary row's value in plain words, starting with a capital letter ("on" said "On").
    public static func checkValue(_ row: CheckSummaryRow) -> String {
        capitalFirst(plainWords(row.value))
    }

    /// Check network's next step: "All set: ..." is no step to take, so it is said as done (it read
    /// "Next step: All set: Raven can send ...").
    public static func checkNextStep(_ step: String) -> (text: String, done: Bool) {
        let plain = plainWords(step.trimmingCharacters(in: .whitespacesAndNewlines))
        if plain.lowercased().hasPrefix("all set") { return (plain, true) }
        return (tr(.networkCheckNextStep, ["step": plain]), false)
    }

    static func capitalFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Menu bar

    /// The menu bar's friends: all of them in the sidebar's order while they fit in `limit` rows;
    /// with more, those with new messages first, then the others, and `more` says how many are left
    /// out (Open Raven lists them all). With many friends the menu grew taller than the screen, its
    /// last rows (Quit among them) out of reach.
    public static func menuFriends(_ contacts: [Contact], unread: [String: Int], limit: Int) -> (shown: [Contact], more: Int) {
        guard contacts.count > limit else { return (contacts, 0) }
        let ordered = contacts.filter { (unread[$0.address] ?? 0) > 0 } + contacts.filter { (unread[$0.address] ?? 0) == 0 }
        let shown = Array(ordered.prefix(max(0, limit)))
        return (shown, contacts.count - shown.count)
    }

    /// A friend's menu line where the whole one does not fit: "Neighbour · 1 waiting" without its
    /// deadline (the chat says until when), instead of "Neighbour · 1 waiting · until Wed 12:05 (UTC…".
    public static func menuLineShort(_ c: Contact, unread: Int, now: Date) -> String {
        if unread > 0 { return menuLine(c, unread: unread, now: now) }
        if let w = c.waiting, w.count > 0 { return c.name + " · " + tr(.macTrayWaiting, ["n": String(w.count)]) }
        return menuLine(c, unread: unread, now: now)
    }

    /// The row under the menu's friends when some are left out.
    public static func menuMore(_ n: Int) -> String {
        n == 1 ? tr(.macTrayMoreFriend) : tr(.macTrayMoreFriends, ["n": String(n)])
    }
}
