import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Text(title)
                .font(.headline)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(24)
    }
}

#Preview {
    EmptyStateView(title: "Nothing here yet", systemImage: "tray", message: "Try enabling OMFK and typing a few words.")
        .frame(width: 600, height: 300)
}

