import SwiftUI

/** What the overlay is saying, which decides how it draws. */
enum OverlayStyle {
    /** Work in progress, over the text being read. */
    case scanning
    /** Work finished, over the words that actually changed. */
    case settled
}

/**
 The correction animation.

 Two moments, deliberately different. While the model is thinking, a highlight
 sweeps across the text being read, driven by a single phase spanning the whole
 block rather than per line, so on wrapped text it reads as one pass over the
 passage instead of several independent lines blinking at once. When the
 correction lands, a short pulse sits on the words that changed and fades, which
 is the only chance the user gets to see what was touched before the overlay
 goes away.
 */
struct OverlayView: View {
    /** One rect per visual line, positioned relative to the window's top-left. */
    let rects: [CGRect]

    var style: OverlayStyle = .scanning

    private let sweepDuration: Double = 1.4
    private let cornerRadius: CGFloat = 4

    /** Drives the pulse, since it plays once rather than looping. */
    @State private var pulse: Double = 0

    var body: some View {
        Group {
            switch style {
            case .scanning: scanning
            case .settled: settled
            }
        }
        .allowsHitTesting(false)
    }

    private var scanning: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let phase = phase(at: context.date)
                let highlightWidth = max(size.width * 0.28, 48)
                let travel = size.width + highlightWidth
                let sweepCentre = -highlightWidth / 2 + travel * phase

                for rect in rects {
                    let shape = Path(roundedRect: rect, cornerRadius: cornerRadius)

                    canvas.fill(shape, with: .color(.accentColor.opacity(0.16)))

                    /**
                     The highlight is clipped to the line rects, so it only ever
                     brightens text and never the gaps around it.
                     */
                    canvas.drawLayer { layer in
                        layer.clip(to: shape)
                        layer.fill(
                            Path(
                                CGRect(
                                    x: sweepCentre - highlightWidth / 2,
                                    y: rect.minY,
                                    width: highlightWidth,
                                    height: rect.height
                                )
                            ),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .accentColor.opacity(0),
                                    .accentColor.opacity(0.55),
                                    .accentColor.opacity(0),
                                ]),
                                startPoint: CGPoint(x: sweepCentre - highlightWidth / 2, y: 0),
                                endPoint: CGPoint(x: sweepCentre + highlightWidth / 2, y: 0)
                            )
                        )
                    }

                    canvas.stroke(shape, with: .color(.accentColor.opacity(0.4)), lineWidth: 1)
                }
            }
        }
    }

    /**
     Green rather than the accent colour, so "this changed" cannot be mistaken
     for another sweep of "this is being read".
     */
    private var settled: some View {
        Canvas { canvas, _ in
            for rect in rects {
                let shape = Path(roundedRect: rect.insetBy(dx: -2, dy: -1), cornerRadius: cornerRadius)

                canvas.fill(shape, with: .color(.green.opacity(0.28)))
                canvas.stroke(shape, with: .color(.green.opacity(0.6)), lineWidth: 1)
            }
        }
        .opacity(pulse)
        .onAppear {
            /** Arrives quickly enough to be seen, leaves slowly enough not to flicker. */
            withAnimation(.easeOut(duration: 0.12)) { pulse = 1 }
            withAnimation(.easeIn(duration: 0.32).delay(0.24)) { pulse = 0 }
        }
    }

    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return elapsed.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration
    }
}

#Preview("Scanning") {
    OverlayView(rects: [
        CGRect(x: 8, y: 8, width: 280, height: 18),
        CGRect(x: 8, y: 30, width: 200, height: 18),
        CGRect(x: 8, y: 52, width: 240, height: 18),
    ])
    .frame(width: 320, height: 80)
    .background(.black)
}

#Preview("Settled") {
    OverlayView(
        rects: [
            CGRect(x: 20, y: 10, width: 42, height: 16),
            CGRect(x: 120, y: 32, width: 28, height: 16),
        ],
        style: .settled
    )
    .frame(width: 320, height: 80)
    .background(.black)
}
