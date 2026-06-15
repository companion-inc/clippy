import Foundation

public struct ImageObservation: Equatable, Sendable {
    public let data: Data
    public let mimeType: String
    public let capturedAt: Date
    public let note: String?

    public init(data: Data, mimeType: String, capturedAt: Date = Date(), note: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.capturedAt = capturedAt
        self.note = note
    }
}

public struct UIElementSnapshot: Codable, Equatable, Sendable {
    public let role: String?
    public let title: String?
    public let value: String?
    public let frame: RectSnapshot?
    public let children: [UIElementSnapshot]

    public init(
        role: String? = nil,
        title: String? = nil,
        value: String? = nil,
        frame: RectSnapshot? = nil,
        children: [UIElementSnapshot] = []
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.children = children
    }
}

public struct RectSnapshot: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public protocol ScreenObserving: Sendable {
    func captureScreen(question: String?) async throws -> ImageObservation
}

public protocol CameraObserving: Sendable {
    func captureCamera(question: String?) async throws -> ImageObservation
}

public protocol UIElementObserving: Sendable {
    func focusedElement() async throws -> UIElementSnapshot
    func element(at point: CharacterPoint) async throws -> UIElementSnapshot
}
