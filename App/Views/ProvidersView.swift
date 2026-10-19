import SwiftUI

struct ProvidersView: View {
    @State private var providers: [VideoProvider] = ProviderStore.all()
    @State private var adultGate = AdultGate.on

    @State private var showAdd = false
    @State private var newP = VideoProvider(id: "", name: "", endpoint: "", key: nil, adult: false, enabled: true)

    var body: some View {
        NavigationStack {
            Form {
                Section("成人内容锁") {
                    Toggle("允许成人源（18+）", isOn: $adultGate)
                        .onChange(of: adultGate) { v in
                            AdultGate.on = v
                        }
                    Label("成人源默认隐藏；开启后才会在搜索里显示。内容来源的合法性由添加者负责", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("在线源 \(providers.count)") {
                    ForEach($providers) { $p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.name).lineLimit(1)
                                if p.adult {
                                    Text("18+")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(.red.opacity(0.85)))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                Toggle("", isOn: $p.enabled)
                                    .labelsHidden()
                            }
                            Text(p.endpoint)
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        newP = VideoProvider(id: UUID().uuidString, name: "", endpoint: "", key: "", adult: false, enabled: true)
                        showAdd = true
                    } label: {
                        Label("添加在线源", systemImage: "plus.circle")
                    }
                    Button(role: .destructive) {
                        deleteLast()
                    } label: {
                        Label("删除最后一个源", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("在线源")
            .sheet(isPresented: $showAdd) {
                AddProviderSheet(provider: $newP) {
                    addProvider()
                    showAdd = false
                }
            }
        }
        .onAppear {
            providers = ProviderStore.all()
            adultGate = AdultGate.on
        }
    }

    private func addProvider() {
        guard !newP.name.isEmpty, !newP.endpoint.isEmpty else { return }
        if let i = providers.firstIndex(where: { $0.id == newP.id }) {
            providers[i] = newP
        } else {
            providers.append(newP)
        }
        persist()
    }

    private func deleteLast() {
        guard !providers.isEmpty else { return }
        providers.removeLast()
        persist()
    }

    private func persist() {
        ProviderStore.save(providers)
    }
}

struct AddProviderSheet: View {
    @Binding var provider: VideoProvider
    let onSave: () -> Void

    @State private var name = ""
    @State private var endpoint = ""
    @State private var key = ""
    @State private var adult = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：我的源", text: $name)
                }
                Section("接口地址（{q} 为关键词占位）") {
                    TextField("https://…?q={q}", text: $endpoint)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Key（可选）", text: $key)
                    Toggle("成人源（18+）", isOn: $adult)
                    Label("出参需为 JSON：title / url(直链) / thumb / duration；url 必须 mp4、m3u8、webm、ogg、mp3 等可播直链", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加在线源")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        provider.name = name
                        provider.endpoint = endpoint
                        provider.key = key.isEmpty ? nil : key
                        provider.adult = adult
                        onSave()
                    }
                    .disabled(name.isEmpty || endpoint.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onSave()
                    }
                }
            }
            .onAppear {
                name = provider.name
                endpoint = provider.endpoint
                key = provider.key ?? ""
                adult = provider.adult
            }
        }
    }
}
