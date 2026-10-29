import SwiftUI

/// Your 10 security words as chips, with the read-aloud highlight stepping through them every
/// `readAloudStep` (800 ms) while they are on screen, and "Say: {word}" under them. Word 10 carries
/// the small "check" tag. With reduced motion nothing steps by itself: click a word to move the
/// highlight. Only ever shows *your* words.
public struct ReadAloudWords: View {
    let words: [String]
    var fixedHighlight: Int?
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var manual = 0
    @ViewState private var start = Date()

    public init(words: [String], fixedHighlight: Int? = nil) {
        self.words = words
        self.fixedHighlight = fixedHighlight
    }

    private var step: Double { Theme.shared.motion.readAloudStep }

    public var body: some View {
        if words.isEmpty {
            EmptyView()
        } else if let fixed = fixedHighlight ?? (snapshot ? 0 : nil) {
            content(fixed)
        } else if motionOff {
            content(manual)
        } else {
            TimelineView(.periodic(from: start, by: step)) { context in
                content(Int(max(0, context.date.timeIntervalSince(start)) / step) % words.count)
            }
        }
    }

    private func content(_ highlight: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                    WordTile(number: i + 1, word: word, check: i == 9, say: i == highlight, index: i)
                        .onTapGesture { jump(to: i) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(i + 1). \(word)" + (i == 9 ? ", " + tr(.wordsCheckLabel) : ""))
                        .accessibilityAddTraits(.isButton)
                }
            }
            HStack(spacing: 4) {
                Text(tr(.wordsSay, ["word": ""]).trimmingCharacters(in: .whitespaces)).foregroundColor(p.textSecondary)
                Text(words[min(highlight, words.count - 1)]).font(.system(size: 16, weight: .semibold))
                if highlight == 9 { Text("(" + tr(.wordsCheckLabel) + ")").foregroundColor(p.textSecondary) }
            }
            .font(.system(size: 14))
            .accessibilityElement(children: .combine)
        }
    }

    private func jump(to i: Int) {
        if motionOff { manual = i } else { start = Date().addingTimeInterval(-Double(i) * step) }
    }
}

/// One security word as a tile (Calm): its number and the word; word 10 carries "check"; the word
/// to say now is filled with the accent and lifted. Tiles appear one after another when the words
/// first show (`wordReveal` apart), not with reduced motion.
struct WordTile: View {
    let number: Int
    let word: String
    let check: Bool
    let say: Bool
    let index: Int
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var shown = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Text(String(number)).font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(say ? .white : p.textTertiary)
                Spacer(minLength: 0)
                if check {
                    Text(tr(.wordsCheckLabel).uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                        .foregroundColor(say ? .white : p.named("pathFriend"))
                }
            }
            Text(word).font(.system(size: 15.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(say ? .white : p.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(say ? p.accentFill : p.background)
            .shadow(color: say ? p.accentFill.opacity(0.35) : .clear, radius: 9, y: 6))
        .overlay(shape.strokeBorder(check && !say ? p.named("pathFriend").opacity(0.55) : (say ? .clear : p.border),
                                    lineWidth: check ? 1.5 : 1))
        .offset(y: say && !motionOff ? -2 : 0)
        .animation(motionOff ? nil : .easeOut(duration: 0.25), value: say)
        .opacity(shown || motionOff || snapshot ? 1 : 0)
        .offset(y: shown || motionOff || snapshot ? 0 : 8)
        .scaleEffect(shown || motionOff || snapshot ? 1 : 0.94)
        .onAppear {
            guard !motionOff, !snapshot, !shown else { return }
            withAnimation(Theme.shared.curve("chip", 0.3).delay(Double(index) * Theme.shared.motion.wordReveal)) { shown = true }
        }
    }
}

/// A sheet's frame: title, optional subtitle, content, and a right-aligned row of buttons.
public struct SheetFrame<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let width: CGFloat
    let content: Content
    let footer: Footer
    @Environment(\.palette) private var p

    public init(_ title: String, subtitle: String? = nil, width: CGFloat = 540,
                @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: Theme.shared.type.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 12)
            content
                .padding(.horizontal, 26)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: width, alignment: .leading)
        .background(p.surface)
    }
}

/// A small section heading (Calm: FRIENDS, GROUPS, the Settings group labels): uppercase, semibold,
/// tertiary text, a little tracking. VoiceOver reads the text as written.
public struct SectionLabel: View {
    let text: String
    @Environment(\.palette) private var p
    public init(_ text: String) { self.text = text }
    public var body: some View {
        let style = Theme.shared.type.sectionLabel
        Text(text.uppercased()).font(style.font).tracking(style.tracking).foregroundColor(p.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}
