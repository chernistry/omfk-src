import Foundation
import AppKit
import os.log

// MARK: - Models

/// Represents a GitHub release from the API
struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [Asset]
    
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
    
    /// Extracts version string from tag_name (removes "v" prefix if present)
    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
    
    /// Finds the .pkg download URL from assets
    var pkgDownloadURL: URL? {
        guard let pkgAsset = assets.first(where: { $0.name.hasSuffix(".pkg") }) else {
            return nil
        }
        return URL(string: pkgAsset.browserDownloadURL)
    }
    
    /// Fallback download URL (releases page)
    var releasesPageURL: URL? {
        URL(string: htmlURL)
    }
}

/// Result of checking for updates
enum UpdateResult: Sendable {
    case upToDate
    case updateAvailable(release: GitHubRelease)
    case error(UpdateError)
}

/// Errors that can occur during update checking
enum UpdateError: Error, Sendable, LocalizedError {
    case networkUnavailable
    case rateLimited
    case invalidResponse
    case decodingFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .rateLimited:
            return "GitHub API rate limit exceeded. Please try again later."
        case .invalidResponse:
            return "Invalid response from GitHub. Please try again later."
        case .decodingFailed(let message):
            return "Failed to parse update information: \(message)"
        case .unknown(let message):
            return "An error occurred: \(message)"
        }
    }
}

// MARK: - UpdateChecker Actor

/// Actor responsible for checking GitHub releases for updates
actor UpdateChecker {
    static let shared = UpdateChecker()
    
    private let releasesURL = URL(string: "https://api.github.com/repos/chernistry/omfk/releases/latest")!
    private let logger = Logger(subsystem: "com.chernistry.omfk", category: "UpdateChecker")
    
    /// Checks for available updates
    /// - Returns: UpdateResult indicating whether an update is available
    func checkForUpdate() async -> UpdateResult {
        logger.info("Checking for updates...")
        
        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("OMFK/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                return .error(.invalidResponse)
            }
            
            // Handle rate limiting
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                logger.warning("GitHub API rate limited")
                return .error(.rateLimited)
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.error("Unexpected status code: \(httpResponse.statusCode)")
                return .error(.invalidResponse)
            }
            
            let decoder = JSONDecoder()
            let release: GitHubRelease
            do {
                release = try decoder.decode(GitHubRelease.self, from: data)
            } catch {
                logger.error("Failed to decode release: \(error.localizedDescription)")
                return .error(.decodingFailed(error.localizedDescription))
            }
            
            let latestVersion = release.version
            let current = currentVersion
            
            logger.info("Current version: \(current), Latest version: \(latestVersion)")
            
            // Compare versions
            let comparison = compareVersions(current, latestVersion)
            
            if comparison == .orderedAscending {
                // Current version is older than latest
                logger.info("Update available: \(latestVersion)")
                return .updateAvailable(release: release)
            } else {
                logger.info("App is up to date")
                return .upToDate
            }
            
        } catch let error as URLError {
            logger.error("Network error: \(error.localizedDescription)")
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                return .error(.networkUnavailable)
            }
            return .error(.unknown(error.localizedDescription))
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            return .error(.unknown(error.localizedDescription))
        }
    }
    
    /// Current app version from bundle
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
    
    /// Compares two version strings (e.g., "1.2" vs "1.10")
    /// - Returns: ComparisonResult indicating the relationship between versions
    func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0
            
            if v1Part < v2Part {
                return .orderedAscending
            } else if v1Part > v2Part {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}

// MARK: - Update State (Observable)

/// Observable state for tracking update status across the app
@MainActor
final class UpdateState: ObservableObject {
    static let shared = UpdateState()
    
    @Published var isChecking: Bool = false
    @Published var lastResult: UpdateResult?
    @Published var lastCheckDate: Date?
    @Published var showingUpdateAlert: Bool = false
    
    /// Whether an update is available
    var isUpdateAvailable: Bool {
        if case .updateAvailable = lastResult {
            return true
        }
        return false
    }
    
    /// The available release, if any
    var availableRelease: GitHubRelease? {
        if case .updateAvailable(let release) = lastResult {
            return release
        }
        return nil
    }
    
    /// Latest version string, if update available
    var latestVersion: String? {
        availableRelease?.version
    }
    
    /// Download URL for the update
    var downloadURL: URL? {
        availableRelease?.pkgDownloadURL ?? availableRelease?.releasesPageURL
    }
    
    /// Check for updates and update state
    func checkForUpdate() async {
        guard !isChecking else { return }
        
        isChecking = true
        defer { isChecking = false }
        
        let result = await UpdateChecker.shared.checkForUpdate()
        lastResult = result
        lastCheckDate = Date()
        
        // Persist last check date
        SettingsManager.shared.lastUpdateCheckDate = Date()
        
        // Show alert if update available
        if case .updateAvailable = result {
            showingUpdateAlert = true
        }
    }
    
    /// Opens the download URL in browser
    func openDownloadURL() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }
}
