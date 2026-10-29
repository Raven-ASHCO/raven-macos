import SwiftUI

// The Calm design's shared pieces (desktop/design/tokens.json version 2): cards, grouped rows,
// segmented controls, radio rows, path chips and their icons, the message status icons, the group
// ring and the toast pill. Every piece is drawn from SwiftUI shapes, so it follows the tokens and
// renders in ImageRenderer snapshots.

// MARK: - Cards

struct CalmCard: ViewModifier {
    var radius: CGFloat
    var fill: Color?
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill ?? p.surface).ravenShadow(p.cardShadow))
            .overlay(shape.strokeBorder(p.border, lineWidth: 1))
    }
}

extension View {
    /// A Calm card: `surface`, a hairline and the card shadow.
    func calmCard(radius: CGFloat = Theme.shared.radius.card, fill: Color? = nil) -> some View {
        modifier(CalmCard(radius: radius, fill: fill))
    }
}

/// A grouped card of rows with hairlines between them (Settings, the Network page's protections).
struct CalmGroup<Content: View>: View {
    let label: String?
    let content: Content

    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { SectionLabel(label).padding(.leading, 4) }
            _VariadicView.Tree(DividedRows()) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .calmCard(radius: Theme.shared.radius.group)
        }
    }
}

/// Puts a hairline between the rows of a `CalmGroup`.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.offset) { i, child in
                if i > 0 { Rule() }
                child
            }
        }
    }
}

/// One row of a grouped card: title (and an optional description) on the left, the control on the
/// right, as in the Calm Settings.
struct CalmItem<Control: View>: View {
    let title: String
    let description: String?
    var disabled = false
    let control: Control
    @Environment(\.palette) private var p

    init(_ title: String, _ description: String? = nil, disabled: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.disabled = disabled
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if let description, !description.isEmpty {
                    Text(description).font(RFont.caption).foregroundColor(p.textSecondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(disabled ? 0.6 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .contain)
    }
}

extension CalmItem where Control == EmptyView {
    init(_ title: String, _ description: String? = nil, disabled: Bool = false) {
        self.init(title, description, disabled: disabled) { EmptyView() }
    }
}

// MARK: - Segmented control

/// A segmented control whose thumb slides and resizes to the chosen option (curve `thumb`).
/// VoiceOver reads a radio group; each option is a button.
public struct RSegmented<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Namespace private var thumb

    public init(_ label: String, options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.label = label
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    guard !on else { return }
                    if motionOff { selection = option.value } else {
                        withAnimation(Theme.shared.curve("thumb", Theme.shared.motion.segmentThumb)) { selection = option.value }
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundColor(on ? p.textPrimary : p.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: Theme.shared.radius.segmentThumb, style: .continuous)
                                    .fill(p.surface)
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.segmentThumb, style: .continuous)
                                        .strokeBorder(p.border, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Theme.shared.radius.segment, style: .continuous)
            .fill(p.textPrimary.opacity(0.07)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Radio rows

/// A column of radio rows (When I quit): the dot pops in (curve `pop`).
public struct RRadioGroup<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    public init(_ label: String, options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.label = label
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().strokeBorder(on ? p.accentFill : p.borderStrong, lineWidth: 1.5)
                            Circle().fill(p.accentFill).frame(width: 8, height: 8)
                                .scaleEffect(on ? 1 : 0.001)
                                .animation(motionOff ? nil : Theme.shared.curve("pop", Theme.shared.motion.radioDot), value: on)
                        }
                        .frame(width: 16, height: 16)
                        Text(option.label).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - State chips

/// The small state chip of the Calm Settings: a dot and a word, tinted by tone.
struct StatChip: View {
    let text: String
    var tone: AppModel.Tone = .success
    @Environment(\.palette) private var p

    var body: some View {
        let c = tone == .secondary ? p.textSecondary : p.tone(tone)
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .foregroundColor(c)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone == .warning ? p.warningSoft
                                   : tone == .secondary ? p.textPrimary.opacity(0.07)
                                   : (tone == .success ? p.successFill : c).opacity(0.14)))
        .fixedSize()
    }
}

// MARK: - Paths

/// The colour family of a path kind (tokens.json `color.pathRule`).
public enum PathFamily: Equatable {
    case lan, nearby, tor, direct, relay, friend, other

    public static func of(kind: String?) -> PathFamily {
        switch kind {
        case "lan": return .lan
        case "nearby": return .nearby
        case "tor", "onion": return .tor
        case "internet", "p2p_direct", "p2p_reversed", "p2p_hole_punched": return .direct
        case "p2p", "p2p_relayed", "relay", "websocket": return .relay
        case "friend", "handoff", "letter", "custody": return .friend
        default: return .other
        }
    }

    /// A way of the Network page (`network.status` carrier id).
    public static func of(way: String) -> PathFamily {
        switch way {
        case "lan", "lan_beacon": return .lan
        case "nearby": return .nearby
        case "tor", "onion": return .tor
        case "internet", "port_mapping": return .direct
        case "p2p", "wss", "proxy", "friend_relay", "route_hints": return .relay
        case "custody", "custody_wan", "letters", "handoff", "carry_for_friends", "friends_carry_mine": return .friend
        default: return .other
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .lan: return p.named("pathLan")
        case .nearby: return p.named("pathNearby")
        case .tor: return p.named("pathTor")
        case .direct: return p.named("pathDirect")
        case .relay: return p.named("pathRelay")
        case .friend: return p.named("pathFriend")
        case .other: return p.textSecondary
        }
    }
}

/// The small icon of a path family (the prototype's icons; SF Symbols where macOS has one).
struct PathIcon: View {
    let family: PathFamily
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch family {
            case .lan: Image(systemName: "wifi").font(.system(size: size * 0.92, weight: .medium))
            case .direct: Image(systemName: "globe").font(.system(size: size * 0.92, weight: .medium))
            case .friend: Image(systemName: "envelope").font(.system(size: size * 0.85, weight: .medium))
            case .nearby: BluetoothGlyph().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
            case .tor: OnionGlyph().stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
            case .relay: RelayGlyph().stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
            case .other: Image(systemName: "arrow.left.arrow.right").font(.system(size: size * 0.85, weight: .medium))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A coloured path chip with its icon: "LAN direct", "via Tor", "Held by a friend", "Bluetooth".
struct PathPill: View {
    let label: String
    let family: PathFamily
    var small = true
    @Environment(\.palette) private var p

    var body: some View {
        let c = family.color(p)
        HStack(spacing: 4) {
            PathIcon(family: family, size: small ? 11 : 13)
            Text(label).lineLimit(1)
        }
        .font(.system(size: small ? 11 : 12, weight: .medium))
        .foregroundColor(c)
        .padding(.leading, small ? 6 : 9)
        .padding(.trailing, small ? 8 : 10)
        .frame(height: small ? Theme.shared.layout.chipHeight : Theme.shared.layout.pillHeight)
        .background(Capsule().fill(c.opacity(0.11)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr(.networkPathA11y, ["path": label]))
    }
}

/// Bluetooth's rune, in a 16-point box.
struct BluetoothGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 16
        var p = Path()
        p.move(to: CGPoint(x: 4.5 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 11 * s, y: 10.5 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 13 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 3 * s))
        p.addLine(to: CGPoint(x: 11 * s, y: 5.5 * s))
        p.addLine(to: CGPoint(x: 4.5 * s, y: 11 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// An onion (Tor), in a 16-point box.
struct OnionGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var p = Path()
        p.addEllipse(in: CGRect(x: r.minX + 2.8 * s, y: r.minY + 3.8 * s, width: 10.4 * s, height: 10.4 * s))
        p.move(to: pt(8, 3.8))
        p.addQuadCurve(to: pt(8, 14.2), control: pt(3.4, 9))
        p.move(to: pt(8, 3.8))
        p.addQuadCurve(to: pt(8, 14.2), control: pt(12.6, 9))
        p.move(to: pt(8, 3.8))
        p.addLine(to: pt(8, 2))
        return p
    }
}

/// A relay: two ends and the box between them, in a 16-point box.
struct RelayGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 16
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: r.minX + x * s, y: r.minY + y * s, width: w * s, height: h * s)
        }
        var p = Path()
        p.addEllipse(in: rect(1.3, 6.5, 3, 3))
        p.addEllipse(in: rect(11.7, 6.5, 3, 3))
        p.addRoundedRect(in: rect(6, 5.5, 4, 5), cornerSize: CGSize(width: 1.2 * s, height: 1.2 * s))
        p.move(to: CGPoint(x: r.minX + 4.3 * s, y: r.minY + 8 * s))
        p.addLine(to: CGPoint(x: r.minX + 6 * s, y: r.minY + 8 * s))
        p.move(to: CGPoint(x: r.minX + 10 * s, y: r.minY + 8 * s))
        p.addLine(to: CGPoint(x: r.minX + 11.7 * s, y: r.minY + 8 * s))
        return p
    }
}

// MARK: - Message status icons

/// The tick's icon: a spinner while sending, a ring with a check once sent, a filled check once a
/// signed receipt came (it pops when `pop` changes), a dashed clock while waiting. The colour comes
/// from the surrounding foreground.
struct StatusIcon: View {
    typealias Kind = Display.StatusKind
    let kind: Kind
    var pop = 0
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var scale: CGFloat = 1
    @ViewState private var ripple: CGFloat = 0
    @ViewState private var spin = false

    var body: some View {
        ZStack {
            switch kind {
            case .sending:
                Circle().stroke(lineWidth: 1.6).opacity(0.25)
                Circle().trim(from: 0, to: 0.25).stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        guard !motionOff, !snapshot else { return }
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
            case .sent:
                Circle().stroke(lineWidth: 1.4).padding(0.7)
                CheckShape().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .padding(3.6)
            case .delivered:
                Circle().strokeBorder(lineWidth: 1.5).scaleEffect(1 + ripple * 1.2).opacity(Double(1 - ripple) * (ripple > 0 ? 0.9 : 0))
                Circle()
                CheckShape().stroke(p.surface, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .padding(3.4)
            case .waiting:
                Circle().stroke(style: StrokeStyle(lineWidth: 1.4, dash: [2.4, 2.2])).padding(0.7)
                ClockHands().stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            case .problem:
                Circle().stroke(lineWidth: 1.4).padding(0.7)
                Path { path in
                    path.move(to: CGPoint(x: 7, y: 4)); path.addLine(to: CGPoint(x: 7, y: 7.6))
                    path.move(to: CGPoint(x: 7, y: 9.8)); path.addLine(to: CGPoint(x: 7, y: 9.9))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: 14, height: 14)
        .scaleEffect(scale)
        .accessibilityHidden(true)
        .onChange(of: pop) { _ in
            // The receipt came: the check fills and pops, and one ring spreads out.
            let m = Theme.shared.motion
            pulse(motionOff: motionOff, Theme.shared.curve("pop", m.checkPop), start: { scale = 0.4 }, end: { scale = 1 })
            pulse(motionOff: motionOff, .easeOut(duration: m.tickRipple), start: { ripple = 0.01 }, end: { ripple = 1 })
        }
    }
}

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - r.height * 0.08))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        return p
    }
}

private struct ClockHands: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 14
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 7 * s, y: r.minY + 4.3 * s))
        p.addLine(to: CGPoint(x: r.minX + 7 * s, y: r.minY + 7 * s))
        p.addLine(to: CGPoint(x: r.minX + 8.8 * s, y: r.minY + 8.2 * s))
        return p
    }
}

// MARK: - Group ring

/// One arc per member of a group message: delivered (`successFill`), waiting or sent (`warningFill`
/// while the copy waits, `borderStrong` while unconfirmed), failed (`dangerFill`). An arc takes its new
/// colour with a short fade (`groupArc`) when a member's receipt comes.
struct GroupRing: View {
    let states: [String]
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    var body: some View {
        let n = max(1, states.count)
        let gap = n > 1 ? 0.035 : 0
        ZStack {
            ForEach(Array(states.enumerated()), id: \.offset) { i, state in
                let start = Double(i) / Double(n)
                Circle()
                    .trim(from: start, to: start + 1 / Double(n) - gap)
                    .stroke(color(state), style: StrokeStyle(lineWidth: 3.2))
                    .animation(motionOff ? nil : .easeOut(duration: Theme.shared.motion.groupArc), value: state)
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(1.6)
        .frame(width: Theme.shared.layout.groupRing, height: Theme.shared.layout.groupRing)
        .accessibilityHidden(true)
    }

    private func color(_ state: String) -> Color {
        switch state {
        case "delivered": return p.successFill
        case "waiting": return p.warningFill
        case "failed": return p.dangerFill
        default: return p.borderStrong
        }
    }
}

// MARK: - Toast pill

/// What just happened, as a pill floating above the composer (5 s, `toastVisible`): a new message,
/// a delivery, a retry. It rises in (curve `toast`) and fades out.
struct ToastPill: View {
    let toast: AppModel.Toast
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 7) {
            switch toast.tone {
            case .success: StatusIcon(kind: .delivered)
            case .warning: StatusIcon(kind: .waiting)
            default: EmptyView()
            }
            Text(toast.text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 12))
        .foregroundColor(toast.tone == .success ? p.success : toast.tone == .warning ? p.warning : p.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(p.surface).ravenShadow(p.cardShadow))
        .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
