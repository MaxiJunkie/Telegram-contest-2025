import UIKit
import MetalKit

class LiquidGlassTabBarOverlay: UIView {
    
    weak var backgroundView: UIView?
    
    private var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }
    
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    private var displayLink: CADisplayLink?
    
    var renderer: BubbleRenderer?

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
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let scale = UIScreen.main.scale
        let drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
         
        metalLayer?.drawableSize = drawableSize
        
        if renderer == nil, let device = MTLCreateSystemDefaultDevice() {
            renderer = BubbleRenderer(device: device, renderSize: drawableSize)
            
            if let backgroundView {
                renderer?.setBackgroundTexture(from: backgroundView)
            }
        }
    }
    
    private func commonInit() {
        guard let metalLayer else { return }
        
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.contentsScale = UIScreen.main.scale
        
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = UIColor.clear.cgColor
        
        backgroundColor = .clear
    }
    
    @objc
    private func handleDisplayTick(displayLink: CADisplayLink) {
        guard let drawable = metalLayer?.nextDrawable() else { return }
        
        renderer?.draw(to: drawable)
    }
    
}
