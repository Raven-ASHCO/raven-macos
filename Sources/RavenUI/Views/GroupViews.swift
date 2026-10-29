import SwiftUI

// Group chats (API.md "Groups"; Calm prototype: the group chat). Lab only: a release engine says
// `available: false` and the app shows no Groups section. A group message is sealed once for each
// member; under yours a ring fills as each member's Raven confirms it ("Delivered to 3 of 5").

/// GROUPS in the sidebar, when this build has groups.
struct GroupsSidebarSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.groupsAvailable && !model.groups.isEmpty {
            SectionLabel(tr(.homeGroups)).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
            ForEach(model.groups) { group in
                GroupRow(group: group)
            }
        }
    }
}

struct GroupRow: View {
    let group: RavenGroup
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let selected = model.page == .group && model.selectedGroupID == group.id
        let members = model.groupMembers[group.id] ?? []
        SidebarRowButton(selected: selected, action: { model.selectGroup(group.id) }) {
            HStack(spacing: 10) {
                MemberStack(members: members.filter { !$0.me }, ring: selected ? p.surface : p.sidebar)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name).font(RFont.label).lineLimit(1)
                    Text(groupLine(members)).font(.system(size: 12)).foregroundColor(p.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if group.unread > 0 { UnreadBadge(n: group.unread) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func groupLine(_ members: [GroupMember]) -> String {
        switch group.status {
        case "left": return tr(.groupsStatusLeft)
        case "removed": return tr(.groupsStatusRemoved)
        default: return Display.groupMembersLine(group, members: members, contacts: model.contacts)
        }
    }
}

/// Up to three members' avatars in a 36-point square (the sidebar's group icon).
struct MemberStack: View {
    let members: [GroupMember]
    var ring: Color
    @Environment(\.palette) private var p

    var body: some View {
        let shown = Array(members.prefix(3))
        let spots: [CGPoint] = [CGPoint(x: 10.5, y: 11.5), CGPoint(x: 25.5, y: 11.5), CGPoint(x: 18, y: 25.5)]
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, m in
                InitialAvatar(initial: m.initial, colors: p.avatar(for: m.address), size: 21, ring: ring)
                    .position(spots[i])
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

/// The open group: header, route line, messages, composer (or why nothing can be sent).
struct GroupChatArea: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            if let group = model.selectedGroup {
                let members = model.groupMembers[group.id] ?? []
                GroupHeader(group: group, members: members)
                RouteLine(ends: (tr(.youTitle), tr(.groupsMembers, ["n": String(max(group.members, members.count))])),
                          label: RouteLabel(text: tr(.groupsSealed), family: .other, tone: nil, dashed: false))
                GroupMessagesList(group: group, members: members).id(group.id)
                if group.active {
                    ComposerBar(placeholder: tr(.homeComposer, ["name": group.name]), note: tr(.groupsEncrypted)) {
                        await model.sendGroupComposer()
                    }
                } else {
                    Text(group.status == "removed" ? tr(.groupsStatusRemoved) : tr(.groupsStatusLeft))
                        .font(.system(size: 13)).foregroundColor(p.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .overlay(alignment: .top) { Rule() }
                }
            }
        }
        .background(p.background)
    }
}

struct GroupHeader: View {
    let group: RavenGroup
    let members: [GroupMember]
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -6) {
                ForEach(members.filter { !$0.me }.prefix(6)) { m in
                    InitialAvatar(initial: m.initial, colors: p.avatar(for: m.address), size: 22, ring: p.background)
                }
            }
            .padding(.leading, 6)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.system(size: Theme.shared.type.title, weight: .semibold)).lineLimit(1)
                Text(Display.groupMembersLine(group, members: members, contacts: model.contacts) + " · " + tr(.groupsSealed))
                    .font(RFont.caption).foregroundColor(p.textSecondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button { model.presentGroupMembers(group.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2").accessibilityHidden(true)
                    Text(tr(.groupsMembersTitle))
                }
            }
            .buttonStyle(RButtonStyle(.secondary))
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, 22)
        .frame(height: Theme.shared.layout.headerHeight)
        .background(p.background.opacity(0.82))
        .overlay(alignment: .bottom) { Rule() }
    }
}

struct GroupMessagesList: View {
    let group: RavenGroup
    let members: [GroupMember]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let list = model.groupMessages[group.id] ?? []
        let newest = list.last.map { ChatFollow.Newest(id: $0.id, own: $0.mine && model.liftIDs.contains($0.id)) }
        ChatScroll(isEmpty: list.isEmpty, emptyText: tr(.groupsEmpty, ["name": group.name]), newest: newest) { width in
            VStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    if i == 0 || TimeText.differentDays(list[i - 1].atMs, m.atMs) {
                        DayLine(atMs: m.atMs)
                    }
                    GroupMessageRow(message: m, maxBubble: width * Theme.shared.layout.bubbleMaxFraction,
                                    sameAuthorAbove: i > 0 && !m.mine && list[i - 1].fromAddress == m.fromAddress
                                        && !TimeText.differentDays(list[i - 1].atMs, m.atMs))
                        .id(m.id)
                }
            }
        }
    }
}

/// One group message: theirs with the author's name (in their avatar colour) and a small avatar;
/// yours with the ring, "Delivered to n of m", what else is going on, and Details per member.
struct GroupMessageRow: View {
    let message: GroupMessage
    let maxBubble: CGFloat
    var sameAuthorAbove = false
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    var body: some View {
        let out = message.mine
        let colors = p.avatar(for: message.fromAddress)
        VStack(alignment: out ? .trailing : .leading, spacing: 0) {
            if !out && !sameAuthorAbove {
                Text(message.fromName).font(.system(size: 12, weight: .semibold)).foregroundColor(colors.foreground)
                    .padding(.leading, 42).padding(.bottom, 3)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if !out {
                    InitialAvatar(initial: String(message.fromName.prefix(1)).uppercased(), colors: colors, size: 22)
                        .opacity(sameAuthorAbove ? 0 : 1)
                }
                Bubble(text: message.text, outgoing: out, fresh: model.freshUntil[message.id] != nil,
                       liftID: out ? message.id : nil)
                    .frame(maxWidth: maxBubble, alignment: out ? .trailing : .leading)
                    .contextMenu { Button(tr(.addShareCopy)) { Clipboard.copy(message.text) } }
            }
            if out { GroupMeta(message: message) } else { incomingMeta.padding(.leading, 30) }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: out ? .trailing : .leading)
        .transition(motionOff || out ? .identity : .offset(y: 10).combined(with: .opacity))
    }

    private var incomingMeta: some View {
        HStack(spacing: 8) {
            Text(TimeText.bubble(ms: message.atMs, now: clock.now))
            if let via = message.viaName, !via.isEmpty { Text(tr(.groupsViaName, ["name": via])) }
        }
        .font(.system(size: 11.5))
        .foregroundColor(p.textSecondary)
        .padding(.top, 5)
        .padding(.horizontal, 4)
    }
}

/// Under your group message: time, the ring, "Delivered to n of m", the note, and Details / Hide.
struct GroupMeta: View {
    let message: GroupMessage
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    var body: some View {
        let status = Display.groupStatus(message)
        let receipts = message.receipts ?? []
        let open = model.groupDetailsOpen.contains(message.id)
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 8) {
                Text(TimeText.bubble(ms: message.atMs, now: clock.now)).foregroundColor(p.textSecondary)
                GroupRing(states: receipts.map(\.state))
                Text(status.text).font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(!receipts.isEmpty && receipts.allSatisfy { $0.state == "delivered" } ? p.success : p.textPrimary)
                if let note = status.note { Text("· " + note).foregroundColor(p.textSecondary) }
                if !receipts.isEmpty {
                    Button(open ? tr(.groupsHide) : tr(.messageDetails)) {
                        if open { model.groupDetailsOpen.remove(message.id) } else { model.groupDetailsOpen.insert(message.id) }
                    }
                    .buttonStyle(RButtonStyle(.plain))
                    .accessibilityAddTraits(open ? .isSelected : [])
                }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
            .padding(.top, 5)
            .padding(.horizontal, 4)
            if open && !receipts.isEmpty {
                ReceiptsCard(receipts: receipts)
                    .transition(motionOff ? .identity : .opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(motionOff ? nil : .easeOut(duration: 0.25), value: open)
    }
}

/// Each member's copy of one of your group messages.
struct ReceiptsCard: View {
    let receipts: [GroupReceipt]
    @Environment(\.palette) private var p

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(Array(receipts.enumerated()), id: \.offset) { _, r in
                let line = Display.receiptLine(r)
                GridRow {
                    HStack(spacing: 8) {
                        InitialAvatar(initial: String(r.name.prefix(1)).uppercased(), colors: p.avatar(for: r.address), size: 22)
                        Text(r.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        StatusIcon(kind: line.icon)
                        Text(line.text).lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(line.tone == .secondary ? p.textSecondary : p.tone(line.tone))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 290, alignment: .leading)
        .calmCard(radius: 12)
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Sheets

/// New group: a name and friends to add (up to 16 people, you included). Only friends can be added.
public struct NewGroupSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var name: String
    @ViewState private var chosen: Set<String>
    @ViewState private var busy = false
    @ViewState private var error: RavenError?

    public init(name: String = "", chosen: Set<String> = []) {
        self._name = ViewState(wrappedValue: name)
        self._chosen = ViewState(wrappedValue: chosen)
    }

    public var body: some View {
        let max = MockRavenLimits.groupMaxMembers - 1
        SheetFrame(tr(.groupsCreateTitle), subtitle: tr(.groupsCreateBody), width: 480) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(tr(.groupsCreateName))
                    RField(tr(.groupsCreateName), text: $name) { Task { await create() } }
                        .accessibilityLabel(tr(.groupsCreateName))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel(tr(.groupsCreateMembers))
                        Spacer()
                        Text(tr(.groupsCreateCount, ["n": String(chosen.count), "max": String(max)]))
                            .font(.system(size: 11.5)).foregroundColor(p.textSecondary)
                    }
                    if model.contacts.isEmpty {
                        Text(tr(.groupsCreateNoFriends)).font(.system(size: 13)).foregroundColor(p.textSecondary)
                    } else {
                        FriendPicker(contacts: model.contacts, chosen: $chosen, limit: max)
                    }
                    Text(tr(.groupsCreateLimit)).font(.system(size: 12)).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error { ErrorNote(error) }
            }
        } footer: {
            Button(tr(.commonCancel)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.groupsCreateButton)) { Task { await create() } }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(busy || chosen.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func create() async {
        guard !busy, !chosen.isEmpty else { return }
        busy = true
        defer { busy = false }
        let ordered = model.contacts.map(\.address).filter { chosen.contains($0) }
        error = await model.createGroup(name: Sanitizer.line(name, maxLength: 64), members: ordered)
        if error == nil { model.sheet = nil }
    }
}

/// The group size the apps offer (API.md: at most 16 members, you included).
enum MockRavenLimits {
    static let groupMaxMembers = 16
}

/// Friends to tick for a group (rows with a check box; at most `limit`).
struct FriendPicker: View {
    let contacts: [Contact]
    @Binding var chosen: Set<String>
    let limit: Int
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(contacts.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Rule() }
                let on = chosen.contains(c.address)
                Button {
                    if on { chosen.remove(c.address) } else if chosen.count < limit { chosen.insert(c.address) }
                } label: {
                    HStack(spacing: 10) {
                        Avatar(c, size: 26, showDot: false)
                        Text(c.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(on ? p.accentFill : p.borderStrong, lineWidth: 1.5)
                            if on {
                                RoundedRectangle(cornerRadius: 4).fill(p.accentFill)
                                CheckShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                    .padding(3.5)
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.name)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .calmCard(radius: Theme.shared.radius.group)
    }
}

/// A group's members: who is in it, which of them are your friends, the admin; the admin adds and
/// removes, a member can leave.
public struct GroupMembersSheet: View {
    let groupID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var adding = false
    @ViewState private var chosen: Set<String> = []
    @ViewState private var error: RavenError?

    public init(groupID: String) { self.groupID = groupID }

    public var body: some View {
        let group = model.groups.first { $0.id == groupID }
        let members = model.groupMembers[groupID] ?? []
        SheetFrame(group?.name ?? tr(.groupsMembersTitle),
                   subtitle: group.map { Display.groupMembersLine($0, members: members, contacts: model.contacts) },
                   width: 460) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Rule() }
                        HStack(spacing: 10) {
                            InitialAvatar(initial: m.initial, colors: p.avatar(for: m.address), size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.me ? tr(.youTitle) : m.name).font(.system(size: 13, weight: .medium))
                                let notes = [m.admin ? tr(.groupsAdmin) : nil, !m.friend && !m.me ? tr(.groupsNotFriend) : nil]
                                    .compactMap { $0 }
                                if !notes.isEmpty {
                                    Text(notes.joined(separator: " · ")).font(.system(size: 11.5)).foregroundColor(p.textSecondary)
                                }
                            }
                            Spacer()
                            if group?.admin == true && !m.me && group?.active == true {
                                Button(tr(.groupsRemove)) {
                                    Task { error = await model.removeGroupMember(groupID, member: m.address) }
                                }
                                .buttonStyle(RButtonStyle(.plain))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .calmCard(radius: Theme.shared.radius.group)
                if group?.admin != true, let admin = group?.adminName {
                    Text(tr(.groupsAdminOnly, ["name": admin])).font(.system(size: 12)).foregroundColor(p.textSecondary)
                }
                if adding, group?.admin == true {
                    let candidates = model.contacts.filter { c in !members.contains { $0.address == c.address } }
                    SectionLabel(tr(.groupsAddMembersTitle, ["name": group?.name ?? ""]))
                    FriendPicker(contacts: candidates, chosen: $chosen,
                                 limit: max(0, MockRavenLimits.groupMaxMembers - members.count))
                }
                if let error { ErrorNote(error) }
            }
        } footer: {
            if group?.admin != true && group?.active == true {
                Button(tr(.groupsLeave)) { model.presentLeaveGroup(groupID) }
                    .buttonStyle(RButtonStyle(.danger))
                Spacer()
            }
            if group?.admin == true && group?.active == true {
                if adding {
                    Button(tr(.groupsAddMembersButton)) {
                        Task {
                            error = await model.addGroupMembers(groupID, members: Array(chosen))
                            if error == nil { adding = false; chosen = [] }
                        }
                    }
                    .buttonStyle(RButtonStyle(.secondary))
                    .disabled(chosen.isEmpty)
                } else {
                    Button(tr(.groupsAddMembers)) { adding = true }
                        .buttonStyle(RButtonStyle(.secondary))
                        .disabled(members.count >= MockRavenLimits.groupMaxMembers)
                }
            }
            Button(tr(.commonDone)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Leave a group: what that means, then Leave.
public struct LeaveGroupSheet: View {
    let groupID: String
    @EnvironmentObject private var model: AppModel
    @ViewState private var error: RavenError?

    public init(groupID: String) { self.groupID = groupID }

    public var body: some View {
        let name = model.groups.first { $0.id == groupID }?.name ?? ""
        SheetFrame(tr(.groupsLeaveTitle, ["name": name]), width: 440) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(.groupsLeaveBody)).fixedSize(horizontal: false, vertical: true)
                if let error { ErrorNote(error) }
            }
        } footer: {
            Button(tr(.commonCancel)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.groupsLeaveConfirm)) {
                Task {
                    error = await model.leaveGroup(groupID)
                    if error == nil { model.sheet = nil }
                }
            }
            .buttonStyle(RButtonStyle(.danger))
        }
    }
}
