import SwiftUI

// MARK: - Update Available View

/// View displayed when an update is available
struct UpdateAvailableView: View {
    let release: GitHubRelease
    let onDownload: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.linearGradient(
                            colors: [.green.opacity(0.8), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white)
                }
                
                Text("Update Available")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                
                Text("Version \(release.version)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Release notes
            if let body = release.body, !body.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's New")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        Text(body)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .padding(.horizontal, 4)
            }
            
            Spacer(minLength: 0)
            
            // Actions
            VStack(spacing: 12) {
                Button(action: onDownload) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download Update")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
                Button(action: onDismiss) {
                    Text("Later")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 320, height: 400)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Update Check Button (for Settings)

/// Button to manually check for updates
struct UpdateCheckButton: View {
    @ObservedObject var updateState: UpdateState
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: {
                    errorMessage = nil
                    Task {
                        await updateState.checkForUpdate()
                        if case .error(let error) = updateState.lastResult {
                            errorMessage = error.localizedDescription
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if updateState.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check for Updates")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(updateState.isChecking)
                
                Spacer()
                
                // Status indicator
                statusView
            }
            
            // Error message
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Last check date
            if let lastCheck = updateState.lastCheckDate ?? SettingsManager.shared.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch updateState.lastResult {
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .updateAvailable(let release):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("v\(release.version) available")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
        case .error:
            EmptyView()
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Update Available Menu Button

/// Menu bar button shown when update is available
struct UpdateAvailableButton: View {
    let version: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                Text("Update Available (v\(version))")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Update Available View") {
    UpdateAvailableView(
        release: GitHubRelease(
            tagName: "v1.5",
            htmlURL: "https://github.com/chernistry/omfk/releases/tag/v1.5",
            body: """
            ## What's New
            
            - Added auto-update feature
            - Fixed Hebrew layout issues
            - Improved performance
            
            ## Bug Fixes
            
            - Fixed crash on app launch
            - Memory usage improvements
            """,
            assets: [
                GitHubRelease.Asset(
                    name: "OMFK-1.5.pkg",
                    browserDownloadURL: "https://github.com/chernistry/omfk/releases/download/v1.5/OMFK-1.5.pkg"
                )
            ]
        ),
        onDownload: {},
        onDismiss: {}
    )
}

#Preview("Update Check Button") {
    UpdateCheckButton(updateState: UpdateState.shared)
        .padding()
        .frame(width: 350)
}
