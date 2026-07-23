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
                    .tint(PosterPalette.pine)
                } header: {
                    Text("拍摄")
                } footer: {
                    Text("网格也可在取景器左上角开关。模拟器与真机均可使用。")
                }

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
        .tint(PosterPalette.pine)
    }
}

private struct ModelRoutingAdvancedView: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                Text("仅在本地演示联调、远端 API 切换或配置失败恢复时使用。")
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
                                                    ? PosterPalette.pine
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
                                        .foregroundStyle(PosterPalette.pine)
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
