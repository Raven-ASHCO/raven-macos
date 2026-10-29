import SwiftUI
import AppKit

/// The chat with the selected friend (Calm): the header, the route line, the messages with their day
/// lines and status, the away card while a message waits, the not-verified banner, and the composer
/// with the toast pill above it.
struct ChatArea: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            if let contact = model.selectedContact {
                ChatHeader(contact: contact)
                RouteLine(ends: (tr(.youTitle), contact.name), label: RouteLabel.of(contact, model: model))
                // One list per friend: another friend's chat opens at its newest message.
                MessagesList(contact: contact).id(contact.address)
                ComposerBar(placeholder: tr(.homeComposer, ["name": contact.name]),
                            note: tr(.chatEncrypted, ["name": contact.name])) {
                    await model.sendComposer()
                }
            } else {
                VStack(spacing: 10) {
                    Text(tr(.homeNoFriends)).foregroundColor(p.textSecondary)
                    Button(tr(.homeNoFriendsAction)) { model.presentAddFriend() }
                        .buttonStyle(RButtonStyle(.primary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(p.background)
    }
}

/// The chat header (66 pt): avatar, name with Verified / Not verified, the status line and the path;
/// on the right the path pill (or who holds your mail) and Routes.
struct ChatHeader: View {
    let contact: Contact
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    // At the narrowest window (560 px, the sidebar beside it) the status text truncates first, then
    // the path and the name; the Routes button always shows whole (E1: on Windows it was cut off).
    var body: some View {
        let status = Display.statusLine(contact, now: clock.now)
        let kind = model.lastPathKind(contact.address)
        let path = Display.headerPath(contact, lastPath: model.lastPath[contact.address])
        HStack(spacing: 12) {
            Avatar(contact, size: Theme.shared.layout.avatarLarge, blink: model.presenceBlinks[contact.address] ?? 0,
                   retry: model.retryPulses[contact.address] ?? 0, ring: p.background)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(contact.name).font(.system(size: Theme.shared.type.title, weight: .semibold)).lineLimit(1)
                        .layoutPriority(1)
                    if contact.verified {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield").font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(tr(.homeVerified))
                        }
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(p.success).lineLimit(1)
                    } else {
                        Text(tr(.homeNotVerified)).font(.system(size: 12, weight: .semibold)).foregroundColor(p.warning)
                            .lineLimit(1)
                    }
                }
                Text(path != nil && contact.presence == .inTouch ? status.text + " · " + (path ?? "") : status.text)
                    .font(RFont.caption)
                    .foregroundColor(status.tone == .warning ? p.warning : p.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // The path pill only where there is room; Routes always shows whole (E1). Not while
            // messages to the friend wait: the last path isn't how they are reached now (E1).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if let path, contact.presence == .inTouch {
                        PathPill(label: Display.pathChip(kind: kind, path: path) ?? path, family: PathFamily.of(kind: kind), small: false)
                    }
                    routes
                }
                routes
            }
            .layoutPriority(2)
        }
        .padding(.horizontal, 22)
        .frame(height: Theme.shared.layout.headerHeight)
        .background(p.background.opacity(0.82))
        .overlay(alignment: .bottom) { Rule() }
    }

    private var routes: some View {
        Button { model.presentRoutes(contact.address) } label: {
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").accessibilityHidden(true)
                Text(tr(.networkRoutesButton))
            }
        }
        .buttonStyle(RButtonStyle(.secondary))
        .fixedSize()
        .help(tr(.networkRoutesTitle, ["name": contact.name]))
    }
}

/// What the route line says between the two ends.
struct RouteLabel: Equatable {
    var text: String
    var family: PathFamily
    var tone: AppModel.Tone?
    /// Dashed while the friend isn't reachable (messages wait).
    var dashed: Bool

    @MainActor static func of(_ c: Contact, model: AppModel) -> RouteLabel? {
        if c.presence == .waiting || (c.waiting?.count ?? 0) > 0 {
            // Held by a friend only when a waiting message says so (its path is a friend holding it).
            let waiting = model.messages[c.address]?.last { $0.direction == .outgoing && $0.state == .waiting }
            let held = ["friend", "handoff"].contains(waiting?.pathKind ?? "")
            return RouteLabel(text: held ? tr(.chipFriend) : tr(.tickWaitingNoTime, ["name": c.name]),
                              family: held ? .friend : .other, tone: held ? nil : .warning, dashed: true)
        }
        guard c.presence == .inTouch, let path = Display.headerPath(c, lastPath: model.lastPath[c.address]) else {
            return c.presence == .inTouch ? nil : RouteLabel(text: "", family: .other, tone: nil, dashed: true)
        }
        let kind = model.lastPathKind(c.address)
        return RouteLabel(text: Display.pathChip(kind: kind, path: path) ?? path, family: PathFamily.of(kind: kind),
                          tone: nil, dashed: false)
    }
}

/// The route line under the header (34 pt): You ── path ── friend. A dot travels out on
/// `send_started`, a check travels back on `receipt`, a dot travels in on `incoming`. Motions play one
/// after another, only for the open chat, and never with reduced motion.
struct RouteLine: View {
    let ends: (String, String)
    let label: RouteLabel?
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var progress: CGFloat = 0
    @ViewState private var active: AppModel.RouteMotion?

    var body: some View {
        HStack(spacing: 10) {
            Text(ends.0).lineLimit(1)
            GeometryReader { geo in
                let w = geo.size.width
                let mid = geo.size.height / 2
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: mid))
                        path.addLine(to: CGPoint(x: w, y: mid))
                    }
                    .stroke(p.borderStrong, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                               dash: label?.dashed == true ? [6, 5] : []))
                    if let label, !label.text.isEmpty {
                        HStack(spacing: 5) {
                            if label.family != .other { PathIcon(family: label.family, size: 12) }
                            Text(label.text).lineLimit(1)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(label.tone.map { p.tone($0) } ?? label.family.color(p))
                        .padding(.horizontal, 10)
                        .background(p.background)
                    }
                    if let kind = shownKind {
                        Packet(kind: kind)
                            .position(x: 7 + shownProgress * max(0, w - 14), y: mid)
                    }
                }
            }
            .frame(height: 16)
            Text(ends.1).lineLimit(1)
        }
        .font(.system(size: 11.5))
        .foregroundColor(p.textSecondary)
        .padding(.horizontal, 22)
        .frame(height: Theme.shared.layout.routeLineHeight)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { [ends.0, $0.text, ends.1].filter { !$0.isEmpty }.joined(separator: ", ") } ?? "")
        .onAppear { startNext() }
        .onChange(of: model.routeQueue.first?.id) { _ in startNext() }
    }

    /// Snapshots can pin a packet mid-way (`snapshotRoute`).
    private var shownKind: AppModel.RouteKind? { model.snapshotRoute?.kind ?? active?.kind }

    private var shownProgress: CGFloat { model.snapshotRoute.map { CGFloat($0.progress) } ?? progress }

    private func startNext() {
        guard active == nil, let next = model.routeQueue.first else { return }
        if motionOff {
            model.routeFinished(next.id)
            return
        }
        let m = Theme.shared.motion
        let duration = next.kind == .back ? m.receiptBack : m.routePacket
        let from: CGFloat = next.kind == .out ? 0 : 1
        let to: CGFloat = next.kind == .out ? 1 : 0
        active = next
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { progress = from }
        DispatchQueue.main.async {
            withAnimation(Theme.shared.curve("packet", duration)) { progress = to }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.06) {
            active = nil
            model.routeFinished(next.id)
            startNext()
        }
    }
}

/// A packet on the route line: a dot going out or coming in, a check coming back with the receipt.
private struct Packet: View {
    let kind: AppModel.RouteKind
    @Environment(\.palette) private var p

    var body: some View {
        if kind == .back {
            ZStack {
                Circle().fill(p.successFill)
                CheckShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(4)
            }
            .frame(width: 14, height: 14)
            .background(Circle().fill(p.successFill.opacity(0.22)).frame(width: 22, height: 22))
        } else {
            Circle().fill(p.accentFill).frame(width: 10, height: 10)
                .background(Circle().fill(p.accentFill.opacity(0.2)).frame(width: 18, height: 18))
        }
    }
}

/// The messages, their day lines, and what the chat says after them (the away card, the
/// not-verified banner); 760 pt wide at most, centred.
struct MessagesList: View {
    let contact: Contact
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let list = model.messages[contact.address] ?? []
        ChatScroll(isEmpty: model.chatIsEmpty(contact.address),
                   emptyText: tr(.homeEmptyChat, ["name": contact.name]),
                   newest: ChatFollow.newest(list)) { width in
            VStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    // A line between days: "Today", "Yesterday", "Tue 2026-10-20".
                    if i == 0 || TimeText.differentDays(list[i - 1].atMs, m.atMs) {
                        DayLine(atMs: m.atMs)
                    }
                    MessageRow(message: m, name: contact.name, maxBubble: width * Theme.shared.layout.bubbleMaxFraction)
                        .id(m.id)
                }
                if let waiting = list.last(where: { $0.direction == .outgoing && $0.state == .waiting }),
                   (contact.waiting?.count ?? 0) > 0 || contact.presence == .waiting {
                    AwayCard(contact: contact, message: waiting)
                }
                if !contact.verified { NotVerifiedBanner(contact: contact) }
            }
        }
    }
}

/// The scrolling column of a chat: follows its newest message while you are at the bottom (also when
/// that message grows), stops when you scroll up, and comes back when you send (E1).
struct ChatScroll<Rows: View>: View {
    let isEmpty: Bool
    let emptyText: String
    let newest: ChatFollow.Newest?
    let rows: (CGFloat) -> Rows
    @Environment(\.palette) private var p
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var follow = ChatFollow()

    init(isEmpty: Bool, emptyText: String, newest: ChatFollow.Newest?, @ViewBuilder rows: @escaping (CGFloat) -> Rows) {
        self.isEmpty = isEmpty
        self.emptyText = emptyText
        self.newest = newest
        self.rows = rows
    }

    var body: some View {
        if isEmpty {
            // Gone at once when the first message is on its way (sending, waiting, or in): it never
            // fades out behind the first bubble.
            Text(emptyText)
                .foregroundColor(p.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.identity)
        } else {
            GeometryReader { outer in
                let width = min(Theme.shared.layout.contentMaxWidth, outer.size.width) - 56
                if snapshot {
                    RScroll(bottomAligned: true) { column(width) }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                column(width)
                                Color.clear.frame(height: 1).id(ChatFollow.bottomID)
                            }
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: ChatGeometryKey.self, value: ChatGeometry(
                                    bottom: geo.frame(in: .named(ChatFollow.space)).maxY, content: geo.size.height))
                            })
                        }
                        .coordinateSpace(name: ChatFollow.space)
                        .onAppear { toEnd(proxy) }
                        .onPreferenceChange(ChatGeometryKey.self) { g in
                            if follow.layout(bottom: g.bottom, content: g.content, viewport: outer.size.height) {
                                toEnd(proxy)
                            }
                        }
                        .onChange(of: newest) { newest in
                            if follow.newMessage(own: newest?.own ?? false) { toEnd(proxy) }
                        }
                    }
                }
            }
        }
    }

    private func column(_ width: CGFloat) -> some View {
        rows(max(200, width))
            .padding(.horizontal, 28)
            .padding(.top, 18)
            // Room under the newest message for the toast pill above the composer.
            .padding(.bottom, 36)
            .frame(maxWidth: Theme.shared.layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    /// To the end, once this layout pass has placed the newest message (a new row has no height
    /// before it).
    private func toEnd(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async { proxy.scrollTo(ChatFollow.bottomID, anchor: .bottom) }
    }
}

/// One message (Calm): the bubble, then its time, status and path chip. Yours is a blue gradient (an
/// outline while it waits); theirs is a card. Yours lifts out of the composer when this app sent it;
/// theirs rises in with a short highlight. Ended messages offer Send again and Delete.
struct MessageRow: View {
    let message: Message
    let name: String
    let maxBubble: CGFloat
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    var body: some View {
        let out = message.direction == .outgoing
        VStack(alignment: out ? .trailing : .leading, spacing: 0) {
            Bubble(text: message.text, outgoing: out, waiting: out && message.state == .waiting,
                   fresh: model.freshUntil[message.id] != nil, liftID: out ? message.id : nil)
                .frame(maxWidth: maxBubble, alignment: out ? .trailing : .leading)
                .contextMenu {
                    Button(tr(.addShareCopy)) { Clipboard.copy(message.text) }
                    if Display.canDelete(message) {
                        Button(tr(.messageSendAgain)) { Task { await model.retry(message.id) } }
                        Button(tr(.messageDelete)) { Task { await model.deleteMessage(message.id) } }
                    }
                }
            MetaRow(message: message, name: name)
            // A message that was not sent: Send again or Delete, right under it (E1).
            if Display.canDelete(message) {
                HStack(spacing: 12) {
                    Button(tr(.messageSendAgain)) { Task { await model.retry(message.id) } }
                    Button(tr(.messageDelete)) { Task { await model.deleteMessage(message.id) } }
                }
                .buttonStyle(RButtonStyle(.plain))
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: out ? .trailing : .leading)
        .transition(motionOff || out ? .identity : .offset(y: 10).combined(with: .opacity))
    }
}

/// A bubble. `liftID`: a message this app just sent lifts out of the composer once (`liftIDs`).
struct Bubble: View {
    let text: String
    let outgoing: Bool
    var waiting = false
    var fresh = false
    var liftID: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var lift: CGFloat = 0

    var body: some View {
        let shape = BubbleShape(outgoing: outgoing)
        Text(text)
            .font(RFont.bubble)
            .lineSpacing(2)
            .foregroundColor(outgoing ? (waiting ? p.accent : p.onAccent) : p.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if outgoing && waiting {
                    shape.strokeBorder(p.accentFill.opacity(0.55), lineWidth: 1.5)
                } else if outgoing {
                    shape.fill(LinearGradient(colors: [p.accentFillTop, p.accentFill], startPoint: .top, endPoint: .bottom))
                        .ravenShadow(p.bubbleShadow)
                } else {
                    shape.fill(p.surface).ravenShadow(p.cardShadow)
                }
            }
            .overlay {
                // A message that just came: a soft ring for a moment (1.5 s).
                if fresh && !outgoing { shape.stroke(p.accentFill.opacity(0.25), lineWidth: 3) }
            }
            .offset(x: -lift * 60, y: lift * 64)
            .scaleEffect(1 - lift * 0.08, anchor: .bottomTrailing)
            .opacity(1 - Double(lift) * 0.8)
            .onAppear(perform: liftOut)
    }

    /// From the composer to its place (520 ms, curve `lift`).
    private func liftOut() {
        guard let id = liftID, model.liftIDs.contains(id) else { return }
        guard !motionOff else {
            model.liftDone(id)
            return
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { lift = 1 }
        let m = Theme.shared.motion
        DispatchQueue.main.async {
            withAnimation(Theme.shared.curve("lift", m.bubbleLift)) { lift = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + m.bubbleLift) { model.liftDone(id) }
    }
}

/// Under a bubble: its time, and for yours the status (icon and words: Details opens from it), then
/// the path chip, which slides in when the receipt comes.
struct MetaRow: View {
    let message: Message
    let name: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        let out = message.direction == .outgoing
        let chip = Display.pathChip(kind: message.pathKind, path: message.path)
        HStack(spacing: 8) {
            Text(TimeText.bubble(ms: message.atMs, now: clock.now)).foregroundColor(p.textSecondary)
            if out {
                let s = Display.status(message, name: name, now: clock.now)
                Button { model.openDetails(message.id) } label: {
                    HStack(spacing: 5) {
                        StatusIcon(kind: s.icon, pop: model.deliveredPops[message.id] ?? 0)
                        Text(s.text)
                    }
                    .foregroundColor(s.tone == .secondary ? p.textSecondary : p.tone(s.tone))
                }
                .buttonStyle(.plain)
                .help(tr(.messageDetails))
            }
            // Yours: only once it has a path to show (it went, or it waits with a friend).
            if let chip, !out || [.delivered, .waiting].contains(message.state) {
                SlidingChip(pop: model.deliveredPops[message.id] ?? 0) {
                    PathPill(label: chip, family: PathFamily.of(kind: message.pathKind))
                }
            }
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .frame(minHeight: 20)
        .padding(.top, 5)
        .padding(.horizontal, 4)
    }
}

/// A chip that slides in from the left when `pop` changes (the receipt came).
struct SlidingChip<Content: View>: View {
    let pop: Int
    let content: Content
    @Environment(\.motionOff) private var motionOff
    @ViewState private var shift: CGFloat = 0

    init(pop: Int, @ViewBuilder content: () -> Content) {
        self.pop = pop
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: -8 * shift)
            .scaleEffect(1 - 0.1 * shift)
            .opacity(1 - Double(shift))
            .onChange(of: pop) { _ in
                pulse(motionOff: motionOff, Theme.shared.curve("chip", Theme.shared.motion.chipSlide),
                      start: { shift = 1 }, end: { shift = 0 })
            }
    }
}

/// The line between two days of a chat.
struct DayLine: View {
    let atMs: Int64
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 12) {
            Rule()
            Text(TimeText.day(ms: atMs, now: clock.now)).font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(p.textTertiary)
                .fixedSize()
            Rule()
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// While a message to the friend waits: what is happening, who holds it (only when its path says a
/// friend holds it), and Try now, Details, Stop trying.
struct AwayCard: View {
    let contact: Contact
    let message: Message
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        let held = ["friend", "handoff"].contains(message.pathKind ?? "")
        let status: String = {
            guard let until = message.untilMs, until > 0 else { return tr(.tickWaitingNoTime, ["name": contact.name]) }
            let left = Date(ms: until).timeIntervalSince(clock.now)
            return tr(.messageStatusWaiting, ["name": contact.name, "time": TimeText.deadline(ms: until, now: clock.now),
                                              "left": TimeText.left(left)])
        }()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(.chatAwayTitle, ["name": contact.name])).font(.system(size: 14.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.system(size: 13)).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if held {
                        Text(tr(.chatAwayHeld, ["name": contact.name])).font(.system(size: 13)).foregroundColor(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AwayTrio(contact: contact, held: held, retry: model.retryPulses[contact.address] ?? 0)
            }
            HStack(spacing: 8) {
                Button(tr(.messageTryNow)) { Task { await model.retry(message.id) } }.buttonStyle(RButtonStyle(.secondary))
                Button(tr(.messageDetails)) { model.openDetails(message.id) }.buttonStyle(RButtonStyle(.secondary))
                Button(tr(.messageStopTrying)) { Task { await model.stopTrying(message.id) } }
                    .buttonStyle(RButtonStyle(.plain))
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.warningSoft))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.warningFill.opacity(0.35), lineWidth: 1))
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }
}

/// You ── (a friend holding a sealed copy) ┄┄ the friend, faded while away; a retry rings the friend.
private struct AwayTrio: View {
    let contact: Contact
    let held: Bool
    let retry: Int
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            node(InitialAvatar(initial: String(tr(.youTitle).prefix(1)), colors: AvatarColors(background: p.accentSoft, foreground: p.accent), size: 30), tr(.youTitle))
            link(dashed: false)
            if held {
                node(ZStack {
                    Circle().fill(p.named("pathFriend").opacity(0.16))
                    Image(systemName: "envelope.fill").font(.system(size: 12)).foregroundColor(p.named("pathFriend"))
                }.frame(width: 30, height: 30), tr(.chipFriend))
                link(dashed: true)
            }
            node(ZStack(alignment: .bottomTrailing) {
                InitialAvatar(initial: contact.initial, colors: p.avatar(for: contact.address), size: 30).opacity(0.55)
                PresenceDot(presence: contact.presence, retry: retry, ring: p.warningSoft).offset(x: 1, y: 1)
            }, contact.name)
        }
        .accessibilityHidden(true)
    }

    private func node<V: View>(_ v: V, _ label: String) -> some View {
        VStack(spacing: 4) {
            v
            Text(label).font(.system(size: 11)).foregroundColor(p.textSecondary).lineLimit(1)
        }
        .frame(width: 64)
    }

    private func link(dashed: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1))
            path.addLine(to: CGPoint(x: 36, y: 1))
        }
        .stroke(dashed ? p.warningFill.opacity(0.7) : p.borderStrong, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 4] : []))
        .frame(width: 36, height: 2)
        .padding(.top, 14)
    }
}

struct NotVerifiedBanner: View {
    let contact: Contact
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield").foregroundColor(p.warning).accessibilityHidden(true)
            Text(tr(.homeBannerNotVerified, ["name": contact.name]))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(tr(.homeBannerNotVerifiedAction)) { model.presentCheckWords(contact.address) }
                .buttonStyle(RButtonStyle(.primary))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.warningSoft))
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// A bubble with one small corner (the tail): bottom-right for yours, bottom-left for theirs.
struct BubbleShape: InsettableShape {
    let outgoing: Bool
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> BubbleShape {
        var s = self
        s.inset += amount
        return s
    }

    func path(in full: CGRect) -> Path {
        let rect = full.insetBy(dx: inset, dy: inset)
        let r = min(Theme.shared.radius.bubble, rect.height / 2, rect.width / 2)
        let tail = min(Theme.shared.radius.bubbleTail, r)
        let tl = r, tr = r
        let br = outgoing ? tail : r
        let bl = outgoing ? r : tail
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The composer (Calm): a rounded field with the round send button, the toast pill floating above it,
/// and the encryption line under it. Return sends; Option-Return or Shift-Return adds a line.
struct ComposerBar: View {
    let placeholder: String
    let note: String
    var disabled: Bool = false
    let send: () async -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @FocusState private var focused: Bool
    /// The text as it was before its last change, for `ComposerInput.change`.
    @ViewState private var before = ""
    /// Shift-Return's key monitor while the composer is on screen.
    @ViewState private var monitor: Any?

    var body: some View {
        let empty = model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // A line break that comes without Option or Shift (an accessibility client setting the
                // text) sends, as Return does (ComposerInput).
                RField(placeholder, text: $model.composerText, focused: $focused, multiline: true, bare: true) {
                    Task { await send() }
                }
                .disabled(disabled)
                .onChange(of: model.composerText) { text in
                    let change = ComposerInput.change(old: before, new: text,
                                                      newLineKey: ComposerInput.newLineKeyDown(NSApp.currentEvent))
                    before = text
                    if case .send(let kept) = change {
                        model.composerText = kept
                        before = kept
                        Task { await send() }
                    }
                }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(p.onAccent)
                        .frame(width: Theme.shared.layout.sendButton, height: Theme.shared.layout.sendButton)
                        .background(Circle().fill(p.accentFill))
                }
                .buttonStyle(SendButtonStyle())
                .disabled(empty || disabled)
                .opacity(empty || disabled ? 0.5 : 1)
                .accessibilityLabel(tr(.homeSend))
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.shared.radius.composer, style: .continuous)
                .fill(p.surface).ravenShadow(p.cardShadow))
            .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.composer, style: .continuous)
                .strokeBorder(focused ? p.accentFill.opacity(0.45) : p.border, lineWidth: focused ? 2 : 1))
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 9.5)).accessibilityHidden(true)
                Text(note).lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundColor(p.textTertiary)
        }
        .frame(maxWidth: Theme.shared.layout.contentMaxWidth)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            ZStack {
                if let toast = model.toast {
                    ToastPill(toast: toast)
                        .transition(motionOff ? .opacity : .offset(y: 8).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 680)
            .alignmentGuide(.top) { d in d[.bottom] + 2 }
            .animation(motionOff ? nil : Theme.shared.curve("toast", Theme.shared.motion.toastIn), value: model.toast)
        }
        .onAppear {
            focused = true
            before = model.composerText
            // Shift-Return: the field editor's own "insert a line break" (what Option-Return does).
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard focused, ComposerInput.isShiftReturn(keyCode: event.keyCode, modifiers: event.modifierFlags),
                      let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return event }
                editor.insertNewlineIgnoringFieldEditor(nil)
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct SendButtonStyle: ButtonStyle {
    @Environment(\.motionOff) private var motionOff
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !motionOff ? 0.94 : 1)
            .animation(motionOff ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// What the composer does with a change of its text (E1, unverified: through accessibility, Return
/// arrived as a new line in the field instead of sending). A real Return key press never reaches the
/// text: the field sends on it. Option-Return and Shift-Return insert a line break. A text that grew
/// by one line break at its end with neither of those keys down (an accessibility client setting the
/// value, a typed line feed) means Return: what was there is sent, without the line break.
enum ComposerInput {
    enum Change: Equatable { case edit, send(String) }

    static func change(old: String, new: String, newLineKey: Bool) -> Change {
        guard !newLineKey, let last = new.last, last.isNewline, String(new.dropLast()) == old,
              !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .edit }
        return .send(old)
    }

    /// Return or Enter (keypad) with Option or Shift held: a new line.
    static func isNewLine(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        isReturn(keyCode) && !modifiers.intersection([.option, .shift]).isEmpty
    }

    /// Shift-Return, which the field itself would treat as Return (it sends); Option-Return is the
    /// system's own new line.
    static func isShiftReturn(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        isReturn(keyCode) && modifiers.contains(.shift) && !modifiers.contains(.command)
    }

    /// Whether `event` (the one being handled now) is a key press that inserts a line break.
    static func newLineKeyDown(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return isNewLine(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    private static func isReturn(_ keyCode: UInt16) -> Bool { keyCode == 36 || keyCode == 76 }
}

/// The open chat's place: whether it follows its newest message. It stays on while you are at the
/// bottom; new or taller content and a resized window never turn it off (the chat then scrolls to its
/// end); scrolling up does, and scrolling back down or sending a message turns it on again.
struct ChatFollow: Equatable {
    static let bottomID = "chat-bottom"
    static let space = "chat-scroll"
    /// How far above the end still counts as at the bottom.
    static let tolerance: CGFloat = 24

    private(set) var on = true
    private var content: CGFloat = -1
    private var viewport: CGFloat = -1

    /// One layout: `bottom` is the end of the messages in the visible area's coordinates, `content`
    /// their height. Whether to scroll to the end now.
    mutating func layout(bottom: CGFloat, content: CGFloat, viewport: CGFloat) -> Bool {
        let resized = content != self.content || viewport != self.viewport
        self.content = content
        self.viewport = viewport
        if resized { return on }
        on = bottom - viewport <= Self.tolerance
        return false
    }

    /// A new newest message: follow it while on; one you just sent always.
    mutating func newMessage(own: Bool) -> Bool {
        if own { on = true }
        return on
    }

    /// The newest message, and whether it is one this app just sent (still sending), for `onChange`.
    struct Newest: Equatable {
        let id: String
        let own: Bool
    }

    static func newest(_ list: [Message]) -> Newest? {
        list.last.map { Newest(id: $0.id, own: $0.direction == .outgoing && $0.state == .sending) }
    }
}

struct ChatGeometry: Equatable {
    var bottom: CGFloat
    var content: CGFloat
}

struct ChatGeometryKey: PreferenceKey {
    static let defaultValue = ChatGeometry(bottom: 0, content: 0)
    static func reduce(value: inout ChatGeometry, nextValue: () -> ChatGeometry) { value = nextValue() }
}
