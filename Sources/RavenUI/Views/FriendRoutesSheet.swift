import SwiftUI

/// A friend's routes (`contacts.routes` / `contacts.set_routes`): the saved routes, an Internet or
/// peer-to-peer route to add, what the friend told this computer (route hints), hiding this
/// computer's IP from them, and who carries their mail. Never the friend's security words or old code.
public struct FriendRoutesSheet: View {
    let address: String
    @EnvironmentObject private var model: AppModel

    public init(address: String) { self.address = address }

    public var body: some View {
        FriendRoutesBody(address: address, net: model.network)
    }
}

struct FriendRoutesBody: View {
    let address: String
    @ObservedObject var net: NetworkModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var internetDraft = ""
    @ViewState private var p2pDraft = ""
    @ViewState private var relaysDraft = ""
    @ViewState private var picked: Set<String>?

    var body: some View {
        let name = model.contact(address)?.name ?? Fallback.short(address)
        SheetFrame(tr(.networkRoutesTitle, ["name": name]), width: 580) {
            RScroll {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = net.routesError { ErrorNote(error) }
                    if let routes = net.routes[address] {
                        saved(routes)
                        addRoutes()
                        hints(routes, name: name)
                        Toggle(isOn: Binding(
                            get: { routes.hideIp == true },
                            set: { v in Task { await net.setRoutes(address, ["hide_ip": .bool(v)]) } }
                        )) {
                            Text(tr(.networkRoutesHideIp, ["name": name])).font(RFont.bodyBold)
                        }
                        .toggleStyle(RSwitchStyle())
                        carriers(routes, name: name)
                        mailFriends(routes, name: name)
                    } else if net.routesError == nil {
                        Spinner()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 460)
        } footer: {
            Button(tr(.commonClose)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
        .task { await net.loadRoutes(address) }
    }

    // MARK: Parts

    private func saved(_ routes: ContactRoutes) -> some View {
        PageSection(tr(.networkRoutesSaved)) {
            VStack(alignment: .leading, spacing: 0) {
                if routes.routes.isEmpty {
                    small(tr(.networkRoutesNone)).padding(.vertical, 8)
                }
                ForEach(Array(routes.routes.enumerated()), id: \.offset) { i, route in
                    if i > 0 { Rule() }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(route.label.map { Sanitizer.line($0, maxLength: 80) } ?? route.kind).font(RFont.bodyBold)
                            if let state = route.state { StateChip(state: state) }
                            Spacer(minLength: 8)
                            if ["lan", "internet", "p2p"].contains(route.kind) {
                                Button(tr(.networkRoutesRemove)) {
                                    Task { await net.setRoutes(address, ["clear": [.string(route.kind)]]) }
                                }
                                .buttonStyle(RButtonStyle(.secondary, compact: true))
                            }
                        }
                        if let value = route.value, !value.isEmpty {
                            Text(value).font(RFont.mono).lineLimit(1).truncationMode(.middle).selectable()
                        }
                        if let via = route.via, !via.isEmpty {
                            small(tr(.networkRoutesVia, ["relays": via.joined(separator: ", ")]))
                        }
                        if let next = route.next, !next.isEmpty { small(tr(.networkRoutesNext, ["id": next])) }
                        if route.kind == "lan" { lanNow(routes) }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                }
                if !routes.routes.contains(where: { $0.kind == "lan" }) {
                    lanNow(routes).padding(.vertical, routes.lanNow == nil ? 0 : 8)
                }
            }
        }
    }

    /// The address Raven reaches the friend at on the local network now, and when the saved one is
    /// old (or there is none), the button that saves the new one.
    @ViewBuilder private func lanNow(_ routes: ContactRoutes) -> some View {
        let name = model.contact(address)?.name ?? Fallback.short(address)
        if let lines = Display.lanNow(routes, name: name, now: model.now), let lan = routes.lanNow {
            small(lines.reached)
            if let stale = lines.stale { small(stale) }
            if lines.stale != nil || !routes.routes.contains(where: { $0.kind == "lan" }) {
                Button(tr(.networkRoutesLanReplace)) { Task { await net.useLanNow(address, lan.addr) } }
                    .buttonStyle(RButtonStyle(.secondary, compact: true))
                    .padding(.top, 2)
            }
        }
    }

    private func addRoutes() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RField(tr(.networkRoutesInternet), text: $internetDraft, mono: true) { saveInternet() }
                Button(tr(.networkSave)) { saveInternet() }
                    .buttonStyle(RButtonStyle(.secondary, compact: true))
                    .disabled(internetDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                RField(tr(.networkRoutesP2p), text: $p2pDraft, mono: true)
                RField(tr(.networkRoutesRelays), text: $relaysDraft, mono: true) { saveP2p() }
                Button(tr(.networkSave)) { saveP2p() }
                    .buttonStyle(RButtonStyle(.secondary, compact: true))
                    .disabled(p2pDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func hints(_ routes: ContactRoutes, name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                SectionLabel(tr(.networkRoutesHints, ["name": name]))
                if let state = routes.carriers?.hints { StateChip(state: state) }
            }
            if let learned = routes.learned {
                let until = learned.expiresAtMs.map { TimeText.deadline(ms: $0, now: model.now) } ?? "–"
                small(tr(.networkRoutesHintsCounts, ["relays": String(learned.relays ?? 0), "direct": String(learned.direct ?? 0),
                                                     "mail": String(Display.mailFriendCount(routes)), "time": until]))
                if let id = learned.peerId, !id.isEmpty {
                    // Only a proven ID gets a word: "not proven yet" was nothing the user could act on (E1).
                    let proven = learned.peerIdProven == true ? " · " + tr(.networkRoutesPeerIdProven) : ""
                    small(tr(.networkRoutesPeerId, ["id": id]) + proven)
                }
            } else {
                small(tr(.networkRoutesHintsNone, ["name": name]))
            }
        }
    }

    private func carriers(_ routes: ContactRoutes, name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(tr(.networkRoutesCarriers, ["name": name]))
            let told = routes.carriers?.told ?? []
            if !told.isEmpty {
                let names = told.map { f -> String in
                    let n = friendName(f)
                    return f.takesHandoffs == true ? tr(.networkRoutesTakesHandoffs, ["friend": n]) : n
                }
                small(tr(.networkRoutesTold, ["name": name, "friends": names.joined(separator: ", ")]))
            }
            if let unknown = routes.carriers?.toldUnknown, unknown > 0 {
                small(tr(.networkRoutesToldUnknown, ["name": name, "n": String(unknown)]))
            }
            ForEach(Array(Display.awayLines(routes, name: name, now: model.now).enumerated()), id: \.offset) { _, line in
                small(line)
            }
            if routes.carriers?.receiptsStranded == true {
                small(tr(.networkRoutesStranded, ["name": name]))
            }
        }
    }

    private func mailFriends(_ routes: ContactRoutes, name: String) -> some View {
        let listed = routes.carriers?.listed ?? []
        let chosen = picked ?? Set(listed.compactMap(\.address))
        let candidates = model.contacts.filter { $0.verified && $0.address != address }
        return VStack(alignment: .leading, spacing: 4) {
            SectionLabel(tr(.networkRoutesMailFriends, ["name": name]))
            if listed.isEmpty {
                small(tr(.networkRoutesListedNone))
            } else {
                let names = listed.map { f -> String in
                    f.usable == false ? tr(.networkRoutesNotUsable, ["friend": friendName(f)]) : friendName(f)
                }
                small(tr(.networkRoutesListed, ["name": name, "friends": names.joined(separator: ", ")]))
            }
            if !candidates.isEmpty {
                small(tr(.networkRoutesListedPick))
                ForEach(candidates) { c in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(c.address) },
                        set: { on in
                            var next = chosen
                            if on { next.insert(c.address) } else { next.remove(c.address) }
                            picked = next
                        }
                    )) {
                        Text(c.name)
                    }
                    .toggleStyle(RSwitchStyle())
                    .disabled(!chosen.contains(c.address) && chosen.count >= 2)
                }
                Button(tr(.networkSave)) {
                    let list = chosen.sorted()
                    Task { if await net.setRoutes(address, ["custodians": .array(list.map { .string($0) })]) { picked = nil } }
                }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .disabled(picked == nil)
            }
        }
    }

    // MARK: Helpers

    private func friendName(_ f: FriendRef) -> String {
        if let n = f.name.map({ Sanitizer.line($0, maxLength: 64) }), !n.isEmpty { return n }
        if let a = f.address { return model.contact(a)?.name ?? Fallback.short(a) }
        return "–"
    }

    private func small(_ text: String) -> some View {
        Text(text).font(RFont.smallish).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func saveInternet() {
        let value = internetDraft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        Task { if await net.setRoutes(address, ["internet": .string(value)]) { internetDraft = "" } }
    }

    private func saveP2p() {
        let id = p2pDraft.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        // One per line or separated by commas (network.routes.relays), as on Linux and Windows.
        let relays = relaysDraft.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var changes: [String: JSONValue] = ["p2p": .string(id)]
        if !relays.isEmpty { changes["via"] = .array(relays.map { .string($0) }) }
        Task {
            if await net.setRoutes(address, changes) {
                p2pDraft = ""
                relaysDraft = ""
            }
        }
    }
}
