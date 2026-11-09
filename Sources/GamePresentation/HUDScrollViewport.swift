#if canImport(SwiftUI)
import SwiftUI

private struct HUDContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A bounded, vertically scrollable HUD; its content remains reachable in small windows.
public struct HUDScrollViewport<Content: View>: View {
    private let width: Double
    private let height: Double
    private let bottomReserved: Double
    private let content: Content
    @State private var measuredHeight: CGFloat = 0

    public init(width: Double, height: Double, bottomReserved: Double = 0,
                @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.bottomReserved = bottomReserved
        self.content = content()
    }

    public var body: some View {
        let maximumHeight = HostLayout.hudContentHeight(viewHeight: height, bottomReserved: bottomReserved)
        ScrollView(.vertical) {
            content
                .frame(width: HostLayout.hudContentWidth(viewWidth: width), alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: HUDContentHeightKey.self, value: geometry.size.height)
                })
        }
        .scrollIndicators(.visible)
        .frame(width: HostLayout.hudContentWidth(viewWidth: width),
               height: measuredHeight > 0 ? min(maximumHeight, measuredHeight) : maximumHeight,
               alignment: .topLeading)
        .onPreferenceChange(HUDContentHeightKey.self) { measuredHeight = $0 }
        .clipped()
        .padding(HostLayout.innerPadding)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .padding(HostLayout.outerPadding)
    }
}
#endif
