import UIKit

public protocol MetalBackgroundRenderable {
    var shouldRenderBackgroundInMetal: Bool { get set }
    var backgroundNodeCornerRadius: CGFloat { get }
    var visibleView: UIView { get }
    var id: String { get set }
}
