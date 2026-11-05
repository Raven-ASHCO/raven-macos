import Foundation
import Testing
@testable import RavenUI

/// The Mac app's UI pass on the Network screens, Settings, the lock (the Night curtain) and the menu
/// bar: privacy, plain words, and the states the stills showed broken.
@MainActor
@Suite struct NetworkSettingsLockTests {
    func readyModel(network: MockRaven.NetworkMode = .release) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    /// An IP address, a port after a colon, or a process number.
    static func namesAnAddress(_ text: String) -> Bool {
        text.range(of: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|/ip[46]/|:\d{2,5}\b|\bport \d|process \d"#,
                   options: .regularExpression) != nil
    }

    // MARK: Privacy

    /// Owner rule: addresses and ports only under Details. The This computer card, the Network sheet
    /// and Settings > General named the port, the listening and network addresses and the process; the
    /// peer to peer card its port, its relays and its addresses. Technical details keep every one.
    @Test func portsAndAddressesOnlyUnderTechnicalDetails() async throws {
        let (model, _) = await readyModel(network: .lab)
        await model.network.refresh()
        let status = try #require(model.network.status)
        let node = try #require(model.node)
        let port = try #require(node.port)

        for text in [Display.listening(node).text, Display.process(node), tr(.macSettingsReceiveBody)] {
            #expect(!Self.namesAnAddress(text), "\(text)")
        }
        var local = node
        local.listening = "127.0.0.1:" + port
        #expect(Display.listening(local).text == tr(.macNetworkLocalOnly))
        #expect(!Self.namesAnAddress(Display.listening(local).text))

        let details = Display.thisComputerDetails(status: status, node: node)
        #expect(details.contains(tr(.macNetworkDetailPort, ["port": port])))
        #expect(details.contains { $0.contains(node.listening ?? "?") })
        #expect(details.contains(tr(.macNetworkDetailProcess, ["pid": String(node.pid ?? 0)])))
        if let addr = node.address { #expect(details.contains(tr(.macNetworkDetailAddress, ["addr": addr]))) }

        // While nothing runs, the profile's port.
        var stopped = node
        stopped.running = false
        var idle = status
        idle.node = "not_running"
        #expect(Display.thisComputerDetails(status: idle, node: stopped).first == tr(.macNetworkDetailPort, ["port": String(status.port ?? 0)]))

        // The peer to peer card: where it listens, its relays and every address, under Technical details.
        let p2p = try #require(status.way("p2p"))
        let technical = WayRow.technical(p2p, status)
        let listen = try #require(status.p2pListen)
        #expect(technical.contains(tr(.macNetworkDetailP2pListen, ["addr": listen])))
        let relays = try #require(status.relays)
        #expect(!relays.isEmpty)
        for relay in relays { #expect(technical.contains(tr(.macNetworkDetailRelay, ["relay": relay.relay]))) }
        for a in status.p2pAddresses ?? [] { #expect(technical.contains(tr(.macNetworkDetailP2pAddress, ["addr": a]))) }
        #expect(!Self.namesAnAddress(tr(.macNetworkP2pAddressCount, ["n": "2"])))
    }
}
