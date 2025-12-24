import UIKit
import ComponentFlow

public final class LiquidGlassBackgroundContainerView: UIView {
    
    private let liquidGlassBackgroundView: LiquidGlassBackgroundView
    
    public override init(frame: CGRect) {
        self.liquidGlassBackgroundView = LiquidGlassBackgroundView()
        super.init(frame: frame)
        self.addSubview(liquidGlassBackgroundView)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func addSubview(_ view: UIView) {
        super.addSubview(view)
        liquidGlassBackgroundView.addRenderableViewIfNeeded(view)
    }
    
    public func update(size: CGSize, isDark: Bool, transition: ComponentTransition) {
        let scale = UIScreen.main.scale
        let origin = CGPoint(x: 0, y: -100)
        let size = CGSize(width: size.width, height: size.height - 2 * origin.y)
        liquidGlassBackgroundView.setRenderSize(CGSize(width: size.width * scale, height: size.height * scale))
        transition.setFrame(view: liquidGlassBackgroundView, frame: CGRect(origin: origin, size: size))
    }
}
