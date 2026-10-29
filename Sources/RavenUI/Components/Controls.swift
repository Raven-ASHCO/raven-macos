import SwiftUI
import AppKit

// Controls drawn with plain SwiftUI shapes so they follow the tokens and render in ImageRenderer.
// Where AppKit is the right control (text fields, menus, scroll views), the snapshot renderer gets a
// look-alike drawn from shapes instead (`ravenSnapshot` environment flag).

extension Palette {
    public func tone(_ tone: AppModel.Tone) -> Color {
        switch tone {
        case .secondary: return textSecondary
        case .accent: return accent
        case .success: return success
        case .warning: return warning
        case .danger: return danger
        }
    }
}

// MARK: - Buttons

/// Calm buttons (tokens: 30 pt high, control radius, a hairline and a soft shadow; primary filled with
/// `accentFill`; quiet in the accent colour with no frame). They shrink a little while pressed.
public struct RButtonStyle: ButtonStyle {
    public enum Kind { case primary, secondary, danger, plain }
    var kind: Kind
    var compact: Bool

    public init(_ kind: Kind = .secondary, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        RButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct RButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: RButtonStyle.Kind
    let compact: Bool
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @Environment(\.motionOff) private var motionOff
    @ViewState private var hover = false

    var body: some View {
        let r = Theme.shared.radius.control
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        configuration.label
            .font(kind == .plain ? RFont.captionMedium : .system(size: compact ? 12 : Theme.shared.type.caption.size, weight: .medium))
            .foregroundColor(foreground)
            .lineLimit(1)
            .padding(.horizontal, kind == .plain ? 0 : (compact ? 10 : 12))
            .frame(minHeight: kind == .plain ? nil : (compact ? 26 : Theme.shared.layout.buttonHeight))
            .background(shape.fill(fill))
            .overlay(shape.stroke(stroke, lineWidth: kind == .primary || kind == .plain ? 0 : 1))
            .shadow(color: kind == .plain || kind == .primary ? .clear : Color.black.opacity(p.isDark ? 0.2 : 0.04), radius: 0.5, y: 1)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !motionOff && kind != .plain ? 0.97 : 1)
            .animation(motionOff ? nil : .easeOut(duration: Theme.shared.motion.press), value: configuration.isPressed)
            .opacity(enabled ? (configuration.isPressed && kind == .plain ? 0.7 : 1) : 0.45)
            .onHover { hover = $0 }
    }

    var fill: Color {
        switch kind {
        case .primary: return hover && enabled ? p.accentFillTop : p.accentFill
        case .secondary, .danger: return hover && enabled ? p.surface.opacity(0.9).blended(p.textPrimary, 0.05) : p.surface
        case .plain: return .clear
        }
    }

    var stroke: Color {
        switch kind {
        case .danger: return p.dangerFill.opacity(0.35)
        default: return p.borderStrong
        }
    }

    var foreground: Color {
        switch kind {
        case .primary: return p.onAccent
        case .secondary: return p.textPrimary
        case .danger: return p.dangerFill
        case .plain: return p.accent
        }
    }
}

extension Color {
    /// This colour with `amount` of `other` laid over it (for hover tints).
    func blended(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        func mix(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x) * (1 - amount) + Double(y) * amount }
        return Color(.sRGB, red: mix(a.redComponent, b.redComponent), green: mix(a.greenComponent, b.greenComponent),
                     blue: mix(a.blueComponent, b.blueComponent), opacity: Double(a.alphaComponent))
    }
}

// MARK: - Text field

/// A text field with Raven's look. In snapshots it is drawn as text, since ImageRenderer cannot draw
/// an NSTextField.
public struct RField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var mono: Bool
    /// A secure field (the Raven passphrase): never shown, never in a snapshot.
    var secure: Bool
    var focused: FocusState<Bool>.Binding?
    /// Grows to a few lines (the composer). Return still submits; Option+Return adds a line.
    var multiline: Bool
    /// No frame of its own (the Calm composer draws the frame around the field and the send button).
    var bare: Bool
    var onSubmit: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.ravenSnapshot) private var snapshot

    public init(_ placeholder: String, text: Binding<String>, icon: String? = nil, mono: Bool = false,
                secure: Bool = false, focused: FocusState<Bool>.Binding? = nil, multiline: Bool = false,
                bare: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.bare = bare
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.mono = mono
        self.secure = secure
        self.focused = focused
        self.multiline = multiline
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(p.textSecondary)
                    .accessibilityHidden(true)
            }
            if snapshot {
                Text(text.isEmpty ? placeholder : (secure ? String(repeating: "•", count: min(text.count, 12)) : text))
                    .foregroundColor(text.isEmpty ? (bare ? p.textTertiary : p.textSecondary) : p.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                field
            }
        }
        .font(mono ? RFont.mono : .system(size: bare ? 14 : 13))
        .padding(.horizontal, bare ? 0 : 10)
        .padding(.vertical, bare ? 0 : 6)
        .frame(minHeight: bare ? 32 : Theme.shared.layout.buttonHeight)
        .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control, style: .continuous)
            .fill(bare ? Color.clear : p.background))
        .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.control, style: .continuous)
            .strokeBorder(bare ? Color.clear : p.borderStrong, lineWidth: 1))
    }

    @ViewBuilder private var field: some View {
        if secure {
            let sf = SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(p.textPrimary)
                .onSubmit(onSubmit)
            if let focused { sf.focused(focused) } else { sf }
        } else if multiline {
            let tf = TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .foregroundColor(p.textPrimary)
                .onSubmit(onSubmit)
            if let focused { tf.focused(focused) } else { tf }
        } else {
            let tf = TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(p.textPrimary)
                .onSubmit(onSubmit)
            if let focused { tf.focused(focused) } else { tf }
        }
    }
}

// MARK: - Switch

/// Calm switch (36 x 22, a 16 pt knob): the knob springs across (curve `knob`) while the track's colour
/// fades (`switchColor`), and it stretches while pressed. Drawn from shapes; VoiceOver sees a standard
/// toggle. The label sits on the left, the switch on the right.
public struct RSwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        RSwitchBody(configuration: configuration)
    }
}

private struct RSwitchBody: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            // A button, so the switch takes keyboard focus (Full Keyboard Access) and Space toggles it.
            Button { configuration.isOn.toggle() } label: { EmptyView() }
                .buttonStyle(SwitchButtonStyle(isOn: configuration.isOn))
                .opacity(enabled ? 1 : 0.55)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A switch on its own (Calm rows put the title on the left themselves): VoiceOver reads a toggle named
/// `label`; Space toggles it with Full Keyboard Access.
public struct RSwitch: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    public var body: some View {
        Button { isOn.toggle() } label: { EmptyView() }
            .buttonStyle(SwitchButtonStyle(isOn: isOn))
            .opacity(enabled ? 1 : 0.55)
            .fixedSize()
            .accessibilityRepresentation {
                Toggle(label, isOn: $isOn)
            }
    }
}

/// Draws a switch as a button: pressed stretches the knob.
private struct SwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    func makeBody(configuration: Configuration) -> some View {
        CalmSwitch(isOn: isOn, pressed: configuration.isPressed).contentShape(Rectangle())
    }
}

/// The switch's track and knob, for a given state (also used where a switch only shows a state).
public struct CalmSwitch: View {
    let isOn: Bool
    var pressed = false
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff

    public init(isOn: Bool, pressed: Bool = false) {
        self.isOn = isOn
        self.pressed = pressed
    }

    public var body: some View {
        let l = Theme.shared.layout
        let m = Theme.shared.motion
        let knob = l.switchKnob
        let inset = (l.switchHeight - knob) / 2
        let width = pressed ? knob + 5 : knob
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? p.successFill : p.borderStrong)
                .animation(motionOff ? nil : .easeOut(duration: m.switchColor), value: isOn)
            Capsule().fill(Color.white)
                .frame(width: width, height: knob)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .offset(x: isOn ? l.switchWidth - inset - width : inset)
                .animation(motionOff ? nil : Theme.shared.curve("knob", m.switchKnob), value: isOn)
                .animation(motionOff ? nil : .easeOut(duration: m.press), value: pressed)
        }
        .frame(width: l.switchWidth, height: l.switchHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Menu picker

/// A pop-up menu. In snapshots it is drawn as a pill with the current choice.
public struct RPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.palette) private var p
    @Environment(\.ravenSnapshot) private var snapshot

    public init(options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        if snapshot {
            Pill(text: (options.first { $0.value == selection }?.label ?? "") + "  ▾")
        } else {
            Picker("", selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].label).tag(options[i].value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - Action menu

/// A pull-down menu of actions (e.g. "Turn on for…"). In snapshots it is drawn as a pill.
public struct RMenu: View {
    let title: String
    let items: [(label: String, action: () -> Void)]
    @Environment(\.ravenSnapshot) private var snapshot

    public init(_ title: String, items: [(label: String, action: () -> Void)]) {
        self.title = title
        self.items = items
    }

    public var body: some View {
        if snapshot {
            Pill(text: title + "  ▾", tone: .accent)
        } else {
            Menu(title) {
                ForEach(items.indices, id: \.self) { i in Button(items[i].label, action: items[i].action) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

// MARK: - Scroll view

/// A vertical scroll view; a clipped stack in snapshots (ImageRenderer cannot draw NSScrollView).
public struct RScroll<Content: View>: View {
    var bottomAligned: Bool
    let content: Content
    @Environment(\.ravenSnapshot) private var snapshot

    public init(bottomAligned: Bool = false, @ViewBuilder content: () -> Content) {
        self.bottomAligned = bottomAligned
        self.content = content()
    }

    public var body: some View {
        if snapshot {
            VStack(spacing: 0) {
                if bottomAligned { Spacer(minLength: 0) }
                content
                if !bottomAligned { Spacer(minLength: 0) }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: bottomAligned ? .bottom : .top)
            .clipped()
        } else {
            ScrollView(.vertical) { content }
        }
    }
}

// MARK: - Small pieces

public struct Pill: View {
    let text: String
    var tone: AppModel.Tone = .secondary
    @Environment(\.palette) private var p

    public init(text: String, tone: AppModel.Tone = .secondary) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        let c = p.tone(tone)
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(c)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(Capsule().fill(c.opacity(tone == .secondary ? 0.09 : 0.11)))
            .fixedSize()
    }
}

/// A word chip. `highlighted` is the read-aloud highlight; `tag` is the small "check" label.
public struct Chip: View {
    let text: String
    var highlighted = false
    var tag: String?
    var removable = false
    @Environment(\.palette) private var p

    public init(_ text: String, highlighted: Bool = false, tag: String? = nil, removable: Bool = false) {
        self.text = text
        self.highlighted = highlighted
        self.tag = tag
        self.removable = removable
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(text).font(RFont.body)
            if let tag { Text(tag).font(RFont.small).foregroundColor(p.warning) }
            if removable {
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).foregroundColor(p.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(highlighted ? p.accent : p.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Theme.shared.radius.chip, style: .continuous)
            .fill(highlighted ? p.accentSoft : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.chip, style: .continuous)
            .stroke(highlighted ? Color.clear : p.borderStrong, lineWidth: 0.5))
    }
}

/// An activity indicator tied to real work in progress (creating the identity, node starting).
/// With reduced motion it stands still.
public struct Spinner: View {
    var size: CGFloat = 14
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var spinning = false

    public init(size: CGFloat = 14) { self.size = size }

    public var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(p.accent, style: StrokeStyle(lineWidth: max(1.5, size / 9), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !motionOff, !snapshot else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            }
            .accessibilityHidden(true)
    }
}

/// The Raven mark from desktop/design/assets, drawn in the secondary text colour so it stays visible
/// in both light and dark mode (the source PNG is a semi-transparent grey mark).
public struct RavenMark: View {
    var size: CGFloat
    var color: Color?
    @Environment(\.palette) private var p
    public init(size: CGFloat, color: Color? = nil) { self.size = size; self.color = color }
    public var body: some View {
        Image(nsImage: color == nil ? RavenResources.mark(size: size, template: true) : RavenResources.solidMark(size: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .foregroundColor(color ?? p.textSecondary)
            .frame(width: size, height: size)
            .accessibilityLabel(tr(.appName))
    }
}

/// An error that says what happened and one thing to do, with the technical text one click away.
public struct ErrorNote: View {
    let error: RavenError
    @ViewState private var showDetail = false
    @Environment(\.palette) private var p

    public init(_ error: RavenError) { self.error = error }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.message).foregroundColor(p.danger).fixedSize(horizontal: false, vertical: true)
            if !error.detail.isEmpty {
                Button(tr(.messageDetails)) { showDetail.toggle() }.buttonStyle(RButtonStyle(.plain))
                if showDetail {
                    Text(error.detail).font(RFont.mono).foregroundColor(p.textSecondary).selectable()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A thin horizontal rule in the border colour.
public struct Rule: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View { Rectangle().fill(p.border).frame(height: 0.5) }
}

/// A thin vertical rule in the border colour.
public struct VRule: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View { Rectangle().fill(p.border).frame(width: 0.5) }
}

/// Puts text on the general pasteboard.
public enum Clipboard {
    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Text selection, except in snapshots (selectable text is drawn by AppKit).
struct SelectableText: ViewModifier {
    @Environment(\.ravenSnapshot) private var snapshot
    func body(content: Content) -> some View {
        if snapshot { content } else { content.textSelection(.enabled) }
    }
}

extension View {
    func selectable() -> some View { modifier(SelectableText()) }
}
