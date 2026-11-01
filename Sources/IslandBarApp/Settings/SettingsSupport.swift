import IslandCore
import SwiftUI

extension SettingsStore {
    /// Two-way binding to any setting; writes go through `update(_:)` so they are persisted.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// Slider with a label and formatted value, for the many numeric settings.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        LabeledContent {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

/// Secondary explanatory text under a control.
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum SettingsFormat {
    static func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }
    static func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func multiplier(_ value: Double) -> String { String(format: "%.2f×", value) }
}
