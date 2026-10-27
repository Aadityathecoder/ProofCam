import SwiftUI

/// The ProofCam ring mark at work. While a check runs, the back ring set wanders;
/// a real result then locks it into the front set (match) or leaves it visibly off (mismatch).
struct RegistrationAlignment: View {
    enum Phase: Equatable { case searching, aligned, offset, idle }

    let phase: Phase
    var size: CGFloat = 76
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = CGSize(width: 0.9, height: -0.6)

    private var tier: RingMark.Tier { size >= 64 ? .lg : size >= 36 ? .md : .sm }
    private var tint: Color {
        switch phase {
        case .aligned: ProofCamTheme.success
        case .offset: ProofCamTheme.warning
        case .searching: ProofCamTheme.secondary
        case .idle: ProofCamTheme.border
        }
    }

    var body: some View {
        RingMark(tier: tier, front: ProofCamTheme.text, back: tint, drift: drift)
            .frame(width: size, height: size)
            .task(id: phase) { await settle() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    private func settle() async {
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)
        switch phase {
        case .searching:
            guard !reduceMotion else { drift = CGSize(width: 0.9, height: -0.6); return }
            let wander = [CGSize(width: -0.5, height: 0.4), CGSize(width: 0.3, height: 0.6), CGSize(width: 0.9, height: -0.6)]
            var index = 0
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.0)) { drift = wander[index % wander.count] }
                index += 1
                try? await Task.sleep(for: .milliseconds(1000))
            }
        case .aligned:
            await Task.yield()
            withAnimation(spring) { drift = .zero }
        case .offset:
            withAnimation(spring) { drift = RingMark.resting(tier) }
        case .idle:
            drift = .zero
        }
    }

    private var label: String {
        switch phase {
        case .aligned: "Image and proof line up"
        case .offset: "Image and proof do not line up"
        case .searching: "Checking"
        case .idle: "No proof to compare"
        }
    }
}

/// Fades and lifts content in one step after another. Under Reduce Motion it only fades.
private struct Reveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.5).delay(reduceMotion ? 0 : 0.15 + Double(index) * 0.08)) { shown = true }
            }
    }
}

extension View {
    func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) }
}
