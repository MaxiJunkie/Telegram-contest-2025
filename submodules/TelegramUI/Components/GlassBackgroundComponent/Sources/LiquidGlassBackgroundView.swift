import UIKit
import Metal
import Display

final class LiquidGlassBackgroundView: UIView {

    private struct AnimState {
        var from: Float
        var to: Float
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    private var animStates: [String: AnimState] = [:]
    private var currentScale: [String: Float] = [:]
    
    private let animDuration: CFTimeInterval = 0.25

    private func easeOutCubic(_ t: Float) -> Float {
        let u = 1 - t
        return 1 - u * u * u
    }
    
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
        
        for (id, renderable) in renderableViews {
            if let animation = renderable.animation {
                let scale = currentScale[id] ?? 1.0
                let target: Float = animation.target

                if abs(scale - target) > 0.0001 {
                    animStates[id] = AnimState(from: scale, to: target, start: now, duration: animDuration)
                }
                renderable.animation = nil
            }
        }
        
        for (id, renderableView) in renderableViews {
            let view = renderableView.visibleView
            
            guard view.superview != nil, !view.isHidden, view.alpha > 0.001 else {
                animStates.removeValue(forKey: id)
                currentScale.removeValue(forKey: id)
                continue
            }
            
            var scale: Float = currentScale[id] ?? 1.0
            if let state = animStates[id] {
                let point = Float(min(1.0, max(0.0, (now - state.start) / state.duration)))
                let eased = easeOutCubic(point)
                scale = state.from + (state.to - state.from) * eased
                currentScale[id] = scale

                if point >= 1.0 {
                    animStates.removeValue(forKey: id)
                    if abs(state.to - 1.0) < 0.0001 {
                        currentScale.removeValue(forKey: id)
                    } else {
                        currentScale[id] = state.to
                    }
                }
            }
            
            let rect = view.convert(view.bounds, to: self)
            
            let cx = Float(rect.midX)
            let cy = Float(rect.midY)
            let w0 = Float(rect.width)
            let h0 = Float(rect.height)

            let w = w0 * scale
            let h = h0 * scale

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
