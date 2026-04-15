import Foundation
import MenuWattCore

struct ReleaseInfo: Sendable, Equatable {
    let tagName: String
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Sendable, Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private let endpoint = URL(string: "https://api.github.com/repos/Ketchio-dev/MenuWatt/releases/latest")!
    private let logger = MenuWattDiagnostics.preferences
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() async -> ReleaseInfo? {
        status = .checking

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                status = .failed("GitHub API returned \(code)")
                logger.error("Update check failed: HTTP \(code, privacy: .public)")
                return nil
            }

            let release = try parseRelease(from: data)
            if compareVersions(release.tagName, current: currentVersion) > 0 {
                status = .updateAvailable(release)
                return release
            } else {
                status = .upToDate(currentVersion: currentVersion)
                return nil
            }
        } catch {
            status = .failed(error.localizedDescription)
            logger.error("Update check error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func parseRelease(from data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let published_at: String?
            let body: String?
        }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        guard let url = URL(string: decoded.html_url) else {
            throw URLError(.badServerResponse)
        }
        let date: Date? = decoded.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        return ReleaseInfo(
            tagName: decoded.tag_name,
            htmlURL: url,
            publishedAt: date,
            body: decoded.body
        )
    }

    /// Compares semver-like strings (with optional "v" prefix). Returns positive if `a > b`.
    func compareVersions(_ a: String, current b: String) -> Int {
        let parsedA = parse(a)
        let parsedB = parse(b)
        for i in 0..<max(parsedA.count, parsedB.count) {
            let lhs = i < parsedA.count ? parsedA[i] : 0
            let rhs = i < parsedB.count ? parsedB[i] : 0
            if lhs != rhs { return lhs - rhs }
        }
        return 0
    }

    private func parse(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
