import UIKit
import Metal
import Display

final class LiquidGlassBackgroundView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    
    private var renderer: LiquidGlassBackgroundRenderer?

    private let device = MTLCreateSystemDefaultDevice()!
    
    private var displayLink: CADisplayLink?
    private var renderableViews: [String: MetalBackgroundRenderable] = [:]
    private var needsRebuild = true
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
       
        displayLink = CADisplayLink(target: self, selector: #selector(drawItems))
        displayLink?.add(to: .main, forMode: .common)
    }

    override func addSubview(_ view: UIView) {
        super.addSubview(view)

        if let component = view as? MetalBackgroundRenderable,
           component.shouldRenderBackgroundInMetal,
           renderableViews[component.id] == nil
        {
            renderableViews[component.id] = component
        } else {
            for subview in view.subviews {
                if let component = subview as? MetalBackgroundRenderable,
                   component.shouldRenderBackgroundInMetal,
                   renderableViews[component.id] == nil
                {
                    renderableViews[component.id] = component
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        if renderer == nil {
            renderer = LiquidGlassBackgroundRenderer(device: device)
        }
    }

    func setRenderSize(_ renderSize: CGSize) {
        needsRebuild = true
        metalLayer.drawableSize = renderSize
    }
    
    private func rebuildElements() {
        let scale = Float(metalLayer.contentsScale)
        var elems: [LiquidGlassBackgroundRenderer.GlassElement] = []
        elems.reserveCapacity(renderableViews.count)

        for renderableView in renderableViews.values where renderableView.visibleView.superview != nil && !renderableView.visibleView.isHidden && renderableView.visibleView.alpha > 0.001 {
            let view = renderableView.visibleView
            
            let rect = view.convert(view.bounds, to: self)

            // в пиксели
            let x = Float(rect.minX) * scale
            let y = Float(rect.minY) * scale
            let w = Float(rect.width) * scale
            let h = Float(rect.height) * scale
            
            let cornerRadius = Float(renderableView.backgroundNodeCornerRadius) * scale
            
            // можешь тонировать как хочешь (например розоватый)
            let tint = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

            elems.append(.init(
                rect: SIMD4<Float>(x, y, w, h),
                radius: cornerRadius,
                intensity: Float(view.alpha),
                kind: 0,
                tint: tint
            ))
        }

        renderer?.setElements(elems)
    }

    @objc private func drawItems() {
        guard let renderer, let drawable = metalLayer.nextDrawable() else { return }
        
        if needsRebuild {
            rebuildElements()
            needsRebuild = false
        }
        
        renderer.render(
            drawable: drawable,
            renderSize: metalLayer.drawableSize,
            time: CACurrentMediaTime()
        )
    }

    deinit {
        displayLink?.invalidate()
    }
}
