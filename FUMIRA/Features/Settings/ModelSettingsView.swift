import SwiftUI

/// User-facing Settings. Model routing lives under Advanced — not a primary product entry.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("FUMIRA", value: "时间相机")
                }

                Section {
                    Toggle(
                        "取景网格",
                        isOn: Binding(
                            get: { model.isCameraGridEnabled },
                            set: { newValue in
                                if model.isCameraGridEnabled != newValue {
                                    model.toggleCameraGrid()
                                }
                            }
                        )
                    )
                    .tint(PosterPalette.actionBlue)
                } header: {
                    Text("拍摄")
                }

                Section {
                    Picker(
                        "生成服务",
                        selection: Binding(
                            get: { model.modelConfiguration.imageOptionID },
                            set: { optionID in
                                Task {
                                    await model.selectModel(optionID: optionID, for: .image)
                                }
                            }
                        )
                    ) {
                        ForEach(readyImageOptions) { option in
                            Text(option.provider.displayName)
                                .tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("图片生成")
                }

                Section {
                    NavigationLink {
                        ModelRoutingAdvancedView(model: model)
                    } label: {
                        Text("模型路由")
                    }
                } header: {
                    Text("高级")
                }

                if let message = model.lastErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(PosterPalette.errorCoral)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .tint(PosterPalette.skyDeep)
    }

    private var readyImageOptions: [AIModelOption] {
        model.modelCatalog.options(for: .image).filter {
            $0.availability == .ready && $0.provider.imageGenerationRoute != nil
        }
    }
}

private struct ModelRoutingAdvancedView: View {
    let model: AppModel

    var body: some View {
        List {
            ForEach(AIModelRole.allCases, id: \.self) { role in
                Section {
                    ForEach(model.modelCatalog.options(for: role)) { option in
                        Button {
                            Task {
                                await model.selectModel(optionID: option.id, for: role)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(option.displayName)
                                            .foregroundStyle(PosterPalette.ink)
                                        Text(option.availability.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                option.availability == .ready
                                                    ? PosterPalette.actionBlue
                                                    : PosterPalette.mutedInk
                                            )
                                    }
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.modelConfiguration.optionID(for: role) == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PosterPalette.actionBlue)
                                } else if option.availability == .requiresBackend {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(PosterPalette.mutedInk)
                                }
                            }
                        }
                        .disabled(option.availability == .requiresBackend)
                    }
                } header: {
                    Text(role.displayName)
                }
            }
        }
        .navigationTitle("模型路由")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("设置") {
    SettingsView(model: PreviewFixtures.model(phase: .cameraPermission))
}

#Preview("高级 · 模型路由") {
    NavigationStack {
        ModelRoutingAdvancedView(model: PreviewFixtures.model(phase: .cameraPermission))
    }
}
