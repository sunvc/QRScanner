# QRScanner

Fork from: [mercari/QRScanner](https://github.com/mercari/QRScanner)

一个现代化的iOS二维码扫描框架，支持SwiftUI和UIKit，提供原生iOS扫描体验。

* 修改源代码，新增遮罩层，适配设备的横屏扫描支持，修复ipad横屏状态下相机方向不一致问题
* 增加扫描区域控制，可以单独控制扫描区域是否限制在扫描框内
* 增加扫描二维码的类型控制，自定义指定支持的类型， 默认支持QRCode, Aztec， 可以根据需求添加其他类型， 如PDF417, DataMatrix ...等。
* 增加rescan功能， 可以在扫描到二维码后， 控制重新扫描
* 修改其他若干细节，优化性能和用户体验


## 安装

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/sunvc/QRScanner.git", from: "0.3.0")
]
```


## 使用

请参考项目中的示例代码，了解如何在SwiftUI和UIKit中使用QRScanner。

## 贡献

欢迎提交Pull Request来改进QRScanner。在提交之前，请确保您的代码符合项目的编码规范。