import AVFoundation
import SwiftUI
import UIKit

struct PairingQRCodeScannerView: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PairingScannerRepresentable { payload in
                onScanned(payload)
                dismiss()
            }
            .ignoresSafeArea()
            .navigationTitle("扫描桌面二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct PairingScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    func makeUIViewController(context: Context) -> PairingScannerViewController {
        let controller = PairingScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PairingScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScanned: (String) -> Void
        private var didScan = false

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue,
                  !value.isEmpty
            else { return }

            didScan = true
            onScanned(value)
        }
    }
}

private final class PairingScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let unavailableLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCapture() {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            showUnavailable("请在系统设置中允许 FUMIRA 使用相机")
            return
        }

        let configure: () -> Void = { [weak self] in
            guard let self,
                  let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input)
            else {
                DispatchQueue.main.async { self?.showUnavailable("无法访问相机") }
                return
            }

            self.captureSession.beginConfiguration()
            self.captureSession.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard self.captureSession.canAddOutput(output) else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { self.showUnavailable("相机不支持二维码扫描") }
                return
            }
            self.captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self.delegate, queue: .main)
            output.metadataObjectTypes = [.qr]
            self.captureSession.commitConfiguration()

            DispatchQueue.main.async {
                let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
                preview.videoGravity = .resizeAspectFill
                self.previewLayer = preview
                self.view.layer.insertSublayer(preview, at: 0)
                self.previewLayer?.frame = self.view.bounds
            }
            self.captureSession.startRunning()
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async(execute: configure)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else {
                    DispatchQueue.main.async { [weak self] in
                        self?.showUnavailable("需要相机权限才能扫描二维码")
                    }
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async(execute: configure)
            }
        default:
            showUnavailable("请在系统设置中允许 FUMIRA 使用相机")
        }
    }

    private func showUnavailable(_ message: String) {
        unavailableLabel.text = message
        unavailableLabel.textColor = .white
        unavailableLabel.textAlignment = .center
        unavailableLabel.numberOfLines = 0
        unavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        if unavailableLabel.superview == nil {
            view.addSubview(unavailableLabel)
            NSLayoutConstraint.activate([
                unavailableLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
                unavailableLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
                unavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
    }
}
