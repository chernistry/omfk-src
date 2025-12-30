import SwiftUI

// MARK: - Liquid Glass Modifier (macOS 26+)

extension View {
    /// Apply Liquid Glass effect on macOS 26+, fallback to ultraThinMaterial on older versions.
    @ViewBuilder
    func liquidGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 14)) -> some View {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

