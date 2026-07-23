import SwiftUI

struct ModelSettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("App 只保存路由 ID。供应商密钥与具体模型版本由未来的 FUMIRA 后台管理，不会写入客户端。")
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
                                                        ? PosterPalette.parkGreen
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
                                            .foregroundStyle(PosterPalette.timeBlue)
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

                if let message = model.lastErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(PosterPalette.errorCoral)
                    }
                }
            }
            .navigationTitle("模型后台")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .tint(PosterPalette.timeBlue)
    }
}

#Preview {
    ModelSettingsView(model: PreviewFixtures.model(phase: .viewfinder))
}
