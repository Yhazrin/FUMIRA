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

/// 拍摄页面的设置视图，包含翻转摄像头和桌面端实时配对。
struct ViewfinderSettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pairing = PairingClient()
    @State private var manualCode = ""
    @State private var isScannerPresented = false

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
                    HStack(spacing: 12) {
                        Circle()
                            .fill(pairing.state == .paired ? ClayPalette.parkGreen : ClayPalette.orange)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pairing.state.title)
                                .font(.subheadline.weight(.semibold))
                            Text(pairing.state.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(
                                pairing.generationServerState == .unavailable
                                    ? ClayPalette.error
                                    : ClayPalette.orange
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pairing.generationServerState.title)
                                .font(.subheadline.weight(.semibold))
                            Text(pairing.generationServerState.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Button {
                        isScannerPresented = true
                    } label: {
                        Label("扫描桌面二维码", systemImage: "qrcode.viewfinder")
                    }

                    HStack(spacing: 10) {
                        TextField("输入 6 位连接码", text: $manualCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: manualCode) { _, newValue in
                                manualCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            }

                        Button("连接") {
                            Task { await pairing.connect(sessionCode: manualCode) }
                        }
                        .disabled(manualCode.count != 6)
                    }

                    if let code = pairing.sessionCode {
                        LabeledContent("当前连接码", value: code)
                            .font(.caption.monospaced())
                    }

                    if let endpoint = pairing.endpointDescription {
                        Text(endpoint)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Button {
                        Task { await pairing.checkServer() }
                    } label: {
                        Label("检查配对服务器", systemImage: "server.rack")
                    }
                    .font(.subheadline)
                } header: {
                    Text("桌面联机")
                } footer: {
                    Text("请先在电脑打开 FUMIRA 网页端。网页端二维码出现后，用这里的扫描器完成握手；只有双方都在线才会显示“已配对”。")
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
            await pairing.checkServer()
        }
        .sheet(isPresented: $isScannerPresented) {
            PairingQRCodeScannerView { payload in
                Task { await pairing.connect(scannedPayload: payload) }
            }
        }
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
