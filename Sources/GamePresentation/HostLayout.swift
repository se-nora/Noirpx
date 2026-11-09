/// Shared bounds for the top-left HUD, expressed in host view points.
public enum HostLayout {
    public static let outerPadding: Double = 16
    public static let innerPadding: Double = 10

    public static func hudWidth(viewWidth: Double) -> Double {
        max(0, viewWidth * 0.45)
    }

    public static func hudContentWidth(viewWidth: Double) -> Double {
        max(0, hudWidth(viewWidth: viewWidth) - 2 * (outerPadding + innerPadding))
    }

    public static func hudContentHeight(viewHeight: Double, bottomReserved: Double = 0) -> Double {
        max(0, viewHeight - max(0, bottomReserved) - 2 * (outerPadding + innerPadding))
    }
}
