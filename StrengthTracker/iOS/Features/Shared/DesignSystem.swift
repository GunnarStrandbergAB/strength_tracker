#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared
#if canImport(UIKit)
import UIKit
#endif

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
    static let inputHeight: CGFloat = 44
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
    let onToggle: () -> Void

    init(isChecked: Bool, onToggle: @escaping () -> Void) {
        self.isChecked = isChecked
        self.onToggle = onToggle
    }

    var body: some View {
        Button {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            onToggle()
        } label: {
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
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Number Field

/// Input-only policy. Stored kg precision is never changed by merely visiting a field.
enum STNumericKind: Equatable {
    case weight, reps, rpe, rir
    var keyboard: UIKeyboardType { self == .reps ? .numberPad : .decimalPad }
    var error: String {
        switch self {
        case .weight: return "Enter a weight with at most two decimal places."
        case .reps: return "Enter a whole number of reps."
        case .rpe: return "Enter RPE from 1 to 10, or clear the field."
        case .rir: return "Enter RIR from 0 to 9, or clear the field."
        }
    }
    func acceptedDraft(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let pattern = self == .reps ? "^[0-9]*$" : self == .weight ? "^-?[0-9]*([.,][0-9]*)?$" : "^[0-9]*([.,][0-9]*)?$"
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        if self != .reps, let separator = text.firstIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = text[text.index(after: separator)...]
            if fraction.count > 2 {
                // Pasted redundant zeros are harmless; never silently truncate significant digits.
                guard fraction.dropFirst(2).allSatisfy({ $0 == "0" }) else { return nil }
                text = String(text[...separator]) + fraction.prefix(2)
            }
        }
        if self == .reps, !text.isEmpty {
            guard let integer = Int(text), Int(exactly: Double(integer)) != nil else { return nil }
        } else if let number = Double(normalized), !number.isFinite { return nil }
        return text
    }
    enum Result: Equatable { case value(Double?), invalid }
    func parsed(_ text: String) -> Result {
        guard let draft = acceptedDraft(text) else { return .invalid }
        if draft.isEmpty { return .value(nil) }
        guard let value = Double(draft.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return .invalid }
        if self == .rpe && !(1...10).contains(value) { return .invalid }
        if self == .rir && !(0...9).contains(value) { return .invalid }
        return .value(value)
    }
    static func formatted(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}

@MainActor
final class STFieldNavigation {
    private struct WeakField { weak var value: STNumericTextField? }
    private var fields: [Int: WeakField] = [:]
    func register(_ field: STNumericTextField, at index: Int) { fields[index] = WeakField(value: field) }
    func remove(_ field: STNumericTextField, at index: Int) {
        if fields[index]?.value === field { fields[index] = nil }
    }
    func neighbor(of index: Int, direction: Int) -> STNumericTextField? {
        let indices = fields.keys.filter { fields[$0]?.value?.window != nil }.sorted()
        return (direction > 0 ? indices.first { $0 > index } : indices.last { $0 < index }).flatMap { fields[$0]?.value }
    }
}

extension Notification.Name { static let commitWorkoutNotes = Notification.Name("ST.commitWorkoutNotes") }

final class STNumericTextField: UITextField {
    static weak var active: STNumericTextField?
    /// Resigning invokes the delegate synchronously, before callers enqueue completion/Finish.
    @discardableResult static func commitActiveInput() -> Bool {
        if let active, active.isFirstResponder {
            guard active.resignFirstResponder() else { return false }
        } else {
            active = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        NotificationCenter.default.post(name: .commitWorkoutNotes, object: nil)
        return true
    }
}

struct STNumberField: UIViewRepresentable {
    let value: Double?
    let kind: STNumericKind
    let label: String
    let navigation: STFieldNavigation
    let position: Int
    let onCommit: (Double?) -> Void
    let onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> STNumericTextField {
        let field = STNumericTextField()
        field.delegate = context.coordinator
        field.keyboardType = kind.keyboard
        field.keyboardAppearance = .dark
        field.overrideUserInterfaceStyle = .dark
        field.returnKeyType = .done
        field.textAlignment = .center
        field.textColor = UIColor(STColors.textPrimary)
        field.tintColor = UIColor(STColors.primary)
        field.backgroundColor = UIColor(STColors.background)
        field.layer.cornerRadius = STRadius.input
        field.layer.borderWidth = 1.5
        field.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .monospacedDigitSystemFont(ofSize: 22, weight: .semibold))
        field.adjustsFontForContentSizeCategory = true
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 16
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.attributedPlaceholder = NSAttributedString(string: "—", attributes: [.foregroundColor: UIColor(STColors.textSecondary)])
        field.accessibilityLabel = label
        field.accessibilityHint = "Double tap to replace the value. Use Next or Done above the keyboard."
        field.text = STNumericKind.formatted(value)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.attach(to: field)
        navigation.register(field, at: position)
        return field
    }
    func updateUIView(_ field: STNumericTextField, context: Context) {
        context.coordinator.parent = self
        if !field.isFirstResponder { field.text = STNumericKind.formatted(value) }
        field.accessibilityLabel = label
        context.coordinator.updateAppearance()
    }
    static func dismantleUIView(_ field: STNumericTextField, coordinator: Coordinator) {
        // Removed rows must not write their stale drafts back into a converted/deleted model.
        coordinator.discarding = true
        field.resignFirstResponder()
        coordinator.parent.navigation.remove(field, at: coordinator.parent.position)
    }

    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: STNumberField
        weak var field: STNumericTextField?
        var seed = ""
        var dirty = false
        var discarding = false
        private var previous: UIBarButtonItem?
        private var next: UIBarButtonItem?
        init(_ parent: STNumberField) { self.parent = parent }
        func attach(to field: STNumericTextField) {
            self.field = field
            let bar = UIToolbar()
            bar.barStyle = .black
            bar.overrideUserInterfaceStyle = .dark
            bar.tintColor = UIColor(STColors.primary)
            let previous = UIBarButtonItem(title: "Previous", style: .plain, target: self, action: #selector(goPrevious))
            let next = UIBarButtonItem(title: "Next", style: .plain, target: self, action: #selector(goNext))
            let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
            previous.accessibilityIdentifier = "workout.input.previous"
            next.accessibilityIdentifier = "workout.input.next"
            done.accessibilityIdentifier = "workout.input.done"
            bar.items = [previous, next, .flexibleSpace(), done]
            bar.sizeToFit()
            field.inputAccessoryView = bar
            self.previous = previous; self.next = next
            NotificationCenter.default.addObserver(self, selector: #selector(ensureVisible), name: UIResponder.keyboardDidShowNotification, object: nil)
            updateAppearance()
        }
        func updateAppearance() {
            field?.layer.borderColor = UIColor(field?.isFirstResponder == true ? STColors.primary : STColors.border).cgColor
            previous?.isEnabled = parent.navigation.neighbor(of: parent.position, direction: -1) != nil
            next?.isEnabled = parent.navigation.neighbor(of: parent.position, direction: 1) != nil
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            STNumericTextField.active = field
            seed = textField.text ?? ""; dirty = false
            parent.onError(nil)
            updateAppearance()
            // Let UIKit finish the initial tap before selecting. Never reselect during typing.
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, textField.isFirstResponder, !self.dirty else { return }
                textField.selectAll(nil)
                self.ensureVisible()
            }
        }
        @objc private func ensureVisible() {
            guard let field, field.isFirstResponder else { return }
            var ancestor = field.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    scroll.layoutIfNeeded()
                    scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll).insetBy(dx: 0, dy: -24), animated: true)
                    break
                }
                ancestor = view.superview
            }
        }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let original = textField.text ?? ""
            guard let swiftRange = Range(range, in: original) else { return false }
            let proposed = original.replacingCharacters(in: swiftRange, with: string)
            guard let accepted = parent.kind.acceptedDraft(proposed) else {
                parent.onError(parent.kind.error)
                return false
            }
            parent.onError(nil)
            if accepted != proposed {
                textField.text = accepted
                changed(textField)
                return false
            }
            return true
        }
        @objc func changed(_ textField: UITextField) { dirty = (textField.text ?? "") != seed }
        func commit() -> Bool {
            guard !discarding, let field else { return true }
            guard dirty else { return true }
            switch parent.kind.parsed(field.text ?? "") {
            case .invalid:
                parent.onError(parent.kind.error)
                UIAccessibility.post(notification: .announcement, argument: parent.kind.error)
                return false
            case .value(let value):
                dirty = false
                didCommitDuringVisit = true
                seed = STNumericKind.formatted(value)
                field.text = seed
                parent.onCommit(value)
                parent.onError(nil)
                return true
            }
        }
        func textFieldShouldEndEditing(_ textField: UITextField) -> Bool { commit() }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if STNumericTextField.active === field { STNumericTextField.active = nil }
            // Untouched visits must adopt external updates without generating an edit.
            if (textField.text ?? "") == seed && !discarding {
                // A newly committed model may not have reached SwiftUI yet; keep its display.
                if !didCommitDuringVisit { textField.text = STNumericKind.formatted(parent.value) }
            }
            didCommitDuringVisit = false
            updateAppearance()
        }
        private var didCommitDuringVisit = false
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder() }
        @objc func done() { field?.resignFirstResponder() }
        @objc func goPrevious() { move(-1) }
        @objc func goNext() { move(1) }
        private func move(_ direction: Int) {
            guard let destination = parent.navigation.neighbor(of: parent.position, direction: direction), field?.resignFirstResponder() == true else { return }
            destination.becomeFirstResponder()
        }
    }
}

/// Shared by ordinary sets and drop segments; one keyboard-navigation group per row.
struct STSetValuesEditor: View {
    let weight: Double?
    let reps: Int?
    let intensity: Double?
    let showIntensity: Bool
    let intensityMetric: IntensityMetric
    let weightUnit: WeightUnit
    var weightLabel: String? = nil
    let context: String
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onIntensityChange: (Double?) -> Void
    @State private var navigation = STFieldNavigation()
    @State private var errors: [Int: String] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var inputHeight = 52.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                number(weight.map(weightUnit.fromKg), kind: .weight, title: weightLabel ?? weightUnit.symbol, position: 0) { onWeightChange($0.map(weightUnit.toKg)) }
                number(reps.map(Double.init), kind: .reps, title: "Reps", position: 1) { onRepsChange($0.flatMap { Int(exactly: $0) }) }
                if showIntensity {
                    number(intensity, kind: intensityMetric == .rpe ? .rpe : .rir, title: intensityMetric.displayName, position: 2, commit: onIntensityChange)
                }
            }
            ForEach(errors.keys.sorted(), id: \.self) { key in
                Text(errors[key] ?? "").font(.caption).foregroundStyle(STColors.danger).accessibilityLabel("Input error: \(errors[key] ?? "")")
            }
        }
    }
    private func number(_ value: Double?, kind: STNumericKind, title: String, position: Int, commit: @escaping (Double?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(STColors.textSecondary)
            STNumberField(value: value, kind: kind, label: "\(context), \(title)", navigation: navigation, position: position,
                onCommit: commit, onError: { errors[position] = $0 })
                .frame(height: inputHeight)
        }.frame(maxWidth: .infinity)
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

// MARK: - Navigation Bar Style

struct STNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func stNavigationBarStyle() -> some View {
        modifier(STNavigationBarStyle())
    }
}

// MARK: - Typography Font Extensions

extension Font {
    static let stTitle = Font.system(size: 18, weight: .bold)
    static let stBody = Font.system(size: 14)
    static let stCaption = Font.system(size: 12)
    static let stLabel = Font.system(size: 10, weight: .bold)
    static let stTimer = Font.system(size: 20, weight: .bold, design: .default)
    static let stSetNumber = Font.system(size: 14, weight: .bold)
}

#endif
