import AVFoundation

public enum CameraPermission {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static var isGranted: Bool {
        status == .authorized
    }

    public static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
