import SwiftUI
import AppKit
import os

/// The app's log (Console.app, subsystem io.github.raven-ashco.Raven): which engine runs and the
/// profile state it reported at start. Never anything about friends, messages or keys.
let engineLog = Logger(subsystem: AppIdentity.bundleID, category: "engine")

/// The 1-second clock for relative times ("node ok · 5 s", "In touch 2 min ago") and the menu-bar
/// mark. Kept apart from `AppModel` so only the few views that show a relative time re-render each
/// second. Polling `events.poll` is a separate loop (see `AppModel.pollInterval`).
@MainActor
public final class ClockModel: ObservableObject {
    @Published public private(set) var now: Date
    @Published public private(set) var tick = 0

    public init(now: Date = Date()) { self.now = now }

    func set(_ date: Date) {
        now = date
        tick &+= 1
    }
}

/// Everything the screens show, fed only by engine calls and engine events.
///
/// Threading: the model lives on the main actor, but no engine call runs there. Every call goes
/// through the engine's `call`, which runs the blocking `raven_call` on `EngineQueue` and resumes
/// here with the result, so a slow `node.start` never freezes a window.
///
/// Motion is driven by events (API.md, "Event"): `status_ok` bumps `heartbeatPulse`, `send_started`,
/// `receipt` and `incoming` queue `RouteMotion`s for the open chat, `retry` bumps `retryPulses`,
/// `presence` bumps `presenceBlinks`. When motion is off, the counters still change (texts update)
/// but no route motion is queued and nothing is animated.
@MainActor
public final class AppModel: ObservableObject {
    public enum Phase: Equatable { case loading, welcome, setup, ready, locked, failed(RavenError) }
    public enum SetupStep: Int, Comparable {
        case name, receive, creating, words
        public static func < (a: SetupStep, b: SetupStep) -> Bool { a.rawValue < b.rawValue }
    }
    public enum Sheet: Identifiable, Equatable {
        case addFriend, checkWords(String), messageDetails(String), network, quit, you
        /// The consent sheet of a network setting (`network.set` name), the restart prompt, and a
        /// friend's routes (by address).
        case consent(String), restartNode, friendRoutes(String)
        /// Lock now's question (what Lock does and doesn't protect), and renaming a friend.
        case confirmLock, rename(String)
        /// Groups: a new group, a group's members (add, remove), leaving a group.
        case newGroup, groupMembers(String), leaveGroup(String)
        public var id: String {
            switch self {
            case .addFriend: return "add"
            case .checkWords(let a): return "check-\(a)"
            case .messageDetails(let id): return "details-\(id)"
            case .network: return "network"
            case .quit: return "quit"
            case .you: return "you"
            case .consent(let setting): return "consent-\(setting)"
            case .restartNode: return "restart"
            case .friendRoutes(let a): return "routes-\(a)"
            case .confirmLock: return "confirm-lock"
            case .rename(let a): return "rename-\(a)"
            case .newGroup: return "new-group"
            case .groupMembers(let g): return "group-members-\(g)"
            case .leaveGroup(let g): return "leave-group-\(g)"
            }
        }
    }
    /// What the main window's right side shows: the open chat, a group chat, one of the network
    /// pages, or Settings (Calm: Settings live in the main window).
    public enum Page: Equatable { case chat, group, network, checkNetwork, security, updates, settings }
    /// The seven sections of Settings, in their order.
    public enum SettingsSection: String, CaseIterable, Equatable {
        case general, appearance, privacy, lock, network, updates, about
    }
    /// Settings > Appearance > Theme: follow this computer, or always light or dark (this app only).
    public enum ThemeChoice: String, CaseIterable, Equatable {
        case system, light, dark
        public var scheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    public enum Tone: Equatable { case secondary, accent, success, warning, danger }
    public struct Toast: Equatable {
        public var text: String
        public var tone: Tone
        public var until: Date
    }
    public enum RouteKind: Equatable { case out, back, incoming }
    public struct RouteMotion: Identifiable, Equatable {
        public let id = UUID()
        public let kind: RouteKind
        public let address: String
    }
    public enum QuitChoice { case quit, quitAndStop, stay }
    /// A packet pinned on the route line, for snapshots only.
    public struct PinnedRoute {
        public let kind: RouteKind
        public let progress: Double
        public init(kind: RouteKind, progress: Double) { self.kind = kind; self.progress = progress }
    }

    public let engine: RavenEngine
    public let clock: ClockModel
    /// The Network screens (network, check, routes, security, updates).
    public let network: NetworkModel
    let nowProvider: () -> Date

    @Published public var phase: Phase = .loading
    @Published public var setupStep: SetupStep = .name
    @Published public var setupName = ""
    @Published public var setupReceive = true
    @Published public var identity: Identity?
    @Published public var contacts: [Contact] = []
    @Published public var selectedAddress: String?
    @Published public var messages: [String: [Message]] = [:]
    /// Unread messages by friend, as the engine counts them (`Contact.unread` and the `unread` event): a
    /// chat read in this app or in the terminal app counts as read in both, also after a restart.
    @Published public var unread: [String: Int] = [:]
    @Published public var node: NodeStatus?
    @Published public var settings = RavenSettings()
    /// `privacy.state`; `.unavailable` until the engine says otherwise (and when it cannot say).
    @Published public var privacy = PrivacyState.unavailable
    @Published public var appInfo: AppInfo?
    @Published public var toast: Toast?
    @Published public var lastStatusOk: Date?
    @Published public var heartbeatPulse = 0
    @Published public var routeQueue: [RouteMotion] = []
    @Published public var retryPulses: [String: Int] = [:]
    @Published public var presenceBlinks: [String: Int] = [:]
    @Published public var freshUntil: [String: Date] = [:]
    @Published public var lastPath: [String: String] = [:]
    // Groups (API.md, "Groups"): `groupsAvailable` follows `groups.list` (false in a release build,
    // where the app shows no Groups section).
    @Published public var groupsAvailable = false
    @Published public var groups: [RavenGroup] = []
    @Published public var groupMembers: [String: [GroupMember]] = [:]
    @Published public var groupMessages: [String: [GroupMessage]] = [:]
    @Published public var selectedGroupID: String?
    /// Group messages of yours whose arcs changed (a receipt came): the ring's arcs fade to their colour.
    @Published public var groupDetailsOpen: Set<String> = []
    /// Bumped when a message's signed receipt arrives: its check fills and pops (Calm).
    @Published public var deliveredPops: [String: Int] = [:]
    /// Messages this app just sent: each bubble lifts out of the composer once, then leaves the set.
    @Published public var liftIDs: Set<String> = []
    /// The open Settings section (Calm Settings, in the main window).
    @Published public var settingsSection: SettingsSection = .general
    /// Settings > Appearance > Theme (kept by this app, not the engine).
    @Published public var themeChoice: ThemeChoice = .system {
        didSet { preferences?.set(themeChoice.rawValue, forKey: AppModel.themeKey) }
    }
    /// Settings > Appearance > Show technical details: Technical details open by themselves.
    @Published public var showTechnical = false {
        didSet { preferences?.set(showTechnical, forKey: AppModel.technicalKey) }
    }
    @Published public var sheet: Sheet?
    @Published public var page: Page = .chat {
        didSet {
            if page == .chat, oldValue != .chat { readOpenChat() }
            if page == .group, oldValue != .group { readOpenGroup() }
        }
    }
    /// Lock v2 (`lock.state`): nil until read; an engine that can't say counts as not available.
    @Published public var lockV2: LockState?
    @Published public var lockError: RavenError?
    @Published public var actionError: RavenError?
    @Published public var searchText = ""
    @Published public var composerText = ""
    /// The main window's columns: the sidebar is shown unless it is `.detailOnly`. The toolbar button
    /// and View > Show Sidebar / Hide Sidebar change it, and the menu item's title follows it (E1: the
    /// menu said "Show Sidebar" while the sidebar was shown).
    @Published public var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    /// Sends asked for and not answered yet, by friend: the chat is not empty while one is on its way.
    @Published public private(set) var sendsInFlight: [String: Int] = [:]
    /// The system's Reduce motion, reported by the root view.
    @Published public var systemReduceMotion = false

    /// True while the main window is open. Polling follows it (500 ms with a window, 5 s from the
    /// menu bar only); opening the window polls at once.
    public var windowVisible = true {
        didSet {
            guard windowVisible != oldValue else { return }
            readOpenChat()
            if pollTask != nil { startPolling() }
        }
    }
    public var snapshotRoute: PinnedRoute?
    var lastSeq = 0
    /// Messages that have been waiting at some point: their receipt means "{name} is back".
    private var waitedIDs = Set<String>()
    private var started = false
    private var clockTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var polling = false
    private var pollAgain = false
    private var quitDecided = false
    private var sleepObserver: NSObjectProtocol?

    /// Where the app keeps its own preferences (theme, technical details); nil keeps nothing (tests,
    /// snapshots).
    let preferences: UserDefaults?
    static let themeKey = "calm.theme"
    static let technicalKey = "calm.showTechnicalDetails"

    public init(engine: RavenEngine, now: @escaping () -> Date = Date.init, preferences: UserDefaults? = nil) {
        self.engine = engine
        self.nowProvider = now
        self.preferences = preferences
        self.clock = ClockModel(now: now())
        self.network = NetworkModel(engine: engine)
        if let preferences {
            themeChoice = preferences.string(forKey: AppModel.themeKey).flatMap(ThemeChoice.init(rawValue:)) ?? .system
            showTechnical = preferences.bool(forKey: AppModel.technicalKey)
        }
        self.network.app = self
    }

    public var motionOff: Bool { systemReduceMotion || settings.reducedMotion }
    public var now: Date { clock.now }

    /// `events.poll` intervals from API.md: every 500 ms while a window is open, every 5 s when only
    /// the menu bar extra is alive.
    public static let pollIntervalWindow: TimeInterval = 0.5
    public static let pollIntervalMenuBar: TimeInterval = 5
    public var pollInterval: TimeInterval { windowVisible ? AppModel.pollIntervalWindow : AppModel.pollIntervalMenuBar }

    // MARK: Lifecycle

    /// Loads the profile, then starts the 1-second clock and the event poll. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings.lockOnSleep, self.phase == .ready, self.canLock else { return }
                await self.lock()
            }
        }
        clockTask = Task { [weak self] in
            await self?.bootstrap()
            self?.startPolling()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    public func stop() {
        clockTask?.cancel()
        clockTask = nil
        pollTask?.cancel()
        pollTask = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }

    /// (Re)starts the poll loop at the interval for the current window state, polling at once.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.phase == .ready { await self.pollNow() }
                let interval = self.pollInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func bootstrap() async {
        clock.set(nowProvider())
        do {
            appInfo = try? await engine.appInfo()
            await refreshPrivacy()
            let profile = try await engine.profileState()
            engineLog.notice("""
                engine \(String(describing: type(of: self.engine)), privacy: .public) \
                (\(self.appInfo?.build ?? "-", privacy: .public), \(self.appInfo?.version ?? "-", privacy: .public)): \
                profile \(profile.state.rawValue, privacy: .public)
                """)
            switch profile.state {
            case .new: phase = .welcome
            case .ready:
                try await loadAll()
                // Lock v2: raven-node runs without its keys; the app opens on the locked screen.
                await refreshLock()
                phase = lockV2?.locked == true ? .locked : .ready
            case .locked: phase = .locked
            case .unreadable:
                phase = .failed(RavenError(code: ErrorCode.profileUnreadable, message: profile.reason ?? tr(.errorInternal),
                                           detail: profile.detail ?? ""))
            }
        } catch {
            engineLog.notice("""
                engine \(String(describing: type(of: self.engine)), privacy: .public): \
                \(RavenError.from(error).code, privacy: .public)
                """)
            phase = .failed(RavenError.from(error))
        }
    }

    public func loadAll() async throws {
        identity = try await engine.me()
        settings = try await engine.settings()
        node = try await engine.nodeStatus()
        if let node, node.running { lastStatusOk = Date(ms: node.lastOkMs) }
        try await reloadContacts()
        for c in contacts { messages[c.address] = try await engine.history(address: c.address) }
        for (address, list) in messages {
            if let path = list.last(where: { $0.path != nil })?.path { lastPath[address] = path }
            for m in list where m.state == .waiting { waitedIDs.insert(m.id) }
        }
        if selectedAddress == nil || !contacts.contains(where: { $0.address == selectedAddress }) {
            selectedAddress = contacts.first?.address
        }
        await loadGroups()
    }

    func reloadContacts() async throws {
        contacts = try await engine.contacts()
        unread = Dictionary(contacts.map { ($0.address, $0.unread ?? 0) }, uniquingKeysWith: { a, _ in a })
        readOpenChat()
    }

    /// The open chat is on screen (the main window shows it): it counts as read up to its newest
    /// message, here and in the terminal app (`messages.mark_read`). The badge goes at once; a failed
    /// mark leaves the engine's count, which the next reload shows again.
    func readOpenChat() {
        guard windowVisible, page == .chat, let address = selectedAddress, (unread[address] ?? 0) > 0,
              let newest = messages[address]?.last?.id else { return }
        unread[address] = 0
        let engine = self.engine
        Task { _ = try? await engine.markRead(address: address, upTo: newest) }
    }

    /// One clock tick: update the time and drop expired texts. Polling has its own loop.
    public func tick() {
        clock.set(nowProvider())
        let now = clock.now
        if let t = toast, t.until <= now { toast = nil }
        if freshUntil.values.contains(where: { $0 <= now }) { freshUntil = freshUntil.filter { $0.value > now } }
    }

    /// Polls `events.poll` once and applies the events. A call while a poll is in flight does not
    /// start a second one (the same events would be applied twice); the running poll goes once more.
    public func pollNow() async {
        if polling {
            pollAgain = true
            return
        }
        polling = true
        defer { polling = false }
        repeat {
            pollAgain = false
            do {
                let batch = try await engine.poll(after: lastSeq)
                if batch.reset == true {
                    // Events were lost (API.md, Events): reload what the window shows instead of
                    // trusting them, and go on from the engine's seq (lower after an engine restart).
                    lastSeq = batch.seq
                    await reloadAfterReset()
                } else {
                    lastSeq = max(lastSeq, batch.seq)
                    await apply(batch.events)
                }
            } catch let e as RavenError where e.code == ErrorCode.profileLocked {
                phase = .locked
                return
            } catch {
                // A failed poll changes nothing on screen; the heartbeat text goes stale and says so.
                return
            }
        } while pollAgain
    }

    /// After `reset`: contacts, histories, node status and settings read again; no motion is played
    /// for what was missed (delivery is never animated without its receipt event).
    func reloadAfterReset() async {
        do {
            try await loadAll()
        } catch let e as RavenError where e.code == ErrorCode.profileLocked {
            phase = .locked
        } catch {
            // As for a failed poll: the screen keeps what it had; the next poll tries again.
        }
    }

    // MARK: Events

    public func apply(_ events: [RavenEvent]) async {
        var refreshContacts = false
        for e in events {
            switch e.kind {
            case .statusOk:
                lastStatusOk = Date(ms: e.atMs)
                node?.lastOkMs = e.atMs
                heartbeatPulse &+= 1
            case .sendStarted:
                guard let id = e.id else { continue }
                if message(id) == nil { await reloadHistories() }
                if let m = message(id) {
                    if m.state != .delivered { updateMessage(id) { $0.state = .sending } }
                    queueRoute(.out, m.address)
                }
            case .receipt:
                guard let id = e.id else { continue }
                if message(id) == nil { await reloadHistories() }
                guard let m = message(id) else { continue }
                let wasWaiting = waitedIDs.contains(id) || m.state == .waiting
                updateMessage(id) {
                    $0.state = .delivered
                    if let p = e.path { $0.path = p }
                    if let p = e.pathKind, !p.isEmpty { $0.pathKind = p }
                    // A late delivery says when it came (E1).
                    if let at = e.deliveredAtMs { $0.deliveredAtMs = at }
                }
                if let p = e.path { lastPath[m.address] = p }
                deliveredPops[id, default: 0] &+= 1
                queueRoute(.back, m.address)
                let name = contactName(m.address)
                if wasWaiting {
                    showToast(tr(.tickerBack, ["name": name]), .success)
                } else {
                    showToast(tr(.tickerDelivered, ["name": name, "path": e.path ?? Fallback.path,
                                                    "secs": TimeText.secs(ms: e.ms ?? 0)]), .success)
                }
                refreshContacts = true
            case .incoming:
                guard let m = e.message else { continue }
                insertIncoming(m)
                refreshContacts = true
            case .outgoing:
                // Yours, sent by another program on this profile (the terminal app): shown at once.
                guard let m = e.message else { continue }
                insertOutgoing(m)
                refreshContacts = true
            case .retry:
                guard let address = e.address else { continue }
                retryPulses[address, default: 0] &+= 1
                if let id = e.id { waitedIDs.insert(id) }
                if let id = e.id, let attempts = e.attempts { updateMessage(id) { $0.attempts = attempts } }
                // waiting.until_ms is 0 when not known: then the line says no time.
                let until = (e.id.flatMap { message($0)?.untilMs } ?? contact(address)?.waiting?.untilMs).flatMap { $0 > 0 ? $0 : nil }
                if let until {
                    showToast(tr(.tickerRetry, ["name": contactName(address), "time": TimeText.deadline(ms: until, now: clock.now)]), .warning)
                } else {
                    showToast(tr(.tickerRetryNoTime, ["name": contactName(address)]), .warning)
                }
                refreshContacts = true
            case .presence:
                guard let address = e.address, let p = e.presence else { continue }
                if let i = contacts.firstIndex(where: { $0.address == address }) {
                    contacts[i].presence = p
                    if p == .inTouch { contacts[i].lastContactMs = e.atMs }
                }
                presenceBlinks[address, default: 0] &+= 1
                refreshContacts = true
            case .state:
                guard let id = e.id, let s = e.state else { continue }
                if message(id) == nil { await reloadHistories() }
                if s == .waiting { waitedIDs.insert(id) }
                updateMessage(id) {
                    $0.state = s
                    // The deadline travels with the state (and comes again when it becomes known).
                    if let until = e.untilMs { $0.untilMs = until } else if s != .waiting { $0.untilMs = nil }
                }
                refreshContacts = true
            case .unread:
                // Counted by the engine: a message came, or the chat was read here or in the terminal app.
                guard let address = e.address, let n = e.unread else { continue }
                unread[address] = n
                readOpenChat()
            case .node:
                if let s = e.status {
                    let wasRunning = node?.running
                    node = s
                    if s.running, lastStatusOk == nil { lastStatusOk = Date(ms: s.lastOkMs) }
                    // Lock v2 is served by a running raven-node: read again when it starts or stops.
                    if wasRunning != s.running { await refreshLock() }
                }
            case .groupMessage:
                guard let g = e.group ?? e.groupMessage?.group, let m = e.groupMessage else { continue }
                insertGroupMessage(m, group: g)
            case .groupChanged:
                guard let g = e.group else { continue }
                await reloadGroup(g)
            case .unknown:
                continue
            }
        }
        if refreshContacts { try? await reloadContacts() }
    }

    // MARK: Groups

    /// Reads `groups.list`, then each group's members and history. An engine without groups (an
    /// older one, or the engine-missing screen) counts as "not available".
    func loadGroups() async {
        do {
            let list = try await engine.groups()
            groupsAvailable = list.available
            groups = list.groups
            for g in list.groups {
                if let full = try? await engine.group(g.id) { groupMembers[g.id] = full.members }
                if let history = try? await engine.groupHistory(g.id) { groupMessages[g.id] = history }
            }
            if let id = selectedGroupID, !groups.contains(where: { $0.id == id }) {
                selectedGroupID = nil
                if page == .group { page = .chat }
            }
        } catch {
            groupsAvailable = false
            groups = []
        }
    }

    /// `group_changed`: the group's summary, members and history read again.
    func reloadGroup(_ id: String) async {
        guard let full = try? await engine.group(id) else {
            // A group that isn't there any more (or a list that changed): read the whole list.
            await loadGroups()
            return
        }
        if let i = groups.firstIndex(where: { $0.id == id }) { groups[i] = full.group } else { groups.append(full.group) }
        groupMembers[id] = full.members
        if let history = try? await engine.groupHistory(id) {
            let before = groupMessages[id] ?? []
            groupMessages[id] = history
            // A receipt that arrived: the arc fills (motion only for the open group).
            if page == .group, selectedGroupID == id {
                for m in history where m.mine {
                    if let old = before.first(where: { $0.id == m.id }), old.delivered < m.delivered {
                        deliveredPops[m.id, default: 0] &+= 1
                    }
                }
            }
        }
        readOpenGroup()
    }

    private func insertGroupMessage(_ m: GroupMessage, group: String) {
        var list = groupMessages[group] ?? []
        guard !list.contains(where: { $0.id == m.id }) else { return }
        list.append(m)
        list.sort { $0.atMs < $1.atMs }
        if motionOff || !(page == .group && selectedGroupID == group) {
            groupMessages[group] = list
        } else {
            withAnimation(.easeOut(duration: Theme.shared.motion.bubbleIn)) { groupMessages[group] = list }
        }
        freshUntil[m.id] = clock.now.addingTimeInterval(Theme.shared.motion.incomingHighlight)
        if let i = groups.firstIndex(where: { $0.id == group }) {
            if !(page == .group && selectedGroupID == group && windowVisible) { groups[i].unread += 1 }
            groups[i].lastMs = m.atMs
            groups[i].lastText = Sanitizer.line(m.text, maxLength: 120)
            groups[i].lastFrom = m.fromName
            showToast(tr(.groupsTickerIncoming, ["group": groups[i].name, "name": m.fromName]), .accent)
        }
        readOpenGroup()
    }

    public var selectedGroup: RavenGroup? { groups.first { $0.id == selectedGroupID } }

    public func selectGroup(_ id: String) {
        page = .group
        guard selectedGroupID != id else {
            readOpenGroup()
            return
        }
        selectedGroupID = id
        composerText = ""
        readOpenGroup()
    }

    /// The open group is on screen: it counts as read (`groups.mark_read`).
    func readOpenGroup() {
        guard windowVisible, page == .group, let id = selectedGroupID,
              let i = groups.firstIndex(where: { $0.id == id }), groups[i].unread > 0 else { return }
        groups[i].unread = 0
        let engine = self.engine
        Task { try? await engine.markGroupRead(id) }
    }

    public func sendGroupComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = selectedGroupID else { return }
        composerText = ""
        do {
            let m = try await engine.sendToGroup(id, text: text)
            var list = groupMessages[id] ?? []
            if !list.contains(where: { $0.id == m.id }) {
                list.append(m)
                if !motionOff && windowVisible { liftIDs.insert(m.id) }
                groupMessages[id] = list
            }
            if let i = groups.firstIndex(where: { $0.id == id }) {
                groups[i].lastMs = m.atMs
                groups[i].lastText = Sanitizer.line(m.text, maxLength: 120)
                groups[i].lastFrom = m.fromName
            }
        } catch {
            composerText = text
            fail(error)
        }
    }

    /// Creates a group (you are its admin) with friends; opens it. The engine's refusal comes back.
    public func createGroup(name: String, members: [String]) async -> RavenError? {
        do {
            let created = try await engine.createGroup(name: name, members: members)
            groups.removeAll { $0.id == created.group.id }
            groups.append(created.group)
            groupMembers[created.group.id] = created.members
            groupMessages[created.group.id] = (try? await engine.groupHistory(created.group.id)) ?? []
            groupsAvailable = true
            selectGroup(created.group.id)
            return nil
        } catch {
            return RavenError.from(error)
        }
    }

    public func addGroupMembers(_ id: String, members: [String]) async -> RavenError? {
        do {
            let r = try await engine.addGroupMembers(id, members: members)
            if let i = groups.firstIndex(where: { $0.id == id }) { groups[i] = r.group }
            groupMembers[id] = r.members
            return nil
        } catch { return RavenError.from(error) }
    }

    public func removeGroupMember(_ id: String, member: String) async -> RavenError? {
        do {
            let r = try await engine.removeGroupMember(id, member: member)
            if let i = groups.firstIndex(where: { $0.id == id }) { groups[i] = r.group }
            groupMembers[id] = r.members
            return nil
        } catch { return RavenError.from(error) }
    }

    public func leaveGroup(_ id: String) async -> RavenError? {
        do {
            let g = try await engine.leaveGroup(id)
            if let i = groups.firstIndex(where: { $0.id == id }) { groups[i] = g }
            return nil
        } catch { return RavenError.from(error) }
    }

    public func presentNewGroup() { sheet = .newGroup }
    public func presentGroupMembers(_ id: String) { sheet = .groupMembers(id) }
    public func presentLeaveGroup(_ id: String) { sheet = .leaveGroup(id) }

    private func insertIncoming(_ m: Message) {
        var list = messages[m.address] ?? []
        guard !list.contains(where: { $0.id == m.id }) else { return }
        list.append(m)
        if motionOff {
            messages[m.address] = list
        } else {
            withAnimation(.easeOut(duration: Theme.shared.motion.bubbleIn)) { messages[m.address] = list }
        }
        freshUntil[m.id] = clock.now.addingTimeInterval(1.5)
        if let p = m.path { lastPath[m.address] = p }
        // The badge is the engine's (the `unread` event that follows, and the contacts reload).
        queueRoute(.incoming, m.address)
        showToast(Display.incomingTicker(name: contactName(m.address), path: m.path), .accent)
    }

    /// A message of yours another program sent: it joins its chat (no unread count, no toast).
    func insertOutgoing(_ m: Message) {
        var list = messages[m.address] ?? []
        guard !list.contains(where: { $0.id == m.id }) else { return }
        list.append(m)
        list.sort { $0.atMs < $1.atMs }
        if motionOff {
            messages[m.address] = list
        } else {
            withAnimation(.easeOut(duration: Theme.shared.motion.bubbleIn)) { messages[m.address] = list }
        }
        if let p = m.path { lastPath[m.address] = p }
    }

    private func queueRoute(_ kind: RouteKind, _ address: String) {
        guard !motionOff, address == selectedAddress, windowVisible else { return }
        routeQueue.append(RouteMotion(kind: kind, address: address))
        if routeQueue.count > 6 { routeQueue.removeFirst(routeQueue.count - 6) }
    }

    /// Called by the route line when a packet has finished its trip.
    public func routeFinished(_ id: UUID) {
        routeQueue.removeAll { $0.id == id }
    }

    func reloadHistories() async {
        for c in contacts {
            if let list = try? await engine.history(address: c.address) { messages[c.address] = list }
        }
    }

    public func showToast(_ text: String, _ tone: Tone) {
        toast = Toast(text: text, tone: tone, until: clock.now.addingTimeInterval(Theme.shared.motion.toastVisible))
    }

    // MARK: Lookups

    public func contact(_ address: String?) -> Contact? {
        guard let address else { return nil }
        return contacts.first { $0.address == address }
    }

    public var selectedContact: Contact? { contact(selectedAddress) }

    func contactName(_ address: String) -> String { contact(address)?.name ?? Fallback.short(address) }

    public func message(_ id: String) -> Message? {
        for list in messages.values { if let m = list.first(where: { $0.id == id }) { return m } }
        return nil
    }

    private func updateMessage(_ id: String, _ change: (inout Message) -> Void) {
        for (address, list) in messages {
            if let i = list.firstIndex(where: { $0.id == id }) {
                var copy = list
                change(&copy[i])
                messages[address] = copy
                return
            }
        }
    }

    public var filteredContacts: [Contact] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.shortAddress.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Setup

    public func beginSetup() {
        phase = .setup
        setupStep = .name
    }

    public func submitName() { setupStep = .receive }

    public func chooseReceive(_ receive: Bool) async {
        setupReceive = receive
        setupStep = .creating
        do {
            let name = Sanitizer.line(setupName, maxLength: 64)
            _ = try await engine.createIdentity(displayName: name.isEmpty ? nil : name)
            settings = try await engine.setSettings(["receive": .bool(receive), "display_name": .opt(name.isEmpty ? nil : name)])
            node = try await engine.startNode()
            identity = try await engine.me()
            setupStep = .words
        } catch {
            actionError = RavenError.from(error)
            setupStep = .receive
        }
    }

    public func finishSetup() async {
        do {
            try await loadAll()
            phase = .ready
        } catch {
            phase = .failed(RavenError.from(error))
        }
    }

    // MARK: Chat actions

    public func select(_ address: String?) {
        page = .chat
        guard selectedAddress != address else { return }
        selectedAddress = address
        routeQueue.removeAll()
        composerText = ""
        readOpenChat()
    }

    public func sendComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let address = selectedAddress else { return }
        composerText = ""
        await send(text, to: address)
    }

    /// No message with this friend, and none on its way: the "Say hello!" text shows only then.
    public func chatIsEmpty(_ address: String) -> Bool {
        AppModel.chatIsEmpty(messages: messages[address] ?? [], sendsInFlight: sendsInFlight[address] ?? 0)
    }

    static func chatIsEmpty(messages: [Message], sendsInFlight: Int) -> Bool {
        messages.isEmpty && sendsInFlight == 0
    }

    public func send(_ text: String, to address: String) async {
        sendsInFlight[address, default: 0] += 1
        defer {
            sendsInFlight[address, default: 1] -= 1
            if sendsInFlight[address] == 0 { sendsInFlight[address] = nil }
        }
        do {
            let m = try await engine.send(address: address, text: text)
            var list = messages[address] ?? []
            if !list.contains(where: { $0.id == m.id }) {
                list.append(m)
                // Calm: the bubble lifts out of the composer to its place (the row plays it once).
                if !motionOff && windowVisible { liftIDs.insert(m.id) }
                messages[address] = list
            }
            await pollNow()
        } catch {
            fail(error)
        }
    }

    /// Try now (waiting) and Send again (ended): the same bubble shows the message from then on. An
    /// ended message comes back as a new message (`replaces` the old id): it takes the old one's place,
    /// so the chat never shows the text twice.
    public func retry(_ id: String) async {
        do {
            let m = try await engine.retry(id: id)
            replaceMessage(id, with: m)
            await pollNow()
        } catch { fail(error) }
    }

    private func replaceMessage(_ id: String, with m: Message) {
        for (address, list) in messages {
            guard let i = list.firstIndex(where: { $0.id == id }) else { continue }
            var copy = list
            copy[i] = m
            // A row the new id already has (an event came first) goes: one bubble per message.
            copy = copy.enumerated().filter { $0.offset == i || $0.element.id != m.id }.map(\.element)
            messages[address] = copy
            return
        }
    }

    /// Delete an ended message of yours (not sent, failed, time ran out): it leaves the chat for good.
    public func deleteMessage(_ id: String) async {
        do {
            try await engine.deleteMessage(id: id)
            for (address, list) in messages where list.contains(where: { $0.id == id }) {
                messages[address] = list.filter { $0.id != id }
            }
        } catch { fail(error) }
    }

    /// Rename a friend (the name only this computer shows). Returns the engine's refusal, if any.
    @discardableResult
    public func renameContact(_ address: String, to name: String) async -> RavenError? {
        do {
            let c = try await engine.renameContact(address: address, name: name)
            if let i = contacts.firstIndex(where: { $0.address == address }) { contacts[i] = c }
            try? await reloadContacts()
            return nil
        } catch {
            return RavenError.from(error)
        }
    }

    public func presentRename(_ address: String) { sheet = .rename(address) }

    public var sidebarShown: Bool { sidebarVisibility != .detailOnly }

    /// View > Show Sidebar / Hide Sidebar.
    public func toggleSidebar() {
        sidebarVisibility = sidebarShown ? .detailOnly : .all
    }

    public func stopTrying(_ id: String) async {
        do {
            let m = try await engine.stop(id: id)
            updateMessage(id) { $0 = m }
            try? await reloadContacts()
        } catch { fail(error) }
    }

    public func details(_ id: String) async -> Result<MessageDetails, RavenError> {
        do { return .success(try await engine.details(id: id)) } catch { return .failure(RavenError.from(error)) }
    }

    public func openDetails(_ id: String) { sheet = .messageDetails(id) }

    func fail(_ error: Error) {
        let e = RavenError.from(error)
        actionError = e
        showToast(e.message, .danger)
    }

    // MARK: Friends and words

    public func makeCard(includeAddress: Bool) async throws -> ShareCard {
        try await engine.makeCard(includeAddress: includeAddress)
    }

    public func parseCard(_ text: String) async throws -> CardSummary {
        try await engine.parseCard(text)
    }

    public func addContact(text: String, name: String) async throws -> Contact {
        let c = try await engine.addContact(text: text, name: name)
        try? await reloadContacts()
        messages[c.address] = messages[c.address] ?? []
        select(c.address)
        return c
    }

    public func wordHint(_ prefix: String) async -> String? {
        try? await engine.wordHint(prefix: prefix)
    }

    public func checkWords(address: String, words: [String]) async throws -> VerifyResult {
        let result = try await engine.checkWords(address: address, words: words)
        if result == .match { try? await reloadContacts() }
        return result
    }

    /// The old code, for friends with an older Raven: match or mismatch. A match verifies the friend
    /// exactly as the words do.
    public func checkOldCode(address: String, code: String) async throws -> VerifyResult {
        let result = try await engine.checkOldCode(address: address, code: code)
        if result == .match { try? await reloadContacts() }
        return result
    }

    public func presentAddFriend() { sheet = .addFriend }
    public func presentCheckWords(_ address: String) { sheet = .checkWords(address) }
    public func presentNetwork() { sheet = .network }
    public func presentYou() { sheet = .you }
    public func presentRoutes(_ address: String) { sheet = .friendRoutes(address) }

    /// Shows a network page in the main window (the chat comes back when a friend is picked).
    public func open(_ page: Page) {
        if sheet == .network { sheet = nil }
        self.page = page
    }

    /// Settings in the main window, at a section.
    public func openSettings(_ section: SettingsSection? = nil) {
        if let section { settingsSection = section }
        open(.settings)
    }

    /// A bubble finished lifting out of the composer.
    public func liftDone(_ id: String) { liftIDs.remove(id) }

    // MARK: Settings, node, privacy

    public func updateSettings(_ partial: [String: JSONValue]) async {
        do {
            settings = try await engine.setSettings(partial)
            if partial["receive"] != nil { node = try? await engine.nodeStatus() }
        } catch { fail(error) }
    }

    public func startNode() async {
        do { node = try await engine.startNode() } catch { fail(error) }
    }

    public func stopNode() async {
        do {
            let status = try await engine.stopNode()
            node = status
            noteStop(status)
        } catch { fail(error) }
    }

    /// raven-client says how a stop went (`stop`, `note`). A node left running is explained: by a
    /// login service, or with how to stop it by hand; a failed stop shows its reason under Details.
    func noteStop(_ status: NodeStatus) {
        guard let outcome = status.stop else { return }
        let note = status.note ?? ""
        switch outcome {
        case "still_running", "advice", "managed":
            if !note.isEmpty { showToast(note, .warning) }
        case "failed":
            fail(RavenError(code: ErrorCode.internalError, message: tr(.errorInternal), detail: note))
        default:
            break
        }
    }

    /// Reads `privacy.state`. An engine that cannot answer counts as "not available".
    public func refreshPrivacy() async {
        privacy = (try? await engine.privacyState()) ?? .unavailable
    }

    /// Lock now: Lock v2 where the running raven-node serves it (it keeps running without its
    /// keys), else the privacy pack's lock (`privacy.lock`, when available).
    public var canLock: Bool { privacy.available || lockV2?.supported == true }

    /// The page shown when Raven was locked: Unlock comes back to it (E1).
    var pageBeforeLock: Page?

    /// Lock now asks first, saying what Lock does and doesn't protect (E1).
    public func requestLock() {
        guard phase == .ready, canLock else { return }
        sheet = .confirmLock
    }

    /// After an unlock: the page that was open before.
    private func returnToPageBeforeLock() {
        if let before = pageBeforeLock { page = before }
        pageBeforeLock = nil
    }

    public func lock() async {
        if lockV2?.supported == true {
            await lockNow()
            return
        }
        guard privacy.available else { return }
        do {
            _ = try await engine.lock()
            sheet = nil
            pageBeforeLock = page
            phase = .locked
        } catch { fail(error) }
    }

    /// Reads `lock.state`. An engine that cannot answer counts as "not available".
    public func refreshLock() async {
        lockV2 = try? await engine.lockState()
    }

    /// Lock v2's Lock now.
    public func lockNow() async {
        lockError = nil
        do {
            let state = try await engine.lockNow()
            lockV2 = state
            if state.locked {
                sheet = nil
                pageBeforeLock = page
                phase = .locked
            }
        } catch {
            lockError = RavenError.from(error)
            fail(error)
        }
    }

    /// The locked screen's Unlock: Lock v2 (with the Raven passphrase when the profile has one; it
    /// goes only to raven-node), else the privacy pack's unlock.
    public func unlockLocked(passphrase: String?) async {
        guard lockV2?.locked == true else {
            await unlock()
            return
        }
        lockError = nil
        actionError = nil
        do {
            let state = try await engine.lockUnlock(passphrase: passphrase.flatMap { $0.isEmpty ? nil : $0 })
            lockV2 = state
            guard !state.locked else { return }
            try await loadAll()
            returnToPageBeforeLock()
            phase = .ready
        } catch {
            lockError = RavenError.from(error)
        }
    }

    /// Settings > Privacy > Encrypt everything (only offered when `privacy.available`).
    public func encrypt() async {
        do { try await engine.encrypt() } catch { fail(error) }
        await refreshPrivacy()
    }

    /// Settings > Privacy > Erase, after the user typed "erase": removes Raven's data from this
    /// computer and goes back to the welcome screen. Returns the error when the engine refused.
    @discardableResult
    public func erase() async -> RavenError? {
        do {
            try await engine.erase()
        } catch {
            let e = RavenError.from(error)
            actionError = e
            return e
        }
        sheet = nil
        identity = nil
        contacts = []
        messages = [:]
        unread = [:]
        selectedAddress = nil
        lastSeq = 0
        waitedIDs = []
        settings = RavenSettings()
        await refreshPrivacy()
        await bootstrap()
        return nil
    }

    public func unlock() async {
        actionError = nil
        do {
            _ = try await engine.unlock()
            try await loadAll()
            returnToPageBeforeLock()
            phase = .ready
        } catch { fail(error) }
    }

    // MARK: Quit

    /// Answer for `applicationShouldTerminate`, following Settings > When I quit.
    public func quitReply() -> NSApplication.TerminateReply {
        if quitDecided { return .terminateNow }
        switch settings.whenQuit {
        case "stop_if_started":
            guard node?.startedByApp == true else { return .terminateNow }
            Task { await self.answerQuit(.quitAndStop) }
            return .terminateLater
        case "ask":
            guard windowVisible, phase == .ready else { return .terminateNow }
            sheet = .quit
            return .terminateLater
        default:
            return .terminateNow
        }
    }

    /// The Quit dialog's buttons (and the menu bar's quit items).
    public func answerQuit(_ choice: QuitChoice) async {
        switch choice {
        case .stay:
            sheet = nil
            NSApp.reply(toApplicationShouldTerminate: false)
        case .quit:
            quitDecided = true
            sheet = nil
            NSApp.reply(toApplicationShouldTerminate: true)
        case .quitAndStop:
            quitDecided = true
            _ = try? await engine.stopNode()
            sheet = nil
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    /// Menu bar items: quit without asking, keeping or stopping the background program.
    public func quitFromMenu(stopNode: Bool) async {
        if stopNode { _ = try? await engine.stopNode() }
        quitDecided = true
        NSApp.terminate(nil)
    }
}

/// Fallbacks used only when the engine leaves a field out.
enum Fallback {
    static let path = "–"
    static func short(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return String(address.prefix(8)) + "…" + String(address.suffix(5))
    }
}
