import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import UIKitRuntimeUtils
import CoreImage
import AppBundle

final class LiquidGlassBlurNode: MTKView {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func commonInit() {
        backgroundColor = .red
    }
    
    func update(
        size: CGSize,
        cornerRadius: CGFloat = 0.0,
        transition: ContainedViewLayoutTransition,
        beginWithCurrentState: Bool = true
    ) {
        let contentFrame = CGRect(origin: CGPoint(), size: size)
        self.frame = contentFrame
        self.layer.cornerRadius = cornerRadius
    }
    
    func update(size: CGSize, cornerRadius: CGFloat = 0.0, animator: ControlledTransitionAnimator) {
        let contentFrame = CGRect(origin: CGPoint(), size: size)
        self.frame = contentFrame
        self.layer.cornerRadius = cornerRadius
    }
}
