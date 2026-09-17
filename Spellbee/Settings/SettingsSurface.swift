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

    /**
     Wide between sections, which carry their own titles, and tight on the
     table pages, where the buttons and the note belong to the table above.
     */
    var spacing: CGFloat = 22

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(24)
        .frame(width: Self.width, alignment: .leading)
    }
}

/**
 A titled group of lines in a rounded box, with a hairline between each.

 The dividers are drawn here rather than written into every page, so a line
 that appears conditionally can never leave a doubled or dangling one behind.
 */
struct SettingsSection<Content: View>: View {
    let title: String?
    var trailing: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        trailing: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }

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
                                .padding(.horizontal, 12)
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

            if let footer {
                SettingsNote(footer)
                    .padding(.horizontal, 2)
            }
        }
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

            if let note {
                SettingsNote(note)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsLine where Control == SettingsSwitch {
    /** The common case: a line whose whole control is one switch. */
    init(_ title: String, note: String? = nil, isOn: Binding<Bool>) {
        self.init(title, note: note) {
            SettingsSwitch(isOn: isOn)
        }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** Secondary text that explains the thing above it. */
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

/** A bordered group of rows, which is what most of these pages are. */
struct Table<Content: View>: View {
    /**
     The least height of a row, before its padding.

     A pop-up button's height, so a row with only text in it lines up with a
     row that holds a picker, and tables on different pages look the same.
     */
    static var rowHeight: CGFloat { 24 }

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        }
    }
}

/**
 The name of a table, above it rather than in a header row inside it, so every
 row in the table looks the same.
 */
struct TableTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .fontWeight(.medium)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

/** One setting as a table row: its name with its control on the right, and an explanation across the full width below. */
struct TableLine<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(title)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    control
                }
                .fixedSize()
            }
            .frame(minHeight: Table<EmptyView>.rowHeight)

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** The line under a table that says what it is for. */
struct SettingsFootnote: View {
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
