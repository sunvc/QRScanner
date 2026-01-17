//
//  QRScannerView.swift
//  QRScanner
//
//  Created by wbi on 2019/10/16.
//  Copyright © 2019 Mercari, Inc. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - QRScannerViewDelegate

public protocol QRScannerViewDelegate: AnyObject {
    // Required
    func qrScannerView(_ qrScannerView: QRScannerView, didFailure error: QRScannerError)
    func qrScannerView(_ qrScannerView: QRScannerView, didSuccess code: String)
    // Optional
    func qrScannerView(_ qrScannerView: QRScannerView, didChangeTorchActive isOn: Bool)
}

extension QRScannerViewDelegate {
    public func qrScannerView(_ qrScannerView: QRScannerView, didChangeTorchActive isOn: Bool) {}
}

// MARK: - QRScannerView

@IBDesignable
public class QRScannerView: UIView {
    // MARK: - Input

    public struct Input {
        var focusImage: UIImage?
        var focusImagePadding: CGFloat?
        var videoZoomFactor: CGFloat?
        var metadataObjectTypes: [AVMetadataObject.ObjectType]

        public static var `default`: Input { Self() }

        public init(
            focusImage: UIImage? = nil,
            focusImagePadding: CGFloat? = nil,
            videoZoomFactor: CGFloat? = nil,
            metadataObjectTypes: [AVMetadataObject.ObjectType] = [.qr, .aztec]
        ) {
            self.focusImage = focusImage
            self.focusImagePadding = focusImagePadding
            self.videoZoomFactor = videoZoomFactor
            self.metadataObjectTypes = metadataObjectTypes
        }
    }

    // MARK: - Public Properties

    @IBInspectable
    public var focusImage: UIImage?

    @IBInspectable
    public var focusImagePadding: CGFloat = 8.0

    @IBInspectable
    public var overlayCornerRadius: CGFloat = 30.0

    @IBInspectable
    public var overlayAnimationDuration: Double = 0.6

    @IBInspectable
    public var videoZoomFactor: CGFloat = 1.0

    // MARK: - Public

    /// Configure QR Scanner
    ///
    /// This is the main initialization method for QRScannerView, responsible for setting up all
    /// necessary components and configurations.
    ///
    /// @param delegate Callback delegate for scan results
    /// @param input Configuration parameters, including scan frame image, animation duration, etc.
    public func configure(delegate: QRScannerViewDelegate, input: Input = .default) {
        // Set delegate
        self.delegate = delegate

        // Apply input configuration parameters
        if let focusImage = input.focusImage {
            self.focusImage = focusImage
        }
        if let focusImagePadding = input.focusImagePadding {
            self.focusImagePadding = focusImagePadding
        }

        if let videoZoomFactor = input.videoZoomFactor {
            self.videoZoomFactor = videoZoomFactor
        }

        // Initialize components in order
        configureSession(metadataObjectTypes: input.metadataObjectTypes) // Configure camera session
        addPreviewLayer() // Add preview layer
        setupImageViews() // Setup scan frame image
        setupOverlayMask() // Setup overlay mask
        setupOrientationObserver() // Setup device orientation observer
    }

    /// Start Scanning
    ///
    /// Starts the camera session to begin scanning for QR codes. This method executes on a
    /// background queue to avoid blocking the main thread.
    public func startRunning() {
        guard isAuthorized() else { return } // Check camera authorization
        guard !session.isRunning else { return } // Avoid duplicate start
        metadataQueue.async { [weak self] in
            self?.session.startRunning() // Start session on background queue
        }
    }

    /// Stop Scanning
    ///
    /// Stops the camera session to save resources. This method executes on a background queue.
    public func stopRunning() {
        guard session.isRunning else { return } // Check if session is running
        metadataQueue.async { [weak self] in
            self?.session.stopRunning() // Stop session on background queue
        }
    }

    /// Start Overlay Zoom Animation
    ///
    /// This method creates a zoom-in animation effect, providing visual feedback for the scanning
    /// interface.
    /// The animation starts from 30% scale and gradually zooms to normal size, enhancing user
    /// experience.
    ///
    /// Implementation steps:
    /// 1. Calculate the frame for initial scaled state (30% size)
    /// 2. Create corresponding initial path
    /// 3. Immediately set initial state
    /// 4. Delay execution of zoom animation to normal size
    public func startOverlayAnimation() {
        guard let overlayLayer = overlayLayer else { return }

        // Set initial small size state for animation
        let initialScale: CGFloat = 0.3
        let finalFrame = calculation()
        let centerX = finalFrame.midX
        let centerY = finalFrame.midY
        let scaledWidth = finalFrame.width * initialScale
        let scaledHeight = finalFrame.height * initialScale
        let scaledFrame = CGRect(
            x: centerX - scaledWidth / 2,
            y: centerY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )

        // Create initial small size path
        let initialPath = UIBezierPath(rect: bounds)
        let initialFocusPath = UIBezierPath(
            roundedRect: scaledFrame,
            cornerRadius: overlayCornerRadius * initialScale
        )
        initialPath.append(initialFocusPath.reversing())

        // Immediately set initial state
        overlayLayer.path = initialPath.cgPath
        focusImageView.frame = scaledFrame

        // Delay animation execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateOverlayMaskScale()
        }
    }

    /// Control Device Torch State
    ///
    /// This method controls the device's torch during scanning to help in low-light environments.
    ///
    /// @param isOn Whether to turn on the torch, true for on, false for off
    ///
    /// Safety checks:
    /// - Ensure execution on main thread
    /// - Check if device supports torch
    /// - Check if torch is available
    /// - Ensure scanner is enabled
    public func setTorchActive(isOn: Bool) {
        assert(Thread.isMainThread)

        guard let videoInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let videoDevice = videoInput.device

        guard videoDevice.hasTorch, videoDevice.isTorchAvailable else { return }

        try? videoDevice.lockForConfiguration()
        videoDevice.torchMode = isOn ? .on : .off
        videoDevice.unlockForConfiguration()
    }

    /// Set Video Zoom Factor
    ///
    /// Sets the zoom factor for the video device.
    ///
    /// @param factor The zoom factor to apply.
    /// @param animated Whether to animate the change. Default is true.
    public func setVideoZoomFactor(_ factor: CGFloat, animated: Bool = true) {
        guard let videoInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let videoDevice = videoInput.device

        do {
            try videoDevice.lockForConfiguration()
            defer { videoDevice.unlockForConfiguration() }

            let zoomFactor = max(
                videoDevice.minAvailableVideoZoomFactor,
                min(factor, videoDevice.maxAvailableVideoZoomFactor)
            )

            if animated {
                videoDevice.ramp(toVideoZoomFactor: zoomFactor, withRate: 10.0)
            } else {
                videoDevice.cancelVideoZoomRamp()
                videoDevice.videoZoomFactor = zoomFactor
            }
        } catch {
            print("Failed to set video zoom factor: \(error)")
        }
    }

    /// Layout Subviews
    ///
    /// System automatically calls this method when view bounds change (e.g., device rotation,
    /// resize).
    /// Responsible for updating layout of preview layer and scanning area, ensuring correct display
    /// across different sizes.
    ///
    /// Main functions:
    /// - Call super.layoutSubviews
    /// - Update preview layer frame to fit new bounds
    /// - Recalculate and update scanning area
    public override func layoutSubviews() {
        super.layoutSubviews()

        // Update frames for preview layer and overlay layer
        let boundsChanged = previewLayer?.frame != bounds
        if boundsChanged {
            previewLayer?.frame = bounds
            overlayLayer?.frame = bounds

            // Update scan frame position
            focusImageView.frame = calculation()
        }

        // Ensure correct video orientation
        updateVideoOrientation()

        // If bounds changed, update mask
        if boundsChanged {
            updateOverlayMask()
        }
    }

    /// Deinitializer
    ///
    /// Automatically called when QRScannerView instance is deallocated. Responsible for cleaning up
    /// all resources and observers,
    /// preventing memory leaks and potential crashes.
    ///
    /// Cleanup steps:
    /// 1. Turn off torch
    /// 2. Stop camera session
    /// 3. Remove all inputs and outputs
    /// 4. Remove preview layer
    /// 5. Remove device orientation observer
    /// 6. Cleanup torch state observer
    deinit {
        setTorchActive(isOn: false)
        session.stopRunning()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        removePreviewLayer()
        removeOrientationObserver()
        torchActiveObservation = nil
    }

    // MARK: - Private Properties

    // MARK: Delegate

    private weak var delegate: QRScannerViewDelegate?

    // MARK: Camera Session

    private let session = AVCaptureSession()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput = AVCaptureMetadataOutput()
    private var metadataOutputDisable = false

    // MARK: Queues

    private let metadataQueue = DispatchQueue(label: "metadata.session.qrreader.queue")
    private let videoDataQueue = DispatchQueue(label: "videoData.session.qrreader.queue")

    // MARK: UI Components

    private var focusImageView = UIImageView()
    private var overlayLayer: CAShapeLayer?

    // MARK: Device Orientation

    private var currentOrientation: UIDeviceOrientation = .portrait
    private var orientationObserver: NSObjectProtocol?

    // MARK: Torch Observation

    private var torchActiveObservation: NSKeyValueObservation?

    // MARK: Tracking State

    private var lastFrame: CGRect?
    private var displayLink: CADisplayLink?
    private var lastScannedCode: String?

    private enum AuthorizationStatus {
        case authorized, notDetermined, restrictedOrDenied
    }

    // MARK: - Private Methods

    // MARK: Authorization

    private func isAuthorized() -> Bool {
        return authorizationStatus() == .authorized
    }

    private func authorizationStatus() -> AuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            failure(.unauthorized(.notDetermined))
            return .notDetermined
        case .denied:
            failure(.unauthorized(.denied))
            return .restrictedOrDenied
        case .restricted:
            failure(.unauthorized(.restricted))
            return .restrictedOrDenied
        @unknown default:
            return .restrictedOrDenied
        }
    }

    // MARK: Session Configuration

    private func configureSession(metadataObjectTypes: [AVMetadataObject.ObjectType]) {
        // check device initialize
        var device: AVCaptureDevice?

        if #available(iOS 13.0, *) {
            if let tripleCamera = AVCaptureDevice.default(
                .builtInTripleCamera,
                for: .video,
                position: .back
            ) {
                device = tripleCamera
            } else if let dualWideCamera = AVCaptureDevice.default(
                .builtInDualWideCamera,
                for: .video,
                position: .back
            ) {
                device = dualWideCamera
            }
        }

        if device == nil {
            if let dualCamera = AVCaptureDevice.default(
                .builtInDualCamera,
                for: .video,
                position: .back
            ) {
                device = dualCamera
            } else if let wideAngle = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) {
                device = wideAngle
            } else {
                device = AVCaptureDevice.default(for: .video)
            }
        }

        guard let videoDevice = device else {
            failure(.deviceFailure(.videoUnavailable))
            return
        }

        // check input
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput)
        else {
            failure(.deviceFailure(.inputInvalid))
            return
        }

        // check metadata output
        guard session.canAddOutput(metadataOutput) else {
            failure(.deviceFailure(.metadataOutputFailure))
            return
        }

        // commit session
        session.beginConfiguration()
        session.addInput(videoInput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
        session.addOutput(metadataOutput)
        metadataOutput.metadataObjectTypes = metadataObjectTypes

        // Configure high frame rate
        configureFrameRate(for: videoDevice)

        session.commitConfiguration()

        // torch observation
        if videoDevice.hasTorch {
            torchActiveObservation = videoDevice
                .observe(\.isTorchActive, options: .new) { [weak self] _, change in
                    self?.didChangeTorchActive(isOn: change.newValue ?? false)
                }
        }

        // start running
        if authorizationStatus() == .notDetermined {
            metadataQueue.async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    // MARK: - Frame Rate Configuration

    private func configureFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // Filter formats that support high resolution (>= 1080p)
            // This ensures we don't pick a low-res high-fps format (like 720p 240fps) which might
            // degrade scanning distance
            let highResFormats = device.formats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width >= 1920 && dimensions.height >= 1080
            }

            // If no 1080p formats found, fallback to all formats
            let candidates = highResFormats.isEmpty ? device.formats : highResFormats

            // Find format with highest max FPS among candidates
            if let bestFormat = candidates.max(by: { f1, f2 in
                let maxFps1 = f1.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
                let maxFps2 = f2.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
                return maxFps1 < maxFps2
            }) {
                device.activeFormat = bestFormat

                // Set frame rate to max supported by the selected format
                if let bestRange = bestFormat.videoSupportedFrameRateRanges
                    .max(by: { $0.maxFrameRate < $1.maxFrameRate })
                {
                    device.activeVideoMinFrameDuration = bestRange.minFrameDuration
                    device.activeVideoMaxFrameDuration = bestRange.minFrameDuration
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure frame rate: \(error)")
        }
    }

    // MARK: UI Setup

    /// Setup Scan Frame Image View
    ///
    /// Initializes and configures UI components for the scan frame, including the image and overlay
    /// mask.
    /// This is a key step in UI initialization, preparing for subsequent scan match animations.
    private func setupImageViews() {
        // Create scan frame image view using calculated initial position and size
        focusImageView = UIImageView(frame: calculation())

        // Set scan frame image, prioritize custom image, otherwise use default
        let image = focusImage ?? UIImage(
            named: "scan_qr_focus",
            in: .module,
            compatibleWith: nil
        )
        focusImageView.image = image?.withRenderingMode(.alwaysTemplate)
        focusImageView.tintColor = .white

        // Add scan frame to view hierarchy
        addSubview(focusImageView)

        // Setup overlay mask (without animation, animation will be triggered by SwiftUI)
        setupOverlayMask(animated: false)
    }

    /// Create overlay mask, transparent in focusImage area, semi-transparent black elsewhere
    /// Setup Overlay Mask
    ///
    /// Creates a semi-transparent overlay mask covering the entire view, with a transparent cutout
    /// at the scan frame position.
    /// Supports animation mode, scaling from small size to target size.
    ///
    /// Implementation principle:
    /// 1. Use CAShapeLayer to create mask
    /// 2. Use UIBezierPath evenOdd fill rule to create cutout effect
    /// 3. Support scaling effect in animation mode
    ///
    /// @param animated Whether to enable animation effect
    private func setupOverlayMask(animated: Bool = false) {
        // Step 1: Remove existing overlay layer (if any)
        overlayLayer?.removeFromSuperlayer()
        overlayLayer = nil

        // Step 2: Create new overlay layer
        let overlay = CAShapeLayer()
        overlay.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor // Semi-transparent black
        overlay.frame = bounds

        if animated {
            // Animation mode: Create small initial state, will scale up later
            let initialScale: CGFloat = 0.3 // Initial scale ratio
            let finalFrame = focusImageView.frame
            let centerX = finalFrame.midX
            let centerY = finalFrame.midY
            let scaledWidth = finalFrame.width * initialScale
            let scaledHeight = finalFrame.height * initialScale
            let scaledFrame = CGRect(
                x: centerX - scaledWidth / 2,
                y: centerY - scaledHeight / 2,
                width: scaledWidth,
                height: scaledHeight
            )

            // Create initial small transparent area path
            let path = UIBezierPath(rect: bounds) // Solid path covering entire view
            let focusPath = UIBezierPath(
                roundedRect: scaledFrame,
                cornerRadius: overlayCornerRadius * initialScale
            )
            path.append(focusPath.reversing()) // Create cutout for transparent area
            overlay.path = path.cgPath

            // Synchronously set initial small size for focusImageView
            focusImageView.frame = scaledFrame
        } else {
            // Static mode: Create final state directly
            let path = UIBezierPath(rect: bounds)
            let focusPath = UIBezierPath(
                roundedRect: focusImageView.frame,
                cornerRadius: overlayCornerRadius
            )
            path.append(focusPath.reversing())
            overlay.path = path.cgPath
        }

        // Step 3: Set fill rule to evenOdd to achieve cutout effect
        overlay.fillRule = .evenOdd

        // Step 4: Insert overlay layer at correct hierarchy position
        // Ensure overlay layer is above preview layer but below scan frame
        if let previewLayer = previewLayer {
            layer.insertSublayer(overlay, above: previewLayer)
        } else {
            layer.insertSublayer(overlay, at: 0)
        }

        // Step 5: Save overlay layer reference
        overlayLayer = overlay

        // Step 6: If animation needed, delay execution of scale animation
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.animateOverlayMaskScale()
            }
        }
    }

    /// Update position and size of transparent area in overlay mask
    private func updateOverlayMask() {
        guard let overlayLayer = overlayLayer else { return }

        // First update overlay layer frame to match current view bounds
        overlayLayer.frame = bounds

        // Create path for the entire view
        let path = UIBezierPath(rect: bounds)

        // Create transparent hole for current focus area with rounded corners
        let focusPath = UIBezierPath(
            roundedRect: focusImageView.frame,
            cornerRadius: overlayCornerRadius
        )

        // Apply same rotation transform as focusImageView
        if !focusImageView.transform.isIdentity {
            let center = CGPoint(x: focusImageView.frame.midX, y: focusImageView.frame.midY)
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: center.x, y: center.y)
            transform = transform.concatenating(focusImageView.transform)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            focusPath.apply(transform)
        }

        path.append(focusPath.reversing())

        overlayLayer.path = path.cgPath
    }

    /// Execute move and rotate animation for overlay mask transparent area
    /// Execute Overlay Mask Move and Rotate Animation
    ///
    /// This function creates a smooth overlay mask animation, moving the transparent area from
    /// current position to target position,
    /// while applying rotation transform to match QR code angle.
    ///
    /// Implementation principle:
    /// 1. Animate using CAShapeLayer's path property
    /// 2. Create a path covering entire view, then cut out a rotating rectangle
    /// 3. Implement rotation around center using CGAffineTransform
    ///
    /// @param targetFrame Target frame for transparent area
    /// @param rotation Rotation angle (radians)
    /// @param duration Animation duration
    // Deprecated: Replaced by CADisplayLink synchronization
    // private func animateOverlayMaskMovement(to targetFrame: CGRect, rotation: CGFloat, duration:
    // TimeInterval) {
    //    // ... (code removed)
    // }

    /// Execute zoom-in animation for transparent area
    private func animateOverlayMaskScale() {
        guard let overlayLayer = overlayLayer else { return }

        // Get current small size state (initial state)
        let currentPath = overlayLayer.presentation()?.path ?? overlayLayer.path

        // Calculate final appropriate size state (back to original calculation() size)
        let finalFrame = calculation()

        // Create final path (appropriate size)
        let finalPath = UIBezierPath(rect: bounds)
        let finalFocusPath = UIBezierPath(
            roundedRect: finalFrame,
            cornerRadius: overlayCornerRadius
        )
        finalPath.append(finalFocusPath.reversing())

        // Update Model Layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayLayer.path = finalPath.cgPath
        CATransaction.commit()

        // Create overlay layer path animation
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = currentPath
        pathAnimation.toValue = finalPath.cgPath
        pathAnimation.duration = overlayAnimationDuration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        overlayLayer.removeAnimation(forKey: "pathScaleAnimation")
        overlayLayer.add(pathAnimation, forKey: "pathScaleAnimation")

        // Create focusImageView frame animation
        UIView.animate(
            withDuration: overlayAnimationDuration,
            delay: 0,
            options: [.curveEaseOut],
            animations: { [weak self] in
                self?.focusImageView.frame = finalFrame
            },
            completion: nil
        )
    }

    // MARK: Calculations

    /// Calculate Scan Frame Position and Size
    ///
    /// Intelligently calculates the best position and size for the scan frame based on device
    /// orientation and screen dimensions.
    /// Ensures good user experience across different devices and orientations.
    ///
    /// Design principles:
    /// - Portrait: Use golden ratio (0.618) for size, position slightly higher for easier operation
    /// - Landscape: Use smaller size to avoid blocking too much content, display completely
    /// centered
    ///
    /// @return CGRect for scan frame, containing position and size info
    private func calculation() -> CGRect {
        let bounds = self.bounds
        let isLandscape = bounds.width > bounds.height

        // Step 1: Calculate scan frame size based on device orientation
        let scanSize: CGFloat
        if isLandscape {
            // Landscape mode: Use conservative size to avoid taking up too much screen space
            // Take smaller of 60% height and 40% width
            scanSize = min(bounds.height * 0.6, bounds.width * 0.4)
        } else {
            // Portrait mode: Use golden ratio (0.618) for best visual effect
            // Based on 61.8% of shorter screen side
            scanSize = min(bounds.width, bounds.height) * 0.618
        }

        // Step 2: Calculate horizontal center position
        let x = (bounds.width - scanSize) / 2

        // Step 3: Calculate vertical position based on orientation
        let y: CGFloat
        if isLandscape {
            // Landscape: Completely vertically centered for balanced visual effect
            y = (bounds.height - scanSize) / 2
        } else {
            // Portrait: Slightly higher (19.1% position) for easier operation
            // This position is not too high to affect status bar, nor too centered to affect bottom
            // operations
            y = bounds.height * 0.191
        }

        return CGRect(x: x, y: y, width: scanSize, height: scanSize)
    }

    // MARK: Preview Layer

    private func addPreviewLayer() {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)

        self.previewLayer = previewLayer
    }

    private func removePreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    // MARK: Device Orientation

    private func setupOrientationObserver() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone: Check if app only supports portrait
            let supportedOrientations = UIApplication.shared
                .supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations ==
                .portraitUpsideDown

            if isPortraitOnly {
                // For portrait-only iPhone apps, no need to listen for orientation changes, set
                // initial orientation directly
                currentOrientation = .portrait
                updateVideoOrientation()
                return
            }
        }

        // Enable device orientation notifications
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        // Listen for device rotation notifications
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleOrientationChange()
        }

        // Initialize current orientation
        currentOrientation = UIDevice.current.orientation
    }

    private func removeOrientationObserver() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func handleOrientationChange() {
        let newOrientation = UIDevice.current.orientation

        // Only handle valid orientation changes
        guard newOrientation != currentOrientation,
              newOrientation.isValidInterfaceOrientation
        else {
            return
        }

        let previousOrientation = currentOrientation
        currentOrientation = newOrientation

        // Immediately update video orientation
        updateVideoOrientation()

        // Update UI layout using animation
        UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseInOut]) { [weak self] in
            // Force layout update
            self?.setNeedsLayout()
            self?.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self = self else { return }
            // Reset overlay mask after animation completes to ensure correct adaptation
            self.setupOverlayMask(animated: false)
        }
    }

    private func updateVideoOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoOrientationSupported
        else {
            return
        }

        // Get current app interface orientation
        let interfaceOrientation: UIInterfaceOrientation
        if #available(iOS 13.0, *) {
            interfaceOrientation = UIApplication.shared.windows.first?.windowScene?
                .interfaceOrientation ?? .portrait
        } else {
            interfaceOrientation = UIApplication.shared.statusBarOrientation
        }

        let videoOrientation: AVCaptureVideoOrientation

        // For portrait-only apps, prioritize interface orientation
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone: Check if app only supports portrait
            let supportedOrientations = UIApplication.shared
                .supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations ==
                .portraitUpsideDown

            if isPortraitOnly {
                // Portrait-only iPhone apps always use portrait orientation
                videoOrientation = .portrait
            } else {
                // Multi-orientation iPhone apps use interface orientation
                switch interfaceOrientation {
                case .portrait:
                    videoOrientation = .portrait
                case .portraitUpsideDown:
                    videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    videoOrientation = .landscapeLeft
                case .landscapeRight:
                    videoOrientation = .landscapeRight
                default:
                    videoOrientation = .portrait
                }
            }
        } else {
            // iPad: Use interface orientation
            switch interfaceOrientation {
            case .portrait:
                videoOrientation = .portrait
            case .portraitUpsideDown:
                videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                videoOrientation = .landscapeLeft
            case .landscapeRight:
                videoOrientation = .landscapeRight
            default:
                videoOrientation = .portrait
            }
        }

        connection.videoOrientation = videoOrientation
    }

    // MARK: - DisplayLink for Synchronization

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink() {
        updateOverlayMaskFromPresentation()
    }

    private func updateOverlayMaskFromPresentation() {
        guard let overlayLayer = overlayLayer else { return }

        // Get presentation layer to capture current animation state
        // If no animation, fallback to model layer
        let presentation = focusImageView.layer.presentation() ?? focusImageView.layer
        let center = presentation.position
        let bounds = presentation.bounds
        let transform = presentation.affineTransform()

        // Create full screen path
        let path = UIBezierPath(rect: self.bounds)

        // Create focus path based on current bounds
        let defaultRect = calculation()
        let scale = defaultRect.width > 0 ? bounds.width / defaultRect.width : 1.0
        let dynamicRadius = overlayCornerRadius * scale
        let focusPath = UIBezierPath(roundedRect: bounds, cornerRadius: dynamicRadius)

        // Calculate transform to match focusImageView's visual state
        // 1. Center alignment offset (from bounds origin to anchor point)
        let offsetToOrigin = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
        // 2. Apply layer transform (rotation/scale)
        // 3. Move to actual position in superlayer
        let offsetToPosition = CGAffineTransform(translationX: center.x, y: center.y)

        let finalTransform = offsetToOrigin.concatenating(transform).concatenating(offsetToPosition)

        // Apply transform
        focusPath.apply(finalTransform)

        // Create cutout
        path.append(focusPath.reversing())

        // Update layer path immediately without implicit animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayLayer.path = path.cgPath
        CATransaction.commit()
    }

    /// Move and Adjust Scan Frame to Match Detected QR Code
    ///
    /// This function is the core algorithm for precise matching of QR code scan frame, solving key
    /// issues:
    /// 1. Scan frame shape distortion (rectangular -> square)
    /// 2. Angle offset (90-degree rotation error)
    /// 3. Center point misalignment
    /// 4. Size mismatch
    ///
    /// @param corners Coordinates of 4 corner points of QR code, order: [TopLeft, TopRight,
    /// BottomRight, BottomLeft]
    ///                These coordinates have been converted to view coordinate system via
    /// previewLayer
    private func moveImageViews(corners: [CGPoint]) {
//        assert(Thread.isMainThread)

        // Data validation: Ensure 4 corners
        guard corners.count == 4 else { return }

        // Step 1: Calculate geometric center of QR code
        // Use average of 4 corners, more precise than path.bounds.center
        let centerX = corners.reduce(0) { $0 + $1.x } / 4
        let centerY = corners.reduce(0) { $0 + $1.y } / 4
        let qrCenter = CGPoint(x: centerX, y: centerY)

        // Step 2: Calculate average side length of QR code
        // Iterate through 4 sides, calculate length of each, then take average
        // This handles slight perspective distortion for more stable size
        var totalLength: CGFloat = 0
        for i in 0..<4 {
            let nextIndex = (i + 1) % 4
            let sideLength = hypot(
                corners[i].x - corners[nextIndex].x,
                corners[i].y - corners[nextIndex].y
            )
            totalLength += sideLength
        }
        let averageSideLength = totalLength / 4

        // Step 3: Calculate rotation angle of QR code
        // Key fix: Use left side (corners[0] -> corners[3]) instead of top side (corners[0] ->
        // corners[1])
        // This avoids 90-degree angle offset issue
        // corners order: [0]TopLeft -> [1]TopRight -> [2]BottomRight -> [3]BottomLeft
        // let deltaX = corners[3].x - corners[0].x // X component from TopLeft to BottomLeft
        // let deltaY = corners[3].y - corners[0].y // Y component from TopLeft to BottomLeft
        // let rotationAngle = atan2(deltaY, deltaX) // Calculate angle with horizontal axis

        // Step 4: Create target frame for scan frame
        // Keep square shape, size based on average side length plus padding
        // Use focusImagePadding as a percentage factor to scale padding dynamically
        // Default 8.0 means 8% of the side length
        let dynamicPadding = averageSideLength * (focusImagePadding / 100.0)
        let frameSize = averageSideLength + dynamicPadding * 2
        let targetFrame = CGRect(
            x: qrCenter.x - frameSize / 2, // Based on center point
            y: qrCenter.y - frameSize / 2,
            width: frameSize,
            height: frameSize
        )

        lastFrame = targetFrame

        // Step 5: Start DisplayLink for perfect synchronization
        startDisplayLink()

        // Step 6: Execute focusImageView animation transform
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { [weak self] in
                guard let strongSelf = self else { return }

                strongSelf.focusImageView.tintColor = .red
                // Reset transform to avoid cumulative transform effects
                strongSelf.focusImageView.transform = CGAffineTransform.identity

                // Set new frame (position and size)
                strongSelf.focusImageView.frame = targetFrame
            },
            completion: { [weak self] _ in
                guard let strongSelf = self else { return }
                // Stop display link and do one final update to ensure exact match
                strongSelf.stopDisplayLink()
                strongSelf.updateOverlayMaskFromPresentation()
            }
        )
    }

    private func resetTracking() {
        let defaultFrame = calculation()

        // Check if already at default (with some tolerance)
        // Check frame overlap, center point distance, size difference, and transform
        if focusImageView.frame.intersects(defaultFrame) &&
            abs(focusImageView.frame.midX - defaultFrame.midX) < 1 &&
            abs(focusImageView.frame.midY - defaultFrame.midY) < 1 &&
            abs(focusImageView.frame.width - defaultFrame.width) < 1 &&
            focusImageView.transform == .identity
        {
            return
        }

        lastFrame = nil

        // Start DisplayLink to keep overlay synced during reset animation
        startDisplayLink()

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            self.focusImageView.tintColor = .white
            self.focusImageView.transform = .identity
            self.focusImageView.frame = defaultFrame
        }) { _ in
            self.stopDisplayLink()
            self.updateOverlayMaskFromPresentation()
        }
    }

    // MARK: Delegate Callbacks

    private func failure(_ error: QRScannerError) {
        delegate?.qrScannerView(self, didFailure: error)
    }

    private func success(_ code: String) {
        delegate?.qrScannerView(self, didSuccess: code)
    }

    private func didChangeTorchActive(isOn: Bool) {
        delegate?.qrScannerView(self, didChangeTorchActive: isOn)
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension QRScannerView: AVCaptureMetadataOutputObjectsDelegate {
    /// Handle Metadata Objects Detected by Camera (QR Code, etc.)
    ///
    /// Core callback method for AVCaptureMetadataOutputObjectsDelegate, called when camera detects
    /// QR code or other supported metadata objects.
    ///
    /// Process flow:
    /// 1. Get first detected metadata object
    /// 2. Convert to readable machine code object
    /// 3. Update UI on main thread (move scan frame to detected position)
    /// 4. If scanning enabled, extract string value and callback success result
    /// 5. Turn off torch and disable further scanning
    ///
    /// @param output Metadata output object
    /// @param metadataObjects Array of detected metadata objects
    /// @param connection Capture connection
    public func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // 1. If no objects detected, reset to default state
        if metadataObjects.isEmpty {
            DispatchQueue.main.async {
                self.resetTracking()
            }
            return
        }

        // 2. Get the first metadata object
        guard let metadataObject = metadataObjects.first else { return }

        // 3. Perform UI updates and coordinate transformation on Main Thread

        // 3. Transform metadata object coordinates to view coordinates
        // It is CRITICAL to do this on the main thread because it relies on previewLayer's
        // current layout/bounds
        guard let readableObject = previewLayer?
            .transformedMetadataObject(
                for: metadataObject
            ) as? AVMetadataMachineReadableCodeObject
        else { return }

        DispatchQueue.main.async {[weak self] in
            // 4. Update scan frame UI
            self?.moveImageViews(corners: readableObject.corners)
        }

        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self,
                  let stringValue = readableObject.stringValue else { return }
            
            if strongSelf.lastScannedCode != stringValue {
                strongSelf.lastScannedCode = stringValue
                strongSelf.success(stringValue)
            }
        }
    }
}
