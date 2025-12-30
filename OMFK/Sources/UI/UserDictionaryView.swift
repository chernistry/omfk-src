import SwiftUI

struct UserDictionaryView: View {
    @State private var rules: [UserDictionaryRule] = []
    @State private var searchText = ""
    @State private var showAddRule = false
    @State private var selected: Set<UserDictionaryRule.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search rules", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Spacer()

                Button {
                    showAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }

                if !rules.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await UserDictionary.shared.clearAll()
                                await loadRules()
                            }
                        } label: {
                            Label("Clear All Rules", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .menuStyle(.borderlessButton)
                    .help("More actions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if filteredRules.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "No rules yet" : "No matches",
                    systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass",
                    message: searchText.isEmpty ? "Rules are learned automatically or added manually." : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredRules, selection: $selected) {
                    TableColumn("Token") { rule in
                        Text(rule.token)
                            .fontDesign(.monospaced)
                            .lineLimit(1)
                    }
                    TableColumn("Action") { rule in
                        RuleActionBadge(rule: rule)
                    }
                    TableColumn("Source") { rule in
                        Text(rule.source == .learned ? "Learned" : "Manual")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Updated") { rule in
                        Text(rule.updatedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UserDictionaryRule.ID.self) { ids in
                    if !ids.isEmpty {
                        Button(role: .destructive) {
                            for id in ids {
                                deleteRule(id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadRules() }
        .sheet(isPresented: $showAddRule) {
            AddRuleDialog { newRule in
                Task {
                    await UserDictionary.shared.addRule(newRule)
                    await loadRules()
                }
            }
        }
    }

    private var filteredRules: [UserDictionaryRule] {
        let sorted = rules.sorted { $0.updatedAt > $1.updatedAt }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sorted }
        return sorted.filter { $0.token.localizedCaseInsensitiveContains(q) }
    }

    private func loadRules() async {
        rules = await UserDictionary.shared.getAllRules()
    }

    private func deleteRule(_ id: UUID) {
        Task {
            await UserDictionary.shared.removeRule(id: id)
            await loadRules()
        }
    }
}

private struct RuleActionBadge: View {
    let rule: UserDictionaryRule

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(label)
                .font(.callout)
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch rule.action {
        case .none: "questionmark.circle"
        case .keepAsIs: "hand.raised"
        case .preferLanguage: "scope"
        case .preferHypothesis: "wand.and.stars"
        }
    }

    private var label: String {
        switch rule.action {
        case .none:
            "Pending"
        case .keepAsIs:
            "Keep"
        case .preferLanguage(let lang):
            "Prefer \(lang.shortName)"
        case .preferHypothesis(let h):
            "Prefer \(h)"
        }
    }

    private var color: Color {
        switch rule.action {
        case .none: .secondary
        case .keepAsIs: .green
        case .preferLanguage: .blue
        case .preferHypothesis: .purple
        }
    }
}

private extension Language {
    var shortName: String {
        switch self {
        case .english: "EN"
        case .russian: "RU"
        case .hebrew: "HE"
        }
    }
}

#Preview {
    UserDictionaryView()
        .frame(width: 820, height: 420)
}
