import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var history: [CorrectionEngine.CorrectionRecord] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Correction History")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear") {
                    history.removeAll()
                }
                .disabled(history.isEmpty)
            }
            .padding()
            
            Divider()
            
            if history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No corrections yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(history) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.original)
                                .strikethrough()
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            Text(record.corrected)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("\(record.fromLang.rawValue.uppercased()) → \(record.toLang.rawValue.uppercased())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(record.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            Button("Done") {
                dismiss()
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
