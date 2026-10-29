import Foundation
import Network

/// Whether this Mac reaches its network over Wi-Fi, from the system's current path. A Mac on a
/// cable (with Wi-Fi joined too, or not) is "on your network", never "on your Wi-Fi" (E1).
public final class NetworkKind: @unchecked Sendable {
    public static let shared = NetworkKind()

    private let lock = NSLock()
    private var wifi = false
    private var monitor: NWPathMonitor?

    /// The path's preferred interface is Wi-Fi (false until the first answer, and on a cable).
    public var isWiFi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wifi
    }

    /// Starts watching the path (once; the app calls it at launch).
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in self?.update(NetworkKind.isWiFi(path)) }
        m.start(queue: DispatchQueue(label: "raven.network-kind"))
        monitor = m
    }

    private func update(_ value: Bool) {
        lock.lock()
        wifi = value
        lock.unlock()
    }

    /// Wi-Fi only when the path uses it and no cable.
    static func isWiFi(_ path: NWPath) -> Bool {
        path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet)
    }
}
