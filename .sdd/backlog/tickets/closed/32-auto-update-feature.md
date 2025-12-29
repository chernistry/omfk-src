# Ticket 32: Auto-Update Feature

## Problem

Currently, users have no way to know when a new version of OMFK is available. They must manually check the GitHub releases page or remember to update. This leads to:

1. Users running outdated versions with known bugs
2. Friction in delivering important fixes
3. No way to notify users of critical security/stability updates

## User Story

As an OMFK user, I want to be notified when a new version is available and easily update, so that I always have the latest features and bug fixes without manually checking GitHub.

## Current Distribution Model

OMFK uses a **two-repo model**:
- `chernistry/omfk-src` (private) — source code
- `chernistry/omfk` (public) — releases only

Releases are triggered via `./omfk.sh release github` which:
1. Runs GitHub Actions workflow on `omfk-src`
2. Builds and notarizes the `.pkg` installer
3. Creates a GitHub Release on `chernistry/omfk` with the `.pkg` attached

The release URL pattern is:
```
https://github.com/chernistry/omfk/releases/latest
https://github.com/chernistry/omfk/releases/download/vX.Y/OMFK-X.Y.pkg
```

## Proposed Features

### 1. Manual "Check for Updates" (Settings UI)

**UI Location:** Settings → About (or dedicated "Updates" tab)

**Button:** "Check for Updates"

**Behavior:**
- Fetch latest release from GitHub API: `https://api.github.com/repos/chernistry/omfk/releases/latest`
- Compare `tag_name` (e.g., `v1.5`) with current `CFBundleShortVersionString`
- If newer version available:
  - Show alert with release notes and "Download" button
  - "Download" opens browser to `.pkg` download URL
- If up to date:
  - Show "You're up to date! (version X.Y)"

### 2. Automatic Update Monitoring (Optional)

**UI Location:** Settings → General → "Check for updates automatically"

**Behavior:**
- When enabled, check for updates:
  - On app launch (if last check was >24 hours ago)
  - Periodically (every 24 hours while running)
- Store `lastUpdateCheckDate` in UserDefaults
- If update found:
  - Show persistent notification in menu bar (red badge on icon?)
  - Optional: Show macOS notification (non-intrusive)

**Menu bar indication options:**
- **Option A:** Red dot badge on menu bar icon
- **Option B:** Separate menu item "Update Available (v1.6)" at top of menu
- **Option C:** macOS User Notification (with "Download" action)

**Recommendation:** Option B + Option C — menu item is always visible, notification is dismissible.

### 3. Update Installation

**Consideration:** Can we make updates silent/automatic?

**Analysis:**

| Approach | Pros | Cons |
|----------|------|------|
| **A. Open browser to download** | Simple, no security concerns | Manual installation required |
| **B. Download .pkg, prompt to open** | Streamlined UX | Still requires user interaction for installer |
| **C. Silent .pkg install** | Best UX | Requires root, complex, potential security issues |
| **D. Sparkle framework** | Industry standard, handles everything | External dependency, may conflict with notarization |
| **E. App bundle replacement** | Could work if we didn't use .pkg | We use .pkg for postinstall script (permissions setup) |

**Recommendation:** Start with **Option A** (browser download) for MVP. Consider **Option B** for v2.

**Why not silent install?**
- Our `.pkg` includes a postinstall script that sets up permissions
- Silent `.pkg` installation requires `sudo installer -pkg` which needs root
- Launching installer as root from a sandboxed app is complex and risky
- Users expect to approve system-level installations

### 4. Implementation Details

#### GitHub API Integration

```swift
struct GitHubRelease: Decodable {
    let tag_name: String      // "v1.5"
    let html_url: String      // Release page URL
    let body: String?         // Release notes (markdown)
    let assets: [Asset]
    
    struct Asset: Decodable {
        let name: String           // "OMFK-1.5.pkg"
        let browser_download_url: String
    }
}

actor UpdateChecker {
    private let releasesURL = URL(string: "https://api.github.com/repos/chernistry/omfk/releases/latest")!
    
    func checkForUpdate() async throws -> UpdateResult {
        let (data, _) = try await URLSession.shared.data(from: releasesURL)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        
        if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            return .updateAvailable(release)
        }
        return .upToDate
    }
}

enum UpdateResult {
    case upToDate
    case updateAvailable(GitHubRelease)
    case error(Error)
}
```

#### Settings Storage

```swift
// Add to SettingsManager
@Published var checkForUpdatesAutomatically: Bool {
    didSet { UserDefaults.standard.set(checkForUpdatesAutomatically, forKey: "checkForUpdatesAutomatically") }
}

var lastUpdateCheckDate: Date? {
    get { UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date }
    set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheckDate") }
}
```

#### Menu Bar Integration

When update is available:
```swift
// In MenuBarContentView
if updateState.isUpdateAvailable {
    Button {
        // Open download URL
        NSWorkspace.shared.open(updateState.downloadURL)
    } label: {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.green)
            Text("Update Available (v\(updateState.latestVersion))")
        }
    }
    Divider()
}
```

#### macOS Notification

```swift
import UserNotifications

func showUpdateNotification(version: String, downloadURL: URL) {
    let content = UNMutableNotificationContent()
    content.title = "OMFK Update Available"
    content.body = "Version \(version) is ready to download"
    content.sound = .default
    
    let request = UNNotificationRequest(identifier: "updateAvailable", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

## Files to Create/Modify

### New Files
- `OMFK/Sources/Core/UpdateChecker.swift` — GitHub API integration
- `OMFK/Sources/UI/UpdateView.swift` — Update UI (alert/sheet)

### Modified Files
- `OMFK/Sources/Settings/SettingsManager.swift` — Add update settings
- `OMFK/Sources/UI/SettingsView.swift` — Add "Updates" section
- `OMFK/Sources/UI/MenuBarContentView.swift` — Add update indicator
- `OMFK/Sources/App/OMFKApp.swift` — Trigger background update check

## Privacy Consideration

> [!IMPORTANT]
> This feature introduces the **first network call** in OMFK. Previously, the app was 100% offline.

**Mitigations:**
1. Only contacts GitHub API (trusted, no tracking)
2. Sends no user data (only reads public release info)
3. User can disable "Check for updates automatically"
4. Manual check is always available even if auto-check is off
5. Add note in Settings: "Checks github.com/chernistry/omfk for new releases. No personal data is sent."

## Edge Cases

1. **No internet connection** — Fail silently for auto-check; show error for manual check
2. **GitHub API rate limit** — Unlikely for single user, but handle 403 gracefully
3. **Downgrade scenario** — Don't prompt if user has newer version than latest release
4. **First launch after update** — Show "What's new" dialog (optional, v2)
5. **User dismisses update multiple times** — Don't nag; only show once per version in notification

## Tests

1. `test_version_comparison` — Correctly compares X.Y version strings
2. `test_update_available_detection` — Detects when newer version exists
3. `test_up_to_date` — Returns correct result when current == latest
4. `test_github_api_parsing` — Parses GitHub release JSON correctly
5. `test_settings_persistence` — Saves/loads update preferences

## Definition of Done

- [ ] "Check for Updates" button in Settings works
- [ ] Shows update available alert with release notes and download link
- [ ] "Download" button opens browser to `.pkg` URL
- [ ] "Check for updates automatically" toggle in Settings
- [ ] Auto-check runs on launch (if enabled and >24h since last check)
- [ ] Menu bar shows "Update Available" when update found
- [ ] macOS notification shown when update found (if enabled)
- [ ] Privacy note visible in Settings
- [ ] Tests pass for version comparison and API parsing
- [ ] No network calls if auto-check is disabled

## Out of Scope (Future)

- Silent/automatic installation
- In-app download with progress
- Delta updates (patching instead of full .pkg)
- Sparkle framework integration
- "What's new" dialog after update

## Dependencies

- None (uses only Foundation URLSession)

## Priority

Medium-High — Important for long-term user experience and delivering fixes

## Estimated Effort

2-3 days
