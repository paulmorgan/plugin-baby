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

/// One live-updating control for a single AU parameter.
private struct ParameterRow: View {
    let param: AUParameter
    @State private var value: Float

    init(param: AUParameter) {
        self.param = param
        _value = State(initialValue: param.value)
    }

    private var isBoolean: Bool { param.unit == .boolean }
    private var hasRange: Bool { param.maxValue > param.minValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(param.displayName.isEmpty ? "Parameter" : param.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if isBoolean {
                Toggle("", isOn: Binding(
                    get: { value >= 0.5 },
                    set: { set($0 ? param.maxValue : param.minValue) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            } else if hasRange {
                Slider(value: Binding(get: { value }, set: { set($0) }),
                       in: param.minValue...param.maxValue)
                    .controlSize(.small)
            }
        }
    }

    private var valueLabel: String {
        var v = value   // string(fromValue:) needs a pointer to a real variable
        let s = param.string(fromValue: &v)
        return s.isEmpty ? String(format: "%.2f", value) : s
    }

    private func set(_ v: Float) {
        value = v
        param.value = v   // write straight to the live Audio Unit
    }
}
