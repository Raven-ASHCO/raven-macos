import Foundation

/// The app's only way to Raven's logic: one call, JSON in and JSON out (desktop/api/API.md).
///
/// `call` returns the `result` object of a success envelope, or throws `RavenError` built from a
/// failure envelope. The typed wrappers below decode results into the API's types and sanitise every
/// string before it can reach the screen.
public protocol RavenEngine: AnyObject, Sendable {
    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue
}

/// Where engine calls run. `raven_call` is thread-safe and may block (`node.start` can take a few
/// seconds, API.md), so no engine call ever runs on the main thread: every engine hands its blocking
/// `raven_call`-shaped function to `run`, which executes it on this queue and resumes the caller with
/// the response. The caller (the `@MainActor` AppModel) then applies the result on the main thread.
public enum EngineQueue {
    static let queue = DispatchQueue(label: AppIdentity.bundleID + ".engine", qos: .userInitiated,
                                     attributes: .concurrent)

    /// Runs `rawCall(request)` off the main thread and returns its response envelope.
    public static func run(_ request: String, _ rawCall: @escaping @Sendable (String) -> String) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: rawCall(request)) }
        }
    }
}

/// Envelope v1: `{"v": 1, "op", "args"}` -> `{"v": 1, "ok": true, "result"}` or
/// `{"v": 1, "ok": false, "error": {"code", "message", "detail"}}`.
public enum RavenEnvelope {
    public static let version = 1

    public static func request(op: String, args: [String: JSONValue]) -> String {
        JSONValue.object(["v": .int(version), "op": .string(op), "args": .object(args)]).text()
    }

    public static func success(_ result: JSONValue) -> String {
        JSONValue.object(["v": .int(version), "ok": true, "result": result]).text()
    }

    public static func failure(_ error: RavenError) -> String {
        JSONValue.object([
            "v": .int(version), "ok": false,
            "error": ["code": .string(error.code), "message": .string(error.message), "detail": .string(error.detail)],
        ]).text()
    }

    /// Parses a request (used by engines written in Swift, such as MockRaven).
    public static func parseRequest(_ json: String) throws -> (op: String, args: [String: JSONValue]) {
        let value = try JSONValue.parse(json)
        guard let op = value["op"]?.string else { throw RavenError.badRequest("request without op") }
        if let v = value["v"]?.int, v > version {
            throw RavenError.badRequest("unsupported envelope version \(v)")
        }
        return (op, value["args"]?.object ?? [:])
    }

    /// Parses a response; throws the failure as `RavenError`. Unknown fields are ignored.
    public static func parseResponse(_ json: String) throws -> JSONValue {
        let value: JSONValue
        do { value = try JSONValue.parse(json) } catch {
            throw RavenError.badResponse("response is not JSON: \(json.prefix(200))")
        }
        if value["ok"]?.bool == true { return value["result"] ?? .object([:]) }
        let e = value["error"]
        throw RavenError(code: Sanitizer.line(e?["code"]?.string ?? ErrorCode.internalError, maxLength: 40),
                         message: Sanitizer.text(e?["message"]?.string ?? tr(.errorBadResponse), maxLength: 600),
                         detail: Sanitizer.text(e?["detail"]?.string ?? "", maxLength: 4000))
    }
}

// MARK: - Typed wrappers (one per operation in API.md)

extension RavenEngine {
    func typed<T: Decodable>(_ op: String, _ args: [String: JSONValue] = [:], key: String? = nil, as type: T.Type) async throws -> T {
        let result = try await call(op: op, args: args).sanitized()
        if let key {
            guard let inner = result[key] else { throw RavenError.badResponse("\(op): missing \(key)") }
            return try inner.decode(T.self)
        }
        return try result.decode(T.self)
    }

    public func appInfo() async throws -> AppInfo { try await typed("app.info", as: AppInfo.self) }
    public func profileState() async throws -> ProfileState { try await typed("profile.state", as: ProfileState.self) }

    public func createIdentity(displayName: String?) async throws -> Identity {
        try await typed("identity.create", ["display_name": .opt(displayName)], as: Identity.self)
    }

    public func me() async throws -> Identity { try await typed("identity.me", as: Identity.self) }

    public func makeCard(includeAddress: Bool) async throws -> ShareCard {
        try await typed("card.make", ["include_address": .bool(includeAddress)], as: ShareCard.self)
    }

    public func parseCard(_ text: String) async throws -> CardSummary {
        try await typed("card.parse", ["text": .string(text)], as: CardSummary.self)
    }

    public func contacts() async throws -> [Contact] {
        try await typed("contacts.list", key: "contacts", as: [Contact].self).map { $0.sanitized() }
    }

    public func addContact(text: String, name: String) async throws -> Contact {
        try await typed("contacts.add", ["text": .string(text), "name": .string(name)], key: "contact", as: Contact.self).sanitized()
    }

    public func renameContact(address: String, name: String) async throws -> Contact {
        try await typed("contacts.rename", ["address": .string(address), "name": .string(name)], key: "contact", as: Contact.self).sanitized()
    }

    public func removeContact(address: String) async throws {
        _ = try await call(op: "contacts.remove", args: ["address": .string(address)])
    }

    public func setContactAddress(address: String, lan: String) async throws -> Contact {
        try await typed("contacts.set_address", ["address": .string(address), "lan": .string(lan)], key: "contact", as: Contact.self).sanitized()
    }

    public func checkWords(address: String, words: [String]) async throws -> VerifyResult {
        try await typed("verify.check_words", ["address": .string(address), "words": .array(words.map { .string($0) })],
                        key: "result", as: VerifyResult.self)
    }

    /// The old letters-and-digits code, for friends with an older Raven. Only match or mismatch
    /// (anything else is treated as a mismatch); on a match the engine pins the friend as verified.
    public func checkOldCode(address: String, code: String) async throws -> VerifyResult {
        let result = try await typed("verify.check_old_code", ["address": .string(address), "code": .string(code)],
                                     key: "result", as: VerifyResult.self)
        return result == .match ? .match : .mismatch
    }

    public func wordHint(prefix: String) async throws -> String? {
        let result = try await call(op: "verify.word_hint", args: ["prefix": .string(prefix)]).sanitized()
        return result["word"]?.string.map { Sanitizer.line($0, maxLength: 16) }
    }

    public func history(address: String, before: String? = nil, limit: Int = 100) async throws -> [Message] {
        var args: [String: JSONValue] = ["address": .string(address), "limit": .int(limit)]
        if let before { args["before"] = .string(before) }
        return try await typed("messages.history", args, key: "messages", as: [Message].self).map { $0.sanitized() }
    }

    public func send(address: String, text: String) async throws -> Message {
        try await typed("messages.send", ["address": .string(address), "text": .string(text)], key: "message", as: Message.self).sanitized()
    }

    public func retry(id: String) async throws -> Message {
        try await typed("messages.retry", ["id": .string(id)], key: "message", as: Message.self).sanitized()
    }

    public func stop(id: String) async throws -> Message {
        try await typed("messages.stop", ["id": .string(id)], key: "message", as: Message.self).sanitized()
    }

    /// `messages.mark_read`: the friend's chat is read up to `upTo` (default its newest message), in this
    /// app and the terminal app; never moved back. The friend's unread count afterwards.
    @discardableResult
    public func markRead(address: String, upTo: String? = nil) async throws -> Int {
        var args: [String: JSONValue] = ["address": .string(address)]
        if let upTo { args["id"] = .string(upTo) }
        return try await call(op: "messages.mark_read", args: args)["unread"]?.int ?? 0
    }

    /// `messages.delete`: an ended message of yours leaves the chat for good.
    public func deleteMessage(id: String) async throws {
        _ = try await call(op: "messages.delete", args: ["id": .string(id)])
    }

    public func details(id: String) async throws -> MessageDetails {
        var d = try await typed("messages.details", ["id": .string(id)], as: MessageDetails.self)
        d.message = d.message.sanitized()
        return d
    }

    public func nodeStatus() async throws -> NodeStatus { try await typed("node.status", as: NodeStatus.self) }
    public func startNode() async throws -> NodeStatus { try await typed("node.start", as: NodeStatus.self) }
    public func stopNode() async throws -> NodeStatus { try await typed("node.stop", as: NodeStatus.self) }

    public func settings() async throws -> RavenSettings { try await typed("settings.get", as: RavenSettings.self) }

    /// `partial` uses the wire names, e.g. `["reduced_motion": true]` or `["keep_chats_days": nil]`.
    public func setSettings(_ partial: [String: JSONValue]) async throws -> RavenSettings {
        try await typed("settings.set", partial, as: RavenSettings.self)
    }

    public func poll(after seq: Int) async throws -> EventBatch {
        var batch = try await typed("events.poll", ["after_seq": .int(seq)], as: EventBatch.self)
        batch.events = batch.events.map { e in
            var e = e
            e.message = e.message?.sanitized()
            e.path = e.path.map { Sanitizer.line($0, maxLength: 40) }
            e.pathKind = e.pathKind.map { Sanitizer.line($0, maxLength: 24) }
            return e
        }
        return batch
    }

    public func privacyState() async throws -> PrivacyState { try await typed("privacy.state", as: PrivacyState.self) }
    public func lock() async throws -> ProfileState { try await typed("privacy.lock", as: ProfileState.self) }
    public func unlock() async throws -> ProfileState { try await typed("privacy.unlock", as: ProfileState.self) }

    /// Encrypts everything Raven stores on this computer. Read `privacy.state` afterwards.
    public func encrypt() async throws { _ = try await call(op: "privacy.encrypt", args: [:]) }

    /// Removes Raven's data from this computer; afterwards `profile.state` is `new`.
    public func erase() async throws { _ = try await call(op: "privacy.erase", args: ["confirm": "erase"]) }

    // MARK: Network (API.md, "Network")

    /// Every way to reach friends and what the background program does.
    public func networkStatus() async throws -> NetworkStatus { try await typed("network.status", as: NetworkStatus.self) }

    /// `partial` uses the wire names, e.g. `["store": false]` or `["carry_for_friends": true, "agreed": true]`.
    /// A held way turned on is NOT_AVAILABLE_YET; a setting without the person's yes CONSENT_NEEDED.
    public func setNetwork(_ partial: [String: JSONValue]) async throws -> NetworkSetResult {
        try await typed("network.set", partial, as: NetworkSetResult.self)
    }

    /// `raven doctor`'s summary and network rows; `router` also asks the router (read-only, ~4 s).
    public func checkNetwork(router: Bool = false) async throws -> NetworkCheck {
        try await typed("network.check", ["router": .bool(router)], as: NetworkCheck.self)
    }

    public func contactRoutes(address: String) async throws -> ContactRoutes {
        try await typed("contacts.routes", ["address": .string(address)], as: ContactRoutes.self)
    }

    /// `changes` uses the wire names: `internet`, `p2p`, `via`, `clear`, `custodians`, `hide_ip`.
    public func setContactRoutes(address: String, _ changes: [String: JSONValue]) async throws -> SetRoutesResult {
        var args = changes
        args["address"] = .string(address)
        var r = try await typed("contacts.set_routes", args, as: SetRoutesResult.self)
        r.contact = r.contact.sanitized()
        return r
    }

    public func securityStatus() async throws -> SecurityStatus { try await typed("security.status", as: SecurityStatus.self) }
    public func lockState() async throws -> LockState { try await typed("lock.state", as: LockState.self) }
    /// Lock v2: the background program keeps running without its keys.
    public func lockNow() async throws -> LockState { try await typed("lock.now", as: LockState.self) }

    /// Lock v2's unlock; the passphrase goes only to the background program.
    public func lockUnlock(passphrase: String? = nil) async throws -> LockState {
        try await typed("lock.unlock", ["passphrase": .opt(passphrase)], as: LockState.self)
    }

    /// `raven update status`; installing stays in the CLI.
    public func updatesStatus() async throws -> UpdatesStatus { try await typed("updates.status", as: UpdatesStatus.self) }

    // MARK: Groups (API.md, "Groups"; lab only: a release engine says `available: false`)

    /// `groups.list`: whether this build has groups, and the groups.
    public func groups() async throws -> (available: Bool, groups: [RavenGroup]) {
        let result = try await call(op: "groups.list", args: [:]).sanitized()
        let available = result["available"]?.bool ?? false
        let groups = try (result["groups"] ?? .array([])).decode([RavenGroup].self).map { $0.sanitized() }
        return (available, groups)
    }

    public func group(_ id: String) async throws -> (group: RavenGroup, members: [GroupMember]) {
        let result = try await call(op: "groups.get", args: ["group": .string(id)]).sanitized()
        return try Self.groupAndMembers(result, op: "groups.get")
    }

    public func createGroup(name: String, members: [String]) async throws -> (group: RavenGroup, members: [GroupMember]) {
        let result = try await call(op: "groups.create", args: ["name": .string(name),
                                                                "members": .array(members.map { .string($0) })]).sanitized()
        return try Self.groupAndMembers(result, op: "groups.create")
    }

    public func addGroupMembers(_ id: String, members: [String]) async throws -> (group: RavenGroup, members: [GroupMember]) {
        let result = try await call(op: "groups.add", args: ["group": .string(id),
                                                             "members": .array(members.map { .string($0) })]).sanitized()
        return try Self.groupAndMembers(result, op: "groups.add")
    }

    public func removeGroupMember(_ id: String, member: String) async throws -> (group: RavenGroup, members: [GroupMember]) {
        let result = try await call(op: "groups.remove", args: ["group": .string(id), "member": .string(member)]).sanitized()
        return try Self.groupAndMembers(result, op: "groups.remove")
    }

    public func leaveGroup(_ id: String) async throws -> RavenGroup {
        try await typed("groups.leave", ["group": .string(id)], key: "group", as: RavenGroup.self).sanitized()
    }

    public func groupHistory(_ id: String, before: String? = nil, limit: Int = 100) async throws -> [GroupMessage] {
        var args: [String: JSONValue] = ["group": .string(id), "limit": .number(Double(limit))]
        if let before { args["before"] = .string(before) }
        return try await typed("groups.history", args, key: "messages", as: [GroupMessage].self).map { $0.sanitized() }
    }

    public func sendToGroup(_ id: String, text: String) async throws -> GroupMessage {
        try await typed("groups.send", ["group": .string(id), "text": .string(text)], key: "message",
                        as: GroupMessage.self).sanitized()
    }

    public func markGroupRead(_ id: String) async throws {
        _ = try await call(op: "groups.mark_read", args: ["group": .string(id)])
    }

    static func groupAndMembers(_ result: JSONValue, op: String) throws -> (group: RavenGroup, members: [GroupMember]) {
        guard let g = result["group"], let m = result["members"] else { throw RavenError.badResponse("\(op): missing group") }
        return (try g.decode(RavenGroup.self).sanitized(), try m.decode([GroupMember].self))
    }
}
