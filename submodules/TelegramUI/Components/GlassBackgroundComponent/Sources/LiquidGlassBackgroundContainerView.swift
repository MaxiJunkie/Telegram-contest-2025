import UIKit
import ComponentFlow
import AsyncDisplayKit

public final class LiquidGlassBackgroundContainerView: UIView {
    
    public var renderView: UIView {
        liquidGlassBackgroundView
    }
    
    private let liquidGlassBackgroundView: LiquidGlassBackgroundView
    
    public override init(frame: CGRect) {
        self.liquidGlassBackgroundView = LiquidGlassBackgroundView()
        super.init(frame: frame)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func addSubview(_ view: UIView) {
        super.addSubview(view)
        liquidGlassBackgroundView.addRenderableViewIfNeeded(view)
    }
    
    public func update(frame: CGRect, transition: ComponentTransition) {
        let scale = UIScreen.main.scale
        liquidGlassBackgroundView.setRenderSize(CGSize(width: frame.width * scale, height: frame.height * scale))
        transition.setFrame(view: liquidGlassBackgroundView, frame: frame)
    }
}
