import SwiftUI

/**
 The frame every list-shaped settings page sits in.

 One width for all of them, deliberately. Sizing each page to its own content
 made the window jump about as the toolbar was clicked, which reads as the app
 losing its place rather than as a tidy fit. Height still follows the page,
 since that is what a settings window is expected to do and it never moves under
 the pointer.
 */
struct SettingsSurface<Content: View>: View {
    /** Wide enough for the widest page, which is the rules table. */
    static var width: CGFloat { 720 }

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(24)
        .frame(width: Self.width, alignment: .leading)
    }
}

/** A bordered group of rows, which is what most of these pages are. */
struct Table<Content: View>: View {
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

/** The first row of a table, naming what the rows below it are. */
struct TableHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
            }
        }
        .font(.callout)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
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
