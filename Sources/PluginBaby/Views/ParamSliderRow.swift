import SwiftUI

/// One labelled control for a plugin parameter — name, current value, and a
/// slider or toggle. Shared by the inline CLAP parameters (detail panel) and the
/// generic Audio Unit editor, which previously had near-identical copies.
struct ParamSliderRow: View {
    /// How the parameter is adjusted.
    enum Style { case continuous, stepped, toggle, fixed }

    var name: String
    var valueText: String
    var range: ClosedRange<Double>   // lowerBound <= upperBound (callers clamp)
    var style: Style
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name.isEmpty ? "Parameter" : name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            switch style {
            case .toggle:
                Toggle("", isOn: Binding(
                    get: { value >= midpoint },
                    set: { value = $0 ? range.upperBound : range.lowerBound }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            case .stepped:
                Slider(value: $value, in: range, step: 1).controlSize(.small)
            case .continuous:
                Slider(value: $value, in: range).controlSize(.small)
            case .fixed:
                EmptyView()   // unadjustable: value shown above, no control
            }
        }
    }

    private var midpoint: Double { (range.lowerBound + range.upperBound) / 2 }
}
