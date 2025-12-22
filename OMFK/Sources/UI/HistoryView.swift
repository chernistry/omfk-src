import SwiftUI

struct HistoryView: View {
    @State private var history: [CorrectionEngine.CorrectionRecord] = []
    @State private var hoveredId: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            if history.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(width: 380, height: 380)
        .background(.ultraThinMaterial)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("History").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(history.count) corrections").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !history.isEmpty {
                Button(action: { history.removeAll() }) {
                    Text("Clear").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.1)).frame(width: 64, height: 64)
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(.tertiary)
            }
            VStack(spacing: 4) {
                Text("No corrections yet").font(.system(size: 14, weight: .medium))
                Text("Start typing to see corrections here").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(history) { record in
                    HistoryRow(record: record, isHovered: hoveredId == record.id)
                        .onHover { hoveredId = $0 ? record.id : nil }
                }
            }
            .padding(12)
        }
    }
}

struct HistoryRow: View {
    let record: CorrectionEngine.CorrectionRecord
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            languageBadge
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(record.original).font(.system(size: 12)).foregroundStyle(.secondary).strikethrough(color: .secondary.opacity(0.5))
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(record.corrected).font(.system(size: 12, weight: .medium))
                }
                Text(record.timestamp, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02)))
    }
    
    private var languageBadge: some View {
        HStack(spacing: 2) {
            Text(record.fromLang.flag).font(.system(size: 12))
            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            Text(record.toLang.flag).font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
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
