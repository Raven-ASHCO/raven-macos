import Foundation

/// The Network screens' state (desktop/api/NETWORK_PARITY.md): every way to reach friends
/// (`network.status` / `network.set`), the consent sheets, the restart prompt, Check network
/// (`network.check`), a friend's routes (`contacts.routes` / `contacts.set_routes`), Security
/// (`security.status`) and Updates (`updates.status`). Lock v2 lives in `AppModel` (it decides the
/// locked screen).
///
/// Nothing here changes a setting without the engine: a switch shows the engine's answer, never a
/// guess. A setting that needs the person's yes opens its consent sheet first and is sent with
/// `agreed: true` only after they agree.
@MainActor
public final class NetworkModel: ObservableObject {
    /// The restart prompt after `network.set` said `restart_needed`.
    public enum Restart: Equatable {
        case asking, working, restarted
        /// A login service runs raven-node: left running (the engine's note says how to restart it).
        case managed(String)
        /// The stop did not happen (`still_running`, `advice`): the note says why or what to do.
        case notStopped(String)
        case failed(RavenError)
    }

    /// A refusal shown under the row the person changed (e.g. NOT_AVAILABLE_YET).
    public struct RowError: Equatable {
        public let setting: String
        public let error: RavenError
    }

    let engine: RavenEngine
    weak var app: AppModel?

    @Published public private(set) var status: NetworkStatus?
    @Published public private(set) var loadError: RavenError?
    @Published public private(set) var rowError: RowError?
    /// What the last `network.set` changed, in the engine's words.
    @Published public private(set) var changes: [NetworkChange] = []
    /// Settings with a `network.set` in flight (their switch is disabled meanwhile).
    @Published public private(set) var busy: Set<String> = []
    /// The setting whose consent sheet is open, and what went wrong after the person agreed.
    @Published public private(set) var consent: String?
    @Published public private(set) var consentError: RavenError?
    @Published public private(set) var restart: Restart?
    @Published public private(set) var check: NetworkCheck?
    @Published public private(set) var checkError: RavenError?
    @Published public private(set) var checking = false
    @Published public private(set) var askingRouter = false
    @Published public private(set) var routes: [String: ContactRoutes] = [:]
    @Published public private(set) var routesError: RavenError?
    @Published public private(set) var security: SecurityStatus?
    @Published public private(set) var securityError: RavenError?
    @Published public private(set) var updates: UpdatesStatus?
    @Published public private(set) var updatesError: RavenError?

    public init(engine: RavenEngine) {
        self.engine = engine
    }

    // MARK: What the screens ask

    /// The settings that open a consent sheet before they are turned on: exactly the three
    /// raven-client answers with CONSENT_NEEDED without `agreed: true` (API.md, the consent rule).
    /// Relay for friends and the bridge, store and relay flags show their effect beside the switch.
    public static let consentSettings = ["carry_for_friends", "friends_carry_mine", "handoff"]

    /// The `network.set` setting behind a way's switch (nil: the way has none).
    public static func setting(forWay id: String) -> String? {
        switch id {
        case "lan", "internet", "port_mapping", "p2p", "proxy", "handoff", "nearby": return id
        case "friend_relay": return "relay_for_friends"
        case "custody": return "friends_carry_mine"
        default: return nil
        }
    }

    /// Developer build with lab switches set: the screens show the "Lab switches on" banner.
    /// A release engine reads no switch and lists none, so a release build never shows it.
    public static func labSwitches(status: NetworkStatus?, node: NodeStatus?) -> [String] {
        let build = status?.build ?? node?.build
        guard build == "dev" else { return [] }
        let list = status?.labSwitches ?? node?.labSwitches ?? []
        return list.map { Sanitizer.line($0, maxLength: 64) }.filter { !$0.isEmpty }
    }

    /// A way's switch: shown where `network.set` changes the way; it can be used unless the way is
    /// not on this computer, or held in this build and off (turning a way off is always allowed).
    public static func toggle(for way: NetworkWay) -> (shown: Bool, enabled: Bool) {
        guard way.canSet == true, let setting = setting(forWay: way.id), setting != "proxy" else { return (false, false) }
        switch way.state {
        case .notOnThisOs: return (true, false)
        case .preview: return (true, way.setting == true)
        case .on, .off, .lab: return (true, true)
        }
    }

    /// Whether a way's switch reads on: the person's setting where the engine gives one, else the state.
    /// The "This profile's port" line's port: only while raven-node doesn't run (E1: it said 7420
    /// two lines below "Listening on port 17420").
    public static func profilePortLine(status: NetworkStatus, node: NodeStatus?) -> Int? {
        guard node?.running != true, status.node != "running" else { return nil }
        return status.port
    }

    public static func isOn(_ way: NetworkWay) -> Bool {
        way.setting ?? (way.state == .on || way.state == .lab)
    }

    // MARK: network.status / network.set

    public func refresh() async {
        do {
            status = try await engine.networkStatus()
            loadError = nil
        } catch {
            loadError = RavenError.from(error)
        }
    }

    /// A switch was flipped. Turning on a setting that needs the person's yes opens its consent
    /// sheet; nothing is sent until they agree.
    public func toggle(_ setting: String, on: Bool) async {
        if on && NetworkModel.consentSettings.contains(setting) {
            ask(setting)
            return
        }
        await apply([setting: .bool(on)], setting: setting)
    }

    /// LAN for a while (`30m`, `1h`, ... up to `24h`).
    public func lanFor(_ span: String) async {
        await apply(["lan": true, "lan_for": .string(span)], setting: "lan")
    }

    /// `auto`, `off` or `http://host:port` (never a user name or password).
    public func setProxy(_ value: String) async {
        let clean = Sanitizer.line(value, maxLength: 200)
        guard !clean.isEmpty else { return }
        await apply(["proxy": .string(clean)], setting: "proxy")
    }

    func ask(_ setting: String) {
        consent = setting
        consentError = nil
        app?.sheet = .consent(setting)
    }

    /// The person agreed in the consent sheet: now (and only now) `agreed: true` goes to the engine.
    public func agree() async {
        guard let setting = consent else { return }
        consentError = nil
        if await apply([setting: true, "agreed": true], setting: setting) {
            consent = nil
            if app?.sheet == .consent(setting) { app?.sheet = nil }
        }
    }

    /// "Not now": nothing was sent, nothing changes.
    public func decline() {
        if let setting = consent, app?.sheet == .consent(setting) { app?.sheet = nil }
        consent = nil
        consentError = nil
    }

    /// One `network.set`. A refusal is shown under the row (or in the consent sheet); CONSENT_NEEDED
    /// for a request without `agreed` opens the consent sheet (a newer engine may ask for more yeses).
    @discardableResult
    func apply(_ args: [String: JSONValue], setting: String) async -> Bool {
        busy.insert(setting)
        defer { busy.remove(setting) }
        rowError = nil
        do {
            let result = try await engine.setNetwork(args)
            status = result.status
            changes = result.changes
            if let node = try? await engine.nodeStatus() { app?.node = node }
            if result.restartNeeded {
                restart = .asking
                app?.sheet = .restartNode
            }
            return true
        } catch {
            let e = RavenError.from(error)
            if e.code == ErrorCode.consentNeeded, args["agreed"] == nil {
                ask(setting)
            } else if consent == setting {
                consentError = e
            } else {
                rowError = RowError(setting: setting, error: e)
            }
            return false
        }
    }

    public func dismissChanges() { changes = [] }

    // MARK: Restart the background program

    /// `node.stop` then `node.start`. A raven-node a login service runs is left running (the engine
    /// never stops one) and the note says how to restart it; nothing is started then.
    public func restartNode() async {
        restart = .working
        do {
            let stopped = try await engine.stopNode()
            app?.node = stopped
            let note = stopped.note ?? ""
            switch stopped.stop {
            case "managed":
                restart = .managed(note)
            case "still_running", "advice":
                restart = .notStopped(note)
            case "failed":
                restart = .failed(RavenError(code: ErrorCode.internalError, message: tr(.errorInternal), detail: note))
            default:
                let started = try await engine.startNode()
                app?.node = started
                restart = .restarted
            }
        } catch {
            restart = .failed(RavenError.from(error))
        }
        await refresh()
    }

    /// "Later" or Close: the prompt goes; the changes wait for the next start.
    public func dismissRestart() {
        restart = nil
        if app?.sheet == .restartNode { app?.sheet = nil }
    }

    // MARK: Check network

    /// `network.check`; `router: true` also asks the router (read-only, a few seconds).
    public func runCheck(router: Bool = false) async {
        if router { askingRouter = true } else { checking = true }
        defer {
            if router { askingRouter = false } else { checking = false }
        }
        do {
            let result = try await engine.checkNetwork(router: router)
            // A plain check keeps the router's answer from an earlier ask.
            var merged = result
            if !router, merged.router == nil { merged.router = check?.router }
            check = merged
            checkError = nil
        } catch {
            checkError = RavenError.from(error)
        }
    }

    // MARK: A friend's routes

    public func loadRoutes(_ address: String) async {
        do {
            routes[address] = try await engine.contactRoutes(address: address)
            routesError = nil
        } catch {
            routesError = RavenError.from(error)
        }
    }

    /// `contacts.set_routes`; every value is checked by the engine before anything is saved.
    @discardableResult
    public func setRoutes(_ address: String, _ changes: [String: JSONValue]) async -> Bool {
        do {
            let result = try await engine.setContactRoutes(address: address, changes)
            routes[address] = result.routes
            routesError = nil
            try? await app?.reloadContacts()
            return true
        } catch {
            routesError = RavenError.from(error)
            return false
        }
    }

    /// The saved LAN address replaced with the one Raven reaches the friend at now (`lan_now`, through
    /// `contacts.set_address`), then the routes read again.
    @discardableResult
    public func useLanNow(_ address: String, _ addr: String) async -> Bool {
        do {
            _ = try await engine.setContactAddress(address: address, lan: addr)
            routesError = nil
            try? await app?.reloadContacts()
            await loadRoutes(address)
            return true
        } catch {
            routesError = RavenError.from(error)
            return false
        }
    }

    // MARK: Security and updates (read-only)

    public func loadSecurity() async {
        do {
            security = try await engine.securityStatus()
            securityError = nil
        } catch {
            securityError = RavenError.from(error)
        }
    }

    public func loadUpdates() async {
        do {
            updates = try await engine.updatesStatus()
            updatesError = nil
        } catch {
            updatesError = RavenError.from(error)
        }
    }
}
