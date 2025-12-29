import SwiftUI

struct AddRuleDialog: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (UserDictionaryRule) -> Void
    
    @State private var token: String = ""
    @State private var matchMode: MatchMode = .exact
    @State private var actionType: ActionType = .keepAsIs
    @State private var selectedLanguage: Language = .english
    
    enum ActionType: String, CaseIterable, Identifiable {
        case keepAsIs = "Keep As-Is"
        case preferLanguage = "Prefer Language"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Dictionary Rule").font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word or Phrase").font(.caption).foregroundStyle(.secondary)
                    TextField("", text: $token)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Match Mode").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $matchMode) {
                        Text("Exact Case").tag(MatchMode.exact)
                        Text("Case Insensitive").tag(MatchMode.caseInsensitive)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $actionType) {
                        ForEach(ActionType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                
                if actionType == .preferLanguage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Language").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $selectedLanguage) {
                            Text("🇺🇸 English").tag(Language.english)
                            Text("🇷🇺 Russian").tag(Language.russian)
                            Text("🇮🇱 Hebrew").tag(Language.hebrew)
                        }
                        .labelsHidden()
                    }
                }
                
                Text(descriptionForAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 30, alignment: .topLeading)
            }
            .padding()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: {
                    let ruleAction: RuleAction
                    switch actionType {
                    case .keepAsIs: ruleAction = .keepAsIs
                    case .preferLanguage: ruleAction = .preferLanguage(selectedLanguage)
                    }
                    
                    let rule = UserDictionaryRule(
                        id: UUID(),
                        token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                        matchMode: matchMode,
                        scope: .global,
                        action: ruleAction,
                        source: .manual,
                        evidence: RuleEvidence(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    onAdd(rule)
                    dismiss()
                }) {
                    Text("Add Rule")
                }
                .disabled(token.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350)
    }
    
    var descriptionForAction: String {
        switch actionType {
        case .keepAsIs: return "Never auto-correct this word."
        case .preferLanguage: return "If ambiguous (e.g. mixed characters), treat as \(selectedLanguage.rawValue.capitalized)."
        }
    }
}
