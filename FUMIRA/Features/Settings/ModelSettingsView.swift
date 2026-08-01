import SwiftUI

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
                    .tint(ClayPalette.orange)
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
                                            .foregroundStyle(ClayPalette.charcoal)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.modelConfiguration.imageOptionID == option.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ClayPalette.orange)
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
                            .foregroundStyle(ClayPalette.error)
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
        .tint(ClayPalette.orangeRim)
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
                                            .foregroundStyle(ClayPalette.charcoal)
                                        Text(option.availability.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                option.availability == .ready
                                                    ? ClayPalette.orange
                                                    : ClayPalette.textMuted
                                            )
                                    }
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.modelConfiguration.optionID(for: role) == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ClayPalette.orange)
                                } else if option.availability == .requiresBackend {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(ClayPalette.textMuted)
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

/// 拍摄页面的设置视图，包含翻转摄像头和 Web Demo 连接码
struct ViewfinderSettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sessionCode: String = "------"
    @State private var isLoadingSession = false
    @State private var serverURL: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await model.switchCameraLens() }
                        dismiss()
                    } label: {
                        Label("翻转摄像头", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!model.canSwitchCamera || model.isPipelineBusy)

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
                    .tint(ClayPalette.orange)
                } header: {
                    Text("拍摄")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("连接码")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isLoadingSession {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(sessionCode)
                                    .font(.title3.monospaced().weight(.bold))
                                    .foregroundStyle(ClayPalette.orange)
                            }
                        }

                        if !serverURL.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("手机浏览器访问")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(serverURL)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(ClayPalette.orange)
                                    .textSelection(.enabled)
                            }
                        }

                        Button {
                            Task { await fetchSessionCode() }
                        } label: {
                            Label("刷新连接码", systemImage: "arrow.clockwise")
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Web Demo")
                } footer: {
                    Text("在电脑浏览器打开 Web Demo 后，用手机扫描二维码或输入连接码进行控制。")
                }

                Section {
                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Label("高级设置", systemImage: "gearshape.2")
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
        .tint(ClayPalette.orangeRim)
        .task {
            await fetchSessionCode()
        }
    }

    private func fetchSessionCode() async {
        isLoadingSession = true
        defer { isLoadingSession = false }

        // 尝试从本地服务器获取 session
        let hosts = ["localhost", "10.220.32.125"]
        let port = 3210

        for host in hosts {
            let urlString = "http://\(host):\(port)/api/session"
            guard let url = URL(string: urlString) else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sessionId = json["sessionId"] as? String {
                    sessionCode = sessionId
                    serverURL = "http://\(host):\(port)/mobile.html?session=\(sessionId)"
                    return
                }
            } catch {
                continue
            }
        }

        // 服务器未连接
        sessionCode = "未连接"
        serverURL = ""
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
