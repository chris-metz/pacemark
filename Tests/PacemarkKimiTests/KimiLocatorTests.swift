import Foundation
@testable import PacemarkKimi
import Testing

/// Reads answers of the login shell to `command -v node; command -v kimi`.
/// The live check runs the real shell.
@Suite struct KimiLocatorTests {
    /// Shell startup files may print anything before the answers.
    @Test func theLoginShellReportsKimiAndTheNodeItRunsWith() throws {
        let cli = try ScriptedKimi()
        let (kimi, node) = try cli.pnpmInstall()
        #expect(KimiLocator.installation(in: "Welcome back\n/bin/sh\n\(node.path)\n\(kimi.path)\n")
            == KimiInstallation(binary: kimi, node: node))
    }

    @Test func withoutNodeKimiIsStillFound() throws {
        let cli = try ScriptedKimi()
        let (kimi, _) = try cli.pnpmInstall()
        #expect(KimiLocator.installation(in: "/bin/sh\n\(kimi.path)\n") == KimiInstallation(binary: kimi, node: nil))
    }

    /// The provider then shows "Kimi Code not found".
    @Test func withoutKimiNothingIsFound() throws {
        let cli = try ScriptedKimi()
        let (_, node) = try cli.pnpmInstall()
        #expect(KimiLocator.installation(in: "\(node.path)\n/bin/sh\n") == nil)
    }
}
