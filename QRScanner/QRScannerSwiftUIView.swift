import SwiftUI

// MARK: - QRScannerSwiftUIView

/// A SwiftUI wrapper for QRScannerView
public struct QRScannerSwiftUIView: UIViewRepresentable {
    public typealias Configuration = QRScannerView.Input

    // MARK: - Properties

    /// Configuration for the scanner view
    private let configuration: Configuration
    
    /// Initial video zoom factor
    private let videoZoomFactor: CGFloat
    
    /// Callback when scanning succeeds
    private let onSuccess: (String) -> Void
    
    /// Callback when scanning fails
    private let onFailure: (QRScannerError) -> Void
    
    /// Callback when torch state changes
    private let onTorchActiveChange: ((Bool) -> Void)?
    
    /// Callback to determine which code to track from multiple detected codes
    private let pickCodeToTrack: (([String]) -> String?)?
    
    /// Binding to control scanning state
    @Binding private var isScanning: Bool
    
    /// Binding to control torch state
    @Binding private var torchActive: Bool

    // MARK: - Initializers

    /// Initialize the QRScannerSwiftUIView
    /// - Parameters:
    ///   - configuration: Scanner configuration
    ///   - isScanning: Binding to control scanning state
    ///   - torchActive: Binding to control torch state
    ///   - videoZoomFactor: Initial video zoom factor
    ///   - onSuccess: Closure called on successful scan
    ///   - onFailure: Closure called on scan failure
    ///   - onTorchActiveChange: Closure called on torch state change
    ///   - pickCodeToTrack: Closure to select which code to track from multiple detected codes
    public init(
        configuration: Configuration = Configuration(),
        isScanning: Binding<Bool> = .constant(true),
        torchActive: Binding<Bool> = .constant(false),
        videoZoomFactor: CGFloat = 1.0,
        onSuccess: @escaping (String) -> Void,
        onFailure: @escaping (QRScannerError) -> Void,
        onTorchActiveChange: ((Bool) -> Void)? = nil,
        pickCodeToTrack: (([String]) -> String?)? = nil
    ) {
        self.configuration = configuration
        self.videoZoomFactor = videoZoomFactor
        _isScanning = isScanning
        _torchActive = torchActive
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onTorchActiveChange = onTorchActiveChange
        self.pickCodeToTrack = pickCodeToTrack
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> QRScannerView {
        let qrScannerView = QRScannerView()

        qrScannerView.configure(delegate: context.coordinator, input: configuration)
        qrScannerView.setVideoZoomFactor(videoZoomFactor)
        context.coordinator.qrScannerView = qrScannerView

        if isScanning {
            qrScannerView.startRunning()
        }

        // Start overlay animation after a short delay to ensure view is properly laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            qrScannerView.startOverlayAnimation()
        }

        return qrScannerView
    }

    public func updateUIView(_ uiView: QRScannerView, context: Context) {
        if isScanning {
            uiView.startRunning()
        } else {
            uiView.stopRunning()
        }
        
        
        uiView.setVideoZoomFactor(videoZoomFactor)

        uiView.setTorchActive(isOn: torchActive)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            isScanning: $isScanning,
            torchActive: $torchActive,
            onSuccess: onSuccess,
            onFailure: onFailure,
            onTorchActiveChange: onTorchActiveChange,
            pickCodeToTrack: pickCodeToTrack
        )
    }

    // MARK: - Coordinator

    /// Coordinator to handle QRScannerViewDelegate callbacks
    public class Coordinator: NSObject, QRScannerViewDelegate {
        @Binding private var isScanning: Bool
        @Binding private var torchActive: Bool

        private let onSuccess: (String) -> Void
        private let onFailure: (QRScannerError) -> Void
        private let onTorchActiveChange: ((Bool) -> Void)?
        private let pickCodeToTrack: (([String]) -> String?)?

        weak var qrScannerView: QRScannerView?

        init(
            isScanning: Binding<Bool>,
            torchActive: Binding<Bool>,
            onSuccess: @escaping (String) -> Void,
            onFailure: @escaping (QRScannerError) -> Void,
            onTorchActiveChange: ((Bool) -> Void)?,
            pickCodeToTrack: (([String]) -> String?)?
        ) {
            _isScanning = isScanning
            _torchActive = torchActive
            self.onSuccess = onSuccess
            self.onFailure = onFailure
            self.onTorchActiveChange = onTorchActiveChange
            self.pickCodeToTrack = pickCodeToTrack
        }

        public func qrScannerView(_ qrScannerView: QRScannerView, didSuccess code: String) {
            onSuccess(code)
        }

        public func qrScannerView(
            _ qrScannerView: QRScannerView,
            didFailure error: QRScannerError
        ) {
            onFailure(error)
        }

        public func qrScannerView(_ qrScannerView: QRScannerView, didChangeTorchActive isOn: Bool) {
            Task { @MainActor in
                self.torchActive = isOn
            }
            onTorchActiveChange?(isOn)
        }

        public func qrScannerView(_ qrScannerView: QRScannerView, pickCodeToTrackFrom codes: [String]) -> String? {
            return pickCodeToTrack?(codes) ?? codes.first
        }
    }
}
