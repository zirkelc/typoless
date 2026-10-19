import SwiftUI

/**
 One requirement in the setup checklist: what it is, why, and how to grant it.

 The row has three states and shows all three in the same place. Neither
 permission can be granted from inside this app, so the useful part is not the
 button but what sits beside it: a spinner says the app is watching System
 Settings and will notice by itself, which is the answer to the question the
 user is about to ask, and a green check says they can stop looking.
 */
struct PermissionRow: View {
    let symbol: String
    let title: String
    let rationale: String
    let isSatisfied: Bool

    /** Whether the user has already asked for this one and has not come back with it. */
    var isWaiting = false

    let actionTitle: String?
    let action: (() -> Void)?

    /** Said only when there is something to say, under the reason it belongs to. */
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSatisfied ? Color.green : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .onboardingRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title). \(isSatisfied ? "Granted" : "Not granted"). \(rationale)\(note.map { " \($0)" } ?? "")"
        )
    }

    @ViewBuilder private var trailing: some View {
        if isSatisfied {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        } else {
            HStack(spacing: 8) {
                if isWaiting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(isWaiting ? Color.white.opacity(0.12) : Color.accentColor)
                        .foregroundStyle(isWaiting ? Color.primary : Color.black)
                }
            }
        }
    }
}
