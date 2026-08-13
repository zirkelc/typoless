import SwiftUI

/**
 Languages and what each of them may correct, in one table.

 These were two pages, and separating them was wrong: which corrections make
 sense is a property of the language, not of the app. Capitalised nouns and
 umlauts mean something in German and nothing in English, and a single global
 list of rules could only ever offer both to everybody.

 They were then one page but two panes, a list of languages beside a table of
 rules, which left the reader to work out that one drove the other. Now each
 language is a heading in the same table and its rules sit underneath it, so the
 relationship is the layout rather than something to be inferred.

 Each rule is shown with an example in the language it belongs to, because "noun
 capitals" is an abstraction and `ein test` becoming `ein Test` is not.
 */
struct LanguageSettingsView: View {
    @Bindable var preferences: Preferences

    /** Nil when every language is collapsed, which is a normal state to be in. */
    @State private var expanded: CorrectionLanguage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(CorrectionLanguage.allCases.enumerated()), id: \.element) { index, language in
                    if index > 0 {
                        Divider()
                    }

                    LanguageSection(
                        language: language,
                        isEnabled: enabledBinding(for: language),
                        isExpanded: expanded == language,
                        model: modelBinding(for: language),
                        rule: { ruleBinding(for: $0, in: language) },
                        onToggleExpanded: { toggle(language) }
                    )
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            Text("Turning a language off skips it entirely. Turning a rule off drops that change and keeps the rest.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            /** Opening on a collapsed list would hide the thing the page is for. */
            expanded = expanded ?? preferences.enabledLanguages.first
        }
    }

    private func toggle(_ language: CorrectionLanguage) {
        withAnimation(.easeOut(duration: 0.16)) {
            expanded = expanded == language ? nil : language
        }
    }

    private func enabledBinding(for language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.isEnabled ?? false },
            set: { isOn in
                update(language) { $0.isEnabled = isOn }

                /** Opening it is the useful next step; closing it hides nothing. */
                if isOn { expanded = language } else if expanded == language { expanded = nil }
            }
        )
    }

    private func modelBinding(for language: CorrectionLanguage) -> Binding<LocalModel?> {
        Binding(
            get: { preferences.languageSettings[language]?.model },
            set: { model in update(language) { $0.model = model } }
        )
    }

    private func ruleBinding(for rule: CorrectionRule, in language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.allowedRules.contains(rule) ?? false },
            set: { isOn in
                update(language) {
                    if isOn { $0.allowedRules.insert(rule) } else { $0.allowedRules.remove(rule) }
                }
            }
        )
    }

    private func update(_ language: CorrectionLanguage, _ change: (inout LanguageSettings) -> Void) {
        var settings = preferences.languageSettings
        var entry = settings[language] ?? .default(for: language)
        change(&entry)
        settings[language] = entry
        preferences.languageSettings = settings
    }
}

/** One language: a heading that opens to show what it is allowed to correct. */
private struct LanguageSection: View {
    let language: CorrectionLanguage
    @Binding var isEnabled: Bool
    let isExpanded: Bool
    @Binding var model: LocalModel?
    let rule: (CorrectionRule) -> Binding<Bool>
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded, isEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Model:")
                        Picker("", selection: $model) {
                            Text("Same as Corrections").tag(LocalModel?.none)
                            Divider()
                            ForEach(LocalModel.allCases, id: \.self) { option in
                                Text(option.displayName).tag(LocalModel?.some(option))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .font(.callout)
                    .padding(.leading, 34)
                    .padding(.vertical, 6)

                    Divider().padding(.leading, 34)

                    ForEach(Array(language.rules.enumerated()), id: \.element.rule) { index, example in
                        if index > 0 {
                            Divider().padding(.leading, 34)
                        }

                        RuleRow(example: example, isOn: rule(example.rule))
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()

            Text(language.displayName)
                .fontWeight(.medium)

            if !language.isTuned {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.tertiary)
                    .help("Not measured. English and German are scored against a dataset; this one uses the same wording with the language named, and its quality is unknown.")
            }

            Spacer()

            if isEnabled {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            onToggleExpanded()
        }
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
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $isOn) {
                Text(example.rule.displayName)
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
                .frame(width: 168, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(example.after)
                .frame(width: 168, alignment: .leading)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
    }
}

#Preview {
    LanguageSettingsView(preferences: Preferences()).frame(width: 700)
}
