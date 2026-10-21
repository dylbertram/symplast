import XCTest
@testable import Symplast

final class SSHAgentTests: XCTestCase {
    private func candidate(_ socket: String, keys: Bool) -> MutagenClient.AgentCandidate {
        MutagenClient.AgentCandidate(socket: socket, hasKeys: keys)
    }

    func testPrefersTheAgentThatHoldsKeys() {
        // The situation on machines where the real agent (Bitwarden,
        // 1Password, …) is configured in .zshrc: launchd exposes an empty
        // agent socket first, the shell exposes the one with keys.
        let chosen = MutagenClient.chooseAgentSocket([
            candidate("/var/run/com.apple.launchd/Listeners", keys: false),
            candidate("/Users/me/.bitwarden-ssh-agent.sock", keys: true),
            candidate("/Users/me/.other.sock", keys: true)
        ])
        XCTAssertEqual(chosen, "/Users/me/.bitwarden-ssh-agent.sock")
    }

    func testFallsBackToAnEmptyAgentWhenNoneHasKeys() {
        XCTAssertEqual(MutagenClient.chooseAgentSocket([
            candidate("/var/run/com.apple.launchd/Listeners", keys: false),
            candidate("/Users/me/.empty.sock", keys: false)
        ]), "/var/run/com.apple.launchd/Listeners",
        "an empty agent is still better than none")
    }

    func testNoAgentFound() {
        XCTAssertNil(MutagenClient.chooseAgentSocket([]))
    }
}
