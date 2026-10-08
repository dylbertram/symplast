import Foundation

struct AvailableUpdate: Equatable {
    let version: String
    let releaseURL: URL
}

enum VersionCheckStatus: Equatable {
    case notChecked
    case checking
    case upToDate
    case updateAvailable(AvailableUpdate)
    case failed(String)
}

enum VersionChecker {
    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
        }
    }

    static func check(currentVersion: String, session: URLSession = .shared) async throws -> AvailableUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/dylbertram/symplast/releases/latest")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Symplast macOS app", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw VersionCheckError.unavailable
        }
        if response.statusCode == 404 { throw VersionCheckError.noPublicRelease }
        guard (200..<300).contains(response.statusCode) else { throw VersionCheckError.unavailable }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let releasedVersion = normalizedVersion(release.tagName),
              let installedVersion = normalizedVersion(currentVersion) else {
            throw VersionCheckError.invalidRelease
        }
        guard compare(releasedVersion, installedVersion) == .orderedDescending else { return nil }
        let tag = "v" + releasedVersion
        return AvailableUpdate(version: releasedVersion,
                               releaseURL: URL(string: "https://github.com/dylbertram/symplast/releases/tag/\(tag)")!)
    }

    static func normalizedVersion(_ value: String) -> String? {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = version.split(separator: ".")
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { (48...57).contains($0.value) } })
        else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return numbers.map(String.init).joined(separator: ".")
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<3 {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

enum VersionCheckError: LocalizedError {
    case unavailable
    case invalidRelease
    case noPublicRelease

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Could not reach GitHub to check for updates. Try again later."
        case .invalidRelease:
            return "GitHub returned release information that Symplast could not read."
        case .noPublicRelease:
            return "There is no stable public release to check yet."
        }
    }
}
