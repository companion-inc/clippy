import AVFoundation

public enum MicrophonePermission {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static var isGranted: Bool {
        status == .authorized
    }

    public static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
