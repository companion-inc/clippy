import CoreGraphics

public struct ClippyBodyScale: Equatable, Sendable {
    public static let `default` = ClippyBodyScale(1.0)
    public static let minimum = 0.5
    public static let maximum = 2.0
    public static let step = 0.25
    public static let defaultRasterScale: CGFloat = 2

    public let value: Double

    public init(_ value: Double) {
        self.value = min(Self.maximum, max(Self.minimum, value))
    }

    public func adjusted(by steps: Int) -> ClippyBodyScale {
        ClippyBodyScale(value + Double(steps) * Self.step)
    }

    public var rasterScale: CGFloat {
        Self.defaultRasterScale * CGFloat(value)
    }

    public var percentTitle: String {
        "\(Int((value * 100).rounded()))%"
    }
}
