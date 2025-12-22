import SwiftUI

struct HistoryView: View {
    @StateObject private var historyManager = HistoryManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("\(historyManager.records.count) corrections")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !historyManager.records.isEmpty {
                    Button("Clear") { historyManager.clear() }
                        .font(.system(size: 12, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            
            // Content
            if historyManager.records.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 64, height: 64)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                    Text("No corrections yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(historyManager.records) { record in
                            HistoryCard(record: record)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 340, height: 380)
        .background(.ultraThinMaterial)
    }
}

struct HistoryCard: View {
    let record: HistoryManager.HistoryRecord
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Flags
            HStack(spacing: 4) {
                Text(record.fromLang.flag)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(record.toLang.flag)
            }
            .font(.system(size: 14))
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.original)
                        .strikethrough(color: .secondary.opacity(0.5))
                        .foregroundStyle(.secondary)
                    Text("→")
                        .foregroundStyle(.tertiary)
                    Text(record.corrected)
                        .fontWeight(.medium)
                }
                .font(.system(size: 12))
                
                Text(record.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(.ultraThinMaterial))
        }
        .onHover { isHovered = $0 }
    }
}

extension Language {
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .russian: return "🇷🇺"
        case .hebrew: return "🇮🇱"
        }
    }
}

#Preview { HistoryView() }
