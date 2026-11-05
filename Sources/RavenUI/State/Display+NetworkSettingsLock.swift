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
