//
//  QRScannerView.swift
//  QRScanner
//
//  Created by wbi on 2019/10/16.
//  Copyright © 2019 Mercari, Inc. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - QRScannerViewDelegate
public protocol QRScannerViewDelegate: AnyObject {
    // Required
    func qrScannerView(_ qrScannerView: QRScannerView, didFailure error: QRScannerError)
    func qrScannerView(_ qrScannerView: QRScannerView, didSuccess code: String)
    // Optional
    func qrScannerView(_ qrScannerView: QRScannerView, didChangeTorchActive isOn: Bool)
}

public extension QRScannerViewDelegate {
    func qrScannerView(_ qrScannerView: QRScannerView, didChangeTorchActive isOn: Bool) {}
}

// MARK: - QRScannerView
@IBDesignable
public class QRScannerView: UIView {
    
    // MARK: - Input
    public struct Input {
        let focusImage: UIImage?
        let focusImagePadding: CGFloat?
        let animationDuration: Double?
        let scanningAreaLimit: Bool
        let metadataObjectTypes: [AVMetadataObject.ObjectType]
        
        
        public static var `default`: Input { Self() }
        
        public init(focusImage: UIImage? = nil,
                    focusImagePadding: CGFloat? = nil,
                    animationDuration: Double? = nil,
                    scanningAreaLimit: Bool = false,
                    metadataObjectTypes: [AVMetadataObject.ObjectType] = [.qr,.aztec] ) {
            self.focusImage = focusImage
            self.focusImagePadding = focusImagePadding
            self.animationDuration = animationDuration
            self.scanningAreaLimit = scanningAreaLimit
            self.metadataObjectTypes = metadataObjectTypes
        }
    }
    
    // MARK: - Public Properties
    @IBInspectable
    public var focusImage: UIImage?
    
    @IBInspectable
    public var focusImagePadding: CGFloat = 8.0
    
    @IBInspectable
    public var animationDuration: Double = 0.5
    
    @IBInspectable
    public var overlayCornerRadius: CGFloat = 20.0
    
    @IBInspectable
    public var overlayAnimationDuration: Double = 0.6
    
    @IBInspectable
    public var scanningAreaLimit:Bool = false
    
    // MARK: - Public
    
    /**
     * Configure QR Scanner
     *
     * This is the main initialization method for QRScannerView, responsible for setting up all necessary components and configurations.
     *
     * @param delegate Callback delegate for scan results
     * @param input Configuration parameters, including scan frame image, animation duration, etc.
     */
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
        if let animationDuration = input.animationDuration {
            self.animationDuration = animationDuration
        }
        
        self.scanningAreaLimit = input.scanningAreaLimit
        
        // Initialize components in order
        configureSession(metadataObjectTypes: input.metadataObjectTypes)  // Configure camera session
        addPreviewLayer()           // Add preview layer
        setupImageViews()          // Setup scan frame image
        setupOverlayMask()         // Setup overlay mask
        setupOrientationObserver() // Setup device orientation observer
    }
    
    /**
     * Start Scanning
     *
     * Starts the camera session to begin scanning for QR codes. This method executes on a background queue to avoid blocking the main thread.
     */
    public func startRunning() {
        guard isAuthorized() else { return }        // Check camera authorization
        guard !session.isRunning else { return }   // Avoid duplicate start
        metadataOutputEnable = true                 // Enable metadata output
        metadataQueue.async { [weak self] in
            self?.session.startRunning()            // Start session on background queue
        }
    }
    
    /**
     * Stop Scanning
     *
     * Stops the camera session to save resources. This method executes on a background queue.
     */
    public func stopRunning() {
        guard session.isRunning else { return }    // Check if session is running
        videoDataQueue.async { [weak self] in
            self?.session.stopRunning()             // Stop session on background queue
        }
        metadataOutputEnable = false               // Disable metadata output
    }
    
    /**
     * Rescan
     *
     * Resets the scanner state and restarts scanning. This method cleans up the current UI state,
     * recreates the scan frame and overlay mask with animation effects.
     *
     * Usage scenarios:
     * - Continue scanning after completion
     * - Restart after scan error
     * - User manually triggers rescan
     */
    public func rescan() {
        // Check camera authorization
        guard isAuthorized() else { return }
        
        // Step 1: Stop current scanning
        metadataOutputEnable = false
        
        // Step 2: Cleanup UI state
        focusImageView.removeFromSuperview()        // Remove scan frame
        
        // Step 3: Cleanup overlay mask
        overlayLayer?.removeFromSuperlayer()
        overlayLayer = nil
        
        // Step 4: Reset scan frame transform state
        focusImageView.transform = CGAffineTransform.identity
        
        // Step 5: Recreate scan frame
        focusImageView = UIImageView(frame: calculation())
        focusImageView.image = focusImage ?? UIImage(named: "scan_qr_focus", in: .module, compatibleWith: nil)
        addSubview(focusImageView)
        
        // Step 6: Reset overlay mask (with animation)
        setupOverlayMask(animated: true)
        
        // Step 7: Delay restart scanning (avoid timing issues)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.metadataOutputEnable = true
            self?.startRunning()
        }
    }
    
    /**
     * Start Overlay Zoom Animation
     *
     * This method creates a zoom-in animation effect, providing visual feedback for the scanning interface.
     * The animation starts from 30% scale and gradually zooms to normal size, enhancing user experience.
     *
     * Implementation steps:
     * 1. Calculate the frame for initial scaled state (30% size)
     * 2. Create corresponding initial path
     * 3. Immediately set initial state
     * 4. Delay execution of zoom animation to normal size
     */
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
        let initialPath = UIBezierPath(rect: self.bounds)
        let initialFocusPath = UIBezierPath(roundedRect: scaledFrame, cornerRadius: overlayCornerRadius * initialScale)
        initialPath.append(initialFocusPath.reversing())
        
        // Immediately set initial state
        overlayLayer.path = initialPath.cgPath
        focusImageView.frame = scaledFrame
        
        // Delay animation execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateOverlayMaskScale()
        }
    }
    
    /**
     * Control Device Torch State
     *
     * This method controls the device's torch during scanning to help in low-light environments.
     *
     * @param isOn Whether to turn on the torch, true for on, false for off
     *
     * Safety checks:
     * - Ensure execution on main thread
     * - Check if device supports torch
     * - Check if torch is available
     * - Ensure scanner is enabled
     */
    public func setTorchActive(isOn: Bool) {
        assert(Thread.isMainThread)
        
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              videoDevice.hasTorch, videoDevice.isTorchAvailable, metadataOutputEnable else {
            return
        }
        try? videoDevice.lockForConfiguration()
        videoDevice.torchMode = isOn ? .on : .off
        videoDevice.unlockForConfiguration()
    }
    
    /**
     * Layout Subviews
     *
     * System automatically calls this method when view bounds change (e.g., device rotation, resize).
     * Responsible for updating layout of preview layer and scanning area, ensuring correct display across different sizes.
     *
     * Main functions:
     * - Call super.layoutSubviews
     * - Update preview layer frame to fit new bounds
     * - Recalculate and update scanning area
     */
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update frames for preview layer and overlay layer
        let boundsChanged = previewLayer?.frame != self.bounds
        if boundsChanged {
            previewLayer?.frame = self.bounds
            overlayLayer?.frame = self.bounds
            
            // Update scan frame position
            focusImageView.frame = calculation()
        }
        
        // Ensure correct video orientation
        updateVideoOrientation()
        
        // If bounds changed, update mask
        if boundsChanged {
            updateOverlayMask()
            if scanningAreaLimit{
                updateScanningArea()
            }
        }
    }
    
    /**
     * Deinitializer
     *
     * Automatically called when QRScannerView instance is deallocated. Responsible for cleaning up all resources and observers,
     * preventing memory leaks and potential crashes.
     *
     * Cleanup steps:
     * 1. Turn off torch
     * 2. Stop camera session
     * 3. Remove all inputs and outputs
     * 4. Remove preview layer
     * 5. Remove device orientation observer
     * 6. Cleanup torch state observer
     */
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
    private var metadataOutputEnable = false
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
    private func configureSession(metadataObjectTypes: [AVMetadataObject.ObjectType] ) {
        // check device initialize
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            failure(.deviceFailure(.videoUnavailable))
            return
        }
        
        // check input
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice), session.canAddInput(videoInput) else {
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
        
        session.commitConfiguration()
        
        // torch observation
        if videoDevice.hasTorch {
            torchActiveObservation = videoDevice.observe(\.isTorchActive, options: .new) { [weak self] _, change in
                self?.didChangeTorchActive(isOn: change.newValue ?? false)
            }
        }
        
        // start running
        if authorizationStatus() == .notDetermined {
            metadataOutputEnable = true
            metadataQueue.async { [weak self] in
                self?.session.startRunning()
            }
        }
    }
    
    
    // MARK: UI Setup
    /**
     * Setup Scan Frame Image View
     *
     * Initializes and configures UI components for the scan frame, including the image and overlay mask.
     * This is a key step in UI initialization, preparing for subsequent scan match animations.
     */
    private func setupImageViews() {
        // Create scan frame image view using calculated initial position and size
        focusImageView = UIImageView(frame: calculation())
        
        // Set scan frame image, prioritize custom image, otherwise use default
        focusImageView.image = focusImage ?? UIImage(named: "scan_qr_focus", in: .module, compatibleWith: nil)
        
        // Add scan frame to view hierarchy
        addSubview(focusImageView)
        
        // Setup overlay mask (without animation, animation will be triggered by SwiftUI)
        setupOverlayMask(animated: false)
    }
    
    /// Create overlay mask, transparent in focusImage area, semi-transparent black elsewhere
    /**
     * Setup Overlay Mask
     *
     * Creates a semi-transparent overlay mask covering the entire view, with a transparent cutout at the scan frame position.
     * Supports animation mode, scaling from small size to target size.
     *
     * Implementation principle:
     * 1. Use CAShapeLayer to create mask
     * 2. Use UIBezierPath evenOdd fill rule to create cutout effect
     * 3. Support scaling effect in animation mode
     *
     * @param animated Whether to enable animation effect
     */
    private func setupOverlayMask(animated: Bool = false) {
        // Step 1: Remove existing overlay layer (if any)
        overlayLayer?.removeFromSuperlayer()
        
        // Step 2: Create new overlay layer
        let overlay = CAShapeLayer()
        overlay.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor  // Semi-transparent black
        overlay.frame = self.bounds
        
        if animated {
            // Animation mode: Create small initial state, will scale up later
            let initialScale: CGFloat = 0.3  // Initial scale ratio
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
            let path = UIBezierPath(rect: self.bounds)  // Solid path covering entire view
            let focusPath = UIBezierPath(roundedRect: scaledFrame, cornerRadius: overlayCornerRadius * initialScale)
            path.append(focusPath.reversing())  // Create cutout for transparent area
            overlay.path = path.cgPath
            
            // Synchronously set initial small size for focusImageView
            focusImageView.frame = scaledFrame
        } else {
            // Static mode: Create final state directly
            let path = UIBezierPath(rect: self.bounds)
            let focusPath = UIBezierPath(roundedRect: focusImageView.frame, cornerRadius: overlayCornerRadius)
            path.append(focusPath.reversing())
            overlay.path = path.cgPath
        }
        
        // Step 3: Set fill rule to evenOdd to achieve cutout effect
        overlay.fillRule = .evenOdd
        
        // Step 4: Insert overlay layer at correct hierarchy position
        // Ensure overlay layer is above preview layer but below scan frame
        if let previewLayer = self.previewLayer {
            layer.insertSublayer(overlay, above: previewLayer)
        } else {
            layer.insertSublayer(overlay, at: 0)
        }
        
        // Step 5: Save overlay layer reference
        self.overlayLayer = overlay
        
        // Step 6: If animation needed, delay execution of scale animation
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.animateOverlayMaskScale()
            }
        }
    }
    
    /// Update position and size of transparent area in overlay mask
    private func updateOverlayMask() {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // First update overlay layer frame to match current view bounds
        overlayLayer.frame = self.bounds
        
        // Create path for the entire view
        let path = UIBezierPath(rect: self.bounds)
        
        // Create transparent hole for current focus area with rounded corners
        let focusPath = UIBezierPath(roundedRect: focusImageView.frame, cornerRadius: overlayCornerRadius)
        
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
    /**
     * Execute Overlay Mask Move and Rotate Animation
     *
     * This function creates a smooth overlay mask animation, moving the transparent area from current position to target position,
     * while applying rotation transform to match QR code angle.
     *
     * Implementation principle:
     * 1. Animate using CAShapeLayer's path property
     * 2. Create a path covering entire view, then cut out a rotating rectangle
     * 3. Implement rotation around center using CGAffineTransform
     *
     * @param targetFrame Target frame for transparent area
     * @param rotation Rotation angle (radians)
     * @param duration Animation duration
     */
    private func animateOverlayMaskMovement(to targetFrame: CGRect, rotation: CGFloat, duration: TimeInterval) {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // Step 1: Update overlay layer frame to match current view bounds
        overlayLayer.frame = self.bounds
        
        // Step 2: Save current path as animation start state
        let fromPath = overlayLayer.path
        
        // Step 3: Create target path (solid path covering entire view)
        let toPath = UIBezierPath(rect: self.bounds)
        
        // Step 4: Create transparent area path (with rounded corners)
        let targetFocusPath = UIBezierPath(roundedRect: targetFrame, cornerRadius: overlayCornerRadius)
        
        // Step 5: Apply rotation transform to transparent area
        // Use standard rotation transform: Translate to center -> Rotate -> Translate back
        let center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)    // Move to rotation center
        transform = transform.rotated(by: rotation)                     // Execute rotation
        transform = transform.translatedBy(x: -center.x, y: -center.y)  // Move back to original position
        
        // Step 6: Apply transform and create cutout effect
        targetFocusPath.apply(transform)
        toPath.append(targetFocusPath.reversing())  // reversing() creates cutout effect
        
        // Step 7: Create path animation
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = fromPath          // Start path
        pathAnimation.toValue = toPath.cgPath       // Target path
        pathAnimation.duration = duration           // Animation duration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)  // Timing function
        pathAnimation.fillMode = .forwards          // Keep final state
        pathAnimation.isRemovedOnCompletion = false // Do not remove after completion
        
        // Step 8: Execute animation
        overlayLayer.add(pathAnimation, forKey: "pathMoveAnimation")
        
        // Step 9: Set final state (ensure correct state after animation ends)
        overlayLayer.path = toPath.cgPath
    }
    
    /// Execute zoom-in animation for transparent area
    private func animateOverlayMaskScale() {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // Get current small size state (initial state)
        let currentPath = overlayLayer.path
        
        // Calculate final appropriate size state (back to original calculation() size)
        let finalFrame = calculation()
        
        // Create final path (appropriate size)
        let finalPath = UIBezierPath(rect: self.bounds)
        let finalFocusPath = UIBezierPath(roundedRect: finalFrame, cornerRadius: overlayCornerRadius)
        finalPath.append(finalFocusPath.reversing())
        
        // Create overlay layer path animation
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = currentPath
        pathAnimation.toValue = finalPath.cgPath
        pathAnimation.duration = overlayAnimationDuration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pathAnimation.fillMode = .forwards
        pathAnimation.isRemovedOnCompletion = false
        
        // Execute overlay layer animation
        overlayLayer.add(pathAnimation, forKey: "pathScaleAnimation")
        
        // Create focusImageView frame animation
        UIView.animate(withDuration: overlayAnimationDuration, delay: 0, options: [.curveEaseOut], animations: { [weak self] in
            self?.focusImageView.frame = finalFrame
        }, completion: nil)
        
        // Set final state
        overlayLayer.path = finalPath.cgPath
    }
    
    // MARK: Calculations
    /**
     * Calculate Scan Frame Position and Size
     *
     * Intelligently calculates the best position and size for the scan frame based on device orientation and screen dimensions.
     * Ensures good user experience across different devices and orientations.
     *
     * Design principles:
     * - Portrait: Use golden ratio (0.618) for size, position slightly higher for easier operation
     * - Landscape: Use smaller size to avoid blocking too much content, display completely centered
     *
     * @return CGRect for scan frame, containing position and size info
     */
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
            // This position is not too high to affect status bar, nor too centered to affect bottom operations
            y = bounds.height * 0.191
        }
        
        return CGRect(x: x, y: y, width: scanSize, height: scanSize)
    }
    
    // MARK: Preview Layer
    private func addPreviewLayer() {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = self.bounds
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
            let supportedOrientations = UIApplication.shared.supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations == .portraitUpsideDown
            
            if isPortraitOnly {
                // For portrait-only iPhone apps, no need to listen for orientation changes, set initial orientation directly
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
              newOrientation.isValidInterfaceOrientation else {
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
            guard let self = self else{ return }
            // Reset overlay mask after animation completes to ensure correct adaptation
            self.setupOverlayMask(animated: false)
            
            if self.scanningAreaLimit{
                self.updateScanningArea()
            }
        }
    }
    
    private func updateVideoOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoOrientationSupported else {
            return
        }
        
        // Get current app interface orientation
        let interfaceOrientation: UIInterfaceOrientation
        if #available(iOS 13.0, *) {
            interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
        } else {
            interfaceOrientation = UIApplication.shared.statusBarOrientation
        }
        
        let videoOrientation: AVCaptureVideoOrientation
        
        // For portrait-only apps, prioritize interface orientation
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone: Check if app only supports portrait
            let supportedOrientations = UIApplication.shared.supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations == .portraitUpsideDown
            
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
    
    /// Set scanning area limit
    private func updateScanningArea() {
        guard let previewLayer = self.previewLayer else { return }
        
        // Calculate relative position of scan frame in preview layer
        let scanRect = calculation()
        let previewBounds = previewLayer.bounds
        
        // Convert to relative coordinates (0-1)
        let rectOfInterest = CGRect(
            x: scanRect.minY / previewBounds.height,
            y: scanRect.minX / previewBounds.width,
            width: scanRect.height / previewBounds.height,
            height: scanRect.width / previewBounds.width
        )
        
        // Set scanning area limit
        metadataOutput.rectOfInterest = rectOfInterest
    }
    
    /**
     * Move and Adjust Scan Frame to Match Detected QR Code
     *
     * This function is the core algorithm for precise matching of QR code scan frame, solving key issues:
     * 1. Scan frame shape distortion (rectangular -> square)
     * 2. Angle offset (90-degree rotation error)
     * 3. Center point misalignment
     * 4. Size mismatch
     *
     * @param corners Coordinates of 4 corner points of QR code, order: [TopLeft, TopRight, BottomRight, BottomLeft]
     *                These coordinates have been converted to view coordinate system via previewLayer
     */
    private func moveImageViews(corners: [CGPoint]) {
        assert(Thread.isMainThread)
        
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
            let sideLength = hypot(corners[i].x - corners[nextIndex].x, corners[i].y - corners[nextIndex].y)
            totalLength += sideLength
        }
        let averageSideLength = totalLength / 4
        
        // Step 3: Calculate rotation angle of QR code
        // Key fix: Use left side (corners[0] -> corners[3]) instead of top side (corners[0] -> corners[1])
        // This avoids 90-degree angle offset issue
        // corners order: [0]TopLeft -> [1]TopRight -> [2]BottomRight -> [3]BottomLeft
        let deltaX = corners[3].x - corners[0].x  // X component from TopLeft to BottomLeft
        let deltaY = corners[3].y - corners[0].y  // Y component from TopLeft to BottomLeft
        let rotationAngle = atan2(deltaY, deltaX) // Calculate angle with horizontal axis
        
        // Step 4: Create target frame for scan frame
        // Keep square shape, size based on average side length plus padding
        let frameSize = averageSideLength + focusImagePadding * 2
        let targetFrame = CGRect(
            x: qrCenter.x - frameSize / 2,  // Based on center point
            y: qrCenter.y - frameSize / 2,
            width: frameSize,
            height: frameSize
        )
        
        // Step 5: Execute focusImageView animation transform
        UIView.animate(withDuration: animationDuration, animations: { [weak self] in
            guard let strongSelf = self else { return }
            
            // Reset transform to avoid cumulative transform effects
            strongSelf.focusImageView.transform = CGAffineTransform.identity
            
            // Set new frame (position and size)
            strongSelf.focusImageView.frame = targetFrame
            
            // Apply rotation transform (rotate around center)
            strongSelf.focusImageView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
        }, completion: { _ in })
        
        // Step 6: Synchronously execute overlay mask move and rotate animation
        animateOverlayMaskMovement(to: targetFrame, rotation: rotationAngle, duration: animationDuration)
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
    /**
     * Handle Metadata Objects Detected by Camera (QR Code, etc.)
     *
     * Core callback method for AVCaptureMetadataOutputObjectsDelegate, called when camera detects
     * QR code or other supported metadata objects.
     *
     * Process flow:
     * 1. Get first detected metadata object
     * 2. Convert to readable machine code object
     * 3. Update UI on main thread (move scan frame to detected position)
     * 4. If scanning enabled, extract string value and callback success result
     * 5. Turn off torch and disable further scanning
     *
     * @param output Metadata output object
     * @param metadataObjects Array of detected metadata objects
     * @param connection Capture connection
     */
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            ///  metadataObject.type == .qr || metadataObject.type == .aztec 
            guard let readableObject = previewLayer?.transformedMetadataObject(for: metadataObject) as? AVMetadataMachineReadableCodeObject
                 else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.moveImageViews( corners: readableObject.corners)
            }
            guard metadataOutputEnable else { return }
            guard let stringValue = readableObject.stringValue else { return }
            metadataOutputEnable = false
            
            
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.setTorchActive(isOn: false)
                strongSelf.success(stringValue)
            }
        }
    }
}

// MARK: - UIDeviceOrientation Extension

/**
 * UIDeviceOrientation Extension
 *
 * Adds convenience property to UIDeviceOrientation to determine if device orientation is a valid interface orientation.
 * This extension helps filter out device orientations not suitable for interface layout (e.g., face up, face down).
 */
extension UIDeviceOrientation {
    /**
     * Determine if current device orientation is a valid interface orientation
     *
     * Valid interface orientations include:
     * - portrait: Portrait
     * - portraitUpsideDown: Portrait Upside Down
     * - landscapeLeft: Landscape Left
     * - landscapeRight: Landscape Right
     *
     * @return Returns true if valid interface orientation, otherwise false
     */
    var isValidInterfaceOrientation: Bool {
        switch self {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return true
        default:
            return false
        }
    }
}
