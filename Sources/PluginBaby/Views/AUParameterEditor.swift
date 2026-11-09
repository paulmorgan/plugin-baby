import SwiftUI
import AVFoundation

/// A generic editor the app builds from an Audio Unit's own parameter tree, used
/// when the plugin provides no custom editor window of its own (many Audio Units
/// expose parameters but no UI, or expose a UI the host can't surface). It's the
/// AU analogue of the inline CLAP sliders: one control per parameter, writing
/// straight to the live AU so changes are heard immediately.
struct AUParameterEditorView: View {
    let title: String
    let parameters: [AUParameter]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(parameters.count) parameter\(parameters.count == 1 ? "" : "s")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()

            if parameters.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("This plugin exposes no adjustable parameters.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(parameters, id: \.address) { ParameterRow(param: $0) }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 380, minHeight: 240, idealHeight: 440)
    }
}

/// One live-updating control for a single AU parameter, built on the shared
/// `ParamSliderRow` (writes straight to the live Audio Unit).
private struct ParameterRow: View {
    let param: AUParameter
    @State private var value: Double

    init(param: AUParameter) {
        self.param = param
        _value = State(initialValue: Double(param.value))
    }

    private var style: ParamSliderRow.Style {
        if param.unit == .boolean { return .toggle }
        return param.maxValue > param.minValue ? .continuous : .fixed
    }

    var body: some View {
        ParamSliderRow(
            name: param.displayName,
            valueText: valueLabel,
            range: Double(param.minValue)...Double(max(param.minValue, param.maxValue)),
            style: style,
            value: Binding(
                get: { value },
                set: { value = $0; param.value = AUValue($0) }))   // live write to the AU
    }

    private var valueLabel: String {
        var v = AUValue(value)   // string(fromValue:) needs a pointer to a real variable
        let s = param.string(fromValue: &v)
        return s.isEmpty ? String(format: "%.2f", value) : s
    }
}
