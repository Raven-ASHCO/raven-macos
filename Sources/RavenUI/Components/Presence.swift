import SwiftUI
import AppKit
import QuartzCore

/// Runs `start` without animation, then animates to `end` on the next run-loop turn.
/// Used for one-shot effects (heartbeat pulse, presence blink, retry ring) caused by an event.
@MainActor
func pulse(motionOff: Bool, _ animation: Animation, start: @escaping () -> Void, end: @escaping () -> Void) {
    guard !motionOff else { return }
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, start)
    DispatchQueue.main.async { withAnimation(animation, end) }
}

/// A friend's avatar: initial on the avatar colour (tokens avatarRule) with the presence dot, whose
/// ring takes the colour of what is behind the row (`ring`: the sidebar, or the selected row's card).
public struct Avatar: View {
    let contact: Contact
    var size: CGFloat
    var blink: Int
    var retry: Int
    var ring: Color?
    var showDot: Bool
    @Environment(\.palette) private var p

    public init(_ contact: Contact, size: CGFloat = Theme.shared.layout.avatarSize, blink: Int = 0, retry: Int = 0,
                ring: Color? = nil, showDot: Bool = true) {
        self.contact = contact
        self.size = size
        self.blink = blink
        self.retry = retry
        self.ring = ring
        self.showDot = showDot
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            InitialAvatar(initial: contact.initial, colors: p.avatar(for: contact.address), size: size)
            if showDot {
                PresenceDot(presence: contact.presence, blink: blink, retry: retry, ring: ring ?? p.sidebar)
                    .offset(x: 1, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A round avatar with one letter (friends, you, group members).
public struct InitialAvatar: View {
    let initial: String
    let colors: AvatarColors
    var size: CGFloat
    var ring: Color?

    public init(initial: String, colors: AvatarColors, size: CGFloat = Theme.shared.layout.avatarSize, ring: Color? = nil) {
        self.initial = initial
        self.colors = colors
        self.size = size
        self.ring = ring
    }

    public var body: some View {
        Circle().fill(colors.background)
            .overlay(Text(initial).font(.system(size: size * 0.39, weight: .semibold)).foregroundColor(colors.foreground))
            .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: 2) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The presence dot: green in touch (breathes slowly), amber waiting, grey otherwise.
/// A `presence` event blinks it once; a `retry` event sends one ring outwards (1 s).
public struct PresenceDot: View {
    let presence: Presence
    var blink: Int
    var retry: Int
    var ring: Color?
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var blinkScale = 1.0
    @ViewState private var ringScale = 1.0
    @ViewState private var ringOpacity = 0.0

    public init(presence: Presence, blink: Int = 0, retry: Int = 0, ring: Color? = nil) {
        self.presence = presence
        self.blink = blink
        self.retry = retry
        self.ring = ring
    }

    var color: Color {
        switch presence {
        case .inTouch: return p.presenceInTouch
        case .waiting: return p.presenceWaiting
        case .none, .noAddress: return p.presenceNone
        }
    }

    public var body: some View {
        let d = Theme.shared.layout.presenceDot
        let border = ring ?? p.surface
        ZStack {
            Circle().stroke(p.warningFill, lineWidth: 2)
                .frame(width: d + 4, height: d + 4)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            core(border).frame(width: d, height: d).scaleEffect(blinkScale)
        }
        .frame(width: d, height: d)
        .onChange(of: blink) { _ in
            let m = Theme.shared.motion
            pulse(motionOff: motionOff, .easeOut(duration: m.presenceBlink), start: { blinkScale = 1.5 }, end: { blinkScale = 1 })
        }
        .onChange(of: retry) { _ in
            pulse(motionOff: motionOff, .easeOut(duration: Theme.shared.motion.retryRing),
                  start: { ringScale = 1; ringOpacity = 0.9 }, end: { ringScale = 1.8; ringOpacity = 0 })
        }
    }

    @ViewBuilder private func core(_ border: Color) -> some View {
        if presence == .inTouch && !motionOff && !snapshot {
            // Core Animation runs the slow breathing in the window server: no app CPU while idle.
            BreathingDot(color: NSColor(color), border: NSColor(border), period: Theme.shared.motion.presenceBreathe)
        } else if presence == .noAddress {
            Circle().fill(border).overlay(Circle().strokeBorder(color, lineWidth: 1.5))
        } else {
            Circle().fill(color).overlay(Circle().strokeBorder(border, lineWidth: 2))
        }
    }
}

/// A dot whose opacity breathes with a Core Animation loop (1 -> 0.45 -> 1 over `period`).
struct BreathingDot: NSViewRepresentable {
    let color: NSColor
    let border: NSColor
    let period: Double

    func makeNSView(context: Context) -> BreathingDotView { BreathingDotView() }

    func updateNSView(_ view: BreathingDotView, context: Context) {
        view.configure(color: color, border: border, period: period)
    }
}

final class BreathingDotView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(color: NSColor, border: NSColor, period: Double) {
        guard let layer else { return }
        layer.backgroundColor = color.cgColor
        layer.borderColor = border.cgColor
        layer.borderWidth = 2
        if layer.animation(forKey: "breathe") == nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0
            a.toValue = 0.45
            a.duration = period / 2
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: "breathe")
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

/// Lays children out left to right and wraps to new lines (word chips).
public struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(i)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
