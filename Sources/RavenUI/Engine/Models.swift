import Foundation

// Types of desktop/api/API.md, "Types". Unknown fields are ignored; unknown enum values fall back
// to a safe case so a newer engine never breaks an older app (forward compatibility).

/// A string enum that decodes unknown values to `fallback` instead of failing.
public protocol LenientEnum: RawRepresentable, Codable where RawValue == String {
    static var fallback: Self { get }
}

extension LenientEnum {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum Presence: String, LenientEnum, Sendable {
    case inTouch = "in_touch", waiting, none, noAddress = "no_address"
    public static var fallback: Presence { .none }
}

public struct Waiting: Codable, Equatable, Sendable {
    public var count: Int
    public var untilMs: Int64
    public init(count: Int, untilMs: Int64) { self.count = count; self.untilMs = untilMs }
}

public struct Contact: Codable, Equatable, Identifiable, Sendable {
    public var address: String
    public var name: String
    public var shortAddress: String
    public var verified: Bool
    public var presence: Presence
    public var lastContactMs: Int64?
    public var waiting: Waiting?
    public var avatarIndex: Int?
    public var lan: String?
    /// The friend's messages after the one last read on this computer, in this app or the terminal
    /// app (the engine counts them; API.md, "Read and unread").
    public var unread: Int?
    public var id: String { address }

    public init(address: String, name: String, shortAddress: String, verified: Bool, presence: Presence,
                lastContactMs: Int64? = nil, waiting: Waiting? = nil, avatarIndex: Int? = nil, lan: String? = nil,
                unread: Int? = nil) {
        self.address = address; self.name = name; self.shortAddress = shortAddress; self.verified = verified
        self.presence = presence; self.lastContactMs = lastContactMs; self.waiting = waiting
        self.avatarIndex = avatarIndex; self.lan = lan; self.unread = unread
    }

    /// Display fields as single clean lines (the JSON layer already removed invisible characters).
    public func sanitized() -> Contact {
        var c = self
        c.name = Sanitizer.line(name, maxLength: 64)
        c.shortAddress = Sanitizer.line(shortAddress, maxLength: 64)
        c.lan = lan.map { Sanitizer.line($0, maxLength: 64) }
        return c
    }

    /// The first letter of the name, for the avatar.
    public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

public enum Direction: String, LenientEnum, Sendable {
    case incoming = "in", outgoing = "out"
    public static var fallback: Direction { .incoming }
}

public enum MessageState: String, LenientEnum, Sendable {
    case sending, sent, delivered, waiting
    case timeRanOut = "time_ran_out"
    case notSentMeetFirst = "not_sent_meet_first"
    case failed
    public static var fallback: MessageState { .sent }
}

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var address: String
    public var direction: Direction
    public var text: String
    public var atMs: Int64
    public var state: MessageState
    public var untilMs: Int64?
    public var path: String?
    /// The stable kind of `path` (API.md: `lan`, `internet`, `p2p_relayed`, `websocket`, `nearby`,
    /// `friend`, `handoff`, `letter`, ...).
    public var pathKind: String?
    /// When its receipt came, given only for a delivery more than a minute after it was written (API.md):
    /// the tick then says "Delivered 15:10".
    public var deliveredAtMs: Int64?
    public var attempts: Int?

    public init(id: String, address: String, direction: Direction, text: String, atMs: Int64, state: MessageState,
                untilMs: Int64? = nil, path: String? = nil, pathKind: String? = nil, deliveredAtMs: Int64? = nil,
                attempts: Int? = nil) {
        self.id = id; self.address = address; self.direction = direction; self.text = text; self.atMs = atMs
        self.state = state; self.untilMs = untilMs; self.path = path; self.pathKind = pathKind
        self.deliveredAtMs = deliveredAtMs; self.attempts = attempts
    }

    public func sanitized() -> Message {
        var m = self
        m.text = Sanitizer.text(text)
        m.path = path.map { Sanitizer.line($0, maxLength: 40) }
        m.pathKind = pathKind.map { Sanitizer.line($0, maxLength: 24) }
        return m
    }
}

public struct Carriers: Codable, Equatable, Sendable {
    public var lan: String
    public var internet: String
    public var p2p: String
    public var custody: String
    /// Bluetooth nearby (missing from older engines).
    public var nearby: String?
    public init(lan: String, internet: String, p2p: String, custody: String, nearby: String? = nil) {
        self.lan = lan; self.internet = internet; self.p2p = p2p; self.custody = custody; self.nearby = nearby
    }
}

public struct NodeStatus: Codable, Equatable, Sendable {
    public var running: Bool
    public var startedByApp: Bool
    public var pid: Int?
    public var listening: String?
    public var receive: Bool
    public var address: String?
    public var lastOkMs: Int64
    public var build: String
    public var carriers: Carriers
    /// raven-client's extra: the node's state in one word (`listening`, `local_only`, `send_only`,
    /// `not_running`, `not_answering`, `starting`). Missing from older engines and the mock.
    public var state: String?
    /// raven-client's extras on `node.stop`: what happened (`stopped`, `still_running`, `advice`,
    /// `managed`, `not_running`, `failed`) and, for some, a sentence about it.
    public var stop: String?
    public var note: String?
    /// raven-client's extras: the ways a developer build's lab switch turned on, and the
    /// `RAVEN_LAB_*` switches the engine sees (both empty in a release build and in the mock).
    public var lab: [String]?
    public var labSwitches: [String]?

    public init(running: Bool, startedByApp: Bool, pid: Int? = nil, listening: String? = nil, receive: Bool,
                address: String? = nil, lastOkMs: Int64, build: String, carriers: Carriers, state: String? = nil) {
        self.running = running; self.startedByApp = startedByApp; self.pid = pid; self.listening = listening
        self.receive = receive; self.address = address; self.lastOkMs = lastOkMs; self.build = build
        self.carriers = carriers; self.state = state
    }

    /// The port Raven listens on, e.g. "7420" from "0.0.0.0:7420".
    public var port: String? { listening?.split(separator: ":").last.map(String.init) }
    /// Listening only on the loopback interface: friends on the network cannot reach this computer.
    public var localOnly: Bool { listening?.hasPrefix("127.") ?? false }
    /// Running, but not listening yet. The engine says so in `state`; without it, guessed from the
    /// fields (a node that runs but sends only would otherwise look like it is starting forever).
    public var starting: Bool {
        if let state { return state == "starting" }
        return running && receive && listening == nil
    }
}

public struct RavenSettings: Codable, Equatable, Sendable {
    public var displayName: String?
    public var receive: Bool
    public var reducedMotion: Bool
    public var whenQuit: String
    public var keepChatsDays: Int?
    public var forgetAddresses: Bool
    public var lockOnSleep: Bool

    public init(displayName: String? = nil, receive: Bool = true, reducedMotion: Bool = false, whenQuit: String = "keep",
                keepChatsDays: Int? = 30, forgetAddresses: Bool = true, lockOnSleep: Bool = false) {
        self.displayName = displayName; self.receive = receive; self.reducedMotion = reducedMotion
        self.whenQuit = whenQuit; self.keepChatsDays = keepChatsDays; self.forgetAddresses = forgetAddresses
        self.lockOnSleep = lockOnSleep
    }

    public static let whenQuitValues = ["keep", "stop_if_started", "ask"]
    public static let keepChatsValues: [Int?] = [7, 30, 90, nil]
}

public struct Identity: Codable, Equatable, Sendable {
    public var displayName: String?
    public var address: String
    public var words: [String]
    public var oldCode: String
    public var card: String?
    public var invite: String?
    public init(displayName: String? = nil, address: String, words: [String], oldCode: String, card: String? = nil, invite: String? = nil) {
        self.displayName = displayName; self.address = address; self.words = words; self.oldCode = oldCode
        self.card = card; self.invite = invite
    }
}

public struct ShareCard: Codable, Equatable, Sendable {
    public var card: String
    public var invite: String
    public var addressIncluded: String?
}

public struct CardRoute: Codable, Equatable, Sendable {
    public var kind: String
    public var label: String
    public var preview: Bool
}

/// The summary of a pasted invite or card. It never holds the friend's security words.
public struct CardSummary: Codable, Equatable, Sendable {
    public var shortAddress: String
    public var hasAddress: Bool
    public var routes: [CardRoute]
}

public struct MessageDetails: Codable, Equatable, Sendable {
    public var message: Message
    public var statusText: String
    public var whyText: String
    public var actionText: String
    public var detail: String
    /// The developer fields, shown only under "Technical details" (missing from an older engine).
    public var technical: String?
}

public struct AppInfo: Codable, Equatable, Sendable {
    public var version: String
    public var build: String
    public var platform: String
}

public enum ProfileStateKind: String, LenientEnum, Sendable {
    case new, ready, locked, unreadable
    public static var fallback: ProfileStateKind { .unreadable }
}

public struct ProfileState: Codable, Equatable, Sendable {
    public var state: ProfileStateKind
    public var reason: String?
    /// raven-client's extra for `unreadable`: the technical text (shown under Details).
    public var detail: String?
}

public enum VerifyResult: String, LenientEnum, Sendable {
    case match, typo, mismatch
    /// An unknown result is never treated as a match.
    public static var fallback: VerifyResult { .mismatch }
}

/// `privacy.state`. `available` is false until the privacy pack lands: the privacy actions are then
/// shown disabled with the Preview label.
public struct PrivacyState: Codable, Equatable, Sendable {
    public var available: Bool
    public var encrypted: Bool
    public var locked: Bool
    public init(available: Bool = false, encrypted: Bool = false, locked: Bool = false) {
        self.available = available; self.encrypted = encrypted; self.locked = locked
    }
    /// What the app assumes when the engine cannot say (an older engine, or an error).
    public static let unavailable = PrivacyState()
}

public enum EventKind: String, LenientEnum, Sendable {
    case statusOk = "status_ok", sendStarted = "send_started", receipt, incoming, outgoing, retry, presence, state, node
    /// A friend's unread count changed (a message came, or a chat was read here or in the terminal app).
    case unread
    /// A member's group message came (`group`, `message`: a GroupMessage); something else about a group
    /// changed (`group`): members, status, unread count or a receipt (API.md, "Groups").
    case groupMessage = "group_message", groupChanged = "group_changed"
    case unknown
    public static var fallback: EventKind { .unknown }
}

/// One entry of `events.poll`. Fields beyond `seq`, `kind` and `at_ms` depend on the kind.
public struct RavenEvent: Codable, Equatable, Sendable {
    public var seq: Int
    public var kind: EventKind
    public var atMs: Int64
    public var id: String?
    public var path: String?
    public var pathKind: String?
    public var ms: Int?
    /// A `receipt` event's: when it came, only for a late delivery (as `Message.deliveredAtMs`).
    public var deliveredAtMs: Int64?
    public var message: Message?
    public var address: String?
    public var attempts: Int?
    public var presence: Presence?
    public var state: MessageState?
    /// A `state` event's deadline (API.md: also sent when a waiting message's deadline becomes known).
    public var untilMs: Int64?
    public var status: NodeStatus?
    /// An `unread` event's count.
    public var unread: Int?
    /// A `group_message` / `group_changed` event's group id.
    public var group: String?
    /// A `group_message` event's message (its `message` field has the GroupMessage shape, not Message's).
    public var groupMessage: GroupMessage?

    enum CodingKeys: String, CodingKey {
        case seq, kind, atMs, id, path, pathKind, ms, deliveredAtMs, message, address, attempts, presence, state,
             untilMs, status, unread, group
    }

    public init(seq: Int, kind: EventKind, atMs: Int64, id: String? = nil, path: String? = nil, pathKind: String? = nil,
                ms: Int? = nil, deliveredAtMs: Int64? = nil, message: Message? = nil, address: String? = nil,
                attempts: Int? = nil, presence: Presence? = nil, state: MessageState? = nil, untilMs: Int64? = nil,
                status: NodeStatus? = nil, unread: Int? = nil, group: String? = nil, groupMessage: GroupMessage? = nil) {
        self.seq = seq; self.kind = kind; self.atMs = atMs; self.id = id; self.path = path; self.pathKind = pathKind
        self.ms = ms; self.deliveredAtMs = deliveredAtMs; self.message = message; self.address = address
        self.attempts = attempts; self.presence = presence; self.state = state; self.untilMs = untilMs
        self.status = status; self.unread = unread; self.group = group; self.groupMessage = groupMessage
    }

    /// One event; a `message` that fits neither shape is dropped instead of failing the whole poll.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        kind = try c.decode(EventKind.self, forKey: .kind)
        atMs = try c.decodeIfPresent(Int64.self, forKey: .atMs) ?? 0
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        pathKind = try? c.decodeIfPresent(String.self, forKey: .pathKind)
        ms = try? c.decodeIfPresent(Int.self, forKey: .ms)
        deliveredAtMs = try? c.decodeIfPresent(Int64.self, forKey: .deliveredAtMs)
        address = try? c.decodeIfPresent(String.self, forKey: .address)
        attempts = try? c.decodeIfPresent(Int.self, forKey: .attempts)
        presence = try? c.decodeIfPresent(Presence.self, forKey: .presence)
        state = try? c.decodeIfPresent(MessageState.self, forKey: .state)
        untilMs = try? c.decodeIfPresent(Int64.self, forKey: .untilMs)
        status = try? c.decodeIfPresent(NodeStatus.self, forKey: .status)
        unread = try? c.decodeIfPresent(Int.self, forKey: .unread)
        group = try? c.decodeIfPresent(String.self, forKey: .group)
        if kind == .groupMessage {
            groupMessage = try? c.decodeIfPresent(GroupMessage.self, forKey: .message)
            message = nil
        } else {
            message = try? c.decodeIfPresent(Message.self, forKey: .message)
            groupMessage = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(kind, forKey: .kind)
        try c.encode(atMs, forKey: .atMs)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(pathKind, forKey: .pathKind)
        try c.encodeIfPresent(ms, forKey: .ms)
        try c.encodeIfPresent(deliveredAtMs, forKey: .deliveredAtMs)
        if let groupMessage { try c.encode(groupMessage, forKey: .message) } else { try c.encodeIfPresent(message, forKey: .message) }
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(attempts, forKey: .attempts)
        try c.encodeIfPresent(presence, forKey: .presence)
        try c.encodeIfPresent(state, forKey: .state)
        try c.encodeIfPresent(untilMs, forKey: .untilMs)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(unread, forKey: .unread)
        try c.encodeIfPresent(group, forKey: .group)
    }
}

// MARK: - Groups (API.md, "Groups")

/// One group chat (`groups.list`, `groups.get`). `admin`: you are its admin (its creator).
public struct RavenGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var shortId: String
    /// "active", "left" or "removed".
    public var status: String
    public var admin: Bool
    public var adminAddress: String
    public var adminName: String
    public var members: Int
    public var unread: Int
    public var lastMs: Int64?
    public var lastText: String?
    public var lastFrom: String?

    public init(id: String, name: String, shortId: String, status: String = "active", admin: Bool, adminAddress: String,
                adminName: String, members: Int, unread: Int = 0, lastMs: Int64? = nil, lastText: String? = nil,
                lastFrom: String? = nil) {
        self.id = id; self.name = name; self.shortId = shortId; self.status = status; self.admin = admin
        self.adminAddress = adminAddress; self.adminName = adminName; self.members = members; self.unread = unread
        self.lastMs = lastMs; self.lastText = lastText; self.lastFrom = lastFrom
    }

    public var active: Bool { status == "active" }

    public func sanitized() -> RavenGroup {
        var g = self
        g.name = Sanitizer.line(name, maxLength: 64)
        g.adminName = Sanitizer.line(adminName, maxLength: 64)
        g.lastText = lastText.map { Sanitizer.line($0, maxLength: 120) }
        g.lastFrom = lastFrom.map { Sanitizer.line($0, maxLength: 64) }
        return g
    }
}

/// A member of a group: your friend (`friend`), you (`me`), or someone the admin added whom you don't
/// know (shown as "not your friend", named by the admin's `label`).
public struct GroupMember: Codable, Equatable, Identifiable, Sendable {
    public var address: String
    public var shortAddress: String
    public var name: String
    public var label: String
    public var friend: Bool
    public var admin: Bool
    public var me: Bool
    public var id: String { address }

    public init(address: String, shortAddress: String, name: String, label: String = "", friend: Bool, admin: Bool = false,
                me: Bool = false) {
        self.address = address; self.shortAddress = shortAddress; self.name = name; self.label = label
        self.friend = friend; self.admin = admin; self.me = me
    }

    public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

/// One member's copy of a group message of yours: waiting, sent, delivered (a signed receipt) or
/// failed; `via` "relay" when another member passed it on.
public struct GroupReceipt: Codable, Equatable, Sendable {
    public var address: String
    public var name: String
    public var state: String
    public var via: String?

    public init(address: String, name: String, state: String, via: String? = "direct") {
        self.address = address; self.name = name; self.state = state; self.via = via
    }
}

public struct GroupMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var group: String
    public var fromAddress: String
    public var fromName: String
    public var mine: Bool
    public var text: String
    public var atMs: Int64
    /// The member that passed it on, when it was not its author.
    public var viaName: String?
    public var delivered: Int
    public var total: Int
    public var receipts: [GroupReceipt]?

    public init(id: String, group: String, fromAddress: String, fromName: String, mine: Bool, text: String, atMs: Int64,
                viaName: String? = nil, delivered: Int = 0, total: Int = 0, receipts: [GroupReceipt]? = nil) {
        self.id = id; self.group = group; self.fromAddress = fromAddress; self.fromName = fromName; self.mine = mine
        self.text = text; self.atMs = atMs; self.viaName = viaName; self.delivered = delivered; self.total = total
        self.receipts = receipts
    }

    public func sanitized() -> GroupMessage {
        var m = self
        m.text = Sanitizer.text(text)
        m.fromName = Sanitizer.line(fromName, maxLength: 64)
        m.viaName = viaName.map { Sanitizer.line($0, maxLength: 64) }
        m.receipts = receipts?.map { r in
            var r = r
            r.name = Sanitizer.line(r.name, maxLength: 64)
            return r
        }
        return m
    }
}

public struct EventBatch: Codable, Equatable, Sendable {
    public var seq: Int
    public var events: [RavenEvent]
    /// raven-client's extra: events after `after_seq` were lost (dropped for room, or the engine
    /// restarted). The app reloads what it shows instead of trusting `events` (API.md, Events).
    public var reset: Bool?
}

/// A failure envelope: `{"code", "message", "detail"}`. `message` is plain English with one next step.
public struct RavenError: Error, Equatable, Sendable {
    public var code: String
    public var message: String
    public var detail: String

    public init(code: String, message: String, detail: String = "") {
        self.code = code; self.message = message; self.detail = detail
    }

    /// `INTERNAL`: something went wrong inside Raven (or inside this app).
    static func internalError(_ detail: String) -> RavenError {
        RavenError(code: ErrorCode.internalError, message: tr(.errorInternal), detail: detail)
    }

    /// An answer this app cannot read: not JSON, a missing field, a newer contract. Reported as
    /// `INTERNAL` with its own text ("Restart Raven").
    static func badResponse(_ detail: String) -> RavenError {
        RavenError(code: ErrorCode.internalError, message: tr(.errorBadResponse), detail: detail)
    }

    /// `BAD_REQUEST`: an unknown operation or bad arguments (an engine answer to an app bug).
    static func badRequest(_ detail: String) -> RavenError {
        RavenError(code: ErrorCode.badRequest, message: tr(.errorBadRequest), detail: detail)
    }

    public static func from(_ error: Error) -> RavenError {
        (error as? RavenError) ?? .internalError(String(describing: error))
    }
}

/// The error codes of API.md ("Error codes"). A newer engine may send codes not listed here.
public enum ErrorCode {
    public static let notInitialized = "NOT_INITIALIZED"
    public static let profileUnreadable = "PROFILE_UNREADABLE"
    public static let profileLocked = "PROFILE_LOCKED"
    public static let keychainDenied = "KEYCHAIN_DENIED"
    public static let nodeNotRunning = "NODE_NOT_RUNNING"
    public static let notAContact = "NOT_A_CONTACT"
    public static let contactBlocked = "CONTACT_BLOCKED"
    public static let nameClash = "NAME_CLASH"
    public static let cardInvalid = "CARD_INVALID"
    public static let wordsIncomplete = "WORDS_INCOMPLETE"
    public static let messageTooLong = "MESSAGE_TOO_LONG"
    public static let notSentMeetFirst = "NOT_SENT_MEET_FIRST"
    public static let timeRanOut = "TIME_RAN_OUT"
    public static let notAvailableYet = "NOT_AVAILABLE_YET"
    public static let badRequest = "BAD_REQUEST"
    public static let internalError = "INTERNAL"
    /// `network.set`: a setting that needs the person's yes (`agreed`).
    public static let consentNeeded = "CONSENT_NEEDED"
    /// `lock.unlock`: that Raven passphrase is not right.
    public static let passphraseWrong = "PASSPHRASE_WRONG"
    /// `lock.unlock`: this profile has a Raven passphrase and none came.
    public static let passphraseNeeded = "PASSPHRASE_NEEDED"
    /// `lock.unlock`: too many wrong passphrases; wait, then try again.
    public static let unlockWait = "UNLOCK_WAIT"
    /// Groups (API.md, "Groups").
    public static let groupNotFound = "GROUP_NOT_FOUND"
    public static let groupNotAdmin = "GROUP_NOT_ADMIN"
    public static let groupNotMember = "GROUP_NOT_MEMBER"
    public static let groupTooLarge = "GROUP_TOO_LARGE"
    public static let groupAdminCannotLeave = "GROUP_ADMIN_CANNOT_LEAVE"
    public static let groupAlreadyMember = "GROUP_ALREADY_MEMBER"
    public static let groupBadName = "GROUP_BAD_NAME"
    public static let groupQueueFull = "GROUP_QUEUE_FULL"
    public static let groupNoRoute = "GROUP_NO_ROUTE"
}

// MARK: - Network (API.md, "Network")

/// A way's state: on, off, preview (held in this build), lab (a developer build's lab switch), or
/// not on this OS. An unknown value reads as preview (never as on).
public enum WayState: String, LenientEnum, Sendable {
    case on, off, preview, lab
    case notOnThisOs = "not_on_this_os"
    public static var fallback: WayState { .preview }
}

/// One way to reach friends, or a protection, in `network.status`.
public struct NetworkWay: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String?
    public var state: WayState
    public var reason: String?
    public var lab: Bool?
    public var gate: String?
    public var labSwitches: [String]?
    public var canSet: Bool?
    public var setting: Bool?
    public var running: Bool?
    public var detail: String?
}

public struct PortMapping: Codable, Equatable, Sendable {
    public var setting: String?
    public var router: String?
    public var natPmpPcp: WayState?
    public var v4: String?
    public var v4Port: Int?
    public var v6: String?
}

public struct RelayInUse: Codable, Equatable, Sendable {
    public var relay: String
    public var state: String?
    public var source: String?
    public var friendAddress: String?
}

public struct ProxyState: Codable, Equatable, Sendable {
    public var setting: String?
    public var inUse: String?
    public var lines: [String]?
}

public struct LabelValue: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
}

public struct NearbyState: Codable, Equatable, Sendable {
    public var state: String?
    public var saved: Bool?
    public var onThisOs: Bool?
    public var enabled: Bool?
    public var radio: String?
    public var addressPrivacy: String?
    public var inRange: Int?
    public var connected: Int?
    public var rows: [LabelValue]?
}

public struct FriendsCarryMine: Codable, Equatable, Sendable {
    public var setting: String?
    public var mailFriends: Int?
    public var chosenByHand: Bool?
    public var offering: Int?
    public var offeringOverInternet: Int?
    public var offeringReachable: Int?
    public var listedByHand: Int?
}

public struct CarryForFriends: Codable, Equatable, Sendable {
    public var on: Bool
    public var heldMessages: Int64?
    public var heldBytes: Int64?
    public var handoff: Bool?
    public var handoffLines: [String]?
}

public struct RelayForFriends: Codable, Equatable, Sendable {
    public var setting: Bool
    public var offering: Bool?
    public var offeredTo: Int?
}

/// Who carries mail, both ways, and the relay this computer lends.
public struct CarryState: Codable, Equatable, Sendable {
    public var friendsCarryMine: FriendsCarryMine?
    public var carryForFriends: CarryForFriends?
    public var lettersLeft: [String]?
    public var relayForFriends: RelayForFriends?
}

public struct HelpEffects: Codable, Equatable, Sendable {
    public var bridge: String
    public var store: String
    public var relay: String
}

/// The node policy flags `raven node bridge|store|relay` sets, with what each really does.
public struct HelpFlags: Codable, Equatable, Sendable {
    public var bridge: Bool
    public var store: Bool
    public var relay: Bool
    public var automatic: Bool?
    public var effects: HelpEffects?
}

/// What the settings that need a yes mean (shown before `agreed: true`).
public struct NetworkTexts: Codable, Equatable, Sendable {
    public var carryForFriends: String
    public var friendsCarryMine: String
    public var handoff: String
}

/// The Tor way's state, as raven-node's Status line says it (`NetworkStatus.tor`, API.md "The Tor
/// way"): states only, never an address.
public struct TorState: Codable, Equatable, Sendable {
    /// `ready`, `publishing`, `unreachable`, `starting`, `restarting`, `blocked`, `could_not_start`,
    /// `not_built`, `off` or `unknown`.
    public var phase: String
    /// The line after `Tor: `.
    public var words: String?
    public var percent: Int?
    public var why: String?
    public var retry: String?
    /// The onion service's outage history since raven-node started.
    public var outages: String?

    public init(phase: String, words: String? = nil, percent: Int? = nil, why: String? = nil,
                retry: String? = nil, outages: String? = nil) {
        self.phase = phase
        self.words = words
        self.percent = percent
        self.why = why
        self.retry = retry
        self.outages = outages
    }
}

/// Result of `network.status`.
public struct NetworkStatus: Codable, Equatable, Sendable {
    public var build: String
    public var node: String?
    public var carriers: [NetworkWay]
    public var protections: [NetworkWay]?
    public var listening: [String]?
    public var port: Int?
    public var internetListen: String?
    public var p2pListen: String?
    public var p2pAddresses: [String]?
    public var lanUntilMs: Int64?
    /// raven-node's settings file could not be read: the defaults apply.
    public var policyUnreadable: Bool?
    public var portMapping: PortMapping?
    public var relays: [RelayInUse]?
    public var proxy: ProxyState?
    public var nearby: NearbyState?
    public var carry: CarryState?
    public var help: HelpFlags?
    public var hideIp: Bool?
    public var labSwitches: [String]?
    public var texts: NetworkTexts?
    /// Tor's state while raven-node's Status has its line (lab).
    public var tor: TorState?

    /// One way (or protection) by its id.
    public func way(_ id: String) -> NetworkWay? {
        (carriers + (protections ?? [])).first { $0.id == id }
    }
}

/// One change `network.set` made (`applies`: `now` or `restart`).
public struct NetworkChange: Codable, Equatable, Sendable {
    public var setting: String
    public var effect: String
    public var applies: String
    public var detail: [String]?
}

/// Result of `network.set`.
public struct NetworkSetResult: Codable, Equatable, Sendable {
    public var changes: [NetworkChange]
    public var restartNeeded: Bool
    public var status: NetworkStatus
}

public struct CheckSummaryRow: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
}

public struct CheckRow: Codable, Equatable, Sendable {
    public var key: String
    public var value: String
    public var plain: String?
}

/// Result of `network.check`.
public struct NetworkCheck: Codable, Equatable, Sendable {
    public var summary: [CheckSummaryRow]
    public var nextStep: String
    public var rows: [CheckRow]
    public var router: [CheckRow]?
    /// The CLI's own summary and next step, shown only under Technical details.
    public var technical: [String]?
}

public struct RouteEntry: Codable, Equatable, Sendable {
    public var kind: String
    public var label: String?
    public var value: String?
    public var via: [String]?
    public var next: String?
    public var state: WayState?
}

public struct LearnedRoutes: Codable, Equatable, Sendable {
    public var relays: Int?
    public var direct: Int?
    public var mailFriends: Int?
    public var peerId: String?
    public var peerIdProven: Bool?
    public var lanPort: Int?
    public var expiresAtMs: Int64?
}

/// A friend named among a contact's mail friends.
public struct FriendRef: Codable, Equatable, Sendable {
    public var address: String?
    public var name: String?
    public var takesHandoffs: Bool?
    public var usable: Bool?
}

public struct Coverage: Codable, Equatable, Sendable {
    public var kind: String
    public var name: String
    public var until: String
}

/// How long a message written now could wait while the friend is away (`carriers.away`): until a time,
/// or not at all (meet first). The rule `raven contact list` and the terminal app use. `firstMessage`:
/// none can because Raven hasn't connected with the friend yet (a first message needs both online).
public struct AwayWait: Codable, Equatable, Sendable {
    public var untilMs: Int64?
    public var meetFirst: Bool?
    public var firstMessage: Bool?
}

public struct ContactCarriers: Codable, Equatable, Sendable {
    public var hints: WayState?
    public var told: [FriendRef]?
    public var toldUnknown: Int?
    public var listed: [FriendRef]?
    public var coverage: Coverage?
    public var away: AwayWait?
    public var receiptsStranded: Bool?
}

/// Where Raven reaches the friend on the local network now (`lan_now`), and whether the saved LAN
/// address is another, old one.
public struct LanNow: Codable, Equatable, Sendable {
    public var addr: String
    public var atMs: Int64
    public var savedStale: Bool?
}

/// Result of `contacts.routes`: never the friend's words or old code.
public struct ContactRoutes: Codable, Equatable, Sendable {
    public var address: String
    public var verified: Bool
    public var hideIp: Bool?
    public var routes: [RouteEntry]
    public var learned: LearnedRoutes?
    public var lanNow: LanNow?
    public var carriers: ContactCarriers?
}

/// Result of `contacts.set_routes`.
public struct SetRoutesResult: Codable, Equatable, Sendable {
    public var contact: Contact
    public var routes: ContactRoutes
}

public struct SecurityNotice: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64
    /// `alert` or `warning`.
    public var level: String
    public var address: String?
    public var name: String?
    public var headline: String
    public var whatRavenDid: String?
    public var whatToDo: String?
    public var when: String?
    public var details: [LabelValue]?
}

/// What the running raven-node counted (`security.status` `node`; missing when it doesn't answer).
public struct SecurityNodeCounts: Codable, Equatable, Sendable {
    public var strangersRefused1h: Int?
    public var failedHandshakes1h: Int?
    public var bansActive: Int?
    public var linkTagFailures24h: Int?
    public var alertsOpen: Int?

    public init(strangersRefused1h: Int? = nil, failedHandshakes1h: Int? = nil, bansActive: Int? = nil,
                linkTagFailures24h: Int? = nil, alertsOpen: Int? = nil) {
        self.strangersRefused1h = strangersRefused1h; self.failedHandshakes1h = failedHandshakes1h
        self.bansActive = bansActive; self.linkTagFailures24h = linkTagFailures24h; self.alertsOpen = alertsOpen
    }

    /// The wire names end in digits (`strangers_refused_1h`), which `convertFromSnakeCase` turns into
    /// `...1H`; the keys are matched without case and underscores instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LooseKey.self)
        func int(_ name: String) -> Int? {
            guard let key = c.allKeys.first(where: { LooseKey.fold($0.stringValue) == LooseKey.fold(name) }) else { return nil }
            return try? c.decode(Int.self, forKey: key)
        }
        self.init(strangersRefused1h: int("strangers_refused_1h"), failedHandshakes1h: int("failed_handshakes_1h"),
                  bansActive: int("bans_active"), linkTagFailures24h: int("link_tag_failures_24h"), alertsOpen: int("alerts_open"))
    }
}

/// A coding key matched loosely (see `SecurityNodeCounts`).
struct LooseKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    static func fold(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "_", with: "") }
}

/// Result of `security.status` (`raven security`, read-only).
public struct SecurityStatus: Codable, Equatable, Sendable {
    public var available: Bool
    public var lab: Bool?
    /// `off`, `unsealed` or `live`.
    public var kept: String
    public var notices: [SecurityNotice]
    public var counted: Int?
    public var node: SecurityNodeCounts?
}

/// Result of `lock.state`, `lock.now` and `lock.unlock` (Lock v2).
public struct LockState: Codable, Equatable, Sendable {
    public var available: Bool
    public var lab: Bool?
    public var supported: Bool
    public var locked: Bool
    public var hasPassphrase: Bool?
    public var note: String?
}

/// Result of `updates.status` (`raven update status`, read-only; installing stays in the CLI).
public struct UpdatesStatus: Codable, Equatable, Sendable {
    public var available: Bool
    public var bundles: Bool?
    public var fromFriends: Bool?
    public var lab: Bool?
    public var lines: [String]
    public var summary: String?
    public var offer: [String]?
    public var install: String
    public var installText: String?
}
