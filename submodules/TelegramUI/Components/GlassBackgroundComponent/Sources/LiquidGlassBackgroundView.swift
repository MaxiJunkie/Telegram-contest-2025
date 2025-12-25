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

    func addRenderableViewIfNeeded(_ view: UIView) {
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
        metalLayer.drawableSize = renderSize
    }
    
    private func rebuildElements(now: CFTimeInterval) {
        let scalePx = Float(metalLayer.contentsScale)
        var elements: [LiquidGlassBackgroundRenderer.GlassElement] = []
        
        for (_, renderableView) in renderableViews {
            let view = renderableView.visibleView
            
            guard view.superview != nil, !view.isHidden, view.alpha > 0.001 else {
                continue
            }
            
            let layer: CALayer = (renderableView.isAnimating ? view.layer.presentation() : view.layer) ?? view.layer
            let rect = layer.convert(layer.bounds, to: self.layer)
            
            let transform = layer.affineTransform()
            let sx = sqrt(transform.a * transform.a + transform.c * transform.c)
            let sy = sqrt(transform.b * transform.b + transform.d * transform.d)
            let scale  = Float((sx + sy) * 0.5)
            
            let cx = Float(rect.midX)
            let cy = Float(rect.midY)
            let w0 = Float(rect.width)
            let h0 = Float(rect.height)

            let w = w0
            let h = h0

            let x = (cx - w * 0.5) * scalePx
            let y = (cy - h * 0.5) * scalePx

            let cornerRadius = Float(renderableView.backgroundNodeCornerRadius) * scalePx * scale

            elements.append(.init(
                rect: SIMD4<Float>(x, y, w * scalePx, h * scalePx),
                radius: cornerRadius,
                intensity: Float(view.alpha),
                kind: 0,
                tint: SIMD4<Float>(1,1,1,1)
            ))
        }

        renderer?.setElements(elements)
    }

    @objc private func drawItems() {
        guard let renderer, let drawable = metalLayer.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        
        rebuildElements(now: now)
        
        renderer.render(
            drawable: drawable,
            renderSize: metalLayer.drawableSize,
            time: now
        )
    }

    deinit {
        displayLink?.invalidate()
    }
}
