import SwiftUI

/// The Chains screen: create named, ordered groups of plugins and edit their contents and notes.
struct ChainsView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var selectedChainID: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    TextField("New chain name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        model.addChain(trimmed)
                        newName = ""
                    }
                }
                .padding()

                List(selection: $selectedChainID) {
                    ForEach(model.chains) { chain in
                        Text(chain.name).tag(chain.id)
                    }
                }
            }
            // Keep the chain list a compact column so the detail side has room
            // to show each chain's plugins comfortably.
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            Group {
                if let id = selectedChainID,
                   let chain = model.chains.first(where: { $0.id == id }) {
                    ChainDetailView(chain: chain)
                } else {
                    Text("Select a chain, or create one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .navigationTitle("Chains")
    }
}

struct ChainDetailView: View {
    @Environment(AppModel.self) private var model
    let chain: Chain
    @State private var addPluginKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chain.name).font(.title2).bold()
            Text("\(chain.pluginIdentityKeys.count) plugins")
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(chain.pluginIdentityKeys.enumerated()), id: \.offset) { index, key in
                    HStack {
                        Text(model.plugin(forIdentity: key)?.name ?? key)
                        if model.plugin(forIdentity: key) == nil {
                            Text("missing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.removePlugin(at: index, from: chain.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Picker("Add plugin", selection: $addPluginKey) {
                    Text("Choose a plugin…").tag(String?.none)
                    ForEach(model.plugins) { plugin in
                        Text("\(plugin.name) — \(plugin.manufacturer)")
                            .tag(String?.some(plugin.identityKey))
                    }
                }
                .labelsHidden()

                Button("Add") {
                    if let key = addPluginKey, let plugin = model.plugin(forIdentity: key) {
                        model.addPlugin(plugin, to: chain.id)
                    }
                }
                .disabled(addPluginKey == nil)

                Spacer()

                Button(role: .destructive) {
                    model.deleteChain(chain)
                } label: {
                    Label("Delete chain", systemImage: "trash")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
