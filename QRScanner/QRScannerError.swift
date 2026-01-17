//
//  QRScannerError.swift
//  QRScanner
//
//  Created by wbi on 2019/10/16.
//  Copyright © 2019 Mercari, Inc. All rights reserved.
//

import Foundation
import AVFoundation

// MARK: - QRScannerError

/// Errors that can occur during QR code scanning
public enum QRScannerError: Error {
    /// Camera access unauthorized
    case unauthorized(AVAuthorizationStatus)
    
    /// Device related failure
    case deviceFailure(DeviceError)
    
    /// Failed to read QR code
    case readFailure
    
    /// Unknown error
    case unknown

    /// Specific device errors
    public enum DeviceError {
        /// Video device unavailable
        case videoUnavailable
        
        /// Input device invalid
        case inputInvalid
        
        /// Metadata output configuration failed
        case metadataOutputFailure
    }
}
