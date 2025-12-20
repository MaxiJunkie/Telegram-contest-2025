import UIKit
import MetalKit
import Foundation
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import GlassBackgroundComponent
import MultilineTextComponent
import LottieComponent
import UIKitRuntimeUtils
import BundleIconComponent
import TextBadgeComponent

class LiquidGlassTabBarOverlay: UIView {
    
    enum AnimationProgress {
        case showing(progress: Float)
        case dismissing(progress: Float)
    }
    
    private enum Spec {
        static var bubbleRelativeHeigth: CGFloat { 1.45 }
    }
    
    private var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }
    
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    var animationProgress: ((AnimationProgress) -> Void)?
    
    private var displayLink: CADisplayLink?
    
    private var renderer: LiquidGlassTabBarRenderer?
    
    private var selectionViewSize: CGSize = .zero
    private var tabBarSourceSize: CGSize = .zero
    
    private let innerInset: CGFloat = 3.0
    
    private var cachedComponent: TabBarComponent?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        
        displayLink?.invalidate()
        
        guard window != nil else { return }
        
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayTick))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }
    
    func updateBubblePosition(_ recognizer: UIPanGestureRecognizer, currentSelectionFrame: CGRect) {
        guard let renderer else { return }
        
        let velocity = recognizer.velocity(in: self)
        let xOffset: CGFloat = (bounds.width - tabBarSourceSize.width) / 2
        let initialXPosition = currentSelectionFrame.midX + xOffset
        
        switch recognizer.state {
        case .began:
            renderer.appearTarget = 1.0
            updateCenterAndStretch(xPosition: initialXPosition, velocity: velocity)

        case .changed:
            let location = recognizer.location(in: self)
            let haldWidth = currentSelectionFrame.width / 2 + innerInset
            let minX = haldWidth + xOffset
            let maxX = tabBarSourceSize.width - haldWidth + xOffset
            var newXPosition = min(max(location.x, minX), maxX)
            
            if renderer.bubbleIsAppearing {
                newXPosition = initialXPosition
            }
            
            updateCenterAndStretch(xPosition: newXPosition, velocity: velocity)

        case .ended, .cancelled, .failed:
            renderer.appearTarget = 0.0
            let xPosition = currentSelectionFrame.midX + xOffset
            updateCenterAndStretch(xPosition: xPosition, velocity: velocity)

        default:
            break
        }
    }
    
    func update(
        component: TabBarComponent,
        availableSize: CGSize,
        transition: ComponentTransition,
        selectionFrame: CGRect
    ) {
        self.selectionViewSize = selectionFrame.size
        
        if let cachedComponent, cachedComponent == component {
            return
        }
        
        let availableSize = CGSize(width: min(500.0, availableSize.width), height: availableSize.height)
        
        var itemSize = CGSize(width: floor((availableSize.width - innerInset * 2.0) / CGFloat(component.items.count)), height: 56.0)
        itemSize.width = min(94.0, itemSize.width)
        
        let contentHeight = itemSize.height + innerInset * 2.0
        var contentWidth: CGFloat = innerInset
        
        let backgroundViewForTexture = GlassBackgroundView()
        
        for index in 0 ..< component.items.count {
            let item = component.items[index]
            let itemTransition = transition
            let selectedItemView: ComponentView<ComponentFlow.Empty> = ComponentView()
            
            let _ = selectedItemView.update(
                transition: itemTransition,
                component: AnyComponent(ItemComponent(
                    item: item,
                    theme: component.theme,
                    isSelected: true
                )),
                environment: {},
                containerSize: itemSize
            )
            
            let itemFrame = CGRect(origin: CGPoint(x: contentWidth, y: floor((contentHeight - itemSize.height) * 0.5)), size: itemSize)
            if let selectedItemComponentView = selectedItemView.view as? ItemComponent.View {
                backgroundViewForTexture.addSubview(selectedItemComponentView)
                itemTransition.setFrame(view: selectedItemComponentView, frame: itemFrame)
            }
            
            contentWidth += itemFrame.width
        }
        contentWidth += innerInset
        
        let size = CGSize(width: min(availableSize.width, contentWidth), height: contentHeight)
        tabBarSourceSize = size
        
        transition.setFrame(view: backgroundViewForTexture, frame: CGRect(origin: CGPoint(), size: size))
        backgroundViewForTexture.update(
            size: size,
            cornerRadius: size.height * 0.5,
            isDark: component.theme.overallDarkAppearance,
            tintColor: .init(
                kind: .panel,
                color: component.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)),
            transition: transition
        )
        
        let metalViewHeight: CGFloat = size.height * Spec.bubbleRelativeHeigth
        let xOffset: CGFloat = (UIScreen.main.bounds.width - size.width) / 2
        let metalViewWidth = size.width + 2 * xOffset
        transition.setFrame(
            view: self,
            frame: CGRect(
                origin: CGPoint(x: -xOffset, y: (size.height - metalViewHeight) / 2),
                size: CGSize(width: metalViewWidth, height: metalViewHeight)
            )
        )
        
        if renderer == nil, let device = MTLCreateSystemDefaultDevice() {
            let scale = UIScreen.main.scale
            let drawableSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            self.metalLayer?.drawableSize = drawableSize
            renderer = LiquidGlassTabBarRenderer(
                device: device,
                renderSize: drawableSize
            )
            
            renderer?.bubbleViewSize = CGSize(
                width: selectionViewSize.width * scale,
                height: selectionViewSize.height * scale
            )
        }
        
        renderer?.setBackgroundTexture(
            from: backgroundViewForTexture,
            origin: CGPoint(x: xOffset, y: (metalViewHeight - size.height) / 2)
        )
    }
    
    private func commonInit() {
        guard let metalLayer else { return }
        
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.contentsScale = UIScreen.main.scale
        
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = UIColor.clear.cgColor
    }
    
    @objc
    private func handleDisplayTick(displayLink: CADisplayLink) {
        guard let drawable = metalLayer?.nextDrawable(), let renderer else { return }
        
        if renderer.appearTarget == 1 {
            animationProgress?(.showing(progress: 1 - renderer.appear))
        } else {
            animationProgress?(.dismissing(progress: 1 - renderer.appear))
        }
        
        renderer.draw(to: drawable)
    }
    
    private func updateCenterAndStretch(xPosition: CGFloat, velocity: CGPoint) {
        let xPosition = Float(xPosition / bounds.width)
        
        renderer?.bubbleCenter.x = xPosition
        
        let impulse = Float(velocity.x) * 0.00002

        renderer?.stretch += impulse
    }
    
}
