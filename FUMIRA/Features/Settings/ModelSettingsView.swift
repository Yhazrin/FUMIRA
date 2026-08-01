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
                        selection: imageProviderBinding
                    ) {
                        Text(AIProviderKind.miniMax.displayName)
                            .tag(AIProviderKind.miniMax)
                        Text(AIProviderKind.apiMart.displayName)
                            .tag(AIProviderKind.apiMart)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("图片生成")
                } footer: {
                    Text(
                        selectedImageProvider == .apiMart
                            ? "选择中转站后，可在下方指定具体生图模型。"
                            : "MiniMax 直接图生图，保持主体与构图。"
                    )
                }

                if selectedImageProvider == .apiMart {
                    Section {
                        ForEach(apiMartImageOptions) { option in
                            Button {
                                Task {
                                    await model.selectModel(optionID: option.id, for: .image)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.displayName)
                                            .foregroundStyle(PosterPalette.ink)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.modelConfiguration.imageOptionID == option.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(PosterPalette.actionBlue)
                                    }
                                }
                            }
                            .accessibilityAddTraits(
                                model.modelConfiguration.imageOptionID == option.id
                                    ? [.isSelected]
                                    : []
                            )
                        }
                    } header: {
                        Text("中转站模型")
                    }
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

    private var selectedImageProvider: AIProviderKind {
        model.modelCatalog.option(id: model.modelConfiguration.imageOptionID)?.provider
            ?? .miniMax
    }

    private var imageProviderBinding: Binding<AIProviderKind> {
        Binding(
            get: { selectedImageProvider },
            set: { provider in
                Task {
                    await selectImageProvider(provider)
                }
            }
        )
    }

    private var apiMartImageOptions: [AIModelOption] {
        model.modelCatalog.options(for: .image).filter {
            $0.provider == .apiMart
                && $0.availability == .ready
                && $0.provider.imageGenerationRoute != nil
        }
    }

    private var miniMaxImageOptionID: String {
        model.modelCatalog.options(for: .image).first {
            $0.provider == .miniMax && $0.availability == .ready
        }?.id ?? "fumira.image.identity"
    }

    private var defaultAPIMartImageOptionID: String {
        apiMartImageOptions.first?.id ?? "apimart.image.gpt-image-2"
    }

    private func selectImageProvider(_ provider: AIProviderKind) async {
        switch provider {
        case .miniMax:
            await model.selectModel(optionID: miniMaxImageOptionID, for: .image)
        case .apiMart:
            if selectedImageProvider != .apiMart {
                await model.selectModel(optionID: defaultAPIMartImageOptionID, for: .image)
            }
        default:
            break
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
