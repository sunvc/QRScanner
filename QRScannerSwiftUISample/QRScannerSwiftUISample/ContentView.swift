import AVFoundation
import QRScanner
import SwiftUI

struct ContentView: View {
    @State private var isScanning = true
    @State private var isTorchOn = false
    @State private var shouldRescan = false
    @State private var showOverlay = false
    @State private var videoZoomFactor: Double = 3.0
    @State private var scale: Double = 1
    @GestureState private var gestureScale: CGFloat = 1.0
    var body: some View {
        ZStack {
            QRScannerSwiftUIView(
                isScanning: $isScanning,
                torchActive: $isTorchOn,
                shouldRescan: $shouldRescan,
                showOverlay: showOverlay,
                videoZoomFactor: scale * gestureScale,
                onSuccess: { qrCode in
                    print("QR Code scanned: \(qrCode)")
                },
                onFailure: { error in
                    print("QR Scanner error: \(error.localizedDescription)")
                },
                onTorchActiveChange: { isOn in
                    isTorchOn = isOn
                }
            )
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                setupQRScanner()
            }
            .onDisappear {
                isScanning = false
            }

            VStack {
                Spacer()
                HStack {
                    Button {
                        self.shouldRescan = true
                    } label: {
                        Text("Rescan")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 50)
                    Spacer()
                    Button {
                        self.showOverlay = true
                    } label: {
                        Text("Overly")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 50)
                    Spacer()
                    Button(action: {
                        isTorchOn.toggle()
                    }) {
                        Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 50)
                }
            }
        }
    
        .simultaneousGesture(
            MagnificationGesture()
                .updating($gestureScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    let newScale = scale * value
                    withAnimation { 
                        scale = min(max(newScale, 1.0), 10.0)
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded{_ in
                    withAnimation { 
                        if scale >= 1.0 && scale < 2.0{
                            self.scale = 2.0
                        }else if scale >= 2.0 && scale < 6.0 {
                            self.scale = 6.0
                        }else {
                            scale = 1.0
                        }
                    }
                }
        )
    }

    private func setupQRScanner() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScanning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isScanning = true
                    } else {
                        print("Camera is required to use in this application")
                    }
                }
            }
        default:
            print("Camera access denied or restricted")
        }
    }
}

#Preview {
    ContentView()
}
