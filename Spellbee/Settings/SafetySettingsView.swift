import SwiftUI

/**
 What happens when a correction goes wrong.

 The guardrail decides what is allowed to be changed, and the history decides how
 long a change stays undoable. Both were sitting somewhere else because they
 arrived at different times, and neither is a general setting or a privacy
 statement: they are the two answers to the same question.
 */
struct SafetySettingsView: View {
    @Bindable var preferences: Preferences
    let history: CorrectionHistory

    var body: some View {
        SettingsPage {
            SettingsRow(label: "Corrections:") {
                Toggle("Only fix, never rewrite", isOn: $preferences.isGuardrailEnabled)
                SettingsNote(preferences.isGuardrailEnabled
                    ? "Every change is checked first. Anything that is not spelling, punctuation, capitalisation or spacing is discarded."
                    : "Off: whatever the model returns is applied, including rewritten or translated text. History is the only way back.")
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Keep history:") {
                Picker("", selection: $preferences.historyRetention) {
                    ForEach(HistoryRetention.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()

                SettingsNote(preferences.historyRetention.keepsHistory
                    ? "What each correction replaced, so it can be undone later. In memory only, never written to disk, and cleared when Spellbee quits."
                    : "Nothing is kept. Undo still covers the correction you just made, but anything before that is gone.")

                HStack(spacing: 8) {
                    Button("Clear Now") { history.clear() }
                        .disabled(history.entries.isEmpty)

                    Text(count)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        /**
         Nothing ages entries out on a clock, so the count would otherwise
         include text that has already passed its retention. Unlike the window
         close case, a settings tab really is torn down and rebuilt when you
         switch away and back, so this does run each time.
         */
        .onAppear { history.prune() }
    }

    private var count: String {
        switch history.entries.count {
        case 0: return "Nothing kept"
        case 1: return "1 correction kept"
        case let total: return "\(total) corrections kept"
        }
    }
}

#Preview {
    SafetySettingsView(preferences: Preferences(), history: CorrectionHistory())
}
