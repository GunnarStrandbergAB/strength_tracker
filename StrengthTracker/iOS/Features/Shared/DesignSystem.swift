#if canImport(SwiftUI)
import SwiftUI

// MARK: - Colors

enum STColors {
    static let primary = Color(hex: "F2CC0D")
    static let background = Color(hex: "121212")
    static let surface = Color(hex: "1E1E1A")
    static let border = Color(hex: "333129")
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "94A3B8")
    static let textTertiary = Color(hex: "64748B")
    static let success = Color(hex: "34D399")
    static let danger = Color(hex: "EF4444")
}

// MARK: - Spacing

enum STSpacing {
    static let cardPadding: CGFloat = 16
    static let setRowHorizontal: CGFloat = 16
    static let setRowVertical: CGFloat = 8
    static let cardGap: CGFloat = 24
    static let inputHeight: CGFloat = 36
    static let checkboxSize: CGFloat = 28
}

// MARK: - Corner Radii

enum STRadius {
    static let input: CGFloat = 8
    static let card: CGFloat = 12
    static let timer: CGFloat = 16
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Custom Checkbox

struct STCheckbox: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isChecked ? STColors.primary : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isChecked ? STColors.primary : STColors.textTertiary,
                            lineWidth: 2
                        )
                )
                .overlay(
                    Group {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(STColors.background)
                        }
                    }
                )
                .frame(width: STSpacing.checkboxSize, height: STSpacing.checkboxSize)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Number Field

struct STNumberField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .multilineTextAlignment(.center)
            .font(.system(size: 14, design: .default))
            .frame(height: STSpacing.inputHeight)
            .background(STColors.background)
            .cornerRadius(STRadius.input)
            .foregroundStyle(STColors.textPrimary)
    }
}

// MARK: - Column Header Label

struct STColumnHeader: View {
    let title: String
    var alignment: Alignment = .center

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(STColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

#endif
