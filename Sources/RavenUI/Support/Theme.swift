import SwiftUI

/// The design tokens (desktop/design/tokens.json, version 2: the Calm design), loaded at runtime from
/// the bundled copy.
public final class Theme: @unchecked Sendable {
    public static let shared: Theme = {
        guard let data = RavenResources.data("tokens", "json"), let theme = try? Theme(json: data) else {
            fatalError("tokens.json is missing or unreadable in the RavenUI resource bundle")
        }
        return theme
    }()

    public struct Spacing { public let xs, sm, md, lg, xl, xxl: CGFloat }
    public struct Radius {
        public let control, card, group, row, bubble, bubbleTail, chip, chipSmall, badge, composer, sheet,
            dialog, segment, segmentThumb, window: CGFloat
    }
    public struct Layout {
        public let sidebarWidth, sidebarMinWidth, settingsNavWidth: CGFloat
        public let minWidth: CGFloat, minHeight: CGFloat
        public let headerHeight, routeLineHeight: CGFloat
        public let avatarSize, avatarSmall, avatarLarge, presenceDot: CGFloat
        public let contentMaxWidth, pageMaxWidth, settingsMaxWidth: CGFloat
        public let bubbleMaxFraction: CGFloat
        public let chipHeight, pillHeight, buttonHeight, sendButton: CGFloat
        public let switchWidth, switchHeight, switchKnob, groupRing: CGFloat
    }
    /// Durations in seconds (tokens.json gives milliseconds): `motion.durationsMs` and `motion.calmMs`.
    public struct Motion {
        public let bubbleIn, routePacket, receiptBack, heartbeatPulse, statusCheckInterval,
            presenceBreathe, retryRing, logoReveal, wordReveal, readAloudStep, toastVisible: Double
        public let bubbleLift, checkPop, tickRipple, chipSlide, groupArc, viewIn, sectionOut, sectionIn,
            settingsGlide, segmentThumb, switchKnob, switchColor, radioDot, sheetIn, dialogIn, scrimFade,
            toastIn, presenceBlink, incomingHighlight, lockShackle, lockedFade, unlockFade, shake, hover,
            press, radarPulse: Double
    }
    /// One text style: size in points, weight, tracking (points).
    public struct TextStyle {
        public let size: CGFloat
        public let weight: Font.Weight
        public let tracking: CGFloat
        public var font: Font { .system(size: size, weight: weight) }
    }
    public struct TypeScale {
        public let body, small, title, display, displayTracking, mono: CGFloat
        public let bubble, label, caption, meta, sectionLabel, brand, pageTitle: TextStyle
    }
    /// `motion.curves`: cubic-bezier control points as in CSS.
    public struct Curve: Equatable {
        public let x1, y1, x2, y2: Double
    }
    /// `motion.springs`: response (seconds) and damping fraction.
    public struct Spring: Equatable {
        public let response, damping: Double
    }

    public let spacing: Spacing
    public let radius: Radius
    public let layout: Layout
    public let motion: Motion
    public let type: TypeScale
    public let curves: [String: Curve]
    public let springs: [String: Spring]
    /// `shadow.card` / `shadow.bubbleOut` / `shadow.sheet`, light and dark.
    let shadows: [String: (light: [ShadowLayer], dark: [ShadowLayer])]
    let light: Palette
    let dark: Palette

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let color = root["color"] as? [String: Any],
              let spacing = root["spacing"] as? [String: Double],
              let radius = root["radius"] as? [String: Double],
              let layout = root["layout"] as? [String: Any],
              let motion = root["motion"] as? [String: Any],
              let durations = motion["durationsMs"] as? [String: Double],
              let calm = motion["calmMs"] as? [String: Double],
              let curves = motion["curves"] as? [String: Any],
              let springs = motion["springs"] as? [String: Any],
              let typo = root["typography"] as? [String: Any]
        else { throw RavenError.internalError("tokens.json has an unexpected shape") }

        func num(_ d: [String: Double], _ k: String) throws -> CGFloat {
            guard let v = d[k] else { throw RavenError.internalError("tokens.json misses \(k)") }
            return CGFloat(v)
        }
        func secs(_ k: String) throws -> Double {
            guard let v = durations[k] ?? calm[k] else { throw RavenError.internalError("tokens.json misses motion \(k)") }
            return v / 1000
        }
        func size(_ k: String) -> CGFloat {
            CGFloat(((typo[k] as? [String: Any])?["size"] as? Double) ?? 13)
        }
        func style(_ k: String) throws -> TextStyle {
            guard let s = typo[k] as? [String: Any], let size = s["size"] as? Double else {
                throw RavenError.internalError("tokens.json misses typography \(k)")
            }
            let weight: Font.Weight
            switch s["weight"] as? String {
            case "semibold": weight = .semibold
            case "bold": weight = .bold
            case "medium": weight = .medium
            default: weight = .regular
            }
            // Tracking: em for small values (sectionLabel 0.04, pageTitle -0.01), points otherwise.
            let raw = s["tracking"] as? Double ?? 0
            let tracking = abs(raw) < 1 ? raw * size : raw
            return TextStyle(size: CGFloat(size), weight: weight, tracking: CGFloat(tracking))
        }

        self.spacing = Spacing(xs: try num(spacing, "xs"), sm: try num(spacing, "sm"), md: try num(spacing, "md"),
                               lg: try num(spacing, "lg"), xl: try num(spacing, "xl"), xxl: try num(spacing, "xxl"))
        self.radius = Radius(control: try num(radius, "control"), card: try num(radius, "card"),
                             group: try num(radius, "group"), row: try num(radius, "row"),
                             bubble: try num(radius, "bubble"), bubbleTail: try num(radius, "bubbleTail"),
                             chip: try num(radius, "chip"), chipSmall: try num(radius, "chipSmall"),
                             badge: try num(radius, "badge"), composer: try num(radius, "composer"),
                             sheet: try num(radius, "sheet"), dialog: try num(radius, "dialog"),
                             segment: try num(radius, "segment"), segmentThumb: try num(radius, "segmentThumb"),
                             window: try num(radius, "window"))
        let minWindow = layout["minWindow"] as? [String: Double] ?? [:]
        let sw = layout["switch"] as? [String: Double] ?? [:]
        let flat = layout.compactMapValues { $0 as? Double }
        self.layout = Layout(sidebarWidth: try num(flat, "sidebarWidth"), sidebarMinWidth: try num(flat, "sidebarMinWidth"),
                             settingsNavWidth: try num(flat, "settingsNavWidth"),
                             minWidth: CGFloat(minWindow["width"] ?? 760), minHeight: CGFloat(minWindow["height"] ?? 520),
                             headerHeight: try num(flat, "headerHeight"), routeLineHeight: try num(flat, "routeLineHeight"),
                             avatarSize: try num(flat, "avatarSize"), avatarSmall: try num(flat, "avatarSmall"),
                             avatarLarge: try num(flat, "avatarLarge"), presenceDot: try num(flat, "presenceDot"),
                             contentMaxWidth: try num(flat, "contentMaxWidth"), pageMaxWidth: try num(flat, "pageMaxWidth"),
                             settingsMaxWidth: try num(flat, "settingsMaxWidth"),
                             bubbleMaxFraction: try num(flat, "bubbleMaxFraction"),
                             chipHeight: try num(flat, "chipHeight"), pillHeight: try num(flat, "pillHeight"),
                             buttonHeight: try num(flat, "buttonHeight"), sendButton: try num(flat, "sendButton"),
                             switchWidth: try num(sw, "width"), switchHeight: try num(sw, "height"),
                             switchKnob: try num(sw, "knob"), groupRing: try num(flat, "groupRing"))
        self.motion = Motion(bubbleIn: try secs("bubbleIn"), routePacket: try secs("routePacket"),
                             receiptBack: try secs("receiptBack"), heartbeatPulse: try secs("heartbeatPulse"),
                             statusCheckInterval: try secs("statusCheckInterval"),
                             presenceBreathe: try secs("presenceBreathe"), retryRing: try secs("retryRing"),
                             logoReveal: try secs("logoReveal"), wordReveal: try secs("wordReveal"),
                             readAloudStep: try secs("readAloudStep"), toastVisible: try secs("toastVisible"),
                             bubbleLift: try secs("bubbleLift"), checkPop: try secs("checkPop"),
                             tickRipple: try secs("tickRipple"), chipSlide: try secs("chipSlide"),
                             groupArc: try secs("groupArc"), viewIn: try secs("viewIn"),
                             sectionOut: try secs("sectionOut"), sectionIn: try secs("sectionIn"),
                             settingsGlide: try secs("settingsGlide"), segmentThumb: try secs("segmentThumb"),
                             switchKnob: try secs("switchKnob"), switchColor: try secs("switchColor"),
                             radioDot: try secs("radioDot"), sheetIn: try secs("sheetIn"), dialogIn: try secs("dialogIn"),
                             scrimFade: try secs("scrimFade"), toastIn: try secs("toastIn"),
                             presenceBlink: try secs("presenceBlink"), incomingHighlight: try secs("incomingHighlight"),
                             lockShackle: try secs("lockShackle"), lockedFade: try secs("lockedFade"),
                             unlockFade: try secs("unlockFade"), shake: try secs("shake"), hover: try secs("hover"),
                             press: try secs("press"), radarPulse: try secs("radarPulse"))
        let display = typo["display"] as? [String: Any]
        self.type = TypeScale(body: size("body"), small: size("small"), title: size("title"), display: size("display"),
                              displayTracking: CGFloat((display?["tracking"] as? Double) ?? 8), mono: size("mono"),
                              bubble: try style("bubble"), label: try style("label"), caption: try style("caption"),
                              meta: try style("meta"), sectionLabel: try style("sectionLabel"), brand: try style("brand"),
                              pageTitle: try style("pageTitle"))

        var parsedCurves: [String: Curve] = [:]
        for (name, value) in curves {
            guard let p = value as? [Double] else { continue }
            guard p.count == 4 else { throw RavenError.internalError("tokens.json curve \(name) needs 4 numbers") }
            parsedCurves[name] = Curve(x1: p[0], y1: p[1], x2: p[2], y2: p[3])
        }
        self.curves = parsedCurves
        var parsedSprings: [String: Spring] = [:]
        for (name, value) in springs {
            guard let s = value as? [String: Double], let r = s["response"], let d = s["damping"] else { continue }
            parsedSprings[name] = Spring(response: r, damping: d)
        }
        self.springs = parsedSprings

        func layers(_ any: Any?) throws -> [ShadowLayer] {
            guard let list = any as? [[String: Any]] else { return [] }
            return try list.map { l in
                ShadowLayer(y: CGFloat(l["y"] as? Double ?? 0), blur: CGFloat(l["blur"] as? Double ?? 0),
                            color: try Theme.color(hex: l["color"] as? String ?? "#00000000"))
            }
        }
        var parsedShadows: [String: (light: [ShadowLayer], dark: [ShadowLayer])] = [:]
        for (name, value) in (root["shadow"] as? [String: Any]) ?? [:] {
            guard let s = value as? [String: Any] else { continue }
            parsedShadows[name] = (try layers(s["light"]), try layers(s["dark"]))
        }
        self.shadows = parsedShadows

        func pair(_ name: String) throws -> (String, String) {
            guard let p = color[name] as? [String: String], let l = p["light"], let d = p["dark"] else {
                throw RavenError.internalError("tokens.json misses colour \(name)")
            }
            return (l, d)
        }
        var lightColors: [String: Color] = [:]
        var darkColors: [String: Color] = [:]
        for name in Palette.names {
            let (l, d) = try pair(name)
            lightColors[name] = try Theme.color(hex: l)
            darkColors[name] = try Theme.color(hex: d)
        }
        guard let avatars = color["avatar"] as? [[String: [String: String]]], avatars.count == 5 else {
            throw RavenError.internalError("tokens.json needs 5 avatar colours")
        }
        var lightAvatars: [AvatarColors] = []
        var darkAvatars: [AvatarColors] = []
        for a in avatars {
            guard let bg = a["bg"], let fg = a["fg"], let bl = bg["light"], let bd = bg["dark"],
                  let fl = fg["light"], let fd = fg["dark"] else { throw RavenError.internalError("bad avatar colour") }
            lightAvatars.append(AvatarColors(background: try Theme.color(hex: bl), foreground: try Theme.color(hex: fl)))
            darkAvatars.append(AvatarColors(background: try Theme.color(hex: bd), foreground: try Theme.color(hex: fd)))
        }
        func shadow(_ name: String, dark: Bool) -> [ShadowLayer] {
            guard let s = parsedShadows[name] else { return [] }
            return dark ? s.dark : s.light
        }
        self.light = Palette(colors: lightColors, avatars: lightAvatars, isDark: false,
                             cardShadow: shadow("card", dark: false), bubbleShadow: shadow("bubbleOut", dark: false),
                             sheetShadow: shadow("sheet", dark: false))
        self.dark = Palette(colors: darkColors, avatars: darkAvatars, isDark: true,
                            cardShadow: shadow("card", dark: true), bubbleShadow: shadow("bubbleOut", dark: true),
                            sheetShadow: shadow("sheet", dark: true))
    }

    public func palette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }

    /// "#RRGGBB" or "#RRGGBBAA" in sRGB.
    public static func color(hex: String) throws -> Color {
        let (r, g, b, a) = try rgba(hex: hex)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    public static func rgba(hex: String) throws -> (Double, Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            throw RavenError.internalError("bad colour \(hex)")
        }
        if s.count == 6 {
            return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, 1)
        }
        return (Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// tokens.json avatarRule: (sum of the bytes of the friend's Raven address) mod 5.
    public static func avatarIndex(for address: String) -> Int {
        address.utf8.reduce(0) { ($0 + Int($1)) % 5 }
    }

    // MARK: Motion

    /// A named curve (`motion.curves`) over `duration` seconds. Unknown names fall back to ease-out.
    public func curve(_ name: String, _ duration: Double) -> Animation {
        guard let c = curves[name] else { return .easeOut(duration: duration) }
        return .timingCurve(c.x1, c.y1, c.x2, c.y2, duration: duration)
    }

    /// A named spring (`motion.springs`).
    public func spring(_ name: String) -> Animation {
        guard let s = springs[name] else { return .easeOut(duration: 0.35) }
        return .spring(response: s.response, dampingFraction: s.damping)
    }
}

public struct AvatarColors {
    public let background: Color
    public let foreground: Color
}

/// One layer of a token shadow.
public struct ShadowLayer {
    public let y: CGFloat
    public let blur: CGFloat
    public let color: Color
}

/// Colours for one appearance (light or dark).
public struct Palette {
    static let names = ["background", "surface", "surfaceMuted", "sidebar", "textPrimary", "textSecondary",
                        "textTertiary", "border", "borderStrong", "accent", "accentFill", "accentFillTop", "onAccent",
                        "accentSoft", "focus", "success", "successFill", "warning", "warningFill", "warningSoft",
                        "danger", "dangerFill", "presenceInTouch", "presenceWaiting", "presenceNone",
                        "pathLan", "pathNearby", "pathTor", "pathDirect", "pathRelay", "pathFriend",
                        "sectionGeneral", "sectionAppearance", "sectionPrivacy", "sectionLock", "sectionNetwork",
                        "sectionUpdates", "sectionAbout"]
    let colors: [String: Color]
    public let avatars: [AvatarColors]
    public let isDark: Bool
    public let cardShadow: [ShadowLayer]
    public let bubbleShadow: [ShadowLayer]
    public let sheetShadow: [ShadowLayer]

    func c(_ name: String) -> Color { colors[name] ?? .gray }
    public func named(_ name: String) -> Color { c(name) }
    public var background: Color { c("background") }
    public var surface: Color { c("surface") }
    public var surfaceMuted: Color { c("surfaceMuted") }
    public var sidebar: Color { c("sidebar") }
    public var textPrimary: Color { c("textPrimary") }
    public var textSecondary: Color { c("textSecondary") }
    public var textTertiary: Color { c("textTertiary") }
    public var border: Color { c("border") }
    public var borderStrong: Color { c("borderStrong") }
    public var accent: Color { c("accent") }
    public var accentFill: Color { c("accentFill") }
    public var accentFillTop: Color { c("accentFillTop") }
    public var onAccent: Color { c("onAccent") }
    public var accentSoft: Color { c("accentSoft") }
    public var focus: Color { c("focus") }
    public var success: Color { c("success") }
    public var successFill: Color { c("successFill") }
    public var warning: Color { c("warning") }
    public var warningFill: Color { c("warningFill") }
    public var warningSoft: Color { c("warningSoft") }
    public var danger: Color { c("danger") }
    public var dangerFill: Color { c("dangerFill") }
    public var presenceInTouch: Color { c("presenceInTouch") }
    public var presenceWaiting: Color { c("presenceWaiting") }
    public var presenceNone: Color { c("presenceNone") }

    public func avatar(for address: String) -> AvatarColors { avatars[Theme.avatarIndex(for: address)] }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey { static let defaultValue: Palette = Theme.shared.palette(.light) }
private struct MotionOffKey: EnvironmentKey { static let defaultValue = false }
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The resolved colours for the current appearance.
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    /// True when the system's Reduce motion or Raven's own Reduced motion setting is on: nothing moves.
    public var motionOff: Bool {
        get { self[MotionOffKey.self] }
        set { self[MotionOffKey.self] = newValue }
    }
    /// True while rendering PNG snapshots with ImageRenderer, which cannot draw AppKit-backed controls.
    public var ravenSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

struct RavenThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let appReducedMotion: Bool

    func body(content: Content) -> some View {
        let palette = Theme.shared.palette(scheme)
        content
            .environment(\.palette, palette)
            .environment(\.motionOff, systemReduceMotion || appReducedMotion)
            .foregroundColor(palette.textPrimary)
            .font(.system(size: Theme.shared.type.body))
    }
}

extension View {
    /// Resolves the palette for the current appearance and the reduced-motion flag.
    public func ravenTheme(reducedMotion: Bool = false) -> some View {
        modifier(RavenThemeModifier(appReducedMotion: reducedMotion))
    }

    /// The token shadow layers (`shadow.card` etc.) for the current palette.
    public func ravenShadow(_ layers: [ShadowLayer]) -> some View {
        modifier(ShadowLayers(layers: layers))
    }
}

private struct ShadowLayers: ViewModifier {
    let layers: [ShadowLayer]
    func body(content: Content) -> some View {
        layers.reduce(AnyView(content)) { view, l in
            AnyView(view.shadow(color: l.color, radius: l.blur / 2, x: 0, y: l.y))
        }
    }
}

// MARK: - Fonts

public enum RFont {
    static var t: Theme.TypeScale { Theme.shared.type }
    public static var body: Font { .system(size: t.body) }
    public static var bodyBold: Font { .system(size: t.body, weight: .semibold) }
    public static var small: Font { .system(size: t.small) }
    public static var smallish: Font { .system(size: 12) }
    public static var title: Font { .system(size: t.title, weight: .semibold) }
    public static var display: Font { .system(size: t.display, weight: .semibold) }
    public static var mono: Font { .system(size: t.mono, design: .monospaced) }
    // Calm type ramp (tokens.json typography).
    public static var bubble: Font { t.bubble.font }
    public static var label: Font { t.label.font }
    public static var caption: Font { t.caption.font }
    public static var captionMedium: Font { .system(size: t.caption.size, weight: .medium) }
    public static var meta: Font { t.meta.font }
    public static var metaBold: Font { .system(size: t.meta.size, weight: .semibold) }
    public static var sectionLabel: Font { t.sectionLabel.font }
    public static var brand: Font { t.brand.font }
    public static var pageTitle: Font { t.pageTitle.font }
}
