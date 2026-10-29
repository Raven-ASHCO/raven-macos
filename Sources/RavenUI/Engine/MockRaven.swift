#if DEBUG || RAVEN_MOCK
import Foundation

/// An in-memory engine that follows desktop/api/API.md, for the demo, snapshots and tests. Compiled
/// only in debug builds (or with `-DRAVEN_MOCK`), and the app runs on it only when asked
/// (`EngineFactory`: a demo build, or `RAVEN_DEMO=1`).
///
/// Demo data: Ali (verified, in touch), Mina (one message waiting until a deadline) and Rena (not
/// verified). After setup, the first `events.poll` starts the demo stream of the design mockup:
///
///     every 2 s  status_ok
///     +1.2 s     incoming from Ali                       (packet in, bubble slides in)
///     +2.6 s     presence + incoming from Rena           (unread badge)
///     +4.0 s     retry on Mina's waiting message         (retry ring)
///     +4.5 s     a demo send to Ali: send_started        (packet out)
///     +5.3 s     state: sent                             ("Sent, not confirmed yet")
///     +6.0 s     receipt, signed                         (receipt back, "Delivered")
///     +10.5 s    presence: Mina in touch                 (dot blinks)
///     +10.8 s    send_started for Mina's waiting message
///     +11.3 s    receipt: Mina's waiting message delivered ("Mina is back")
///
/// Messages the user sends get send_started -> state sent -> receipt for friends in touch, and
/// waiting for the others. The friends' security words and old codes live only in here and are never
/// returned. Rena (not verified) also has an old-style code, for `verify.check_old_code`.
///
/// Privacy: `privacy.state` says `available: false`; `privacy.lock`, `unlock`, `encrypt` and `erase`
/// answer `NOT_AVAILABLE_YET` (API.md), as the engine does until the privacy pack lands.
///
/// Network: by default the answers of a release build (API.md "Mocks"): LAN direct on, every other
/// way `preview`. `network: .lab` answers as a developer build started with the lab switches in
/// `labSwitches` (`RAVEN_MOCK_NETWORK=lab` in the demo): Internet direct, port mapping, p2p, friend
/// custody, handoff and route hints open (`lab` or `off`), Bluetooth nearby `not_on_this_os`, the
/// consent settings refused without `agreed` (CONSENT_NEEDED), settings that apply at a restart
/// saying `restart_needed`, Lock v2 with a passphrase, one security notice, and messages that came
/// over a relay or wait with a friend.
///
/// Calls arrive through `call`, which runs the blocking `rawCall` on `EngineQueue` (never on the main
/// thread), as `RavenClientEngine` runs `raven_call`.
public final class MockRaven: RavenEngine, @unchecked Sendable {
    public enum Start: Sendable { case new, ready, locked }
    /// Which build's network answers the mock gives (see above).
    public enum NetworkMode: Sendable { case release, lab }

    public static let meAddress = "rvn1qq0fx52rlh7hg0uxj8rc9etdtg5g8zxpl3649znp"
    public static let aliAddress = "rvn1qtnu9xwlc92xuxjx4fpjtjdgawyazdw46tdnu8kt"
    public static let minaAddress = "rvn1qw7ms09fye5nfrfpvttjxzquwsaz72j8je0sk94q"
    public static let renaAddress = "rvn1qc0cjpdml8z5wrqq392ly4s70tw2gh3t5tgehgx3"
    /// The demo identity's words (reference vector "alice" of the security-words prototype).
    public static let myWords = ["turtle", "frog", "bread", "wolf", "paper", "laptop", "funnel", "mango", "honey", "wagon"]
    public static let myOldCode = "If4x-36FU-omFi"
    static let myPubHex = "062acd9f614d418d6e7b54b387f52772e4397949061acfad1aaf1959e77c6e1a"
    /// Friends' words, valid under the check word. Only used to answer verify.check_words.
    public static let aliWords = ["anchor", "basket", "candle", "eagle", "garden", "helmet", "island", "jacket", "kettle", "milk"]
    static let minaWords = ["apple", "bamboo", "beach", "beetle", "bicycle", "almond", "apron", "badger", "barrel", "phone"]
    static let renaWords = ["airport", "ball", "banana", "battery", "bed", "belt", "baby", "basket", "anchor", "eagle"]
    /// Rena's old-style code (the same demo value in all three apps' mocks). Only used to answer
    /// verify.check_old_code.
    public static let renaOldCode = "Tq7m-29Xa-hKe4"
    /// The demo group's member who is not your friend (the admin's name for them: Sam).
    public static let samAddress = "rvn1qd4n7sxk0mq2f8wlt3e9v6ar5yh2pc8gz7u4jn"
    /// The demo group "Book club": you are its admin; Ali, Mina and Sam are in it.
    public static let bookClubID = "b00c1ab0b00c1ab0b00c1ab0b00c1ab0"
    /// API.md "Groups": at most 16 members, you included.
    public static let groupMaxMembers = 16
    public static let thisComputer = "192.168.1.20"
    public static let lanPath = "LAN direct"
    /// The stable kind of `lanPath` (API.md, Message `path_kind`).
    public static let lanKind = "lan"
    /// Lab mode: the switches the mock's "engine" sees, the ways they open, and the Raven passphrase
    /// Lock v2 asks for.
    public static let labSwitches = ["RAVEN_LAB_LOCAL_PROTECTION", "RAVEN_LAB_ROUTE_HINTS",
                                     "RAVEN_LAB_SECURITY_EVENTS", "RAVEN_LAB_TEST_A", "RAVEN_LAB_TOR"]
    public static let labWays: Set<String> = ["internet", "port_mapping", "p2p", "custody", "handoff", "route_hints",
                                              "lock_v2", "security_events", "tor"]
    /// The lab mock's Tor line from raven-node (states only), and its parts (API.md "The Tor way").
    public static let labTorWords = "ready (onion service outages since start: 1, the last lasted 2 min and ended 1 h ago)"
    public static let labTorOutages = "onion service outages since start: 1, the last lasted 2 min and ended 1 h ago"
    public static let labPassphrase = "max and lily"
    public static let relayAddress = "/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWQzRelayDemo4vX8nP2kLm9sT"

    public let clock: MockClock
    public let network: NetworkMode
    let demo: Bool
    let identityDelay: TimeInterval

    private let lock = NSLock()
    private var profile: ProfileStateKind
    private var identity: Identity?
    private var contacts: [Contact] = []
    private var friendWords: [String: [String]] = [:]
    private var friendOldCodes: [String: String] = [:]
    private var mainThreadCalls = 0
    private var messages: [Message] = []
    /// Per friend (by address): the newest message read (`messages.mark_read`), as the engine keeps the
    /// read markers it shares with the terminal app.
    private var readUpTo: [String: String] = [:]
    private var settings = RavenSettings()
    private var node: NodeStatus
    private var events: [JSONValue] = []
    private var seq = 0
    private var timeline: [Scheduled] = []
    private var order = 0
    private var scriptStarted = false
    private var lastStatusOk: Date?
    private var nextID = 100
    /// The mock's network settings (a release build's: only LAN direct is on).
    private var lanOff = false
    private var hideIp = false
    private var helpFlags = (bridge: true, store: true, relay: false, automatic: true)
    /// Per friend (by address): an Internet route, a p2p route, mail friends, hide my IP.
    private var friendRoutes: [String: (internet: String?, p2p: String?, mailFriends: [String], hideIp: Bool)] = [:]
    /// Lab mode: the person's settings (`network.set` names) and Lock v2.
    private var labSettings: [String: Bool] = ["internet": false, "port_mapping": false, "p2p": true,
                                               "friends_carry_mine": false, "carry_for_friends": false, "handoff": false]
    private var lanUntilMs: Int64?
    private var lockedV2 = false
    /// Groups: on in the demo (`groups.list` says `available`), off when a test turns them off.
    public var groupsOn = true
    private struct MockMember {
        var address: String
        var name: String
        var label: String
        var friend: Bool
        var admin: Bool
        var me: Bool
    }
    private struct MockGroup {
        var id: String
        var name: String
        var admin: String
        var status = "active"
        var members: [MockMember]
        var readMs: Int64
        var messages: [GroupMessage]
    }
    private var mockGroups: [MockGroup] = []
    private var managedNode = false

    private struct Scheduled {
        let at: Date
        let order: Int
        let action: (MockRaven, Date) -> Void
    }

    public init(start: Start = .ready, demo: Bool = true, clock: MockClock = MockClock(), identityDelay: TimeInterval = 0.9,
                network: NetworkMode = .release) {
        self.clock = clock
        self.demo = demo
        self.identityDelay = identityDelay
        self.network = network
        let now = clock.now
        let lab = network == .lab
        // A lab build starts with p2p switched on (and running once raven-node runs); a release build
        // has nothing but LAN.
        labSettings["p2p"] = lab
        let carriers = Carriers(lan: "on", internet: lab ? "on" : "preview", p2p: lab ? "on" : "preview",
                                custody: lab ? "on" : "preview", nearby: "preview")
        node = NodeStatus(running: false, startedByApp: false, pid: nil, listening: nil, receive: false,
                          address: MockRaven.thisComputer, lastOkMs: now.ms, build: "dev", carriers: carriers)
        node.lab = lab ? MockRaven.labWays.sorted() : []
        node.labSwitches = lab ? MockRaven.labSwitches : []
        switch start {
        case .new:
            profile = .new
        case .ready, .locked:
            profile = start == .ready ? .ready : .locked
            identity = Identity(displayName: nil, address: MockRaven.meAddress, words: MockRaven.myWords, oldCode: MockRaven.myOldCode)
            settings.receive = true
            node.running = true
            node.startedByApp = true
            node.pid = 4242
            node.receive = true
            node.listening = "0.0.0.0:7420"
            seedFriends(now: now)
        }
    }

    // MARK: Boundary

    public func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        let response = await EngineQueue.run(RavenEnvelope.request(op: op, args: args)) { [self] request in
            self.rawCall(request)
        }
        return try RavenEnvelope.parseResponse(response)
    }

    /// `raven_call` as the app sees it: blocking (creating the identity takes `identityDelay`), and
    /// called on `EngineQueue`.
    func rawCall(_ request: String) -> String {
        if Thread.isMainThread {
            lock.lock()
            mainThreadCalls += 1
            lock.unlock()
        }
        if identityDelay > 0, (try? RavenEnvelope.parseRequest(request))?.op == "identity.create" {
            Thread.sleep(forTimeInterval: identityDelay)
        }
        return handle(request)
    }

    /// Makes `node.stop` answer as for a raven-node a login service runs (`stop: managed`, left
    /// running), as on a computer where `raven` installed the login item.
    public func runNodeAsLoginService(_ on: Bool = true) {
        lock.lock()
        managedNode = on
        lock.unlock()
    }

    /// How many calls through `call` ran on the main thread (tests expect none).
    public var callsOnMainThread: Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadCalls
    }

    /// The Swift twin of `raven_call`: a request envelope in, a response envelope out, never throws.
    public func handle(_ requestJSON: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        do {
            let (op, args) = try RavenEnvelope.parseRequest(requestJSON)
            advance()
            return RavenEnvelope.success(try dispatch(op, args))
        } catch let e as RavenError {
            return RavenEnvelope.failure(e)
        } catch {
            return RavenEnvelope.failure(.internalError(String(describing: error)))
        }
    }

    // MARK: Operations

    private func dispatch(_ op: String, _ args: [String: JSONValue]) throws -> JSONValue {
        let now = clock.now
        switch op {
        case "app.info":
            return ["version": "0.1.0", "build": "dev", "platform": "macos"]
        case "profile.state":
            return ["state": .string(profile.rawValue)]
        case "identity.create":
            guard profile == .new else { throw RavenError.badRequest("identity already exists") }
            let name = args["display_name"]?.string.map { Sanitizer.line($0, maxLength: 64) }.flatMap { $0.isEmpty ? nil : $0 }
            identity = Identity(displayName: name, address: MockRaven.meAddress, words: MockRaven.myWords, oldCode: MockRaven.myOldCode)
            settings.displayName = name
            profile = .ready
            if demo { seedFriends(now: now) }
            return ["address": .string(MockRaven.meAddress), "words": .array(MockRaven.myWords.map { .string($0) }),
                    "old_code": .string(MockRaven.myOldCode)]
        case "privacy.state":
            return try JSONValue.encode(PrivacyState(available: false, encrypted: false, locked: profile == .locked))
        case "privacy.lock", "privacy.unlock", "privacy.encrypt":
            throw notAvailableYet(op)
        case "privacy.erase":
            guard args["confirm"]?.string == "erase" else { throw RavenError.badRequest("privacy.erase needs confirm: \"erase\"") }
            throw notAvailableYet(op)
        default:
            break
        }

        // Everything else needs a ready profile.
        switch profile {
        case .new, .unreadable: throw notInitialized()
        case .locked: throw RavenError(code: ErrorCode.profileLocked, message: tr(.errorProfileLocked), detail: "op=\(op)")
        case .ready: break
        }

        switch op {
        case "identity.me":
            let me = try requireIdentity()
            let card = makeCard(includeAddress: false)
            return ["display_name": .opt(me.displayName), "address": .string(me.address),
                    "words": .array(me.words.map { .string($0) }), "old_code": .string(me.oldCode),
                    "card": .string(card.card), "invite": .string(card.invite)]
        case "card.make":
            let card = makeCard(includeAddress: args["include_address"]?.bool ?? false)
            return ["card": .string(card.card), "invite": .string(card.invite), "address_included": .opt(card.included)]
        case "card.parse":
            let parsed = try parseCard(args["text"]?.string ?? "")
            var routes: [JSONValue] = []
            if parsed.lan != nil { routes.append(["kind": "lan", "label": .string(tr(.netLan)), "preview": false]) }
            routes.append(["kind": "internet", "label": .string(tr(.netInternet)), "preview": true])
            // As a release engine: a card's internet and p2p addresses are left out (nothing signs them).
            return ["short_address": .string(MockRaven.short(parsed.address)), "has_address": .bool(parsed.lan != nil),
                    "routes": .array(routes), "ignored_routes": .array(parsed.ignored.map { .string($0) }),
                    "note": parsed.ignored.isEmpty ? .null
                        : .string("note: Raven ignored this card's addresses: no key signs a card's addresses")]
        case "contacts.list":
            return ["contacts": .array(try contacts.map { try JSONValue.encode(withUnread($0)) })]
        case "contacts.add":
            return ["contact": try JSONValue.encode(try addContact(text: args["text"]?.string ?? "", name: args["name"]?.string ?? ""))]
        case "contacts.rename":
            let i = try contactIndex(args["address"]?.string)
            let name = Sanitizer.line(args["name"]?.string ?? "", maxLength: 64)
            try checkNameFree(name, except: contacts[i].address)
            contacts[i].name = name
            return ["contact": try JSONValue.encode(withUnread(contacts[i]))]
        case "contacts.remove":
            let i = try contactIndex(args["address"]?.string)
            let address = contacts[i].address
            contacts.remove(at: i)
            messages.removeAll { $0.address == address }
            friendWords[address] = nil
            friendOldCodes[address] = nil
            return [:]
        case "contacts.set_address":
            let i = try contactIndex(args["address"]?.string)
            contacts[i].lan = args["lan"]?.string
            if contacts[i].presence == .noAddress { contacts[i].presence = .none }
            return ["contact": try JSONValue.encode(withUnread(contacts[i]))]
        case "verify.check_words":
            let i = try contactIndex(args["address"]?.string)
            let typed = (args["words"]?.array ?? []).compactMap { $0.string }
            let result = try checkWords(typed, against: friendWords[contacts[i].address] ?? [])
            if result == .match { contacts[i].verified = true }
            return ["result": .string(result.rawValue)]
        case "verify.check_old_code":
            guard args["address"]?.string != nil else { throw RavenError.badRequest("verify.check_old_code needs address") }
            let i = try contactIndex(args["address"]?.string)
            let typed = WordInput.oldCodeKey(args["code"]?.string ?? "")
            guard !typed.isEmpty else { throw RavenError.badRequest("verify.check_old_code needs code") }
            let want = Array((friendOldCodes[contacts[i].address].map(WordInput.oldCodeKey) ?? "").utf8)
            let got = Array(typed.utf8)
            // Case-sensitive; compare every byte, without stopping early.
            var same = !want.isEmpty && want.count == got.count
            for (a, b) in zip(want, got) where a != b { same = false }
            if same { contacts[i].verified = true }
            return ["result": same ? "match" : "mismatch"]
        case "verify.word_hint":
            if let word = MockWordList.shared.hint(args["prefix"]?.string ?? "") { return ["word": .string(word)] }
            return [:]
        case "messages.history":
            let address = try contacts[contactIndex(args["address"]?.string)].address
            var list = messages.filter { $0.address == address }.sorted { $0.atMs < $1.atMs }
            if let before = args["before"]?.string, let cut = list.firstIndex(where: { $0.id == before }) {
                list = Array(list[..<cut])
            }
            let limit = max(1, args["limit"]?.int ?? 100)
            return ["messages": .array(try list.suffix(limit).map { try JSONValue.encode($0) })]
        case "messages.send":
            return ["message": try JSONValue.encode(try send(to: args["address"]?.string, text: args["text"]?.string ?? "", now: now))]
        case "messages.retry":
            return ["message": try JSONValue.encode(try retry(args["id"]?.string, now: now))]
        case "messages.stop":
            let i = try messageIndex(args["id"]?.string)
            messages[i].state = .failed
            emit("state", at: now, ["id": .string(messages[i].id), "state": "failed"])
            recountWaiting(messages[i].address)
            return ["message": try JSONValue.encode(messages[i])]
        case "messages.mark_read":
            let address = try contacts[contactIndex(args["address"]?.string)].address
            let list = chat(address)
            var end = list.count
            if let id = args["id"]?.string {
                guard let at = list.firstIndex(where: { $0.id == id }) else {
                    throw RavenError(code: ErrorCode.badRequest, message: "That message isn't on this computer anymore.",
                                     detail: "no message \(id) with this friend")
                }
                end = at + 1
            }
            let before = unreadCount(address)
            let marked = readUpTo[address].flatMap { id in list.firstIndex { $0.id == id } } ?? -1
            // Never back.
            if end - 1 > marked, end > 0 { readUpTo[address] = list[end - 1].id }
            let after = unreadCount(address)
            if after != before { emit("unread", at: now, ["address": .string(address), "unread": .int(after)]) }
            return ["address": .string(address), "unread": .int(after)]
        case "messages.delete":
            let i = try messageIndex(args["id"]?.string)
            let m = messages[i]
            guard m.direction == .outgoing, [.failed, .timeRanOut, .notSentMeetFirst].contains(m.state) else {
                throw RavenError(code: ErrorCode.badRequest,
                                 message: "Only a message that wasn't sent can be deleted. Stop a waiting message first.",
                                 detail: "message \(m.id) is \(m.state.rawValue)")
            }
            messages.remove(at: i)
            return ["id": .string(m.id), "deleted": true]
        case "messages.details":
            return try details(args["id"]?.string, now: now)
        case "node.status":
            return try JSONValue.encode(node)
        case "node.start":
            if !node.running {
                node.running = true
                node.startedByApp = true
                node.pid = 4242
                node.receive = settings.receive
                node.listening = nil
                emit("node", at: now, ["status": try JSONValue.encode(node)])
                if settings.receive {
                    schedule(at: now.addingTimeInterval(1.5)) { m, at in
                        guard m.node.running, m.settings.receive else { return }
                        m.node.listening = "0.0.0.0:7420"
                        m.node.lastOkMs = at.ms
                        m.emit("node", at: at, ["status": (try? JSONValue.encode(m.node)) ?? .null])
                    }
                }
            }
            return try JSONValue.encode(node)
        case "node.stop":
            if managedNode && node.running {
                // A login service runs it: left running (API.md, Node).
                var v = try JSONValue.encode(node)
                v["stop"] = "managed"
                v["note"] = "A login service runs Raven's background program; it was left running. Restart it with: raven node restart"
                return v
            }
            let was = node.running
            node.running = false
            node.listening = nil
            node.pid = nil
            node.startedByApp = false
            lockedV2 = false
            emit("node", at: now, ["status": try JSONValue.encode(node)])
            var v = try JSONValue.encode(node)
            v["stop"] = .string(was ? "stopped" : "not_running")
            return v
        case "settings.get":
            return try JSONValue.encode(settings)
        case "settings.set":
            try applySettings(args, now: now)
            return try JSONValue.encode(settings)
        case "events.poll":
            if demo && !scriptStarted { startScript(at: now) }
            let after = args["after_seq"]?.int ?? 0
            let fresh = events.filter { ($0["seq"]?.int ?? 0) > after }
            return ["seq": .int(seq), "events": .array(fresh)]
        case "network.status":
            return networkStatus()
        case "network.set":
            return try setNetwork(args)
        case "network.check":
            return networkCheck(router: args["router"]?.bool ?? false)
        case "contacts.routes":
            return try contactRoutes(args["address"]?.string)
        case "contacts.set_routes":
            return try setContactRoutes(args)
        case "security.status":
            return securityStatus()
        case "lock.state":
            return lockState()
        case "lock.now":
            guard network == .lab else { throw lockHeld(op) }
            guard node.running else { throw lockUnsupported() }
            lockedV2 = true
            return lockState()
        case "lock.unlock":
            guard network == .lab else { throw lockHeld(op) }
            guard node.running else { throw lockUnsupported() }
            guard let pass = args["passphrase"]?.string, !pass.isEmpty else {
                throw RavenError(code: ErrorCode.passphraseNeeded, message: tr(.errorPassphraseNeeded), detail: "lock.unlock: no passphrase")
            }
            guard pass == MockRaven.labPassphrase else {
                throw RavenError(code: ErrorCode.passphraseWrong, message: tr(.errorPassphraseWrong), detail: "lock.unlock: wrong passphrase")
            }
            lockedV2 = false
            var v = lockState()
            v["note"] = "Unlocked."
            return v
        case "groups.list", "groups.get", "groups.create", "groups.add", "groups.remove", "groups.leave",
             "groups.history", "groups.send", "groups.mark_read":
            return try groupDispatch(op, args, now: now)
        case "updates.status":
            return updatesStatus()
        default:
            throw RavenError.badRequest("unknown op \(op)")
        }
    }

    // MARK: Groups (API.md, "Groups")

    private func seedGroups(nowMs: Int64) {
        let me = MockMember(address: MockRaven.meAddress, name: tr(.youTitle), label: "", friend: false, admin: true, me: true)
        let ali = MockMember(address: MockRaven.aliAddress, name: "Ali", label: "Ali", friend: true, admin: false, me: false)
        let mina = MockMember(address: MockRaven.minaAddress, name: "Mina", label: "Mina", friend: true, admin: false, me: false)
        let sam = MockMember(address: MockRaven.samAddress, name: "Sam", label: "Sam", friend: false, admin: false, me: false)
        let id = MockRaven.bookClubID
        mockGroups = [MockGroup(id: id, name: "Book club", admin: MockRaven.meAddress, members: [me, ali, mina, sam],
                                readMs: nowMs - 45 * 60_000, messages: [
            GroupMessage(id: "g1", group: id, fromAddress: MockRaven.aliAddress, fromName: "Ali", mine: false,
                         text: "Chapter four by Friday?", atMs: nowMs - 50 * 60_000),
            GroupMessage(id: "g2", group: id, fromAddress: MockRaven.samAddress, fromName: "Sam", mine: false,
                         text: "Friday evening works for me.", atMs: nowMs - 42 * 60_000, viaName: "Ali"),
            GroupMessage(id: "g3", group: id, fromAddress: MockRaven.meAddress, fromName: tr(.youTitle), mine: true,
                         text: "Friday it is. I'll bring tea.", atMs: nowMs - 40 * 60_000, delivered: 2, total: 3,
                         receipts: [GroupReceipt(address: MockRaven.aliAddress, name: "Ali", state: "delivered"),
                                    GroupReceipt(address: MockRaven.minaAddress, name: "Mina", state: "delivered"),
                                    GroupReceipt(address: MockRaven.samAddress, name: "Sam", state: "sent", via: "relay")]),
        ])]
    }

    private func groupJSON(_ g: MockGroup) throws -> JSONValue {
        let unread = g.messages.filter { !$0.mine && $0.atMs > g.readMs }.count
        let last = g.messages.last
        let admin = g.members.first { $0.admin }
        return try JSONValue.encode(RavenGroup(id: g.id, name: g.name, shortId: String(g.id.prefix(8)), status: g.status,
                                               admin: g.admin == MockRaven.meAddress, adminAddress: g.admin,
                                               adminName: admin?.name ?? "", members: g.members.count, unread: unread,
                                               lastMs: last?.atMs, lastText: last?.text, lastFrom: last?.fromName))
    }

    private func membersJSON(_ g: MockGroup) throws -> JSONValue {
        .array(try g.members.map {
            try JSONValue.encode(GroupMember(address: $0.address, shortAddress: MockRaven.short($0.address), name: $0.name,
                                             label: $0.label, friend: $0.friend, admin: $0.admin, me: $0.me))
        })
    }

    private func groupIndex(_ id: String?) throws -> Int {
        guard let id, let i = mockGroups.firstIndex(where: { $0.id == id }) else {
            throw RavenError(code: ErrorCode.groupNotFound, message: tr(.errorGroupNotFound), detail: id ?? "no group")
        }
        return i
    }

    private func groupAndMembers(_ i: Int) throws -> JSONValue {
        ["group": try groupJSON(mockGroups[i]), "members": try membersJSON(mockGroups[i])]
    }

    /// The friends a request names, as members (each must be your friend).
    private func friendMembers(_ value: JSONValue?) throws -> [MockMember] {
        guard let list = value?.array else { throw RavenError.badRequest("\"members\" must be a list of addresses") }
        return try list.map { item in
            guard let address = item.string, let c = contacts.first(where: { $0.address == address }) else {
                throw RavenError(code: ErrorCode.notAContact, message: tr(.errorNotAContact), detail: item.string ?? "")
            }
            return MockMember(address: c.address, name: c.name, label: c.name, friend: true, admin: false, me: false)
        }
    }

    private func groupDispatch(_ op: String, _ args: [String: JSONValue], now: Date) throws -> JSONValue {
        guard groupsOn else {
            if op == "groups.list" { return ["available": false, "groups": .array([])] }
            throw RavenError(code: ErrorCode.notAvailableYet, message: tr(.errorNotAvailableYet), detail: op)
        }
        switch op {
        case "groups.list":
            return ["available": true, "groups": .array(try mockGroups.map(groupJSON))]
        case "groups.get":
            return try groupAndMembers(try groupIndex(args["group"]?.string))
        case "groups.create":
            let name = Sanitizer.line(args["name"]?.string ?? "", maxLength: 64)
            guard !name.isEmpty else {
                throw RavenError(code: ErrorCode.groupBadName, message: tr(.errorGroupBadName), detail: "empty name")
            }
            var members = try friendMembers(args["members"])
            members = members.enumerated().filter { i, m in !members[..<i].contains { $0.address == m.address } }.map(\.element)
            guard !members.isEmpty else { throw RavenError.badRequest("\"members\" names no friend") }
            guard members.count + 1 <= MockRaven.groupMaxMembers else {
                throw RavenError(code: ErrorCode.groupTooLarge, message: tr(.errorGroupTooLarge), detail: "\(members.count + 1)")
            }
            let me = MockMember(address: MockRaven.meAddress, name: tr(.youTitle), label: "", friend: false, admin: true, me: true)
            nextID += 1
            let id = String(format: "%032x", nextID)
            mockGroups.append(MockGroup(id: id, name: name, admin: MockRaven.meAddress, members: [me] + members,
                                        readMs: now.ms, messages: []))
            return try groupAndMembers(mockGroups.count - 1)
        case "groups.add":
            let i = try groupIndex(args["group"]?.string)
            guard mockGroups[i].admin == MockRaven.meAddress else {
                throw RavenError(code: ErrorCode.groupNotAdmin, message: tr(.errorGroupNotAdmin), detail: "not the admin")
            }
            let add = try friendMembers(args["members"]).filter { m in !mockGroups[i].members.contains { $0.address == m.address } }
            guard mockGroups[i].members.count + add.count <= MockRaven.groupMaxMembers else {
                throw RavenError(code: ErrorCode.groupTooLarge, message: tr(.errorGroupTooLarge),
                                 detail: "\(mockGroups[i].members.count + add.count)")
            }
            mockGroups[i].members += add
            return try groupAndMembers(i)
        case "groups.remove":
            let i = try groupIndex(args["group"]?.string)
            guard mockGroups[i].admin == MockRaven.meAddress else {
                throw RavenError(code: ErrorCode.groupNotAdmin, message: tr(.errorGroupNotAdmin), detail: "not the admin")
            }
            let member = args["member"]?.string ?? ""
            guard member != MockRaven.meAddress else {
                throw RavenError(code: ErrorCode.groupAdminCannotLeave, message: tr(.errorGroupAdminCannotLeave), detail: "admin")
            }
            mockGroups[i].members.removeAll { $0.address == member }
            return try groupAndMembers(i)
        case "groups.leave":
            let i = try groupIndex(args["group"]?.string)
            guard mockGroups[i].admin != MockRaven.meAddress else {
                throw RavenError(code: ErrorCode.groupAdminCannotLeave, message: tr(.errorGroupAdminCannotLeave), detail: "admin")
            }
            mockGroups[i].status = "left"
            return ["group": try groupJSON(mockGroups[i])]
        case "groups.history":
            let i = try groupIndex(args["group"]?.string)
            var list = mockGroups[i].messages
            if let before = args["before"]?.string, let cut = list.firstIndex(where: { $0.id == before }) {
                list = Array(list[..<cut])
            }
            let limit = min(500, max(1, args["limit"]?.int ?? 100))
            return ["messages": .array(try list.suffix(limit).map { try JSONValue.encode($0) })]
        case "groups.send":
            let i = try groupIndex(args["group"]?.string)
            guard mockGroups[i].status == "active" else {
                throw RavenError(code: ErrorCode.groupNotMember, message: tr(.errorGroupNotMember), detail: mockGroups[i].status)
            }
            let text = args["text"]?.string ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RavenError.badRequest("empty") }
            guard text.utf8.count <= 8192 else {
                throw RavenError(code: ErrorCode.messageTooLong, message: tr(.errorMessageTooLong), detail: "\(text.utf8.count) bytes")
            }
            nextID += 1
            let others = mockGroups[i].members.filter { !$0.me }
            let receipts = others.map { GroupReceipt(address: $0.address, name: $0.name, state: "waiting",
                                                     via: $0.friend ? "direct" : "relay") }
            let m = GroupMessage(id: "g\(nextID)", group: mockGroups[i].id, fromAddress: MockRaven.meAddress,
                                 fromName: tr(.youTitle), mine: true, text: text, atMs: now.ms, delivered: 0,
                                 total: receipts.count, receipts: receipts)
            mockGroups[i].messages.append(m)
            // Each copy goes like a message: friends in touch confirm, the others' copies wait.
            let gid = mockGroups[i].id
            for (k, r) in receipts.enumerated() {
                let contact = contacts.first { $0.address == r.address }
                schedule(at: now.addingTimeInterval(0.4 + Double(k) * 0.3)) { mock, t in
                    mock.setGroupReceipt(gid, message: m.id, member: r.address, state: "sent", at: t)
                }
                if contact?.presence == .inTouch {
                    schedule(at: now.addingTimeInterval(0.9 + Double(k) * 0.35)) { mock, t in
                        mock.setGroupReceipt(gid, message: m.id, member: r.address, state: "delivered", at: t)
                    }
                }
            }
            return ["message": try JSONValue.encode(m)]
        case "groups.mark_read":
            let i = try groupIndex(args["group"]?.string)
            mockGroups[i].readMs = now.ms
            return ["group": .string(mockGroups[i].id), "unread": 0]
        default:
            throw RavenError.badRequest("unknown op \(op)")
        }
    }

    private func setGroupReceipt(_ group: String, message: String, member: String, state: String, at: Date) {
        guard let i = mockGroups.firstIndex(where: { $0.id == group }),
              let j = mockGroups[i].messages.firstIndex(where: { $0.id == message }),
              let k = mockGroups[i].messages[j].receipts?.firstIndex(where: { $0.address == member }),
              mockGroups[i].messages[j].receipts?[k].state != "delivered" else { return }
        mockGroups[i].messages[j].receipts?[k].state = state
        mockGroups[i].messages[j].delivered = mockGroups[i].messages[j].receipts?.filter { $0.state == "delivered" }.count ?? 0
        emit("group_changed", at: at, ["group": .string(group)])
    }

    private func receiveGroup(_ group: String, from address: String, text: String, at: Date) {
        guard let i = mockGroups.firstIndex(where: { $0.id == group }),
              let member = mockGroups[i].members.first(where: { $0.address == address }) else { return }
        nextID += 1
        let m = GroupMessage(id: "g\(nextID)", group: group, fromAddress: address, fromName: member.name, mine: false,
                             text: text, atMs: at.ms)
        mockGroups[i].messages.append(m)
        emit("group_message", at: at, ["group": .string(group), "message": (try? JSONValue.encode(m)) ?? .null])
    }

    // MARK: Network (API.md "Network" and "Mocks"; a release build's answers unless `network` is `.lab`)

    static let heldWays: [(String, String)] = [
        ("lan_beacon", "Finding friends on a new network"),
        ("internet", "Internet direct"),
        ("port_mapping", "Router port opening (UPnP, NAT-PMP, PCP)"),
        ("p2p", "Peer-to-peer and relays"),
        ("friend_relay", "Relay for friends"),
        ("websocket", "Relays over WebSocket (port 443)"),
        ("proxy", "Web proxy for relays"),
        ("custody", "Friends carry your messages"),
        ("letters", "Sealed letters with friends"),
        ("handoff", "Passing messages on between friends"),
        ("route_hints", "Routes friends tell each other"),
        ("nearby", "Bluetooth nearby"),
        ("tor", "Tor"),
    ]
    static let protections: [(String, String)] = [
        ("random_port", "A port of its own for this profile"),
        ("link_knock", "Silent to strangers (link knock)"),
        ("link_padding", "Padding that hides message sizes"),
        ("lock_v2", "Lock while running"),
        ("security_events", "Security notices"),
        ("updates_from_friends", "Updates passed on by friends"),
    ]
    static let settable: Set<String> = ["lan", "internet", "port_mapping", "p2p", "friend_relay", "proxy", "custody",
                                        "handoff", "nearby"]
    static let settings = ["lan", "internet", "p2p", "port_mapping", "proxy", "nearby", "carry_for_friends",
                           "friends_carry_mine", "handoff", "relay_for_friends", "bridge", "store", "relay", "hide_ip"]
    /// The way whose gate a setting turns on (as raven-client's `gate_for_setting`).
    static let gateOfSetting: [String: String] = [
        "internet": "internet", "p2p": "p2p", "port_mapping": "p2p", "proxy": "proxy", "nearby": "nearby",
        "carry_for_friends": "custody", "friends_carry_mine": "custody", "handoff": "handoff",
        "relay_for_friends": "friend_relay",
    ]
    /// Settings the person must agree to first (`agreed: true`), as raven-client's `needs_consent`.
    static let consentSettings: Set<String> = ["carry_for_friends", "friends_carry_mine", "handoff"]
    /// Settings a running raven-node applies only when it starts again.
    static let restartSettings: Set<String> = ["internet", "p2p", "port_mapping", "proxy"]
    /// The engine's honest words for the bridge, store and relay flags.
    static let effects: [String: String] = [
        "bridge": "Raven's background program passes on sealed envelopes other devices hand it on its bridge listeners (the older mesh envelope path; a program started by Raven listens for these on this computer only). Messages to your friends don't use it.",
        "store": "Lets Raven's background program keep sealed envelopes until their next hop is ready. In this version it always has a next hop, so this changes nothing yet.",
        "relay": "Reserved for relaying between Raven's own links. This version of Raven's background program doesn't use it, so this changes nothing yet. To lend friends a relay, use Relay for friends.",
    ]
    static let heldReason = "Not in this version of Raven yet."
    static let labReason = "On for testing only: a developer build's lab switch turned it on."

    /// The gate of a way is open in this mock's build.
    private func gateOpen(_ id: String) -> Bool {
        id == "lan" || (network == .lab && MockRaven.labWays.contains(id))
    }

    /// The person's setting for a way (nil: nothing to switch).
    private func waySetting(_ id: String) -> Bool? {
        switch id {
        case "lan": return !lanOff
        case "internet", "port_mapping", "p2p", "handoff": return labSettings[id] ?? false
        case "custody": return labSettings["friends_carry_mine"] ?? false
        case "friend_relay", "nearby": return false
        default: return nil
        }
    }

    private func way(_ id: String, _ name: String) -> JSONValue {
        let open = gateOpen(id)
        let lab = open && id != "lan"
        let setting = waySetting(id)
        let state: String
        let reason: String
        if id == "nearby" && network == .lab {
            state = "not_on_this_os"
            reason = "This computer can't use Bluetooth nearby (no Bluetooth LE support for it)."
        } else if !open {
            state = "preview"
            reason = MockRaven.heldReason
        } else if setting == false {
            state = "off"
            reason = id == "lan"
                ? "Turned off on this computer: Raven doesn't send or receive on this network until it is turned on again."
                : (id == "custody" ? "Raven doesn't leave your messages with friends or collect mail from them." : "Turned off.")
        } else if lab && id == "tor" && node.running {
            state = "lab"
            reason = "Ready: friends can reach you over Tor, and you them."
        } else if lab {
            state = "lab"
            reason = MockRaven.labReason
        } else {
            state = "on"
            reason = "On. Works without the internet."
        }
        var w: [String: JSONValue] = ["id": .string(id), "name": .string(name), "state": .string(state),
                                      "reason": .string(reason), "lab": .bool(lab),
                                      "gate": .string(id == "tor" ? "ONION_PRODUCTION_ENABLED" : id.uppercased() + "_PRODUCTION_ENABLED"),
                                      "lab_switches": lab ? (id == "tor" ? ["RAVEN_LAB_TEST_A", "RAVEN_LAB_TOR"] : ["RAVEN_LAB_TEST_A"]) : [],
                                      "can_set": .bool(MockRaven.settable.contains(id))]
        if let setting { w["setting"] = .bool(setting) }
        if node.running {
            switch id {
            case "lan": w["running"] = .bool(!lanOff)
            case "p2p": w["running"] = .bool(open && setting == true)
            case "internet", "port_mapping": w["running"] = .bool(open && setting == true)
            case "tor" where lab:
                w["running"] = true
                w["detail"] = .string(MockRaven.labTorWords)
            default: break
            }
        }
        if id == "lan" {
            w["detail"] = .string(lanOff ? "LAN: off (raven lan on turns it back on)"
                                         : "LAN: on · listening \(node.listening ?? "not running")")
        }
        return .object(w)
    }

    private func networkStatus() -> JSONValue {
        let lab = network == .lab
        var carriers: [JSONValue] = [way("lan", "Same network (Wi-Fi, cable or hotspot)")]
        for (id, name) in MockRaven.heldWays { carriers.append(way(id, name)) }
        let protections = MockRaven.protections.map { way($0.0, $0.1) }
        let p2pUp = lab && node.running && labSettings["p2p"] == true
        let mapped = p2pUp && labSettings["port_mapping"] == true
        var v: [String: JSONValue] = [
            "build": "dev",
            "node": .string(node.running ? "running" : "not_running"),
            "carriers": .array(carriers),
            "protections": .array(protections),
            "listening": .array(node.listening.map { [.string($0)] } ?? []),
            "port": 7420,
            "port_mapping": ["setting": .string(lab ? (labSettings["port_mapping"] == true ? "on" : "off") : "unset"),
                             "router": .string(p2pUp ? (mapped ? "mapped 7423" : "off") : ""),
                             "nat_pmp_pcp": "preview"],
            "relays": p2pUp ? [["relay": .string(MockRaven.relayAddress), "state": "reserved", "source": "manual"]] : [],
            "proxy": ["setting": "auto", "in_use": "", "lines": []],
            "nearby": lab
                ? ["state": "held", "saved": false, "on_this_os": true, "enabled": false, "radio": "unsupported",
                   "rows": [["label": "Bluetooth", "value": "no Bluetooth LE support on this computer"]]]
                : ["state": "held", "saved": nil, "on_this_os": true, "rows": []],
            "carry": [
                "friends_carry_mine": [
                    "setting": .string(lab ? (labSettings["friends_carry_mine"] == true ? "on" : "not_decided") : "not_decided"),
                    "mail_friends": .int(labSettings["friends_carry_mine"] == true ? 1 : 0), "chosen_by_hand": false,
                    "offering": .int(lab ? 1 : 0), "offering_over_internet": 0, "offering_reachable": .int(lab ? 1 : 0),
                    "listed_by_hand": 0],
                "carry_for_friends": ["on": .bool(labSettings["carry_for_friends"] == true),
                                      "held_messages": .int(labSettings["carry_for_friends"] == true ? 2 : 0),
                                      "held_bytes": .int(labSettings["carry_for_friends"] == true ? 3072 : 0),
                                      "handoff": .bool(labSettings["handoff"] == true), "handoff_lines": []],
                "letters_left": [],
                "relay_for_friends": ["setting": false, "offering": false, "offered_to": 0],
            ],
            "help": ["bridge": .bool(helpFlags.bridge), "store": .bool(helpFlags.store), "relay": .bool(helpFlags.relay),
                     "automatic": .bool(helpFlags.automatic),
                     "effects": .object(MockRaven.effects.mapValues { .string($0) })],
            "hide_ip": .bool(hideIp),
            "lab_switches": .array(lab ? MockRaven.labSwitches.map { .string($0) } : []),
            "texts": ["carry_for_friends": "Hold sealed messages for your friends while they are offline?",
                      "friends_carry_mine": "Use friends as mailboxes?",
                      "handoff": "This node may pass sealed messages on between verified contacts."],
        ]
        if lab, labSettings["p2p"] == true { v["p2p_listen"] = "7423" }
        if lab, node.running {
            v["tor"] = ["phase": "ready", "words": .string(MockRaven.labTorWords), "outages": .string(MockRaven.labTorOutages)]
        }
        if p2pUp { v["p2p_addresses"] = ["/ip4/127.0.0.1/tcp/7423/p2p/12D3KooWMeDemo8sQ2vT5nX4kLp7rZ"] }
        if let lanUntilMs, !lanOff { v["lan_until_ms"] = .int(Int(lanUntilMs)) }
        return .object(v)
    }

    /// Everything is checked first (types, gates, consent): a refused request changes nothing.
    private func setNetwork(_ args: [String: JSONValue]) throws -> JSONValue {
        let given = MockRaven.settings.compactMap { key in args[key].flatMap { $0.isNull ? nil : (key, $0) } }
        guard !given.isEmpty else { throw RavenError.badRequest("network.set needs at least one setting") }
        let agreed = args["agreed"]?.bool ?? false
        for (key, value) in given {
            let on: Bool
            if key == "proxy" {
                guard let text = value.string else { throw RavenError.badRequest("\"proxy\" must be auto, off or http://host:port") }
                on = text.lowercased() != "off"
            } else {
                guard let b = value.bool else { throw RavenError.badRequest("\"\(key)\" must be true or false") }
                on = b
            }
            guard on else { continue }
            if let gate = MockRaven.gateOfSetting[key], !gateOpen(gate) {
                throw RavenError(code: ErrorCode.notAvailableYet, message: tr(.errorNotAvailableYet),
                                 detail: "network.set \(key): held in this version")
            }
            if MockRaven.consentSettings.contains(key) && !agreed {
                throw RavenError(code: ErrorCode.consentNeeded, message: tr(.errorConsentNeeded),
                                 detail: "\(key): show network.status texts.\(key) and pass \"agreed\": true with the person's yes")
            }
        }
        var changes: [JSONValue] = []
        var restart = false
        for (key, value) in given {
            let on = value.bool ?? false
            var effect = "Turned off."
            var applies = "now"
            switch key {
            case "lan":
                lanOff = !on
                if on, let span = args["lan_for"]?.string, let secs = MockRaven.duration(span) {
                    lanUntilMs = clock.now.ms + Int64(secs * 1000)
                    effect = "Raven sends and receives on this network for \(span), then turns it off by itself."
                } else {
                    lanUntilMs = nil
                    effect = on ? "Raven sends and receives on this network again." : "Raven stops sending and receiving on this network."
                }
            case "internet", "p2p", "port_mapping":
                labSettings[key] = on
                applies = "restart"
                effect = on ? "Turned on when Raven's background program restarts." : "Turned off when Raven's background program restarts."
            case "carry_for_friends", "friends_carry_mine", "handoff":
                labSettings[key] = on
                effect = on ? "Turned on, as you agreed." : "Turned off."
            case "bridge": helpFlags.bridge = on; helpFlags.automatic = false; effect = MockRaven.effects["bridge"]!
            case "store": helpFlags.store = on; helpFlags.automatic = false; effect = MockRaven.effects["store"]!
            case "relay": helpFlags.relay = on; helpFlags.automatic = false; effect = MockRaven.effects["relay"]!
            case "hide_ip":
                hideIp = on
                effect = on ? "Your contacts no longer learn this computer's IP address from Raven." : "Your contacts may reach you directly again."
            case "proxy":
                applies = "restart"
                effect = "Raven dials relays directly, never through a web proxy."
            default: break
            }
            if applies == "restart" { restart = true }
            changes.append(["setting": .string(key), "value": value, "effect": .string(effect), "applies": .string(applies),
                            "detail": []])
        }
        return ["changes": .array(changes), "restart_needed": .bool(restart && node.running), "status": networkStatus()]
    }

    /// `30m`, `1h`, ... up to `24h`, in seconds.
    static func duration(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let n = Double(text.dropLast()), n > 0 else { return nil }
        switch unit {
        case "m": return min(n * 60, 24 * 3600)
        case "h": return min(n * 3600, 24 * 3600)
        default: return nil
        }
    }

    private func networkCheck(router: Bool) -> JSONValue {
        // As raven-client says it: plain words without commands, the next step once, the CLI's own
        // words under `technical`.
        let lan = lanOff ? "off" : "on"
        var v: [String: JSONValue] = [
            "summary": [
                ["key": "identity", "label": "identity", "value": "OK"],
                ["key": "raven_node", "label": "raven-node",
                 "value": .string(node.running ? "running; you can send and receive" : "NOT running")],
                ["key": "lan", "label": "LAN", "value": .string(lan)],
                ["key": "contacts", "label": "contacts", "value": .string(String(contacts.count))],
            ],
            "next_step": "All set: Raven can send and receive messages on this computer.",
            "technical": [.string("LAN: " + (lanOff ? "off (raven lan on turns it back on)" : "on")),
                          "next step: all set. Send a test message: ash send --contact NAME"],
            "rows": [
                ["key": "receiving", "value": .string(node.running ? "yes" : "not_running"),
                 "plain": .string(node.running ? "Raven receives messages on this network." : "Raven's background program isn't running.")],
                ["key": "reach_class", "value": "off (p2p host not running)",
                 "plain": "Peer-to-peer isn't running, so only direct ways are used."],
                ["key": "policy", "value": .string("bridge=\(helpFlags.bridge) store=\(helpFlags.store) relay=\(helpFlags.relay)")],
            ],
        ]
        if router {
            v["router"] = [["key": "router_gateway_v4", "value": "found"],
                           ["key": "router_upnp_igd", "value": "none", "plain": "No UPnP router answered."],
                           ["key": "router_natpmp", "value": "no", "plain": "Your router didn't answer NAT-PMP."]]
        }
        return .object(v)
    }

    private func contactRoutes(_ address: String?) throws -> JSONValue {
        let c = contacts[try contactIndex(address)]
        let r = friendRoutes[c.address] ?? (nil, nil, [], false)
        let lab = network == .lab
        let held = lab ? "lab" : "preview"
        var routes: [JSONValue] = []
        if let lan = c.lan {
            routes.append(["kind": "lan", "label": "Same network (Wi-Fi, cable or hotspot)", "value": .string(lan),
                           "via": [], "state": "on"])
        }
        if let inet = r.internet {
            routes.append(["kind": "internet", "label": "Internet direct", "value": .string(inet), "via": [], "state": .string(held)])
        }
        if let id = r.p2p {
            routes.append(["kind": "p2p", "label": "Peer-to-peer and relays", "value": .string(id),
                           "via": [.string(MockRaven.relayAddress)], "state": .string(held)])
        }
        if c.verified {
            routes.append(["kind": "nearby", "label": "Bluetooth nearby", "value": "", "via": [], "state": "preview"])
        }
        let listed: [JSONValue] = r.mailFriends.map { a in
            ["address": .string(a), "name": .opt(contacts.first { $0.address == a }?.name), "usable": true]
        }
        var told: [JSONValue] = []
        if lab && c.address == MockRaven.aliAddress {
            told = [["address": .string(MockRaven.minaAddress), "name": "Mina", "takes_handoffs": true]]
        }
        var carriers: [String: JSONValue] = ["hints": .string(held), "told": .array(told), "told_unknown": .int(told.isEmpty ? 0 : 1),
                                             "listed": .array(listed), "receipts_stranded": false]
        if c.verified {
            carriers["coverage"] = told.isEmpty
                ? ["kind": "none", "name": "nobody can carry it", "until": "it goes when you meet"]
                : ["kind": "mutual_friend", "name": "Mina", "until": "up to 24 hours"]
        }
        // How long a message written now could wait (a release build: until the secure connection
        // with a verified friend ends; a friend not verified was never connected with: a first message).
        carriers["away"] = c.verified ? ["until_ms": .int(Int(clock.now.ms + 20 * 3600 * 1000))]
            : ["meet_first": true, "first_message": true]
        var v: [String: JSONValue] = ["address": .string(c.address), "verified": .bool(c.verified), "hide_ip": .bool(r.hideIp),
                                      "routes": .array(routes), "carriers": .object(carriers)]
        if lab && c.address == MockRaven.aliAddress {
            v["learned"] = ["relays": 1, "direct": 1, "mail_friends": 1, "peer_id": "12D3KooWAliDemo3kT9xQ7mV2pR",
                            "peer_id_proven": true, "expires_at_ms": .int(Int(clock.now.ms + 20 * 3600 * 1000))]
        }
        return .object(v)
    }

    private func setContactRoutes(_ args: [String: JSONValue]) throws -> JSONValue {
        let i = try contactIndex(args["address"]?.string)
        let address = contacts[i].address
        var r = friendRoutes[address] ?? (nil, nil, [], false)
        if let inet = args["internet"]?.string, !inet.isEmpty {
            guard inet.contains(":") else { throw RavenError.badRequest("internet must be host:port") }
            r.internet = inet
        }
        if let id = args["p2p"]?.string, !id.isEmpty { r.p2p = id }
        for c in args["clear"]?.array ?? [] {
            if c.string == "lan" { contacts[i].lan = nil }
            if c.string == "internet" { r.internet = nil }
            if c.string == "p2p" { r.p2p = nil }
        }
        if let list = args["custodians"]?.array {
            let picked = list.compactMap { $0.string }
            let ok = picked.count <= 2 && picked.allSatisfy { a in
                a != address && contacts.contains { $0.address == a && $0.verified }
            }
            guard ok else { throw RavenError.badRequest("mail friends must be up to two verified friends") }
            r.mailFriends = picked
        }
        if let h = args["hide_ip"]?.bool { r.hideIp = h }
        friendRoutes[address] = r
        return ["contact": try JSONValue.encode(withUnread(contacts[i])), "routes": try contactRoutes(address)]
    }

    // MARK: Security, Lock v2, updates

    private func securityStatus() -> JSONValue {
        guard network == .lab else {
            return ["available": false, "lab": false, "kept": "off", "notices": [], "counted": 0]
        }
        var v: [String: JSONValue] = [
            "available": true, "lab": true, "kept": "live", "counted": 3,
            "notices": [[
                "id": 1, "level": "warning",
                "name": "A stranger",
                "headline": "Someone you don't know tried to connect 3 times",
                "what_raven_did": "Refused every try. Strangers get no answer from Raven.",
                "what_to_do": "Nothing. If it keeps happening, think about who has your card with your address.",
                "when": "today 13:58",
                "details": [["label": "from", "value": "198.51.100.23"], ["label": "tries", "value": "3"]],
            ]],
        ]
        if node.running {
            v["node"] = ["strangers_refused_1h": 3, "failed_handshakes_1h": 0, "bans_active": 1,
                         "link_tag_failures_24h": 0, "alerts_open": 0]
        }
        return .object(v)
    }

    private func lockState() -> JSONValue {
        guard network == .lab else { return ["available": false, "lab": false, "supported": false, "locked": false] }
        return ["available": true, "lab": true, "supported": .bool(node.running), "locked": .bool(lockedV2 && node.running),
                "has_passphrase": true]
    }

    private func lockHeld(_ op: String) -> RavenError {
        RavenError(code: ErrorCode.notAvailableYet, message: tr(.errorNotAvailableYet),
                   detail: "\(op): Lock v2 is held in this version; raven lock in a terminal stops Raven instead")
    }

    private func lockUnsupported() -> RavenError {
        RavenError(code: ErrorCode.notAvailableYet,
                   message: "Lock while running needs Raven's background program running, in a version that can lock. Nothing was changed.",
                   detail: "raven-node does not serve Lock v2 (no node)")
    }

    private func updatesStatus() -> JSONValue {
        let installText = "Install updates with `raven update install` in a terminal. The app shows what is ready; it doesn't install yet."
        guard network == .lab else {
            return ["available": false, "bundles": false, "from_friends": false, "lab": false,
                    "lines": ["Raven updates are not part of this version."], "install": "cli_only",
                    "install_text": .string(installText)]
        }
        return ["available": true, "bundles": true, "from_friends": false, "lab": true,
                "lines": ["installed: 0.1.0 (dev)", "waiting: none", "last check: today 13:40"],
                "summary": "No update is waiting.", "install": "cli_only", "install_text": .string(installText)]
    }

    // MARK: Demo data and stream

    private func seedFriends(now: Date) {
        guard contacts.isEmpty else { return }
        let nowMs = now.ms
        let minaUntil = nowMs + 22 * 3600 * 1000
        contacts = [
            Contact(address: MockRaven.aliAddress, name: "Ali", shortAddress: MockRaven.short(MockRaven.aliAddress),
                    verified: true, presence: .inTouch, lastContactMs: nowMs - 40_000, waiting: nil,
                    avatarIndex: Theme.avatarIndex(for: MockRaven.aliAddress), lan: "192.168.1.23:7420"),
            Contact(address: MockRaven.minaAddress, name: "Mina", shortAddress: MockRaven.short(MockRaven.minaAddress),
                    verified: true, presence: .waiting, lastContactMs: nowMs - 26 * 3600 * 1000,
                    waiting: Waiting(count: 1, untilMs: minaUntil),
                    avatarIndex: Theme.avatarIndex(for: MockRaven.minaAddress), lan: "192.168.1.27:7420"),
            Contact(address: MockRaven.renaAddress, name: "Rena", shortAddress: MockRaven.short(MockRaven.renaAddress),
                    verified: false, presence: .none, lastContactMs: nil, waiting: nil,
                    avatarIndex: Theme.avatarIndex(for: MockRaven.renaAddress), lan: "192.168.1.31:7420"),
        ]
        friendWords = [MockRaven.aliAddress: MockRaven.aliWords, MockRaven.minaAddress: MockRaven.minaWords,
                       MockRaven.renaAddress: MockRaven.renaWords]
        friendOldCodes = [MockRaven.renaAddress: MockRaven.renaOldCode]
        messages = [
            Message(id: "m1", address: MockRaven.aliAddress, direction: .incoming, text: "Are you coming to the meeting?",
                    atMs: nowMs - 6 * 60_000, state: .delivered, path: MockRaven.lanPath, pathKind: MockRaven.lanKind),
            Message(id: "m2", address: MockRaven.aliAddress, direction: .outgoing, text: "Yes, see you there",
                    atMs: nowMs - 5 * 60_000, state: .delivered, path: MockRaven.lanPath, pathKind: MockRaven.lanKind),
            Message(id: "m3", address: MockRaven.minaAddress, direction: .outgoing, text: "Can you send me the photos from Saturday?",
                    atMs: nowMs - 2 * 3600 * 1000, state: .waiting, untilMs: minaUntil, attempts: 1),
        ]
        // Ali's question was read (and answered) before the demo starts.
        readUpTo = [MockRaven.aliAddress: "m2"]
        seedGroups(nowMs: nowMs)
        if network == .lab {
            // A lab build's other paths: Ali's question came over a relay; Mina's message waits with a friend.
            messages[0].path = "p2p · relayed"
            messages[0].pathKind = "p2p_relayed"
            messages[2].path = "Held by a friend"
            messages[2].pathKind = "friend"
        }
    }

    private func startScript(at start: Date) {
        scriptStarted = true
        emit("node", at: start, ["status": (try? JSONValue.encode(node)) ?? .null])
        if node.running {
            lastStatusOk = start
            node.lastOkMs = start.ms
            emit("status_ok", at: start)
        }
        func at(_ s: TimeInterval, _ action: @escaping (MockRaven, Date) -> Void) {
            schedule(at: start.addingTimeInterval(s), action)
        }
        at(1.2) { m, t in
            m.receive(from: MockRaven.aliAddress, text: "Great. Can you bring the charger?", at: t)
        }
        at(2.6) { m, t in
            m.setPresence(MockRaven.renaAddress, .inTouch, at: t)
            m.receive(from: MockRaven.renaAddress, text: "Hi, it's Rena. Did my invite reach you?", at: t)
        }
        at(4.0) { m, t in
            guard let i = m.messages.firstIndex(where: { $0.id == "m3" }), m.messages[i].state == .waiting else { return }
            let attempts = (m.messages[i].attempts ?? 1) + 1
            m.messages[i].attempts = attempts
            m.emit("retry", at: t, ["id": "m3", "address": .string(MockRaven.minaAddress), "attempts": .int(attempts)])
        }
        at(4.5) { m, t in
            _ = try? m.send(to: MockRaven.aliAddress, text: "Yes, I'll bring it", now: t, id: "demo-send")
        }
        at(7.5) { m, t in
            // Sam's copy of your Book club message, passed on by Ali, is confirmed.
            m.setGroupReceipt(MockRaven.bookClubID, message: "g3", member: MockRaven.samAddress, state: "delivered", at: t)
        }
        at(8.0) { m, t in
            m.receiveGroup(MockRaven.bookClubID, from: MockRaven.aliAddress, text: "I'll bring the second book too.", at: t)
        }
        at(10.5) { m, t in m.setPresence(MockRaven.minaAddress, .inTouch, at: t) }
        at(10.8) { m, t in
            guard m.messages.contains(where: { $0.id == "m3" && $0.state == .waiting }) else { return }
            m.emit("send_started", at: t, ["id": "m3"])
        }
        at(11.3) { m, t in m.deliver("m3", ms: 510, at: t) }
    }

    /// Runs every scheduled step that is due and emits the heartbeat (`status_ok` every 2 s).
    private func advance() {
        let now = clock.now
        while let next = timeline.min(by: { ($0.at, $0.order) < ($1.at, $1.order) }), next.at <= now {
            timeline.removeAll { $0.order == next.order }
            next.action(self, next.at)
        }
        guard profile == .ready, node.running, scriptStarted || !demo else { return }
        let interval = Theme.shared.motion.statusCheckInterval
        if let last = lastStatusOk {
            let steps = floor(now.timeIntervalSince(last) / interval)
            guard steps >= 1 else { return }
            let at = last.addingTimeInterval(steps * interval)
            lastStatusOk = at
            node.lastOkMs = at.ms
            emit("status_ok", at: at)
        } else {
            lastStatusOk = now
            node.lastOkMs = now.ms
            emit("status_ok", at: now)
        }
    }

    private func schedule(at: Date, _ action: @escaping (MockRaven, Date) -> Void) {
        order += 1
        timeline.append(Scheduled(at: at, order: order, action: action))
    }

    private func emit(_ kind: String, at: Date, _ fields: [String: JSONValue] = [:]) {
        seq += 1
        var o = fields
        o["seq"] = .int(seq)
        o["kind"] = .string(kind)
        o["at_ms"] = .int(at.ms)
        events.append(.object(o))
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    private func receive(from address: String, text: String, at: Date) {
        guard let i = contacts.firstIndex(where: { $0.address == address }) else { return }
        nextID += 1
        let msg = Message(id: "in\(nextID)", address: address, direction: .incoming, text: text, atMs: at.ms,
                          state: .delivered, path: MockRaven.lanPath, pathKind: MockRaven.lanKind)
        messages.append(msg)
        contacts[i].lastContactMs = at.ms
        emit("incoming", at: at, ["message": (try? JSONValue.encode(msg)) ?? .null])
        emit("unread", at: at, ["address": .string(address), "unread": .int(unreadCount(address))])
    }

    /// The friend's messages in the order the chat shows them.
    private func chat(_ address: String) -> [Message] {
        messages.filter { $0.address == address }.sorted { $0.atMs < $1.atMs }
    }

    /// The friend's messages after the one last read (API.md, Contact `unread`); yours never count.
    private func unreadCount(_ address: String) -> Int {
        let list = chat(address)
        let start = readUpTo[address].flatMap { id in list.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        return list[start...].filter { $0.direction == .incoming }.count
    }

    private func withUnread(_ c: Contact) -> Contact {
        var c = c
        c.unread = unreadCount(c.address)
        return c
    }

    private func setPresence(_ address: String, _ presence: Presence, at: Date) {
        guard let i = contacts.firstIndex(where: { $0.address == address }) else { return }
        contacts[i].presence = presence
        if presence == .inTouch { contacts[i].lastContactMs = at.ms }
        emit("presence", at: at, ["address": .string(address), "presence": .string(presence.rawValue)])
    }

    private func deliver(_ id: String, ms: Int, at: Date) {
        guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].state != .delivered else { return }
        messages[i].state = .delivered
        messages[i].path = MockRaven.lanPath
        messages[i].pathKind = MockRaven.lanKind
        messages[i].untilMs = nil
        if let c = contacts.firstIndex(where: { $0.address == messages[i].address }) {
            contacts[c].lastContactMs = at.ms
            if contacts[c].presence == .waiting || contacts[c].presence == .none { contacts[c].presence = .inTouch }
        }
        recountWaiting(messages[i].address)
        emit("receipt", at: at, ["id": .string(id), "path": .string(MockRaven.lanPath),
                                 "path_kind": .string(MockRaven.lanKind), "ms": .int(ms)])
    }

    private func recountWaiting(_ address: String) {
        guard let c = contacts.firstIndex(where: { $0.address == address }) else { return }
        let waiting = messages.filter { $0.address == address && $0.direction == .outgoing && $0.state == .waiting }
        if waiting.isEmpty {
            contacts[c].waiting = nil
            if contacts[c].presence == .waiting { contacts[c].presence = .none }
        } else {
            contacts[c].waiting = Waiting(count: waiting.count, untilMs: waiting.compactMap { $0.untilMs }.min() ?? 0)
        }
    }

    // MARK: Sending

    @discardableResult
    private func send(to address: String?, text: String, now: Date, id: String? = nil) throws -> Message {
        let c = try contactIndex(address)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw RavenError.badRequest("empty message") }
        guard body.count <= 4000 else {
            throw RavenError(code: ErrorCode.messageTooLong, message: tr(.errorMessageTooLong), detail: "length \(body.count) > 4000")
        }
        nextID += 1
        let contact = contacts[c]
        var msg = Message(id: id ?? "m\(nextID)", address: contact.address, direction: .outgoing, text: body,
                          atMs: now.ms, state: .sending, attempts: 1)
        if contact.presence == .noAddress {
            msg.state = .notSentMeetFirst
            messages.append(msg)
            emit("state", at: now, ["id": .string(msg.id), "state": "not_sent_meet_first"])
            return msg
        }
        messages.append(msg)
        emit("send_started", at: now, ["id": .string(msg.id)])
        let msgID = msg.id
        if contact.presence == .inTouch {
            schedule(at: now.addingTimeInterval(0.8)) { m, t in
                guard let i = m.messages.firstIndex(where: { $0.id == msgID }), m.messages[i].state == .sending else { return }
                m.messages[i].state = .sent
                m.emit("state", at: t, ["id": .string(msgID), "state": "sent"])
            }
            schedule(at: now.addingTimeInterval(1.5)) { m, t in m.deliver(msgID, ms: 380 + body.count % 300, at: t) }
        } else {
            schedule(at: now.addingTimeInterval(0.8)) { m, t in
                guard let i = m.messages.firstIndex(where: { $0.id == msgID }), m.messages[i].state == .sending else { return }
                m.messages[i].state = .waiting
                m.messages[i].untilMs = t.ms + 24 * 3600 * 1000
                m.emit("state", at: t, ["id": .string(msgID), "state": "waiting"])
                m.recountWaiting(m.messages[i].address)
                if let ci = m.contacts.firstIndex(where: { $0.address == m.messages[i].address }), m.contacts[ci].presence == .none {
                    m.setPresence(m.contacts[ci].address, .waiting, at: t)
                }
            }
        }
        return msg
    }

    private func retry(_ id: String?, now: Date) throws -> Message {
        let i = try messageIndex(id)
        guard messages[i].direction == .outgoing, messages[i].state != .delivered else { return messages[i] }
        let attempts = (messages[i].attempts ?? 1) + 1
        messages[i].attempts = attempts
        if messages[i].state != .waiting {
            messages[i].state = .waiting
            messages[i].untilMs = now.ms + 24 * 3600 * 1000
            recountWaiting(messages[i].address)
        }
        let msgID = messages[i].id
        let address = messages[i].address
        emit("send_started", at: now, ["id": .string(msgID)])
        let inTouch = contacts.first(where: { $0.address == address })?.presence == .inTouch
        if inTouch {
            schedule(at: now.addingTimeInterval(0.9)) { m, t in m.deliver(msgID, ms: 450, at: t) }
        } else {
            schedule(at: now.addingTimeInterval(0.9)) { m, t in
                m.emit("retry", at: t, ["id": .string(msgID), "address": .string(address), "attempts": .int(attempts)])
            }
        }
        return messages[i]
    }

    private func details(_ id: String?, now: Date) throws -> JSONValue {
        let i = try messageIndex(id)
        let msg = messages[i]
        let contact = contacts.first { $0.address == msg.address }
        let name = contact?.name ?? MockRaven.short(msg.address)
        // As the engine: plain lines in `detail`, the developer fields in `technical`.
        var status = "", why = "", action = "", detail = "Message ID: \(msg.id)"
        var technical = "id=\(msg.id) state=\(msg.state.rawValue) attempts=\(msg.attempts ?? 1)"
        switch msg.state {
        case .waiting:
            let until = Date(ms: msg.untilMs ?? now.ms)
            status = tr(.messageStatusWaiting, ["name": name, "time": TimeText.deadline(ms: until.ms, now: now), "left": TimeText.left(until.timeIntervalSince(now))])
            why = tr(.messageWhyUnreachable, ["name": name])
            action = tr(.messageActionWait, ["name": name])
            detail += "\nTries so far: \(msg.attempts ?? 1)"
            technical += " route=lan \(contact?.lan ?? "-") last_error=\"connection refused (os error 61)\""
        case .sent:
            status = tr(.messageStatusSent, ["name": name])
        case .timeRanOut:
            status = tr(.messageTimeRanOut)
        case .delivered:
            status = tr(.tickDelivered)
            detail += "\nWay: \(msg.path ?? "-")"
            technical += " path=\"\(msg.path ?? "-")\" receipt=signed"
        case .sending:
            status = tr(.tickSending)
        case .notSentMeetFirst:
            status = tr(.tickNotSentMeetFirst, ["name": name])
            why = tr(.homeNoAddress)
        case .failed:
            status = tr(.tickFailed)
        }
        return ["message": try JSONValue.encode(msg), "status_text": .string(status), "why_text": .string(why),
                "action_text": .string(action), "detail": .string(detail), "technical": .string(technical)]
    }

    // MARK: Cards, contacts, words

    private func makeCard(includeAddress: Bool) -> (card: String, invite: String, included: String?) {
        let me = identity ?? Identity(address: MockRaven.meAddress, words: MockRaven.myWords, oldCode: MockRaven.myOldCode)
        let lan = "\(node.address ?? MockRaven.thisComputer):7420"
        var card = "raven-card/1 address=\(me.address) pub_hex=\(MockRaven.myPubHex) fingerprint=\(me.oldCode)"
        if includeAddress { card += " lan=\(lan)" }
        let invite = "raven:\(me.address):\(MockRaven.myPubHex)" + (includeAddress ? "@\(lan)" : "")
        return (card, invite, includeAddress ? lan : nil)
    }

    struct ParsedCard { let address: String; let lan: String?; var ignored: [String] = [] }

    func parseCard(_ text: String) throws -> ParsedCard {
        let clean = Sanitizer.line(text, maxLength: 2000)
        let invalid = RavenError(code: ErrorCode.cardInvalid, message: tr(.errorCardInvalid), detail: "could not read: \(clean.prefix(60))")
        if clean.hasPrefix("raven-card/1") {
            var fields: [String: String] = [:]
            for part in clean.split(separator: " ") {
                let kv = part.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
            }
            guard let address = fields["address"], MockRaven.looksLikeAddress(address) else { throw invalid }
            let ignored = [("inet", "internet"), ("p2p", "p2p")].filter { fields[$0.0] != nil }.map(\.1)
            return ParsedCard(address: address, lan: fields["lan"], ignored: ignored)
        }
        if clean.hasPrefix("raven:") {
            let parts = clean.dropFirst("raven:".count).split(separator: ":", maxSplits: 1)
            guard let first = parts.first, MockRaven.looksLikeAddress(String(first)) else { throw invalid }
            let lan = parts.count > 1 ? parts[1].split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init) : nil
            return ParsedCard(address: String(first), lan: lan)
        }
        throw invalid
    }

    static func looksLikeAddress(_ s: String) -> Bool {
        s.hasPrefix("rvn1") && s.count >= 20 && s.count <= 90 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public static func short(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return String(address.prefix(8)) + "…" + String(address.suffix(5))
    }

    private func addContact(text: String, name rawName: String) throws -> Contact {
        let parsed = try parseCard(text)
        let name = Sanitizer.line(rawName, maxLength: 64)
        guard parsed.address != identity?.address else {
            throw RavenError(code: ErrorCode.cardInvalid, message: tr(.errorCardInvalid), detail: "this is your own card")
        }
        if let existing = contacts.first(where: { $0.address == parsed.address }) { return existing }
        let finalName = name.isEmpty ? MockRaven.short(parsed.address) : name
        try checkNameFree(finalName, except: nil)
        let contact = Contact(address: parsed.address, name: finalName, shortAddress: MockRaven.short(parsed.address),
                              verified: false, presence: parsed.lan == nil ? .noAddress : .none,
                              avatarIndex: Theme.avatarIndex(for: parsed.address), lan: parsed.lan)
        contacts.append(contact)
        friendWords[parsed.address] = MockWordList.shared.demoWords(seed: parsed.address)
        return contact
    }

    private func checkNameFree(_ name: String, except address: String?) throws {
        if contacts.contains(where: { $0.address != address && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw RavenError(code: ErrorCode.nameClash, message: tr(.addNameClash, ["name": name]), detail: "petname already used")
        }
    }

    private func checkWords(_ typed: [String], against expected: [String]) throws -> VerifyResult {
        let list = MockWordList.shared
        let indexes = typed.compactMap { list.resolve($0) }
        guard typed.count == 10, indexes.count == 10 else {
            throw RavenError(code: ErrorCode.wordsIncomplete, message: tr(.errorWordsIncomplete),
                             detail: "got \(indexes.count) Raven words out of \(typed.count) typed; need 10")
        }
        guard MockWordList.checkOK(indexes) else { return .typo }
        let want = expected.compactMap { list.resolve($0) }
        // Compare every position, without stopping early.
        var same = want.count == indexes.count
        for (a, b) in zip(want, indexes) where a != b { same = false }
        return same ? .match : .mismatch
    }

    private func applySettings(_ args: [String: JSONValue], now: Date) throws {
        if let v = args["display_name"] {
            settings.displayName = v.string.map { Sanitizer.line($0, maxLength: 64) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let v = args["reduced_motion"]?.bool { settings.reducedMotion = v }
        if let v = args["when_quit"]?.string, RavenSettings.whenQuitValues.contains(v) { settings.whenQuit = v }
        if let v = args["keep_chats_days"] {
            let days = v.int
            if days == nil || [7, 30, 90].contains(days!) { settings.keepChatsDays = days }
        }
        if let v = args["forget_addresses"]?.bool { settings.forgetAddresses = v }
        if let v = args["lock_on_sleep"]?.bool { settings.lockOnSleep = v }
        if let v = args["receive"]?.bool, v != settings.receive {
            settings.receive = v
            node.receive = v
            node.listening = (v && node.running) ? "0.0.0.0:7420" : nil
            emit("node", at: now, ["status": try JSONValue.encode(node)])
        }
    }

    // MARK: Helpers

    private func notInitialized() -> RavenError {
        RavenError(code: ErrorCode.notInitialized, message: tr(.errorNotInitialized), detail: "profile state: \(profile.rawValue)")
    }

    private func notAvailableYet(_ op: String) -> RavenError {
        RavenError(code: ErrorCode.notAvailableYet, message: tr(.errorNotAvailableYet),
                   detail: "\(op): the privacy pack is not in this build")
    }

    private func requireIdentity() throws -> Identity {
        guard let identity else { throw notInitialized() }
        return identity
    }

    private func contactIndex(_ address: String?) throws -> Int {
        guard let address, let i = contacts.firstIndex(where: { $0.address == address }) else {
            throw RavenError(code: ErrorCode.notAContact, message: tr(.errorNotAContact), detail: "address=\(address ?? "-")")
        }
        return i
    }

    private func messageIndex(_ id: String?) throws -> Int {
        guard let id, let i = messages.firstIndex(where: { $0.id == id }) else {
            throw RavenError.badRequest("no message \(id ?? "-")")
        }
        return i
    }
}

/// A clock the tests and snapshots can stop and move by hand.
public final class MockClock: @unchecked Sendable {
    private let lock = NSLock()
    private var manual: Date?

    public init(fixed: Date? = nil) { manual = fixed }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return manual ?? Date()
    }

    public func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        manual = (manual ?? Date()).addingTimeInterval(seconds)
    }
}

/// Raven's 256-word list and the check word (GF(2^8) Damm/Horner), engine side only.
/// Port of core/protocol/reference/raven_protocol/security_words.py.
public struct MockWordList: Sendable {
    public let words: [String]
    let exact: [String: Int]

    public static let shared: MockWordList = {
        guard let data = RavenResources.data("raven-security-words-v1", "txt"), let text = String(data: data, encoding: .utf8) else {
            fatalError("raven-security-words-v1.txt is missing from the resource bundle")
        }
        return MockWordList(fileText: text)
    }()

    public init(fileText: String) {
        var words: [String] = []
        for line in fileText.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t")
            if parts.count == 2 { words.append(String(parts[1])) }
        }
        self.words = words
        var exact: [String: Int] = [:]
        for (i, w) in words.enumerated() { exact[w] = i }
        self.exact = exact
    }

    /// Multiply by 2 in GF(2^8) modulo x^8+x^4+x^3+x+1.
    static func xtime(_ v: Int) -> Int {
        let x = v << 1
        return (x & 0x100) != 0 ? x ^ 0x11B : x
    }

    public static func checkIndex(_ data: [Int]) -> Int {
        var acc = 0
        for d in data { acc = xtime(acc) ^ d }
        return xtime(acc)
    }

    public static func checkOK(_ indexes: [Int]) -> Bool {
        var acc = 0
        for d in indexes { acc = xtime(acc) ^ d }
        return acc == 0
    }

    /// Exact word, a plural of a word, or a unique prefix of at least 3 letters.
    public func resolve(_ token: String) -> Int? {
        guard let p = WordInput.foldLatin(token), !p.isEmpty else { return nil }
        if let i = exact[p] { return i }
        for suffix in ["es", "s"] where p.hasSuffix(suffix) {
            if let i = exact[String(p.dropLast(suffix.count))] { return i }
        }
        guard p.count >= 3 else { return nil }
        let candidates = words.indices.filter { words[$0].hasPrefix(p) }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// `verify.word_hint`: the word a prefix of 3 or more letters completes to, if any.
    public func hint(_ prefix: String) -> String? {
        guard let p = WordInput.foldLatin(prefix), p.count >= 3 else { return nil }
        return resolve(p).map { words[$0] }
    }

    /// Ten valid words derived from a seed, for friends added while running on the mock.
    func demoWords(seed: String) -> [String] {
        var h: UInt32 = 2_166_136_261
        var data: [Int] = []
        for byte in seed.utf8 { h = (h ^ UInt32(byte)) &* 16_777_619 }
        for _ in 0..<9 {
            h = (h ^ (h >> 13)) &* 16_777_619
            data.append(Int(h % 256))
        }
        return (data + [MockWordList.checkIndex(data)]).map { words[$0] }
    }
}
#endif
