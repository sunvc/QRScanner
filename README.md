# QRScanner

Fork from: [mercari/QRScanner](https://github.com/mercari/QRScanner)

A modern iOS QR code scanning framework that supports SwiftUI and UIKit, providing a native iOS scanning experience.

- Modified source code to add an overlay mask, adapted for landscape scanning support, and fixed camera orientation inconsistency on iPad in landscape mode.
- Added scanning area control, allowing you to control whether the scanning area is limited to the scan frame.
- Added QR code type control, allowing custom supported types. Defaults to QRCode and Aztec; other types like PDF417, DataMatrix, etc., can be added as needed.
- Added rescan functionality, allowing control to restart scanning after a QR code is detected.
- Modified various other details to optimize performance and user experience.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/sunvc/QRScanner.git", from: "0.3.0")
]
```

## Usage

Please refer to the example code in the project to learn how to use QRScanner in SwiftUI and UIKit.

## Contribution

Pull Requests are welcome to improve QRScanner. Before submitting, please ensure your code complies with the project's coding standards.
