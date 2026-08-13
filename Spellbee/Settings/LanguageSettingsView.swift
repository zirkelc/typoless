import SwiftUI

/**
 Languages and what each of them may correct, in one place.

 These were two pages, and separating them was wrong: which corrections make
 sense is a property of the language, not of the app. Capitalised nouns and
 umlauts mean something in German and nothing in English, and a single global
 list of rules could only ever offer both to everybody.

 Each rule is shown with an example in the language it belongs to, because
 "noun capitals" is an abstraction and `ein test` becoming `ein Test` is not.
 */
struct LanguageSettingsView: View {
    @Bindable var preferences: Preferences

    @State private var selected: CorrectionLanguage = .english

    var body: some View {
        /**
         Two panes rather than a labelled row. Every other page is a column of
         labels with controls beside them, which this is not: the left pane
         chooses what the right pane is about, and squeezing that into a label
         column leaves no room for either.
         */
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                pane("Languages") { languageList }
                pane("Corrections for \(selected.displayName)") { ruleTable }
            }

            Text(selected.isTuned
                ? "Turning a rule off drops that change and keeps the rest."
                : "\(selected.displayName) has not been measured. English and German are scored against a dataset; this one uses the same wording translated, and its quality is unknown.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private var languageList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(CorrectionLanguage.allCases) { language in
                    HStack(spacing: 6) {
                        Toggle("", isOn: enabledBinding(for: language))
                            .labelsHidden()

                        Text(language.displayName)

                        if !language.isTuned {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.tertiary)
                                .help("Not measured. English and German are tuned against a dataset; this one is not.")
                        }
                    }
                    .tag(language)
                }
            }
            .frame(width: 190, height: 232)
            .border(Color(nsColor: .separatorColor))
        }
    }

    private var ruleTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model:")
                Picker("", selection: modelBinding) {
                    Text("Same as Corrections").tag(LocalModel?.none)
                    Divider()
                    ForEach(LocalModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(LocalModel?.some(model))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            /**
             A plain stack rather than a scrolling list. No language has more
             than eight rules and the window sizes itself to each page, so
             scrolling would only ever hide something the window had room for.
             */
            VStack(alignment: .leading, spacing: 0) {
                ForEach(selected.rules, id: \.rule) { example in
                    RuleRow(example: example, isOn: ruleBinding(for: example.rule))

                    if example.rule != selected.rules.last?.rule {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .border(Color(nsColor: .separatorColor))
        }
        .disabled(!(preferences.languageSettings[selected]?.isEnabled ?? false))
    }

    private func enabledBinding(for language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.isEnabled ?? false },
            set: { isOn in
                var settings = preferences.languageSettings
                var entry = settings[language] ?? .default(for: language)
                entry.isEnabled = isOn
                settings[language] = entry
                preferences.languageSettings = settings
            }
        )
    }

    private var modelBinding: Binding<LocalModel?> {
        Binding(
            get: { preferences.languageSettings[selected]?.model },
            set: { model in
                var settings = preferences.languageSettings
                var entry = settings[selected] ?? .default(for: selected)
                entry.model = model
                settings[selected] = entry
                preferences.languageSettings = settings
            }
        )
    }

    private func ruleBinding(for rule: CorrectionRule) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[selected]?.allowedRules.contains(rule) ?? false },
            set: { isOn in
                var settings = preferences.languageSettings
                var entry = settings[selected] ?? .default(for: selected)
                if isOn { entry.allowedRules.insert(rule) } else { entry.allowedRules.remove(rule) }
                settings[selected] = entry
                preferences.languageSettings = settings
            }
        )
    }
}

/** One rule, with the change it makes shown rather than described. */
private struct RuleRow: View {
    let example: RuleExample
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Text(example.rule.displayName)
                    .frame(width: 132, alignment: .leading)

                /**
                 Both halves get the same width so the arrows line up down the
                 column, which is what makes the table readable at a glance
                 rather than a list of sentences.
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

#Preview {
    LanguageSettingsView(preferences: Preferences()).frame(width: 620)
}
