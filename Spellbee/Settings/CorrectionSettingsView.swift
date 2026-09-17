import SwiftUI

/**
 What each added language is allowed to correct.

 Rules belong to the language rather than to the app: capitalised nouns and
 umlauts mean something in German and nothing in English, so a single global
 list could only ever offer both to everybody. Each rule is shown with an
 example in its own language, because "noun capitals" is an abstraction and
 `ein test` becoming `ein Test` is not.

 Only languages added under Languages appear, since a rule for a language that
 is never detected is a row nobody can act on.

 The guardrail and the history live here too. The rules only mean anything
 while the guardrail is on, so the switch that decides that belongs above them,
 and history is what makes a correction that got through undoable.
 */
struct CorrectionSettingsView: View {
    @Bindable var preferences: Preferences
    let history: CorrectionHistory

    /** Nil when every language is collapsed, which is a normal state to be in. */
    @State private var expanded: CorrectionLanguage?
    @State private var hasSeeded = false

    var body: some View {
        SettingsSurface(spacing: 12) {
            Table {
                TableLine(
                    "Fix only, never rewrite",
                    note: preferences.isGuardrailEnabled
                        ? "Every change is checked against the allowed rules. Anything that is not allowed is discarded."
                        : "Off: whatever the model returns is applied, including rewritten or translated text. History is the only way back."
                ) {
                    SettingsSwitch(isOn: $preferences.isGuardrailEnabled)
                }
            }

            Divider().padding(.vertical, 6)

            TableTitle("Rules")

            Table {
                if added.isEmpty {
                    Text("No languages yet. Add one under Languages.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(added.enumerated()), id: \.element) { index, language in
                    if index > 0 {
                        Divider()
                    }

                    LanguageRules(
                        language: language,
                        isExpanded: expanded == language,
                        rule: { ruleBinding(for: $0, in: language) },
                        onToggleExpanded: { toggle(language) }
                    )
                }
            }
            /**
             The rules are read only by the guardrail, so with it off every
             switch here does nothing. Disabled rather than hidden, so turning
             the guardrail back on does not make the page jump.
             */
            .disabled(!preferences.isGuardrailEnabled)

            SettingsFootnote(preferences.isGuardrailEnabled
                ? "Turning off a rule only drops that change and keeps the rest of the correction."
                : "Rules apply only while \"Fix only, never rewrite\" is on.")

            Divider().padding(.vertical, 6)

            TableTitle("History")

            Table {
                TableLine(
                    "Keep history",
                    note: preferences.historyRetention.keepsHistory
                        ? "Keeps each correction and the original text, so it can be undone later. In memory only, never written to disk and cleared when the application quits."
                        : "Nothing is kept. Undo still covers the correction you just made, but anything before that is gone."
                ) {
                    Picker("", selection: $preferences.historyRetention) {
                        ForEach(HistoryRetention.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                TableLine(historyCount) {
                    Button("Clear Now") { history.clear() }
                        .disabled(history.entries.isEmpty)
                }
            }
        }
        .onAppear {
            /**
             Once only. Opening on a collapsed list would hide the thing the
             page is for, but unlike a window that is merely ordered out, a
             settings tab really is rebuilt on every visit, so re-seeding here
             kept re-expanding the first language after the user had
             deliberately collapsed them all.
             */
            /**
             Nothing ages history out on a clock, so the count would otherwise
             include text that has already passed its retention.
             */
            history.prune()

            guard !hasSeeded else { return }

            hasSeeded = true
            expanded = expanded ?? added.first
        }
    }

    private var historyCount: String {
        switch history.entries.count {
        case 0: return "No corrections yet"
        case 1: return "1 correction kept"
        case let total: return "\(total) corrections kept"
        }
    }

    private var added: [CorrectionLanguage] {
        preferences.enabledLanguages
    }

    private func toggle(_ language: CorrectionLanguage) {
        withAnimation(.easeOut(duration: 0.16)) {
            expanded = expanded == language ? nil : language
        }
    }

    private func ruleBinding(for rule: CorrectionRule, in language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.allowedRules.contains(rule) ?? false },
            set: { isOn in
                var settings = preferences.languageSettings
                var entry = settings[language] ?? .default(for: language)
                if isOn { entry.allowedRules.insert(rule) } else { entry.allowedRules.remove(rule) }
                settings[language] = entry
                preferences.languageSettings = settings
            }
        )
    }
}

/** One language: a heading that opens to show what it is allowed to correct. */
private struct LanguageRules: View {
    let language: CorrectionLanguage
    let isExpanded: Bool
    let rule: (CorrectionRule) -> Binding<Bool>
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()

                ForEach(Array(language.rules.enumerated()), id: \.element.rule) { index, example in
                    if index > 0 {
                        Divider().padding(.leading, 10)
                    }

                    RuleRow(example: example, language: language, isOn: rule(example.rule))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(language.displayName)
                .fontWeight(.medium)

            Spacer()

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .frame(minHeight: Table<EmptyView>.rowHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        /** The open language reads as selected, the same as a picked row under Languages. */
        .background(isExpanded ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
    }

    /** Says what is on without opening it, since most languages are left alone. */
    private var summary: String {
        let allowed = language.rules.filter { rule($0.rule).wrappedValue }.count

        if allowed == language.rules.count { return "All corrections" }
        if allowed == 0 { return "No corrections" }

        return "\(allowed) of \(language.rules.count)"
    }
}

/** One rule, with the change it makes shown rather than described. */
private struct RuleRow: View {
    let example: RuleExample
    /** The same rule answers a different question depending on the language. */
    let language: CorrectionLanguage
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            /** A marker per rule, so the rules read as a list under their language. */
            Text("•")
                .foregroundStyle(.secondary)

            Text(language.label(for: example.rule))
                .frame(width: 130, alignment: .leading)

            Spacer(minLength: 8)

            /**
             Both halves get the same width so the arrows line up down the
             column, which is what makes the table readable at a glance rather
             than as a list of sentences.
             */
            Text(example.before)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(example.after)
                .frame(width: 140, alignment: .leading)

            Spacer(minLength: 8)

            /** On the right, where every other page keeps its switches. */
            SettingsSwitch(isOn: $isOn)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
    }
}

#Preview {
    CorrectionSettingsView(preferences: Preferences(), history: CorrectionHistory())
}
