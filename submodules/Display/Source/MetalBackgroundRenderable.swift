import UIKit

public enum MetalBackgroundAnimation {
    case scaleUp
    case scaleDown
}

public protocol MetalBackgroundRenderable: AnyObject {
    var shouldRenderBackgroundInMetal: Bool { get set }
    var backgroundNodeCornerRadius: CGFloat { get }
    var visibleView: UIView { get }
    var id: String { get set }
    var animation: MetalBackgroundAnimation? { get set }
}
