import Foundation
#if RAVEN_ENGINE
import CRavenClient

/// The real engine: `raven-client` (node/crates/raven-client), a Rust static library linked through
/// the `CRavenClient` module (Package.swift, `RAVEN_ENGINE=1`):
///
///     char *raven_call(const char *request_json);   /* never NULL */
///     void  raven_free(char *response);
///
/// The engine is one per process and works on the profile the CLI uses (`RAVEN_DATA_DIR`, else
/// `~/.raven`), read on the first call. `raven_call` may block (`node.start` takes a few seconds), so
/// it runs on `EngineQueue`, never on the main thread (see `call`). In an app bundle the engine starts
/// the bundle's own raven-node (`BundledNode`, `Contents/Helpers/raven-node`).
public final class RavenClientEngine: RavenEngine, @unchecked Sendable {
    public init() {
        BundledNode.useBundledNode()
    }

    public func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        let response = await EngineQueue.run(RavenEnvelope.request(op: op, args: args)) { request in
            RavenClientEngine.rawCall(request)
        }
        return try RavenEnvelope.parseResponse(response)
    }

    /// One `raven_call`: the request as NUL-terminated UTF-8 in, the response envelope out. The
    /// response is copied into a Swift string and always handed back to `raven_free`. Blocks: call
    /// it off the main thread.
    public static func rawCall(_ request: String) -> String {
        // The JSON text escapes control characters, so it holds no NUL that would cut it short.
        guard let response = request.withCString({ raven_call($0) }) else {
            // raven_call never returns NULL (raven_client.h); answer as the engine would.
            return RavenEnvelope.failure(.internalError("raven_call returned NULL"))
        }
        defer { raven_free(response) }
        return String(cString: response)
    }
}
#endif

/// Stands in for the engine in a build that does not link `raven-client` (`swift build` without
/// `RAVEN_ENGINE=1`): every call fails with a plain-English error, which the app shows with its
/// Details (snapshot `25-release-without-engine`). Like every engine it answers off the main thread.
public final class MissingEngine: RavenEngine, @unchecked Sendable {
    public init() {}

    public func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        let response = await EngineQueue.run(RavenEnvelope.request(op: op, args: args)) { request in
            MissingEngine.rawCall(request)
        }
        return try RavenEnvelope.parseResponse(response)
    }

    static func rawCall(_ request: String) -> String {
        RavenEnvelope.failure(RavenError(
            code: ErrorCode.notInitialized,
            message: tr(.errorEngineMissing),
            detail: "raven-client is not linked into this build: run scripts/build-engine.sh, then build with "
                + "RAVEN_ENGINE=1 (scripts/make-app.sh does both). Request: \(request.prefix(120))"))
    }
}

/// Picks the engine for this build:
///
/// - a demo build (`RAVEN_DEMO=1 scripts/make-app.sh`, compiled with `-DRAVEN_MOCK`): MockRaven;
/// - a debug build started with `RAVEN_DEMO=1`: MockRaven (`RAVEN_MOCK_STATE`, `RAVEN_MOCK_DEMO`,
///   `RAVEN_MOCK_NETWORK` apply);
/// - otherwise `raven-client` when it is linked (`RAVEN_ENGINE=1`), else `MissingEngine`.
///
/// A release build never runs on the mock unless it was built as the demo.
public enum EngineFactory {
    @MainActor
    public static func makeDefault(environment env: [String: String] = ProcessInfo.processInfo.environment) -> RavenEngine {
        #if RAVEN_MOCK
        return demo(env)
        #else
        #if DEBUG
        if env["RAVEN_DEMO"] == "1" { return demo(env) }
        #endif
        #if RAVEN_ENGINE
        return RavenClientEngine()
        #else
        return MissingEngine()
        #endif
        #endif
    }

    #if DEBUG || RAVEN_MOCK
    @MainActor
    static func demo(_ env: [String: String]) -> RavenEngine {
        let start: MockRaven.Start
        switch env["RAVEN_MOCK_STATE"] {
        case "ready": start = .ready
        case "locked": start = .locked   // the Locked screen, for review (privacy.lock is not available yet)
        default: start = .new
        }
        // RAVEN_MOCK_NETWORK=lab: the network answers of a developer build with lab switches set.
        return MockRaven(start: start, demo: env["RAVEN_MOCK_DEMO"] != "0",
                         network: env["RAVEN_MOCK_NETWORK"] == "lab" ? .lab : .release)
    }
    #endif
}
