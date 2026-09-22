import SwiftUI

enum Theme {
    static let corner: CGFloat = 28

    static func accent(_ dark: Bool) -> Color {
        dark ? Color(red: 0.72, green: 0.56, blue: 1.00)
             : Color(red: 0.55, green: 0.38, blue: 0.95)
    }

    static func textPrimary(_ dark: Bool) -> Color {
        dark ? Color(red: 0.93, green: 0.91, blue: 0.99)
             : Color(red: 0.26, green: 0.21, blue: 0.44)
    }

    static func textSecondary(_ dark: Bool) -> Color {
        dark ? Color(red: 0.78, green: 0.74, blue: 0.92).opacity(0.75)
             : Color(red: 0.34, green: 0.29, blue: 0.52).opacity(0.92)
    }

    static func glassTint(_ dark: Bool) -> Color {
        dark ? Color(red: 0.45, green: 0.30, blue: 0.80).opacity(0.40)
             : Color(red: 0.80, green: 0.71, blue: 1.00).opacity(0.36)
    }

    static func rowFill(_ dark: Bool) -> Color {
        dark ? Color(red: 0.66, green: 0.55, blue: 1.00).opacity(0.18)
             : Color.white.opacity(0.34)
    }

    static func gradientFill(_ dark: Bool) -> LinearGradient {
        LinearGradient(
            colors: dark
                ? [Color(red: 0.36, green: 0.25, blue: 0.64).opacity(0.30),
                   Color(red: 0.17, green: 0.11, blue: 0.33).opacity(0.34)]
                : [Color.white.opacity(0.78),
                   Color(red: 0.90, green: 0.85, blue: 1.00).opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func topHighlight(_ dark: Bool) -> LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(dark ? 0.24 : 0.62), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Keep the release build compatible with the macOS 14 SDK used in CI.
    /// Newer systems still render this native translucent material with the app's own highlights.
    func liquidGlass(corner: CGFloat = Theme.corner, tint: Color? = nil) -> some View {
        self.background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    func circularLiquidGlass(tint: Color) -> some View {
        self.background(.ultraThinMaterial, in: Circle())
    }
}
