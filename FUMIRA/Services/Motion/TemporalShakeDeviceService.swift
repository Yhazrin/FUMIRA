import Foundation
import SwiftUI
import UIKit

/// UIKit shake bridge that avoids creating a third `CMMotionManager` beside the
/// existing capture and decorative motion services.
///
/// Mount ``TemporalShakeResponderBridge`` only for the result screen's short
/// listening window. The embedded view controller joins the window responder
/// chain and feeds discrete `.motionShake` events into this service.
@MainActor
final class DeviceTemporalShakeService: TemporalShakeProviding {
    private var continuation: AsyncStream<TemporalShakeServiceEvent>.Continuation?
    private var isStarted = false
    private var responderIsAttached = false

    init() {}

    func events() -> AsyncStream<TemporalShakeServiceEvent> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if responderIsAttached {
            continuation?.yield(.availability(.motionShakeResponder))
        }
    }

    func stop() {
        guard isStarted || continuation != nil else { return }
        isStarted = false
        continuation?.finish()
        continuation = nil
    }

    /// Called by the mounted responder bridge after it joins the window.
    func responderBridgeDidActivate(_ canReceiveMotion: Bool) {
        responderIsAttached = canReceiveMotion
        guard isStarted else { return }

        guard canReceiveMotion else {
            continuation?.yield(.availability(.fallbackRequired))
            isStarted = false
            continuation?.finish()
            continuation = nil
            return
        }
        continuation?.yield(.availability(.motionShakeResponder))
    }

    /// Ends a live stream if the view owning the responder leaves the window.
    func responderBridgeDidDeactivate() {
        responderIsAttached = false
        guard isStarted else { return }
        continuation?.yield(.availability(.fallbackRequired))
        isStarted = false
        continuation?.finish()
        continuation = nil
    }

    /// Feed used by the responder controller or another existing responder.
    func forwardMotionEnded(
        _ motion: UIEvent.EventSubtype,
        timestamp: TimeInterval
    ) {
        guard isStarted, motion == .motionShake, timestamp.isFinite else { return }
        continuation?.yield(.systemShakeEnded(timestamp: timestamp))
    }
}

/// A zero-chrome SwiftUI bridge whose child controller can participate in the
/// UIKit responder chain. Keep it mounted only while the model is monitoring.
@MainActor
struct TemporalShakeResponderBridge: UIViewControllerRepresentable {
    let service: DeviceTemporalShakeService
    var clock: @Sendable () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
    }

    func makeUIViewController(context: Context) -> TemporalShakeResponderController {
        TemporalShakeResponderController(service: service, clock: clock)
    }

    func updateUIViewController(
        _ uiViewController: TemporalShakeResponderController,
        context: Context
    ) {
        uiViewController.service = service
        uiViewController.clock = clock
    }

    static func dismantleUIViewController(
        _ uiViewController: TemporalShakeResponderController,
        coordinator: ()
    ) {
        uiViewController.detachResponder()
    }
}

@MainActor
final class TemporalShakeResponderController: UIViewController {
    var service: DeviceTemporalShakeService
    var clock: @Sendable () -> TimeInterval

    init(
        service: DeviceTemporalShakeService,
        clock: @escaping @Sendable () -> TimeInterval
    ) {
        self.service = service
        self.clock = clock
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        service.responderBridgeDidActivate(becomeFirstResponder())
    }

    override func viewWillDisappear(_ animated: Bool) {
        detachResponder()
        super.viewWillDisappear(animated)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            service.forwardMotionEnded(motion, timestamp: clock())
        } else {
            super.motionEnded(motion, with: event)
        }
    }

    func detachResponder() {
        if isFirstResponder {
            resignFirstResponder()
        }
        service.responderBridgeDidDeactivate()
    }
}
