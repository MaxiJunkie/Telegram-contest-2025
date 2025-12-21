import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import UIKitRuntimeUtils
import CoreImage
import AppBundle

private final class ContentContainer: UIView {
    private let maskContentView: UIView
    
    init(maskContentView: UIView) {
        self.maskContentView = maskContentView
        
        super.init(frame: CGRect())
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if result === self {
            if let gestureRecognizers = self.gestureRecognizers, !gestureRecognizers.isEmpty {
                return result
            }
            return nil
        }
        return result
    }
    
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        
        if let subview = subview as? GlassBackgroundView.ContentView {
            self.maskContentView.addSubview(subview.tintMask)
        }
    }
    
    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        
        if let subview = subview as? GlassBackgroundView.ContentView {
            subview.tintMask.removeFromSuperview()
        }
    }
}

public class LiquidGlassBackgroundView: UIView {
    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }
    
    open class ContentLayer: SimpleLayer {
        public var targetLayer: CALayer?
        
        override init() {
            super.init()
        }
        
        override init(layer: Any) {
            super.init(layer: layer)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override public var position: CGPoint {
            get {
                return super.position
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.position = value
                }
                super.position = value
            }
        }
        
        override public var bounds: CGRect {
            get {
                return super.bounds
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.bounds = value
                }
                super.bounds = value
            }
        }
        
        override public var anchorPoint: CGPoint {
            get {
                return super.anchorPoint
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPoint = value
                }
                super.anchorPoint = value
            }
        }
        
        override public var anchorPointZ: CGFloat {
            get {
                return super.anchorPointZ
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPointZ = value
                }
                super.anchorPointZ = value
            }
        }
        
        override public var opacity: Float {
            get {
                return super.opacity
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.opacity = value
                }
                super.opacity = value
            }
        }
        
        override public var sublayerTransform: CATransform3D {
            get {
                return super.sublayerTransform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.sublayerTransform = value
                }
                super.sublayerTransform = value
            }
        }
        
        override public var transform: CATransform3D {
            get {
                return super.transform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.transform = value
                }
                super.transform = value
            }
        }
        
        override public func add(_ animation: CAAnimation, forKey key: String?) {
            if let targetLayer = self.targetLayer {
                targetLayer.add(animation, forKey: key)
            }
            
            super.add(animation, forKey: key)
        }
        
        override public func removeAllAnimations() {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAllAnimations()
            }
            
            super.removeAllAnimations()
        }
        
        override public func removeAnimation(forKey: String) {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAnimation(forKey: forKey)
            }
            
            super.removeAnimation(forKey: forKey)
        }
    }
    
    public final class ContentColorView: UIView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }
        
        public let tintMask: UIView
        
        override public init(frame: CGRect) {
            self.tintMask = UIView()
            
            super.init(frame: CGRect())
            
            self.tintMask.tintColor = .black
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public final class ContentImageView: UIImageView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }
        
        private let tintImageView: UIImageView
        public var tintMask: UIView {
            return self.tintImageView
        }
        
        override public var image: UIImage? {
            didSet {
                self.tintImageView.image = self.image
            }
        }
        
        override public var tintColor: UIColor? {
            didSet {
                if self.tintColor != oldValue {
                    self.setMonochromaticEffect(tintColor: self.tintColor)
                }
            }
        }
        
        override public init(frame: CGRect) {
            self.tintImageView = UIImageView()
            
            super.init(frame: CGRect())
            
            self.tintImageView.tintColor = .black
        }
        
        override public init(image: UIImage?) {
            self.tintImageView = UIImageView()
            
            super.init(image: image)
            
            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }
        
        override public init(image: UIImage?, highlightedImage: UIImage?) {
            self.tintImageView = UIImageView()
            
            super.init(image: image, highlightedImage: highlightedImage)
            
            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public struct TintColor: Equatable {
        public enum Kind {
            case panel
            case custom
        }
        
        public let kind: Kind
        public let color: UIColor
        public let innerColor: UIColor?
        
        public init(kind: Kind, color: UIColor, innerColor: UIColor? = nil) {
            self.kind = kind
            self.color = color
            self.innerColor = innerColor
        }
    }
    
    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
    }
    
    private final class ClippingShapeContext {
        let view: UIView
        
        private(set) var shape: Shape?
        
        init(view: UIView) {
            self.view = view
        }
        
        func update(shape: Shape, size: CGSize, transition: ComponentTransition) {
            self.shape = shape
            
            switch shape {
            case let .roundedRect(cornerRadius):
                transition.setCornerRadius(layer: self.view.layer, cornerRadius: cornerRadius)
            }
        }
    }
    
    public struct Params: Equatable {
        public let shape: Shape
        public let isDark: Bool
        public let tintColor: TintColor
        public let isInteractive: Bool
        
        init(shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool) {
            self.shape = shape
            self.isDark = isDark
            self.tintColor = tintColor
            self.isInteractive = isInteractive
        }
    }
    
    private let backgroundNode: NavigationBackgroundNode?
    
    private let nativeView: UIVisualEffectView?
    private let nativeViewClippingContext: ClippingShapeContext?
    private let nativeParamsView: EffectSettingsContainerView?
    
    private let foregroundView: UIImageView?
    private let shadowView: UIImageView?
    
    private let maskContainerView: UIView
    public let maskContentView: UIView
    private let contentContainer: ContentContainer
    
    private var innerBackgroundView: UIView?
    
    public var contentView: UIView {
        if let nativeView = self.nativeView {
            return nativeView.contentView
        } else {
            return self.contentContainer
        }
    }
    
    public private(set) var params: Params?
        
    public static var useCustomGlassImpl: Bool = true
    
    public override init(frame: CGRect) {
        let backgroundNode = NavigationBackgroundNode(color: .white, enableBlur: false, customBlurRadius: 8.0)
        self.backgroundNode = backgroundNode
        self.nativeView = nil
        self.nativeViewClippingContext = nil
        self.nativeParamsView = nil
        self.foregroundView = UIImageView()
        
        self.shadowView = UIImageView()
        
        self.maskContainerView = UIView()
        self.maskContainerView.backgroundColor = .white
        if let filter = CALayer.luminanceToAlpha() {
            self.maskContainerView.layer.filters = [filter]
        }
        self.maskContentView = UIView()
        self.maskContainerView.addSubview(self.maskContentView)
        
        self.contentContainer = ContentContainer(maskContentView: self.maskContentView)
        
        super.init(frame: frame)
        
        if let shadowView = self.shadowView {
            self.addSubview(shadowView)
        }
        if let nativeParamsView = self.nativeParamsView {
            self.addSubview(nativeParamsView)
        }
        if let backgroundNode = self.backgroundNode {
            self.addSubview(backgroundNode.view)
        }
        if let foregroundView = self.foregroundView {
            self.addSubview(foregroundView)
            foregroundView.mask = self.maskContainerView
        }
        self.addSubview(self.contentContainer)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let nativeView = self.nativeView {
            if let result = nativeView.hitTest(self.convert(point, to: nativeView), with: event) {
                return result
            }
        } else {
            if let result = self.contentContainer.hitTest(self.convert(point, to: self.contentContainer), with: event) {
                return result
            }
        }
        return nil
    }
        
    public func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, transition: transition)
    }
    
    public func update(size: CGSize, shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        if let nativeView = self.nativeView, let nativeViewClippingContext = self.nativeViewClippingContext, (nativeView.bounds.size != size || nativeViewClippingContext.shape != shape) {
            
            nativeViewClippingContext.update(shape: shape, size: size, transition: transition)
            if transition.animation.isImmediate {
                nativeView.frame = CGRect(origin: CGPoint(), size: size)
            } else {
                let nativeFrame = CGRect(origin: CGPoint(), size: size)
                transition.setFrame(view: nativeView, frame: nativeFrame)
            }
        }
        if let backgroundNode = self.backgroundNode {
            backgroundNode.updateColor(color: .white, forceKeepBlur: tintColor.color.alpha != 1.0, transition: transition.containedViewLayoutTransition)
            
            switch shape {
            case let .roundedRect(cornerRadius):
                backgroundNode.update(size: size, cornerRadius: cornerRadius, transition: transition.containedViewLayoutTransition)
            }
            transition.setFrame(view: backgroundNode.view, frame: CGRect(origin: CGPoint(), size: size))
        }
        
        let shadowInset: CGFloat = 32.0
        
        if let innerColor = tintColor.innerColor {
            let innerBackgroundFrame = CGRect(origin: CGPoint(), size: size).insetBy(dx: 3.0, dy: 3.0)
            let innerBackgroundRadius = min(innerBackgroundFrame.width, innerBackgroundFrame.height) * 0.5
            
            let innerBackgroundView: UIView
            var innerBackgroundTransition = transition
            var animateIn = false
            if let current = self.innerBackgroundView {
                innerBackgroundView = current
            } else {
                innerBackgroundView = UIView()
                innerBackgroundTransition = innerBackgroundTransition.withAnimation(.none)
                self.innerBackgroundView = innerBackgroundView
                self.contentView.insertSubview(innerBackgroundView, at: 0)
                
                innerBackgroundView.frame = innerBackgroundFrame
                innerBackgroundView.layer.cornerRadius = innerBackgroundRadius
                animateIn = true
            }
            
            innerBackgroundView.backgroundColor = innerColor
            innerBackgroundTransition.setFrame(view: innerBackgroundView, frame: innerBackgroundFrame)
            innerBackgroundTransition.setCornerRadius(layer: innerBackgroundView.layer, cornerRadius: innerBackgroundRadius)
            
            if animateIn {
                transition.animateAlpha(view: innerBackgroundView, from: 0.0, to: 1.0)
                transition.animateScale(view: innerBackgroundView, from: 0.001, to: 1.0)
            }
        } else if let innerBackgroundView = self.innerBackgroundView {
            self.innerBackgroundView = nil
            
            transition.setAlpha(view: innerBackgroundView, alpha: 0.0, completion: { [weak innerBackgroundView] _ in
                innerBackgroundView?.removeFromSuperview()
            })
            transition.setScale(view: innerBackgroundView, scale: 0.001)
            
            innerBackgroundView.removeFromSuperview()
        }
        
        let params = Params(shape: shape, isDark: isDark, tintColor: tintColor, isInteractive: isInteractive)
        if self.params != params {
            self.params = params
            
            let outerCornerRadius: CGFloat
            switch shape {
            case let .roundedRect(cornerRadius):
                outerCornerRadius = cornerRadius
            }
            
            if let shadowView = self.shadowView {
                let shadowInnerInset: CGFloat = 0.5
                shadowView.image = generateImage(CGSize(width: shadowInset * 2.0 + outerCornerRadius * 2.0, height: shadowInset * 2.0 + outerCornerRadius * 2.0), rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    
                    context.setFillColor(UIColor.black.cgColor)
                    context.setShadow(offset: CGSize(width: 0.0, height: 1.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.04).cgColor)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))
                    
                    context.setFillColor(UIColor.clear.cgColor)
                    context.setBlendMode(.copy)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))
                })?.stretchableImage(withLeftCapWidth: Int(shadowInset + outerCornerRadius), topCapHeight: Int(shadowInset + outerCornerRadius))
            }
            
            if let foregroundView = self.foregroundView {
                foregroundView.image = GlassBackgroundView.generateLegacyGlassImage(size: CGSize(width: outerCornerRadius * 2.0, height: outerCornerRadius * 2.0), inset: shadowInset, isDark: isDark, fillColor: tintColor.color)
            } else {
                if let nativeParamsView = self.nativeParamsView, let nativeView = self.nativeView {
                    if #available(iOS 26.0, *) {
                        let glassEffect = UIGlassEffect(style: .regular)
                        switch tintColor.kind {
                        case .panel:
                            glassEffect.tintColor = nil
                        case .custom:
                            glassEffect.tintColor = tintColor.color
                        }
                        glassEffect.isInteractive = params.isInteractive
                        
                        if transition.animation.isImmediate {
                            nativeView.effect = glassEffect
                        } else {
                            UIView.animate(withDuration: 0.2, animations: {
                                nativeView.effect = glassEffect
                            })
                        }
                        
                        if isDark {
                            nativeParamsView.lumaMin = 0.0
                            nativeParamsView.lumaMax = 0.15
                        } else {
                            nativeParamsView.lumaMin = 0.25
                            nativeParamsView.lumaMax = 1.0
                        }
                    }
                }
            }
        }
        
        transition.setFrame(view: self.maskContainerView, frame: CGRect(origin: CGPoint(), size: CGSize(width: size.width + shadowInset * 2.0, height: size.height + shadowInset * 2.0)))
        transition.setFrame(view: self.maskContentView, frame: CGRect(origin: CGPoint(x: shadowInset, y: shadowInset), size: size))
        if let foregroundView = self.foregroundView {
            transition.setFrame(view: foregroundView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        if let shadowView = self.shadowView {
            transition.setFrame(view: shadowView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        transition.setFrame(view: self.contentContainer, frame: CGRect(origin: CGPoint(), size: size))
    }
}
