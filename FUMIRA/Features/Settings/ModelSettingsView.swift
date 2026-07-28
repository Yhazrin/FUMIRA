import SwiftUI

/// User-facing Settings. Model routing lives under Advanced — not a primary product entry.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("产品", value: "FUMIRA 时间相机")
                    Text("通用偏好保持克制。取景器顶部只放真实相机控件；模型路由属于开发与联调配置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
                .posterStaggerReveal(index: 0)

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
                } footer: {
                    Text("网格也可在取景器左上角开关。")
                }
                .posterStaggerReveal(index: 1)

                Section {
                    Picker(
                        "图片生成服务",
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

                    if let option = model.modelOption(for: .image) {
                        LabeledContent("当前模型", value: option.displayName)
                        Text(option.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("图片生成")
                } footer: {
                    Text("选择只影响最终图片生成。图片理解与故事仍使用各自的模型路由，服务密钥保存在 FUMIRA 后台。")
                }
                .posterStaggerReveal(index: 2)

                Section {
                    NavigationLink {
                        ModelRoutingAdvancedView(model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("模型路由")
                            Text("识图 / 故事 / 生图 · 开发与联调")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("高级")
                } footer: {
                    Text("App 只保存路由 ID。供应商密钥与具体模型版本由 FUMIRA 后台管理，不会写入客户端。普通使用无需进入此页。")
                }
                .posterStaggerReveal(index: 3)

                if let message = model.lastErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(PosterPalette.errorCoral)
                    }
                    .posterStaggerReveal(index: 4)
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
            Section {
                Text("仅在本地调试、远端 API 切换或配置失败恢复时使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
                                    Text("\(option.provider.displayName) · \(option.detail)")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.displayName)
                        Text(role.shortDescription)
                            .font(.caption2)
                            .textCase(nil)
                    }
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
