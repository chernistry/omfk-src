import SwiftUI

struct UserDictionaryView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var rules: [UserDictionaryRule] = []
    @State private var searchText = ""
    @State private var showAddRule = false
    @State private var selectedRuleId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Toggle
            VStack(spacing: 12) {
                GlassCard {
                    SettingRow(
                        icon: "brain.head.profile",
                        iconColor: .indigo,
                        title: "Learn from usage",
                        subtitle: "Automatically learn from undos and corrections",
                        toggle: $settings.isLearningEnabled
                    )
                }
            }
            .padding(16)
            
            Divider()
            
            // Search & List
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search dictionary...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1))
                
                List(selection: $selectedRuleId) {
                    ForEach(filteredRules) { rule in
                        RuleRow(rule: rule)
                            .tag(rule.id)
                            .contextMenu {
                                Button("Delete") {
                                    deleteRule(rule.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // Footer Actions
            HStack {
                Text("\(rules.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Clear Learning") {
                     Task {
                         await UserDictionary.shared.clearAll()
                         await loadRules()
                     }
                }
                .font(.system(size: 11))
                
                Button(action: { showAddRule = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(12)
            .background(.regularMaterial)
        }
        .task {
            await loadRules()
        }
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
        if searchText.isEmpty {
            return rules.sorted(by: { $0.updatedAt > $1.updatedAt })
        }
        return rules.filter { $0.token.localizedCaseInsensitiveContains(searchText) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }
    
    private func loadRules() async {
        self.rules = await UserDictionary.shared.getAllRules()
    }
    
    private func deleteRule(_ id: UUID) {
        Task {
            await UserDictionary.shared.removeRule(id: id)
            await loadRules()
        }
    }
}

struct RuleRow: View {
    let rule: UserDictionaryRule
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.token)
                    .font(.system(size: 13, weight: .medium))
                Text(actionDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if rule.source == .learned {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(.indigo)
                    .help("Learned automatically")
            }
        }
        .padding(.vertical, 2)
    }
    
    var actionDescription: String {
        switch rule.action {
        case .none: return "Pending"
        case .keepAsIs: return "Keep as-is"
        case .preferLanguage(let l): return "Force \(l.rawValue.capitalized)"
        case .preferHypothesis(let h): return "Hypothesis: \(h)"
        }
    }
}
