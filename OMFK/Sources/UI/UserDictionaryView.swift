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
            GlassCard {
                SettingRow(
                    icon: "brain.head.profile",
                    iconColor: .indigo,
                    title: "Learn from usage",
                    subtitle: "Auto-learn from undos and corrections",
                    toggle: $settings.isLearningEnabled
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 16)
            
            // Rules list
            if filteredRules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "book.closed" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No rules yet" : "No matches")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Text("Rules are learned automatically\nor added manually")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredRules) { rule in
                            RuleRow(rule: rule, isSelected: selectedRuleId == rule.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRuleId = rule.id }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteRule(rule.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
            
            // Footer
            HStack(spacing: 12) {
                Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if !rules.isEmpty {
                    Button("Clear All") {
                        Task {
                            await UserDictionary.shared.clearAll()
                            await loadRules()
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                
                Button(action: { showAddRule = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
        let sorted = rules.sorted { $0.updatedAt > $1.updatedAt }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.token.localizedCaseInsensitiveContains(searchText) }
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
    var isSelected: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Token → Converted
            HStack(spacing: 4) {
                Text(rule.token)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if let converted = rule.convertedText {
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(converted)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.purple)
                }
            }
            .lineLimit(1)
            
            Spacer()
            
            // Action with emoji
            HStack(spacing: 4) {
                Text(actionEmoji)
                Text(actionLabel)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(actionColor.opacity(0.15), in: Capsule())
            .foregroundStyle(actionColor)
            
            // Source indicator
            if rule.source == .learned {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
    
    private var actionEmoji: String {
        switch rule.action {
        case .none: return "⏳"
        case .keepAsIs: return "✋"
        case .preferLanguage(let l):
            switch l {
            case .english: return "🇺🇸"
            case .russian: return "🇷🇺"
            case .hebrew: return "🇮🇱"
            }
        case .preferHypothesis(let h):
            // Parse hypothesis to get target language
            if h.contains("en") { return "🇺🇸" }
            if h.contains("ru") { return "🇷🇺" }
            if h.contains("he") { return "🇮🇱" }
            return "🎯"
        }
    }
    
    private var actionLabel: String {
        switch rule.action {
        case .none: return "pending"
        case .keepAsIs: return "keep"
        case .preferLanguage(let l): return "→ \(l.rawValue.prefix(2).uppercased())"
        case .preferHypothesis(let h):
            // Show simplified hypothesis
            let parts = h.split(separator: "_")
            if parts.count >= 2 {
                return "→ \(parts[0].prefix(2).uppercased())"
            }
            return "→ ?"
        }
    }
    
    private var actionColor: Color {
        switch rule.action {
        case .none: return .gray
        case .keepAsIs: return .green
        case .preferLanguage: return .blue
        case .preferHypothesis: return .purple
        }
    }
}
