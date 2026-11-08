import SwiftUI

/// A dashboard summary tile: label, big value, and an optional accented note.
struct StatTile: View {
    var label: String
    var value: String
    var note: String? = nil
    var noteColor: Color = Theme.accentSecondary
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                if let note {
                    Text(note)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(noteColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .neonPanel()
    }
}
