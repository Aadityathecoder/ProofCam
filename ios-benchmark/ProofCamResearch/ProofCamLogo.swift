import SwiftUI

/// The ProofCam mark: two sets of concentric rings. The back set can drift off the front set;
/// when the two line up, the pattern resolves into clean rings.
struct RingMark: View, Animatable {
    /// Fewer, heavier rings at small sizes keep the interference readable.
    enum Tier {
        case sm, md, lg, xl
        var rings: Int { switch self { case .sm: 4; case .md: 6; case .lg: 9; case .xl: 18 } }
        var strokeShare: CGFloat { switch self { case .sm: 0.54; case .md: 0.50; case .lg, .xl: 0.46 } }
        var offsetShare: CGFloat { switch self { case .sm: 0.42; case .md: 0.40; case .lg: 0.38; case .xl: 0.34 } }
    }

    var tier: Tier = .lg
    var front: Color = ProofCamTheme.text
    var back: Color = ProofCamTheme.primary
    private var dx: CGFloat
    private var dy: CGFloat

    /// The logo's resting offset, in ring steps, toward the upper right.
    static func resting(_ tier: Tier) -> CGSize {
        let value = tier.offsetShare / 2.0.squareRoot()
        return CGSize(width: value, height: -value)
    }

    /// `drift` is the back set's offset in ring steps. `.zero` is perfectly aligned.
    init(tier: Tier = .lg, front: Color = ProofCamTheme.text, back: Color = ProofCamTheme.primary, drift: CGSize? = nil) {
        let d = drift ?? Self.resting(tier)
        self.tier = tier; self.front = front; self.back = back
        dx = d.width; dy = d.height
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(dx, dy) }
        set { dx = newValue.first; dy = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let count = tier.rings
            // Size the rings so the outer stroke edge touches the frame.
            let radius = (side / 2) / (1 + tier.strokeShare / (2 * CGFloat(count)))
            let step = radius / CGFloat(count)
            let width = step * tier.strokeShare
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lens = radius + width / 2
            var clipped = context
            clipped.clip(to: Path(ellipseIn: CGRect(x: center.x - lens, y: center.y - lens, width: lens * 2, height: lens * 2)))
            func ring(_ origin: CGPoint, _ k: Int, _ color: Color) {
                let r = step * CGFloat(k)
                clipped.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)),
                               with: .color(color), lineWidth: width)
            }
            let shifted = CGPoint(x: center.x + dx * step, y: center.y + dy * step)
            for k in 1...(count + 1) { ring(shifted, k, back) }
            for k in 1...count { ring(center, k, front) }
        }
        .accessibilityHidden(true)
    }
}

/// The ProofCam wordmark, drawn from a monoline geometric alphabet (100-unit x-height).
/// Only the second "o" is out of register, with the back colour offset to the upper right.
struct ProofCamWordmark: View {
    /// Height of the capital P, in points.
    var height: CGFloat = 18
    var color: Color = ProofCamTheme.text
    var ghost: Color = ProofCamTheme.primary

    private static let unitsWide: CGFloat = 847.2
    private static let unitsHigh: CGFloat = 144

    var body: some View {
        Canvas { context, size in
            let scale = size.height / Self.unitsHigh
            var ctx = context
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: -56)
            // Keep strokes at least about 1.5 pt so small sizes stay legible.
            let w = max(15, 1.5 / scale)
            let h = w / 2
            let ro = 50 - h
            let style = StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter)

            func arc(_ path: inout Path, center: CGPoint, radius: CGFloat, from: Double, to: Double, moveFirst: Bool = false) {
                let steps = max(24, Int(abs(to - from) / 3))
                for i in 0...steps {
                    let t = (from + (to - from) * Double(i) / Double(steps)) * .pi / 180
                    let point = CGPoint(x: center.x + radius * CGFloat(cos(t)), y: center.y + radius * CGFloat(sin(t)))
                    if i == 0 && moveFirst { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            func ring(_ cx: CGFloat, _ color: Color, dx: CGFloat = 0, dy: CGFloat = 0) {
                ctx.stroke(Path(ellipseIn: CGRect(x: cx + dx - ro, y: 150 + dy - ro, width: ro * 2, height: ro * 2)),
                           with: .color(color), style: style)
            }
            var p = Path()
            // P
            p.move(to: CGPoint(x: h, y: 56)); p.addLine(to: CGPoint(x: h, y: 200))
            p.move(to: CGPoint(x: h, y: 56 + h)); p.addLine(to: CGPoint(x: h + 28, y: 56 + h))
            arc(&p, center: CGPoint(x: h + 28, y: 102), radius: 46 - h, from: -90, to: 90)
            p.addLine(to: CGPoint(x: h, y: 148 - h))
            // r
            let r0: CGFloat = 95.5
            p.move(to: CGPoint(x: r0 + h, y: 100)); p.addLine(to: CGPoint(x: r0 + h, y: 200))
            p.move(to: CGPoint(x: r0 + h, y: 150))
            arc(&p, center: CGPoint(x: r0 + h + ro, y: 150), radius: ro, from: 180, to: 270)
            p.addLine(to: CGPoint(x: r0 + h + ro + 6, y: 100 + h))
            // f
            let f0: CGFloat = 385.5
            p.move(to: CGPoint(x: f0 + 22, y: 200)); p.addLine(to: CGPoint(x: f0 + 22, y: 56 + h + 20))
            arc(&p, center: CGPoint(x: f0 + 42, y: 56 + h + 20), radius: 20, from: 180, to: 270)
            p.addLine(to: CGPoint(x: f0 + 52, y: 56 + h))
            p.move(to: CGPoint(x: f0 + 4, y: 100 + h)); p.addLine(to: CGPoint(x: f0 + 40, y: 100 + h))
            // C
            arc(&p, center: CGPoint(x: 533.5, y: 128), radius: 72 - h, from: -38, to: -322, moveFirst: true)
            // a
            let ca: CGFloat = 654.2
            p.move(to: CGPoint(x: ca + ro, y: 100)); p.addLine(to: CGPoint(x: ca + ro, y: 200))
            // m
            let m0: CGFloat = 716.2
            p.move(to: CGPoint(x: m0 + h, y: 100)); p.addLine(to: CGPoint(x: m0 + h, y: 200))
            for arch in 0..<2 {
                let ax = m0 + h + CGFloat(arch) * 58
                p.move(to: CGPoint(x: ax, y: 136.5))
                arc(&p, center: CGPoint(x: ax + 29, y: 136.5), radius: 29, from: 180, to: 360)
                p.addLine(to: CGPoint(x: ax + 58, y: 200))
            }
            // the misregistered ghost sits behind the second "o"
            ring(323.5, ghost, dx: 6, dy: -6)
            ctx.stroke(p, with: .color(color), style: style)
            ring(213.5, color)
            ring(323.5, color)
            ring(ca, color)
        }
        .frame(width: height * Self.unitsWide / Self.unitsHigh, height: height)
        .accessibilityElement()
        .accessibilityLabel("ProofCam")
    }
}
