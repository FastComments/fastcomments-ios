import SwiftUI

/// ViewModifier that shows a "Demo Mode" banner at the top of the view.
struct DemoBannerModifier: ViewModifier {
    let isDemo: Bool

    func body(content: Content) -> some View {
        if isDemo {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Demo Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)

                content
            }
        } else {
            content
        }
    }
}

extension View {
    func demoBanner(isDemo: Bool) -> some View {
        modifier(DemoBannerModifier(isDemo: isDemo))
    }
}
