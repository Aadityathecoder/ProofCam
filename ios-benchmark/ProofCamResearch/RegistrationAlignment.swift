import SwiftUI

/// Two print registration marks. While the app is working the second mark drifts;
/// a real result then locks it into place (match) or leaves it visibly off (mismatch).
struct RegistrationAlignment: View {
    enum Phase: Equatable { case searching, aligned, offset, idle }

    let phase: Phase
    var size: CGFloat = 76
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private var tint: Color {
        switch phase {
        case .aligned: ProofCamTheme.success
        case .offset: ProofCamTheme.warning
        case .searching, .idle: ProofCamTheme.secondary
        }
    }
    private var drift: CGSize {
        switch phase {
        case .aligned: .zero
        case .offset: CGSize(width: size * 0.11, height: size * 0.08)
        case .searching, .idle: CGSize(width: size * 0.34, height: -size * 0.22)
        }
    }

    var body: some View {
        ZStack {
            RegistrationMark().stroke(ProofCamTheme.text, lineWidth: 1.6)
            if phase == .idle {
                RegistrationMark().stroke(ProofCamTheme.secondary, style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
            } else if phase == .searching && !reduceMotion {
                searchingMark
            } else {
                RegistrationMark().stroke(tint, lineWidth: 1.6)
                    .offset(settled || phase != .aligned ? drift : CGSize(width: size * 0.34, height: -size * 0.22))
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7), value: phase)
        .task(id: phase) {
            guard phase == .aligned else { return }
            // Start offset, let that frame render, then spring the mark into register.
            settled = false
            await Task.yield()
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)) { settled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// Slow, looping drift while a result is pending. Replaced by a static mark under Reduce Motion.
    private var searchingMark: some View {
        PhaseAnimator([CGSize(width: size * 0.34, height: -size * 0.22), CGSize(width: -size * 0.16, height: size * 0.12), CGSize(width: size * 0.1, height: size * 0.18)]) { offset in
            RegistrationMark().stroke(ProofCamTheme.secondary, lineWidth: 1.6).offset(offset)
        } animation: { _ in .easeInOut(duration: 0.9) }
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
