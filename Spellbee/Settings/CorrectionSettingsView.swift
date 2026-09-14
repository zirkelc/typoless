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
 */
struct CorrectionSettingsView: View {
    @Bindable var preferences: Preferences

    /** Nil when every language is collapsed, which is a normal state to be in. */
    @State private var expanded: CorrectionLanguage?
    @State private var hasSeeded = false

    var body: some View {
        SettingsSurface {
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

            SettingsFootnote("Turning a rule off drops that change and keeps the rest of the correction.")
        }
        .onAppear {
            /**
             Once only. Opening on a collapsed list would hide the thing the
             page is for, but unlike a window that is merely ordered out, a
             settings tab really is rebuilt on every visit, so re-seeding here
             kept re-expanding the first language after the user had
             deliberately collapsed them all.
             */
            guard !hasSeeded else { return }

            hasSeeded = true
            expanded = expanded ?? added.first
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
                        Divider().padding(.leading, 34)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
            Toggle(isOn: $isOn) {
                Text(language.label(for: example.rule))
                    .frame(width: 132, alignment: .leading)
            }

            Spacer(minLength: 12)

            /**
             Both halves get the same width so the arrows line up down the
             column, which is what makes the table readable at a glance rather
             than as a list of sentences.
             */
            Text(example.before)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(example.after)
                .frame(width: 150, alignment: .leading)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
    }
}

#Preview {
    CorrectionSettingsView(preferences: Preferences())
}
