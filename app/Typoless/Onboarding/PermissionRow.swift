import SwiftUI

/** One requirement in the setup checklist: what it is, why, and how to grant it. */
struct PermissionRow: View {
    let title: String
    let rationale: String
    let isSatisfied: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSatisfied ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(isSatisfied ? Color.green : Color.secondary)
                .accessibilityHidden(true)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !isSatisfied, let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(isSatisfied ? "Granted" : "Not granted"). \(rationale)")
    }
}
