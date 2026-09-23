import SwiftUI

/** What the app is, before it asks for anything. */
struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.points, id: \.text) { point in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: point.symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    Text(point.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct Point {
        let symbol: String
        let text: String
    }

    private static let points: [Point] = [
        Point(symbol: "keyboard", text: "Press a key twice, and the field you are typing in is corrected where it stands."),
        Point(symbol: "lock.laptopcomputer", text: "The model runs on this Mac. Nothing is uploaded, and there is no account."),
        Point(symbol: "arrow.uturn.backward", text: "Every correction can be undone, and each one is kept in history until you quit."),
    ]
}

/** The two gates, each with the button that opens the right pane of System Settings. */
struct PermissionsPage: View {
    let permissions: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PermissionRow(
                title: "Accessibility",
                rationale: "Lets Typoless read the text in the field you are typing in, and write the corrections back.",
                isSatisfied: permissions.isAccessibilityTrusted,
                actionTitle: "Allow…",
                action: { permissions.openAccessibilitySettings() }
            )

            Divider()

            PermissionRow(
                title: "Apple Intelligence",
                rationale: permissions.modelAvailability.explanation,
                isSatisfied: permissions.modelAvailability == .available,
                actionTitle: permissions.modelAvailability.isActionable ? "Allow…" : nil,
                action: permissions.modelAvailability.isActionable
                    ? { permissions.openAppleIntelligenceSettings() }
                    : nil
            )
        }
    }
}

/**
 Which languages are corrected.

 Tick boxes here rather than the add-and-remove list Settings uses. Setup is
 where someone meets the idea for the first time, and a list of everything the
 app knows says what the choice is; the Settings page assumes it is already
 understood and optimises for changing it.
 */
struct LanguagesPage: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(CorrectionLanguage.allCases.enumerated()), id: \.element) { index, language in
                if index > 0 {
                    Divider()
                }

                Toggle(isOn: binding(for: language)) {
                    HStack(spacing: 6) {
                        Text(language.displayName)

                        if !language.isTuned {
                            Text("not measured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func binding(for language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.isEnabled ?? false },
            set: { isEnabled in
                var settings = preferences.languageSettings
                var entry = settings[language] ?? .default(for: language)
                entry.isEnabled = isEnabled
                settings[language] = entry
                preferences.languageSettings = settings
            }
        )
    }
}

/** The two ways to start a correction, taught before the page that needs one. */
struct TriggersPage: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Double-tap", isOn: $preferences.isDoubleTapEnabled)
                        .toggleStyle(.checkbox)

                    Spacer()

                    Picker("", selection: $preferences.doubleTapModifier) {
                        ForEach(TapModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!preferences.isDoubleTapEnabled)
                }

                Text(preferences.doubleTapModifier.caution
                    ?? "Tap \(preferences.doubleTapModifier.symbol) twice, quickly, with no other key or click in between.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Keyboard shortcut", isOn: $preferences.isHotKeyEnabled)
                        .toggleStyle(.checkbox)

                    Spacer()

                    ShortcutRecorder(shortcut: $preferences.hotKey)
                        .disabled(!preferences.isHotKeyEnabled)
                }

                Text("One key combination, pressed once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/**
 The end of setup: the user corrects a real field with their own trigger.

 The field is ours and the pass is not. It runs through the same accessibility
 read and write as any other application, so what proves the setup is the text
 changing here, not a message from us saying that it should.

 There is a button as well, for anyone who turned both triggers off or whose
 keyboard makes the gesture awkward. It is the fallback rather than the
 instruction: pressing the real trigger once is what makes it stick.
 */
struct TryItPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SampleField(
                model: model,
                caption: "The whole field",
                sample: "i  think its ready , lets see if this works",
                instruction: "with the cursor anywhere in the field.",
                done: "The whole field was corrected."
            )

            /**
             The second example is the one nobody discovers on their own.

             Selecting first is how the app is told to leave the rest alone,
             which matters most in the message someone has half written and
             does not want reflowed. It is one sentence of teaching here and a
             support question otherwise.
             */
            SampleField(
                model: model,
                caption: "Or only what you select",
                sample: "thanks for the update. i will check teh numbers and come back to you",
                instruction: "after selecting a few words. Only the selection changes.",
                done: "Only the selected words were corrected."
            )
        }
    }
}

/** One sample field: what to do, the field itself, and what happened. */
private struct SampleField: View {
    let model: AppModel
    let caption: String
    let sample: String
    let instruction: String
    let done: String

    @State private var text: String
    @State private var hasChanged = false
    @FocusState private var isFocused: Bool

    init(model: AppModel, caption: String, sample: String, instruction: String, done: String) {
        self.model = model
        self.caption = caption
        self.sample = sample
        self.instruction = instruction
        self.done = done
        _text = State(initialValue: sample)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.headline)

            TextEditor(text: $text)
                .focused($isFocused)
                .font(.body)
                .frame(height: 54)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onChange(of: text) { _, new in
                    if new != sample { hasChanged = true }
                }

            HStack(spacing: 10) {
                if hasChanged {
                    Label(done, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Button("Again") {
                        text = sample
                        hasChanged = false
                        isFocused = true
                    }
                    .buttonStyle(.link)
                } else {
                    Text(instructionLine)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                /**
                 The pass reads whichever field has focus, and a click moves
                 focus to the button on a Mac with full keyboard access, so the
                 field is focused again before anything is asked. A selection
                 made by hand survives that, since focus returns to where it was.
                 */
                Button("Fix") {
                    isFocused = true
                    model.trigger()
                }
                .disabled(model.isPaused)
            }
            .font(.subheadline)
        }
    }

    private var instructionLine: String {
        guard let description = model.preferences.triggerDescription else {
            return "Both triggers are off, so use the button."
        }

        return "\(description) \(instruction)"
    }
}
