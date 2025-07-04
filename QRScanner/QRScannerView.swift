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
     * 配置QR扫描器
     * 
     * 这是QRScannerView的主要初始化方法，负责设置所有必要的组件和配置。
     * 
     * @param delegate 扫描结果回调代理
     * @param input 配置参数，包含扫码框图片、动画时长等设置
     */
    public func configure(delegate: QRScannerViewDelegate, input: Input = .default) {
        // 设置代理
        self.delegate = delegate
        
        // 应用输入配置参数
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
        
        // 按顺序初始化各个组件
        configureSession(metadataObjectTypes: input.metadataObjectTypes)  // 配置相机会话
        addPreviewLayer()           // 添加预览层
        setupImageViews()          // 设置扫码框图片
        setupOverlayMask()         // 设置遮罩层
        setupOrientationObserver() // 设置设备方向监听
    }
    
    /**
     * 开始扫描
     * 
     * 启动相机会话开始扫描QR码。该方法会在后台队列中执行以避免阻塞主线程。
     */
    public func startRunning() {
        guard isAuthorized() else { return }        // 检查相机权限
        guard !session.isRunning else { return }   // 避免重复启动
        metadataOutputEnable = true                 // 启用元数据输出
        metadataQueue.async { [weak self] in
            self?.session.startRunning()            // 在后台队列启动会话
        }
    }
    
    /**
     * 停止扫描
     * 
     * 停止相机会话以节省资源。该方法会在后台队列中执行。
     */
    public func stopRunning() {
        guard session.isRunning else { return }    // 检查会话是否正在运行
        videoDataQueue.async { [weak self] in
            self?.session.stopRunning()             // 在后台队列停止会话
        }
        metadataOutputEnable = false               // 禁用元数据输出
    }
    
    /**
     * 重新扫描
     * 
     * 重置扫描器状态并重新开始扫描。该方法会清理当前的UI状态，
     * 重新创建扫码框和遮罩层，并带有动画效果。
     * 
     * 使用场景：
     * - 扫描完成后需要继续扫描
     * - 扫描出错后重新开始
     * - 用户手动触发重新扫描
     */
    public func rescan() {
        // 检查相机权限
        guard isAuthorized() else { return }
        
        // 步骤1：停止当前扫描
        metadataOutputEnable = false
        
        // 步骤2：清理UI状态
        focusImageView.removeFromSuperview()        // 移除扫码框
        
        // 步骤3：清理遮罩层
        overlayLayer?.removeFromSuperlayer()
        overlayLayer = nil
        
        // 步骤4：重置扫码框变换状态
        focusImageView.transform = CGAffineTransform.identity
        
        // 步骤5：重新创建扫码框
        focusImageView = UIImageView(frame: calculation())
        focusImageView.image = focusImage ?? UIImage(named: "scan_qr_focus", in: .module, compatibleWith: nil)
        addSubview(focusImageView)
        
        // 步骤6：重新设置遮罩层（带动画效果）
        setupOverlayMask(animated: true)
        
        // 步骤7：延迟重启扫描（避免时序问题）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.metadataOutputEnable = true
            self?.startRunning()
        }
    }
    
    /**
     * 启动遮罩层的缩放动画效果
     * 
     * 这个方法创建一个从小到大的缩放动画效果，为扫描界面提供视觉反馈。
     * 动画从30%的缩放开始，逐渐放大到正常尺寸，增强用户体验。
     * 
     * 实现步骤：
     * 1. 计算初始缩放状态的frame（30%大小）
     * 2. 创建对应的初始路径
     * 3. 立即设置初始状态
     * 4. 延迟执行缩放动画到正常尺寸
     */
    public func startOverlayAnimation() {
        guard let overlayLayer = overlayLayer else { return }
        
        // 设置动画的初始小尺寸状态
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
        
        // 创建初始的小尺寸路径
        let initialPath = UIBezierPath(rect: self.bounds)
        let initialFocusPath = UIBezierPath(roundedRect: scaledFrame, cornerRadius: overlayCornerRadius * initialScale)
        initialPath.append(initialFocusPath.reversing())
        
        // 立即设置初始状态
        overlayLayer.path = initialPath.cgPath
        focusImageView.frame = scaledFrame
        
        // 延迟执行动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateOverlayMaskScale()
        }
    }
    
    /**
     * 控制设备闪光灯的开关状态
     * 
     * 这个方法用于在扫描过程中控制设备的闪光灯，帮助在光线不足的环境下进行扫描。
     * 
     * @param isOn 是否开启闪光灯，true为开启，false为关闭
     * 
     * 安全检查：
     * - 确保在主线程执行
     * - 检查设备是否支持闪光灯
     * - 检查闪光灯是否可用
     * - 确保扫描器已启用
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
     * 布局子视图
     * 
     * 当视图的bounds发生变化时（如设备旋转、尺寸调整），系统会自动调用此方法。
     * 负责更新预览层和扫描区域的布局，确保界面在不同尺寸下正确显示。
     * 
     * 主要功能：
     * - 调用父类的layoutSubviews
     * - 更新预览层的frame以适应新的bounds
     * - 重新计算和更新扫描区域
     */
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // 更新预览层和遮罩层的frame
        let boundsChanged = previewLayer?.frame != self.bounds
        if boundsChanged {
            previewLayer?.frame = self.bounds
            overlayLayer?.frame = self.bounds
            
            // 更新扫码框位置
            focusImageView.frame = calculation()
        }
        
        // 确保视频方向正确
        updateVideoOrientation()
        
        // 如果bounds发生变化，更新遮罩
        if boundsChanged {
            updateOverlayMask()
            if scanningAreaLimit{
                updateScanningArea()
            }
        }
    }
    
    /**
     * 析构函数
     * 
     * 当QRScannerView实例被释放时自动调用，负责清理所有资源和观察者，
     * 防止内存泄漏和潜在的崩溃问题。
     * 
     * 清理步骤：
     * 1. 关闭闪光灯
     * 2. 停止摄像头会话
     * 3. 移除所有输入和输出
     * 4. 移除预览层
     * 5. 移除设备方向观察者
     * 6. 清理闪光灯状态观察者
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
     * 设置扫码框图片视图
     * 
     * 初始化并配置扫码框的UI组件，包括扫码框图片和遮罩层。
     * 这是UI初始化的关键步骤，为后续的扫码匹配动画做准备。
     */
    private func setupImageViews() {
        // 创建扫码框图片视图，使用计算出的初始位置和尺寸
        focusImageView = UIImageView(frame: calculation())
        
        // 设置扫码框图片，优先使用自定义图片，否则使用默认图片
        focusImageView.image = focusImage ?? UIImage(named: "scan_qr_focus", in: .module, compatibleWith: nil)
        
        // 将扫码框添加到视图层级中
        addSubview(focusImageView)
        
        // 设置遮罩层（不带动画，动画将由SwiftUI触发）
        setupOverlayMask(animated: false)
    }
    
    /// 创建遮罩层，focusImage区域透明，其他区域半透明黑色
    /**
     * 设置遮罩层
     * 
     * 创建一个半透明的遮罩层，覆盖整个视图，并在扫码框位置挖出一个透明区域。
     * 支持动画模式，可以从小尺寸逐渐放大到目标尺寸。
     * 
     * 实现原理：
     * 1. 使用CAShapeLayer创建遮罩
     * 2. 使用UIBezierPath的evenOdd填充规则创建挖空效果
     * 3. 支持动画模式下的缩放效果
     * 
     * @param animated 是否启用动画效果
     */
    private func setupOverlayMask(animated: Bool = false) {
        // 步骤1：移除现有的遮罩层（如果存在）
        overlayLayer?.removeFromSuperlayer()
        
        // 步骤2：创建新的遮罩层
        let overlay = CAShapeLayer()
        overlay.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor  // 半透明黑色
        overlay.frame = self.bounds
        
        if animated {
            // 动画模式：创建小尺寸的初始状态，稍后会放大
            let initialScale: CGFloat = 0.3  // 初始缩放比例
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
            
            // 创建初始的小尺寸透明区域路径
            let path = UIBezierPath(rect: self.bounds)  // 覆盖整个视图的实心路径
            let focusPath = UIBezierPath(roundedRect: scaledFrame, cornerRadius: overlayCornerRadius * initialScale)
            path.append(focusPath.reversing())  // 挖出透明区域
            overlay.path = path.cgPath
            
            // 同步设置focusImageView的初始小尺寸
            focusImageView.frame = scaledFrame
        } else {
            // 静态模式：直接创建最终状态
            let path = UIBezierPath(rect: self.bounds)
            let focusPath = UIBezierPath(roundedRect: focusImageView.frame, cornerRadius: overlayCornerRadius)
            path.append(focusPath.reversing())
            overlay.path = path.cgPath
        }
        
        // 步骤3：设置填充规则为evenOdd，实现挖空效果
        overlay.fillRule = .evenOdd
        
        // 步骤4：将遮罩层插入到正确的层级位置
        // 确保遮罩层在预览层之上，但在扫码框之下
        if let previewLayer = self.previewLayer {
            layer.insertSublayer(overlay, above: previewLayer)
        } else {
            layer.insertSublayer(overlay, at: 0)
        }
        
        // 步骤5：保存遮罩层引用
        self.overlayLayer = overlay
        
        // 步骤6：如果需要动画，延迟执行缩放动画
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.animateOverlayMaskScale()
            }
        }
    }
    
    /// 更新遮罩层的透明区域位置和大小
    private func updateOverlayMask() {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // 首先更新遮罩层的frame以匹配当前视图bounds
        overlayLayer.frame = self.bounds
        
        // Create path for the entire view
        let path = UIBezierPath(rect: self.bounds)
        
        // Create transparent hole for current focus area with rounded corners
        let focusPath = UIBezierPath(roundedRect: focusImageView.frame, cornerRadius: overlayCornerRadius)
        
        // 应用与focusImageView相同的旋转变换
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
    
    /// 执行遮罩层透明区域的移动和旋转动画
    /**
     * 执行遮罩层的移动和旋转动画
     * 
     * 该函数负责创建一个平滑的遮罩层动画，使透明区域从当前位置移动到目标位置，
     * 并同时应用旋转变换以匹配QR码的角度。
     * 
     * 实现原理：
     * 1. 使用CAShapeLayer的path属性进行动画
     * 2. 创建一个覆盖整个视图的路径，然后挖出一个透明的旋转矩形
     * 3. 通过CGAffineTransform实现围绕中心点的旋转
     * 
     * @param targetFrame 目标透明区域的frame
     * @param rotation 旋转角度（弧度）
     * @param duration 动画持续时间
     */
    private func animateOverlayMaskMovement(to targetFrame: CGRect, rotation: CGFloat, duration: TimeInterval) {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // 步骤1：更新遮罩层的frame以匹配当前视图bounds
        overlayLayer.frame = self.bounds
        
        // 步骤2：保存当前路径作为动画起始状态
        let fromPath = overlayLayer.path
        
        // 步骤3：创建目标路径（覆盖整个视图的实心路径）
        let toPath = UIBezierPath(rect: self.bounds)
        
        // 步骤4：创建透明区域的路径（带圆角）
        let targetFocusPath = UIBezierPath(roundedRect: targetFrame, cornerRadius: overlayCornerRadius)
        
        // 步骤5：应用旋转变换到透明区域
        // 使用标准的旋转变换：平移到中心 -> 旋转 -> 平移回原位置
        let center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)    // 移动到旋转中心
        transform = transform.rotated(by: rotation)                     // 执行旋转
        transform = transform.translatedBy(x: -center.x, y: -center.y)  // 移回原位置
        
        // 步骤6：应用变换并创建挖空效果
        targetFocusPath.apply(transform)
        toPath.append(targetFocusPath.reversing())  // reversing()创建挖空效果
        
        // 步骤7：创建路径动画
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = fromPath          // 起始路径
        pathAnimation.toValue = toPath.cgPath       // 目标路径
        pathAnimation.duration = duration           // 动画时长
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)  // 缓动函数
        pathAnimation.fillMode = .forwards          // 保持最终状态
        pathAnimation.isRemovedOnCompletion = false // 动画完成后不移除
        
        // 步骤8：执行动画
        overlayLayer.add(pathAnimation, forKey: "pathMoveAnimation")
        
        // 步骤9：设置最终状态（确保动画结束后状态正确）
        overlayLayer.path = toPath.cgPath
    }
    
    /// 执行透明区域从小到大的缩放动画
    private func animateOverlayMaskScale() {
        guard let overlayLayer = self.overlayLayer else { return }
        
        // 获取当前的小尺寸状态（初始状态）
        let currentPath = overlayLayer.path
        
        // 计算最终的合适尺寸状态（回到原始的calculation()计算出的尺寸）
        let finalFrame = calculation()
        
        // 创建最终路径（合适尺寸）
        let finalPath = UIBezierPath(rect: self.bounds)
        let finalFocusPath = UIBezierPath(roundedRect: finalFrame, cornerRadius: overlayCornerRadius)
        finalPath.append(finalFocusPath.reversing())
        
        // 创建遮罩层路径动画
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = currentPath
        pathAnimation.toValue = finalPath.cgPath
        pathAnimation.duration = overlayAnimationDuration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pathAnimation.fillMode = .forwards
        pathAnimation.isRemovedOnCompletion = false
        
        // 执行遮罩层动画
        overlayLayer.add(pathAnimation, forKey: "pathScaleAnimation")
        
        // 创建focusImageView的frame动画
        UIView.animate(withDuration: overlayAnimationDuration, delay: 0, options: [.curveEaseOut], animations: { [weak self] in
            self?.focusImageView.frame = finalFrame
        }, completion: nil)
        
        // 设置最终状态
        overlayLayer.path = finalPath.cgPath
    }
    
    // MARK: Calculations
    /**
     * 计算扫码框的位置和尺寸
     * 
     * 根据设备方向和屏幕尺寸，智能计算扫码框的最佳位置和大小。
     * 确保在不同设备和方向下都有良好的用户体验。
     * 
     * 设计原则：
     * - 竖屏：使用黄金比例(0.618)确定尺寸，位置稍微偏上便于操作
     * - 横屏：使用较小尺寸避免遮挡过多内容，完全居中显示
     * 
     * @return 扫码框的CGRect，包含位置和尺寸信息
     */
    private func calculation() -> CGRect {
        let bounds = self.bounds
        let isLandscape = bounds.width > bounds.height
        
        // 步骤1：根据设备方向计算扫码框尺寸
        let scanSize: CGFloat
        if isLandscape {
            // 横屏模式：使用较保守的尺寸，避免占用过多屏幕空间
            // 取高度的60%和宽度的40%中的较小值
            scanSize = min(bounds.height * 0.6, bounds.width * 0.4)
        } else {
            // 竖屏模式：使用黄金比例(0.618)计算，提供最佳视觉效果
            // 基于屏幕较短边的61.8%
            scanSize = min(bounds.width, bounds.height) * 0.618
        }
        
        // 步骤2：计算水平居中位置
        let x = (bounds.width - scanSize) / 2
        
        // 步骤3：根据方向计算垂直位置
        let y: CGFloat
        if isLandscape {
            // 横屏时完全垂直居中，提供平衡的视觉效果
            y = (bounds.height - scanSize) / 2
        } else {
            // 竖屏时稍微偏上(19.1%位置)，便于用户操作
            // 这个位置既不会太靠上影响状态栏，也不会太居中影响下方操作
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
            // iPhone: 检查应用是否只支持竖屏
            let supportedOrientations = UIApplication.shared.supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations == .portraitUpsideDown
            
            if isPortraitOnly {
                // 只支持竖屏的iPhone应用，不需要监听方向变化，直接设置初始方向
                currentOrientation = .portrait
                updateVideoOrientation()
                return
            }
        }
        
        // 启用设备方向通知
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        // 监听设备旋转通知
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleOrientationChange()
        }
        
        // 初始化当前方向
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
        
        // 只处理有效的方向变化
        guard newOrientation != currentOrientation,
              newOrientation.isValidInterfaceOrientation else {
            return
        }
        
        let previousOrientation = currentOrientation
        currentOrientation = newOrientation
        
        // 立即更新视频方向
        updateVideoOrientation()
        
        // 使用动画更新UI布局
        UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseInOut]) { [weak self] in
            // 强制布局更新
            self?.setNeedsLayout()
            self?.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self = self else{ return }
            // 动画完成后重新设置遮罩层以确保正确适配
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
        
        // 获取当前应用的界面方向
        let interfaceOrientation: UIInterfaceOrientation
        if #available(iOS 13.0, *) {
            interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
        } else {
            interfaceOrientation = UIApplication.shared.statusBarOrientation
        }
        
        let videoOrientation: AVCaptureVideoOrientation
        
        // 对于只支持竖屏的应用，优先使用界面方向
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone: 检查应用是否只支持竖屏
            let supportedOrientations = UIApplication.shared.supportedInterfaceOrientations(for: UIApplication.shared.windows.first)
            let isPortraitOnly = supportedOrientations == .portrait || supportedOrientations == .portraitUpsideDown
            
            if isPortraitOnly {
                // 只支持竖屏的iPhone应用，始终使用竖屏方向
                videoOrientation = .portrait
            } else {
                // 支持多方向的iPhone应用，使用界面方向
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
            // iPad: 使用界面方向
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
    
    /// 设置扫码区域限制
    private func updateScanningArea() {
        guard let previewLayer = self.previewLayer else { return }
        
        // 计算扫码框在预览层中的相对位置
        let scanRect = calculation()
        let previewBounds = previewLayer.bounds
        
        // 转换为相对坐标 (0-1)
        let rectOfInterest = CGRect(
            x: scanRect.minY / previewBounds.height,
            y: scanRect.minX / previewBounds.width,
            width: scanRect.height / previewBounds.height,
            height: scanRect.width / previewBounds.width
        )
        
        // 设置扫码区域限制
        metadataOutput.rectOfInterest = rectOfInterest
    }
    
    /**
     * 移动和调整扫码框以匹配检测到的QR码
     * 
     * 该函数是QR码扫描框精确匹配的核心算法，解决了以下关键问题：
     * 1. 扫码框形状变形（长条形 -> 正方形）
     * 2. 角度偏移（90度旋转错误）
     * 3. 中心点不对齐
     * 4. 尺寸不匹配
     * 
     * @param corners QR码的四个角点坐标，顺序为：[左上, 右上, 右下, 左下]
     *                这些坐标已经通过previewLayer转换到视图坐标系
     */
    private func moveImageViews(corners: [CGPoint]) {
        assert(Thread.isMainThread)
        
        // 数据验证：确保有4个角点
        guard corners.count == 4 else { return }
        
        // 步骤1：计算QR码的几何中心点
        // 使用四个角点的平均值，比path.bounds.center更精确
        let centerX = corners.reduce(0) { $0 + $1.x } / 4
        let centerY = corners.reduce(0) { $0 + $1.y } / 4
        let qrCenter = CGPoint(x: centerX, y: centerY)
        
        // 步骤2：计算QR码的平均边长
        // 遍历四条边，计算每条边的长度，然后取平均值
        // 这样可以处理轻微的透视变形，得到更稳定的尺寸
        var totalLength: CGFloat = 0
        for i in 0..<4 {
            let nextIndex = (i + 1) % 4
            let sideLength = hypot(corners[i].x - corners[nextIndex].x, corners[i].y - corners[nextIndex].y)
            totalLength += sideLength
        }
        let averageSideLength = totalLength / 4
        
        // 步骤3：计算QR码的旋转角度
        // 关键修复：使用左边（corners[0] -> corners[3]）而不是上边（corners[0] -> corners[1]）
        // 这样避免了90度的角度偏移问题
        // corners顺序：[0]左上 -> [1]右上 -> [2]右下 -> [3]左下
        let deltaX = corners[3].x - corners[0].x  // 左上角到左下角的X方向分量
        let deltaY = corners[3].y - corners[0].y  // 左上角到左下角的Y方向分量
        let rotationAngle = atan2(deltaY, deltaX) // 计算与水平轴的夹角
        
        // 步骤4：创建扫码框的目标frame
        // 保持正方形形状，尺寸基于平均边长加上padding
        let frameSize = averageSideLength + focusImagePadding * 2
        let targetFrame = CGRect(
            x: qrCenter.x - frameSize / 2,  // 以中心点为基准
            y: qrCenter.y - frameSize / 2,
            width: frameSize,
            height: frameSize
        )
        
        // 步骤5：执行focusImageView的动画变换
        UIView.animate(withDuration: animationDuration, animations: { [weak self] in
            guard let strongSelf = self else { return }
            
            // 重置transform以避免累积变换效应
            strongSelf.focusImageView.transform = CGAffineTransform.identity
            
            // 设置新的frame（位置和尺寸）
            strongSelf.focusImageView.frame = targetFrame
            
            // 应用旋转变换（围绕中心点旋转）
            strongSelf.focusImageView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
        }, completion: { _ in })
        
        // 步骤6：同步执行遮罩层的移动和旋转动画
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
     * 处理摄像头检测到的元数据对象（QR码等）
     * 
     * 这是AVCaptureMetadataOutputObjectsDelegate的核心回调方法，当摄像头检测到
     * QR码或其他支持的元数据对象时会被调用。
     * 
     * 处理流程：
     * 1. 获取第一个检测到的元数据对象
     * 2. 转换为可读的机器码对象
     * 3. 在主线程更新UI（移动扫描框到检测位置）
     * 4. 如果扫描已启用，提取字符串值并回调成功结果
     * 5. 关闭闪光灯并禁用进一步扫描
     * 
     * @param output 元数据输出对象
     * @param metadataObjects 检测到的元数据对象数组
     * @param connection 捕获连接
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
 * UIDeviceOrientation扩展
 * 
 * 为UIDeviceOrientation添加便利属性，用于判断设备方向是否为有效的界面方向。
 * 这个扩展帮助过滤掉不适用于界面布局的设备方向（如平放、倒置等）。
 */
extension UIDeviceOrientation {
    /**
     * 判断当前设备方向是否为有效的界面方向
     * 
     * 有效的界面方向包括：
     * - portrait: 竖屏正向
     * - portraitUpsideDown: 竖屏倒置
     * - landscapeLeft: 横屏左转
     * - landscapeRight: 横屏右转
     * 
     * @return 如果是有效的界面方向返回true，否则返回false
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
