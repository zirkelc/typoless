import SwiftUI

/**
 The correction animation.

 A highlight sweeps left to right across the text being worked on. The sweep is
 driven by a single phase spanning the whole block rather than per line, so on
 wrapped text it reads as one pass over the passage instead of several
 independent lines blinking at once.
 */
struct OverlayView: View {
    /** One rect per visual line, positioned relative to the window's top-left. */
    let rects: [CGRect]

    private let sweepDuration: Double = 1.4
    private let cornerRadius: CGFloat = 4

    var body: some View {
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
        .allowsHitTesting(false)
    }

    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return elapsed.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration
    }
}

#Preview {
    OverlayView(rects: [
        CGRect(x: 8, y: 8, width: 280, height: 18),
        CGRect(x: 8, y: 30, width: 200, height: 18),
        CGRect(x: 8, y: 52, width: 240, height: 18),
    ])
    .frame(width: 320, height: 80)
    .background(.black)
}
