import SwiftUI

/// Check network: `raven doctor`'s summary and network lines (`network.check`), and on request the
/// read-only router question (`router: true`), which macOS may gate behind the Local Network
/// permission.
struct CheckNetworkPage: View {
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(tr(.networkCheckTitle), intro: tr(.macNetworkCheckIntro)) {
            if net.checking { Spinner(size: 12) }
            Button(net.checking ? tr(.networkCheckRunning) : tr(.networkCheckAgain)) { Task { await net.runCheck() } }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .disabled(net.checking || net.askingRouter)
                .keyboardShortcut("r", modifiers: .command)
        } content: {
            if let error = net.checkError { ErrorNote(error) }
            if let check = net.check {
                PageSection(tr(.netThisComputer)) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(CheckNetworkPage.summaryRows(check).enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Display.checkLabel(row)).font(RFont.smallish).foregroundColor(p.textSecondary)
                                    .frame(width: 140, alignment: .leading)
                                Text(Display.checkValue(row)).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                                    .selectable()
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if !check.nextStep.isEmpty {
                            // "All set" is no step to take: said as done, with a tick.
                            let next = Display.checkNextStep(check.nextStep)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if next.done {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(p.success).accessibilityHidden(true)
                                }
                                Text(next.text).font(RFont.bodyBold).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
                // Plain sentences only; the doctor's raw lines and the CLI's words (commands
                // included) stay under Technical details (E1).
                PageSection(tr(.networkCheckLines)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(CheckNetworkPage.plainLines(check.rows).enumerated()), id: \.offset) { _, line in
                            Text(line).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                        }
                        TechnicalDetails(lines: CheckNetworkPage.technicalLines(check))
                    }
                    .padding(.vertical, 8)
                }
            } else if net.checkError == nil {
                Spinner()
            }
            PageSection(tr(.networkCheckRouterTitle)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr(.macNetworkCheckRouterBody)).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                    Text(tr(.macNetworkCheckRouterMacos)).font(RFont.smallish).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(net.askingRouter ? tr(.networkCheckRouterAsking) : tr(.networkCheckRouter)) {
                            Task { await net.runCheck(router: true) }
                        }
                        .buttonStyle(RButtonStyle(.primary, compact: true))
                        .disabled(net.askingRouter || net.checking)
                        if net.askingRouter { Spinner(size: 12) }
                    }
                    if let router = net.check?.router {
                        ForEach(Array(CheckNetworkPage.plainLines(router).enumerated()), id: \.offset) { _, line in
                            Text(line).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                        }
                        TechnicalDetails(lines: router.map(CheckNetworkPage.raw))
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .task { if net.check == nil { await net.runCheck() } }
    }

    /// The summary rows the page lists: not the next step (it has its own line below), and no row
    /// left with nothing to say once its command and addresses are out (a label beside nothing).
    static func summaryRows(_ check: NetworkCheck) -> [CheckSummaryRow] {
        check.summary.filter { ($0.key != "next_step" || check.nextStep.isEmpty) && !Display.checkValue($0).isEmpty }
    }

    /// The rows Raven has a sentence for, each sentence once.
    static func plainLines(_ rows: [CheckRow]) -> [String] {
        var seen = Set<String>()
        return rows.compactMap { $0.plain.map(Display.plainWords) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// A doctor line as it printed it ("key: value").
    static func raw(_ row: CheckRow) -> String {
        row.key.isEmpty ? row.value : row.key + ": " + row.value
    }

    /// Everything under Technical details: the doctor's lines, then the CLI's summary and next step.
    static func technicalLines(_ check: NetworkCheck) -> [String] {
        check.rows.map(raw) + (check.technical ?? [])
    }
}
