import AppKit
import SwiftUI

/**
 The look of first-run setup.

 Setup is the only part of this app with a look of its own. Everything after it
 lives in the menu bar and follows the system appearance, because it is read
 every day and has to disappear into the Mac around it. This window is read
 once, by somebody who has just downloaded an app and does not yet know what it
 is, so it is allowed to be a thing rather than a form: one dark window, one
 card in the middle of it, and the icon's own colour on the button that moves
 forward.

 Every page is built from the same three pieces, and nothing here knows what any
 of them is for.
 */

/** Near-black, with the icon's own colour behind the title. */
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.071, blue: 0.075)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.13), .clear],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

/**
 The container every page's content sits in.

 Rows go inside it and separate themselves with `OnboardingDivider`, rather
 than the card inserting dividers between whatever it is given: a page that
 wants a single block of text in a card should get one, not a block with lines
 drawn through it.
 */
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: Self.shape)
            .overlay(Self.shape.strokeBorder(Color.white.opacity(0.09)))
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

/** The line between two rows of one card. */
struct OnboardingDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}

extension View {
    /** The inset every row of a card shares, so that the dividers line up. */
    func onboardingRow() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/**
 One key, drawn as the key itself.

 A keyboard gesture written out as words is read as a sentence and forgotten.
 The same gesture drawn as the keys is matched against the keyboard under the
 reader's hands, which is where it has to end up.
 */
struct Keycap: View {
    let label: String
    var isTinted = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isTinted ? Color.accentColor : .primary)
            .frame(minWidth: 15, minHeight: 20)
            .padding(.horizontal, 5)
            .background(fill, in: Self.shape)
            .overlay(Self.shape.strokeBorder(Color.white.opacity(isTinted ? 0.18 : 0.14)))
    }

    private var fill: Color {
        isTinted ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.07)
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }
}

/** A symbol in a key-sized tile, for a gesture that is not a key. */
struct KeycapSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 25, height: 20)
            .background(Color.accentColor.opacity(0.16), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18)))
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }
}

/**
 How far along setup is.

 Dots rather than the bar this replaces. A bar answers "how much is left",
 which on a six-step setup is a discouraging answer; dots answer "how many
 steps", which is the same information read as a small number.
 */
struct OnboardingDots: View {
    let current: OnboardingPage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases) { page in
                Capsule()
                    .fill(page == current ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: page == current ? 18 : 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingPage.allCases.count)")
    }
}

/** The app's own icon, at the size the Finder shows it. */
struct AppIconMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 92, height: 92)
            .shadow(color: Color.accentColor.opacity(0.30), radius: 26)
            .accessibilityHidden(true)
    }
}
