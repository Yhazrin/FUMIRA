import Combine
import Foundation

enum PairingConnectionState: Equatable, Sendable {
    case idle
    case checkingServer
    case serverReady
    case waitingForDesktop
    case paired
    case disconnected
    case invalidCode
    case unavailable(String)

    var title: String {
        switch self {
        case .idle: "未连接"
        case .checkingServer: "正在检查服务器"
        case .serverReady: "配对服务器在线"
        case .waitingForDesktop: "等待桌面端确认"
        case .paired: "已配对"
        case .disconnected: "连接已断开"
        case .invalidCode: "连接码无效"
        case .unavailable: "服务器不可用"
        }
    }

    var detail: String {
        switch self {
        case .idle: "扫描桌面端二维码开始联机"
        case .checkingServer: "正在确认配对服务是否可达"
        case .serverReady: "服务器在线，等待桌面端二维码"
        case .waitingForDesktop: "手机已完成握手，等待桌面端上线"
        case .paired: "手机与网页端握手完成"
        case .disconnected: "网页端已离线，可重新扫描二维码"
        case .invalidCode: "请确认二维码或 6 位连接码"
        case let .unavailable(message): message
        }
    }
}

enum GenerationServerState: Equatable, Sendable {
    case unknown
    case checking
    case ready(mode: String)
    case unavailable

    var title: String {
        switch self {
        case .unknown: "未检查"
        case .checking: "检查中"
        case let .ready(mode): mode == "live" ? "生成服务在线" : "生成服务为模拟模式"
        case .unavailable: "生成服务器未连接"
        }
    }

    var detail: String {
        switch self {
        case .unknown: ""
        case .checking: "正在检查 8787 服务"
        case let .ready(mode): mode == "live" ? "可以开始拍摄" : "不会调用真实生图服务"
        case .unavailable: "拍摄会一直等待，直到最终显示超时"
        }
    }
}

enum FUMIRAPairingConfiguration {
    static var baseURL: URL? {
        if let value = ProcessInfo.processInfo.environment["FUMIRA_PAIRING_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty,
           let url = URL(string: value)
        {
            return normalized(url)
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "FUMIRA_PAIRING_BASE_URL") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return normalized(url)
            }
        }

        return nil
    }

    private static func normalized(_ url: URL) -> URL {
        guard url.absoluteString.hasSuffix("/") else { return url }
        return URL(string: String(url.absoluteString.dropLast())) ?? url
    }
}

@MainActor
final class PairingClient: ObservableObject {
    @Published private(set) var state: PairingConnectionState = .idle
    @Published private(set) var generationServerState: GenerationServerState = .unknown
    @Published private(set) var sessionCode: String?
    @Published private(set) var endpointDescription: String?

    private let urlSession: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var baseURL: URL?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func checkServer() async {
        await checkGenerationServer()

        guard let baseURL = FUMIRAPairingConfiguration.baseURL else {
            state = .unavailable("未配置配对服务器地址")
            return
        }

        self.baseURL = baseURL
        state = .checkingServer
        do {
            var request = URLRequest(url: baseURL.appending(path: "api/health"))
            request.timeoutInterval = 4
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let health = try JSONDecoder().decode(PairingHealthResponse.self, from: data)
            guard health.ok, health.pairing.ready else {
                throw URLError(.cannotConnectToHost)
            }
            state = .serverReady
        } catch {
            state = .unavailable("配对服务器未启动或手机不在同一局域网")
        }
    }

    private func checkGenerationServer() async {
        guard let baseURL = FUMIRAAPIConfiguration.baseURL else {
            generationServerState = .unavailable
            return
        }

        generationServerState = .checking
        do {
            var request = URLRequest(url: baseURL.appending(path: "health"))
            request.timeoutInterval = 4
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let health = try JSONDecoder().decode(GenerationHealthResponse.self, from: data)
            generationServerState = health.ok && health.generation.ready
                ? .ready(mode: health.generation.mode)
                : .unavailable
        } catch {
            generationServerState = .unavailable
        }
    }

    func connect(sessionCode rawCode: String) async {
        guard let baseURL else {
            await checkServer()
            guard let baseURL = self.baseURL else { return }
            await connect(baseURL: baseURL, sessionCode: rawCode)
            return
        }
        await connect(baseURL: baseURL, sessionCode: rawCode)
    }

    func connect(scannedPayload: String) async {
        guard let payloadURL = URL(string: scannedPayload),
              let sessionCode = Self.sessionCode(from: payloadURL)
        else {
            state = .invalidCode
            return
        }

        let scannedBaseURL = Self.baseURL(from: payloadURL) ?? baseURL
        guard let scannedBaseURL else {
            state = .unavailable("二维码中没有可用的服务器地址")
            return
        }

        baseURL = scannedBaseURL
        await connect(baseURL: scannedBaseURL, sessionCode: sessionCode)
    }

    func stop() {
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func connect(baseURL: URL, sessionCode rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else {
            state = .invalidCode
            return
        }

        stop()
        self.baseURL = baseURL
        sessionCode = code
        endpointDescription = baseURL.absoluteString
        state = .checkingServer

        do {
            var request = URLRequest(url: baseURL.appending(path: "api/session/\(code)"))
            request.timeoutInterval = 4
            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                state = .invalidCode
                return
            }

            var components = URLComponents(
                url: baseURL.appending(path: "ws"),
                resolvingAgainstBaseURL: false
            )
            components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
            components?.queryItems = [
                URLQueryItem(name: "session", value: code),
                URLQueryItem(name: "role", value: "mobile"),
            ]
            guard let webSocketURL = components?.url else { throw URLError(.badURL) }

            let task = urlSession.webSocketTask(with: webSocketURL)
            socket = task
            task.resume()
            state = .waitingForDesktop
            startReceiveLoop()
            startHeartbeat()
        } catch {
            state = .unavailable("无法连接配对服务器，请确认电脑端已启动")
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let socket = self.socket else { return }
                    let message = try await socket.receive()
                    self.handle(message)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.state = .disconnected
                    return
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let socket = self.socket else { return }
                try? await socket.send(.string("{\"type\":\"ping\"}"))
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .string(value):
            data = Data(value.utf8)
        case let .data(value):
            data = value
        @unknown default:
            return
        }

        guard let envelope = try? JSONDecoder().decode(PairingEnvelope.self, from: data) else { return }
        switch envelope.type {
        case "handshake.accepted":
            state = envelope.peerConnected == true ? .paired : .waitingForDesktop
        case "pairing.status":
            switch envelope.state {
            case "paired": state = .paired
            case "waiting_for_desktop": state = .waitingForDesktop
            case "waiting_for_phone": state = .waitingForDesktop
            default: break
            }
        case "peer.disconnected":
            state = .waitingForDesktop
        default:
            break
        }
    }

    private static func sessionCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == "session" })?.value
            ?? components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private static func baseURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.scheme == "fumira" {
            guard let value = components.queryItems?.first(where: { $0.name == "server" })?.value,
                  let serverURL = URL(string: value)
            else { return nil }
            return normalized(serverURL)
        }

        guard let scheme = components.scheme, let host = components.host else { return nil }
        var server = URLComponents()
        server.scheme = scheme
        server.host = host
        server.port = components.port
        return server.url
    }

    private static func normalized(_ url: URL) -> URL {
        guard url.absoluteString.hasSuffix("/") else { return url }
        return URL(string: String(url.absoluteString.dropLast())) ?? url
    }
}

private struct PairingHealthResponse: Decodable {
    let ok: Bool
    let pairing: PairingHealth
}

private struct PairingHealth: Decodable {
    let ready: Bool
}

private struct GenerationHealthResponse: Decodable {
    let ok: Bool
    let generation: GenerationHealth
}

private struct GenerationHealth: Decodable {
    let ready: Bool
    let mode: String
}

private struct PairingEnvelope: Decodable {
    let type: String
    let state: String?
    let peerConnected: Bool?
}
