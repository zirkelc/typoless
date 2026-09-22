import SwiftUI

/**
 The frame every settings page sits in.

 One width for all of them, deliberately. Sizing each page to its own content
 made the window jump about as the toolbar was clicked, which reads as the app
 losing its place rather than as a tidy fit. Height still follows the page,
 since that is what a settings window is expected to do and it never moves under
 the pointer.

 Not a grouped `Form`, which draws the same sections: that one scrolls, and a
 scroll view has no height of its own to report, so the window could no longer
 size itself to the page.
 */
struct SettingsSurface<Content: View>: View {
    /** Wide enough for the widest page, which is the rules table. */
    static var width: CGFloat { 620 }

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content
        }
        .padding(24)
        .frame(width: Self.width, alignment: .leading)
    }
}

/**
 A group of lines in a rounded box, with an optional title above it, buttons
 below it, and a note under those.

 Every page is built from these, the lists as well as the switches, so a box
 looks the same whichever tab it is on. The dividers are drawn here rather than
 written into every page, so a line that appears conditionally can never leave
 a doubled or dangling one behind.
 */
struct SettingsSection<Content: View, Actions: View>: View {
    let title: String?
    var trailing: String?
    var footer: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    init(
        _ title: String? = nil,
        trailing: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.trailing = trailing
        self.footer = footer
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    if let trailing {
                        Text(trailing)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(spacing: 0) {
                Group(subviews: content) { lines in
                    ForEach(lines) { line in
                        if line.id != lines.first?.id {
                            Divider()
                                .padding(.horizontal, SettingsRow.horizontalPadding)
                        }

                        line
                    }
                }
            }
            .background(.quinary)
            /** Clipped so a selected first or last line keeps the rounded corners. */
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator.opacity(0.6))
            }

            HStack(spacing: 8) {
                actions
            }

            if let footer {
                SettingsNote(footer)
                    .padding(.horizontal, 2)
            }
        }
    }
}

extension SettingsSection where Actions == EmptyView {
    init(
        _ title: String? = nil,
        trailing: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, trailing: trailing, footer: footer, content: content) {
            EmptyView()
        }
    }
}

/**
 The spacing of one line in a section, shared by the settings and the list
 rows so both line up in the same box.
 */
enum SettingsRow {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7

    /**
     The least height of a line, before its padding.

     A pop-up button's height, so a line with only text in it is as tall as a
     line that holds a picker.
     */
    static let minHeight: CGFloat = 24
}

extension View {
    /** Pads a line the way every line in a section is padded. */
    func settingsRow() -> some View {
        frame(minHeight: SettingsRow.minHeight)
            .padding(.horizontal, SettingsRow.horizontalPadding)
            .padding(.vertical, SettingsRow.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /** A line that says a section is empty, in place of the rows it would hold. */
    func settingsEmptyRow() -> some View {
        font(.callout)
            .foregroundStyle(.tertiary)
            .settingsRow()
    }
}

/**
 One setting: its name on the left, its control on the right.

 The control lines up with the name, and the explanation runs the full width
 underneath both. Kept beside the name only, a long note squeezed into half the
 row and pushed the control down to the middle of it, away from the words it
 belongs to.
 */
struct SettingsLine<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 16) {
                Text(title)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    control
                }
                .fixedSize()
            }
            .frame(minHeight: SettingsRow.minHeight)

            if let note {
                SettingsNote(note)
            }
        }
        .padding(.horizontal, SettingsRow.horizontalPadding)
        .padding(.vertical, SettingsRow.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** An on/off control, drawn as a switch the way a line-per-setting page expects. */
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/** A line of text inside a section, for a statement rather than a setting. */
struct SettingsText: View {
    let title: String?
    let text: String

    init(_ title: String? = nil, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title {
                Text(title)
            }

            SettingsNote(text)
        }
        .padding(.horizontal, SettingsRow.horizontalPadding)
        .padding(.vertical, SettingsRow.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** Secondary text that explains the thing above or below it: a line, a section, or a table. */
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
