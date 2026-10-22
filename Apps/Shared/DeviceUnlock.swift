#if os(iOS) || os(macOS)
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import LocalAuthentication

    #if os(iOS)
        import UIKit
    #endif

    /// What the backup screens need to know about this device: which kind it is (the copy says "this iPhone" or
    /// "this Mac") and its biometry for the Delete footnote. Read here in the App layer so Domain and Features stay free of system APIs.
    @MainActor
    enum DeviceUnlock {
        static var device: BackupDevice {
            #if os(iOS)
                UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
            #else
                .mac
            #endif
        }

        static var method: AppUnlockMethod {
            let context = LAContext()
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcodeOnly
            }
        }
    }
#endif
