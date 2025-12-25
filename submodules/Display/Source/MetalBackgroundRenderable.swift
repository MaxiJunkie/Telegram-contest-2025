import UIKit

public protocol MetalBackgroundRenderable: AnyObject {
    var shouldRenderBackgroundInMetal: Bool { get set }
    var backgroundNodeCornerRadius: CGFloat { get }
    var visibleView: UIView { get }
    var id: String { get set }
    var isAnimating: Bool { get set }
}
