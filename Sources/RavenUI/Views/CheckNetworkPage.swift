import SwiftUI

/// Check network: `raven doctor`'s summary and network lines (`network.check`), and on request the
/// read-only router question (`router: true`), which macOS may gate behind the Local Network
/// permission.
struct CheckNetworkPage: View {
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(tr(.networkCheckTitle), intro: tr(.networkCheckIntro)) {
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
                        // The next step has its own line below.
                        let summary = check.summary.filter { $0.key != "next_step" || check.nextStep.isEmpty }
                        ForEach(Array(summary.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.label).font(RFont.smallish).foregroundColor(p.textSecondary)
                                    .frame(width: 120, alignment: .leading)
                                Text(row.value).font(RFont.smallish).fixedSize(horizontal: false, vertical: true).selectable()
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if !check.nextStep.isEmpty {
                            Text(tr(.networkCheckNextStep, ["step": check.nextStep])).font(RFont.bodyBold)
                                .fixedSize(horizontal: false, vertical: true)
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
                    Text(tr(.networkCheckRouterBody)).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                    Text(tr(.networkCheckRouterMacos)).font(RFont.smallish).foregroundColor(p.textSecondary)
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

    /// The rows Raven has a sentence for, each sentence once.
    static func plainLines(_ rows: [CheckRow]) -> [String] {
        var seen = Set<String>()
        return rows.compactMap { $0.plain }.filter { !$0.isEmpty && seen.insert($0).inserted }
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
