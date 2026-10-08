import Foundation

/// Condenses a raw Mutagen/OpenSSH error into one short, actionable line. The
/// full text is still available to the UI (tooltip, selection) so nothing is
/// lost, but the panel shows the useful part instead of a wall of nested
/// "unable to…" clauses.
enum ErrorSummary {
    static func isAuthenticationFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["permission denied (", "authentication failed", "no supported authentication methods",
                "sign_and_send_pubkey: signing failed"].contains { lower.contains($0) }
            || isAuthenticationPrompt(message)
    }

    /// Prompts are not newline-terminated, and may arrive in several pipe reads.
    static func isAuthenticationPrompt(_ message: String) -> Bool {
        message.range(of: #"(?im)(enter passphrase for key[^\r\n]*:|[^\r\n]*password\s*:|password for[^\r\n]*:)"#,
                      options: .regularExpression) != nil
    }

    /// Whether an error indicates an SSH/connection problem (as opposed to, say,
    /// a syntax error), so the UI can mark the affected sessions disconnected.
    static func isConnectionFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return isAuthenticationFailure(message) || [
            "permission denied", "publickey", "keyboard-interactive",
            "host key verification", "unable to connect", "unable to dial",
            "handshake", "connection refused", "no route to host",
            "timed out", "did not respond"
        ].contains { lower.contains($0) }
    }

    static func short(_ message: String) -> String {
        let lower = message.lowercased()
        let host = firstHost(in: message)

        if isAuthenticationPrompt(message) {
            return "SSH needs a password or unlocked key. Load a key in your SSH agent and retry."
        }
        if isAuthenticationFailure(message) || lower.contains("permission denied")
            || lower.contains("publickey")
            || lower.contains("keyboard-interactive") {
            return "SSH authentication failed\(forHost(host))."
        }
        if lower.contains("host key verification")
            || lower.contains("remote host identification has changed") {
            return "SSH host key isn't trusted\(forHost(host)). Connect once from Terminal to record it."
        }
        if lower.contains("timed out") || lower.contains("did not respond within") {
            return "Timed out reaching \(host ?? "the server"). SSH may be waiting for a passphrase the app can't prompt for."
        }
        if lower.contains("connection refused")
            || lower.contains("no route to host")
            || lower.contains("connection timed out")
            || lower.contains("operation timed out") {
            return "Couldn't reach \(host ?? "the server"). Check the host, network, and SSH."
        }
        if lower.contains("could not find the `mutagen` executable") {
            return "Mutagen isn't installed or its path is wrong. Set it in Settings."
        }
        if lower.contains("daemon") {
            return "Mutagen daemon isn't running. Start it from the panel or Settings."
        }

        // Fall back to the first non-empty line, trimmed to a sane width.
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? message
        return firstLine.count > 160
            ? String(firstLine.prefix(157)).trimmingCharacters(in: .whitespaces) + "…"
            : firstLine
    }

    private static func forHost(_ host: String?) -> String {
        host.map { " for \($0)" } ?? ""
    }

    /// First `user@host` mentioned in the message, if any.
    private static func firstHost(in message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9._-]+@[A-Za-z0-9.-]+") else {
            return nil
        }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let matchRange = Range(match.range, in: message) else { return nil }
        return String(message[matchRange])
    }
}
