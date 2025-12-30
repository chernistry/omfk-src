import SwiftUI

struct HistoryView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @State private var searchText = ""
    @State private var selected: Set<HistoryManager.HistoryRecord.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 400)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search history")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    guard let firstId = selected.first,
                          let record = historyManager.records.first(where: { $0.id == firstId }) else { return }
                    Clipboard.copy(record.corrected)
                } label: {
                    Label("Copy Result", systemImage: "doc.on.doc")
                }
                .disabled(selected.isEmpty)

                Button(role: .destructive) {
                    historyManager.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(historyManager.records.isEmpty)
            }
        }
        .navigationTitle("History")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.title2.weight(.semibold))
                Text("\(historyManager.records.count) recent corrections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if historyManager.records.isEmpty {
            EmptyStateView(title: "No corrections yet", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRecords.isEmpty {
            EmptyStateView(title: "No matches", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(filteredRecords, selection: $selected) {
                TableColumn("Time") { record in
                    Text(record.timestamp, style: .time)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 90, max: 120)

                TableColumn("From") { record in
                    Text(record.fromLang.flag)
                        .help(record.fromLang.displayName)
                }
                .width(min: 34, ideal: 40, max: 44)

                TableColumn("To") { record in
                    Text(record.toLang.flag)
                        .help(record.toLang.displayName)
                }
                .width(min: 34, ideal: 40, max: 44)

                TableColumn("Original") { record in
                    Text(record.original)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }

                TableColumn("Corrected") { record in
                    Text(record.corrected)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }
            }
            .contextMenu(forSelectionType: HistoryManager.HistoryRecord.ID.self) { ids in
                if !ids.isEmpty {
                    Button {
                        let joined = ids.compactMap { id in
                            historyManager.records.first(where: { $0.id == id })?.original
                        }.joined(separator: "\n")
                        Clipboard.copy(joined)
                    } label: {
                        Label("Copy Original", systemImage: "doc.on.doc")
                    }

                    Button {
                        let joined = ids.compactMap { id in
                            historyManager.records.first(where: { $0.id == id })?.corrected
                        }.joined(separator: "\n")
                        Clipboard.copy(joined)
                    } label: {
                        Label("Copy Corrected", systemImage: "doc.on.doc.fill")
                    }

                    Divider()

                    Button(role: .destructive) {
                        historyManager.clear()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var filteredRecords: [HistoryManager.HistoryRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return historyManager.records }
        return historyManager.records.filter { record in
            record.original.localizedCaseInsensitiveContains(q) ||
                record.corrected.localizedCaseInsensitiveContains(q) ||
                record.fromLang.displayName.localizedCaseInsensitiveContains(q) ||
                record.toLang.displayName.localizedCaseInsensitiveContains(q)
        }
    }
}

private extension Language {
    var displayName: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .hebrew: "Hebrew"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .russian: "🇷🇺"
        case .hebrew: "🇮🇱"
        }
    }
}

#Preview {
    HistoryView()
}
