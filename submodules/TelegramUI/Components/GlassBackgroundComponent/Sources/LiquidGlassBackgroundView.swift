import UIKit
import Metal

final class LiquidGlassBackgroundView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    
    private var renderer: LiquidGlassBackgroundRenderer?

    private var displayLink: CADisplayLink?
    private var tracked: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false

        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    override func addSubview(_ view: UIView) {
        super.addSubview(view)

        if view is GlassBackgroundView {
            tracked.append(view)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        let scale = UIScreen.main.scale
        let renderSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        metalLayer.drawableSize = renderSize
        
        if renderer == nil, let device = MTLCreateSystemDefaultDevice() {
            renderer = LiquidGlassBackgroundRenderer(device: device, renderSize: renderSize)
        }
        
        metalLayer.frame = bounds
        metalLayer.contentsScale = UIScreen.main.scale

        rebuildElements()
    }

    private func rebuildElements() {
        let scale = Float(metalLayer.contentsScale)
        var elems: [LiquidGlassBackgroundRenderer.GlassElement] = []
        elems.reserveCapacity(tracked.count)

        for v in tracked where v.superview != nil && !v.isHidden && v.alpha > 0.001 {
            let r = v.convert(v.bounds, to: self)

            // в пиксели
            let x = Float(r.minX) * scale
            let y = Float(r.minY) * scale
            let w = Float(r.width) * scale
            let h = Float(r.height) * scale

            let cr = v.layer.cornerRadius > 0 ? v.layer.cornerRadius : min(r.width, r.height) * 0.5
            let radiusPx = Float(cr) * scale

            // можешь тонировать как хочешь (например розоватый)
            let tint = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

            elems.append(.init(
                rect: SIMD4<Float>(x, y, w, h),
                radius: radiusPx,
                intensity: Float(v.alpha),
                kind: 0,
                tint: tint
            ))
        }

        renderer?.setElements(elems)
    }

    @objc private func tick() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        renderer?.render(drawable: drawable, time: CACurrentMediaTime())
    }

    deinit { displayLink?.invalidate() }
}
