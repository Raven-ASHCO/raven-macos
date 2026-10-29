import Foundation
import RavenUI

/// Renders the main screens to PNG (light and dark) with ImageRenderer. Opens no window and
/// starts no raven-node: everything runs on MockRaven with a stopped clock.
///
///     swift run RavenSnapshots [output-directory]     (default: .build/snapshots)
@main
struct RavenSnapshotsMain {
    @MainActor
    static func main() async {
        #if DEBUG || RAVEN_MOCK
        let args = CommandLine.arguments.dropFirst()
        let directory = URL(fileURLWithPath: args.first ?? ".build/snapshots", isDirectory: true)
        do {
            let files = try await SnapshotCatalog.renderAll(to: directory)
            for file in files { print(file.path) }
            print("\(files.count) snapshots written to \(directory.path)")
        } catch {
            FileHandle.standardError.write(Data("RavenSnapshots failed: \(error)\n".utf8))
            exit(1)
        }
        #else
        FileHandle.standardError.write(Data("RavenSnapshots needs MockRaven: run it from a debug build (swift run RavenSnapshots).\n".utf8))
        exit(2)
        #endif
    }
}
