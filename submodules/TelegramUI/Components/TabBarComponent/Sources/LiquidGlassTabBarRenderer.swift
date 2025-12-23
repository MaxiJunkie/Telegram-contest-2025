import Metal
import MetalKit
import simd

struct Vertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

final class LiquidGlassTabBarRenderer {
    enum AppearingState {
        case showing(progress: Float)
        case dismissing(progress: Float, targetXPosition: Float)
        
        var progress: Float {
            switch self {
            case .showing(let progress):
                progress
            case .dismissing(let progress, _):
                progress
            }
        }
    }
    
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue

    private var vertexBuffer: MTLBuffer?
    
    var bubbleIsAppearing: Bool {
        return appear > 0.001 && appear < 0.999
    }
    
    var bubbleCenter: SIMD2<Float>
    
    var stretch: Float = 0
    
    var appearTarget: AppearingState = .dismissing(progress: 0, targetXPosition: 0)
    
    var bubbleViewSize: CGSize = .zero
    
    var appear: Float = 0
    
    private var stretchVelocity: Float = 0
    private let stiffness: Float = 25
    private let damping: Float = 0.9
    
    private var followVelX: Float = 0
    private let followStiffness: Float = 50
    private let followDamping: Float = 0.9
    
    private var sampler: MTLSamplerState?
    private var msaaTexture: MTLTexture?
    private let renderSize: CGSize
    private let textureLoader: MTKTextureLoader
    
    private let semaphore = DispatchSemaphore(value: 3)
    
    init?(device: MTLDevice, renderSize: CGSize) {
        self.device = device
        self.renderSize = renderSize
        self.bubbleCenter = .init(x: 0.5, y: 0.5)
        
        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue

        let mainBundle = Bundle(for: LiquidGlassTabBarRenderer.self)
        
        guard let path = mainBundle.path(forResource: "TabBarComponentBundle", ofType: "bundle") else {
            return nil
        }
        
        guard let bundle = Bundle(path: path) else {
            return nil
        }
        
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            return nil
        }
        
        guard let vertexFunction = library.makeFunction(name: "bubbleVertex") else {
            return nil
        }
        
        guard let fragmentFunction = library.makeFunction(name: "bubbleCapsule") else {
            return nil
        }
            
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 4
        
        let colorAttachments = descriptor.colorAttachments[0]
        colorAttachments?.pixelFormat = .bgra8Unorm
        colorAttachments?.isBlendingEnabled = true

        colorAttachments?.rgbBlendOperation = .add
        colorAttachments?.alphaBlendOperation = .add

        colorAttachments?.sourceRGBBlendFactor = .one
        colorAttachments?.destinationRGBBlendFactor = .oneMinusSourceAlpha

        colorAttachments?.sourceAlphaBlendFactor = .one
        colorAttachments?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        self.textureLoader = MTKTextureLoader(device: device)
        
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.pipeline = pipeline
        makeFullscreenQuad()
        setupMSAATexture()
        setupSampler()
    }
    
    private func setupMSAATexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            mipmapped: false
        )
        descriptor.sampleCount = 4
        descriptor.textureType = .type2DMultisample
        descriptor.storageMode = .private
        descriptor.usage = .renderTarget

        msaaTexture = device.makeTexture(descriptor: descriptor)
        msaaTexture?.label = "MSAA Texture"
    }

    private func makeFullscreenQuad() {
        let verts: [Vertex] = [
            Vertex(position: [-1, -1], uv: [0, 1]),
            Vertex(position: [ 1, -1], uv: [1, 1]),
            Vertex(position: [-1,  1], uv: [0, 0]),
            Vertex(position: [ 1,  1], uv: [1, 0]),
        ]
        vertexBuffer = device.makeBuffer(
            bytes: verts,
            length: MemoryLayout<Vertex>.stride * verts.count,
            options: []
        )
    }
    
    private func setupSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    private var backgroundTexture: MTLTexture?
    
    private func createTexture(from view: UIView, origin: CGPoint) {
        let scale = UIScreen.main.scale
        let metalViewSize = CGSize(width: renderSize.width / scale, height: renderSize.height / scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: metalViewSize, format: format)

        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: metalViewSize))
            
            ctx.cgContext.translateBy(x: origin.x, y: origin.y)
            view.layer.render(in: ctx.cgContext)
        }
        
        guard let cgImage = image.cgImage else {
            return
        }

        let width = cgImage.width
        let height = cgImage.height

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard
            let context = CGContext(
                data: &rawData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        desc.usage = [.shaderRead, .renderTarget]
        
        guard let tex = device.makeTexture(descriptor: desc) else {
            return
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        tex.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: &rawData,
            bytesPerRow: bytesPerRow
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { return }

        blit.generateMipmaps(for: tex)
        blit.endEncoding()
        commandBuffer.commit()
        
        backgroundTexture = tex
    }
    
    func setBackgroundTexture(from view: UIView, origin: CGPoint) {
        createTexture(from: view, origin: origin)
    }
    
    func draw(to drawable: CAMetalDrawable, dt: Float) {
        
        _ = semaphore.wait(timeout: .now())
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let backgroundTexture else { return }
        
        let speed: Float = switch appearTarget {
        case .showing:
            4
        case .dismissing:
            2
        }
        
        let diff = appearTarget.progress - appear
        let step = diff * min(1, dt * speed)
        
        if appear <= 0.001 {
            appear = 0
        }
        
        if appear > 0.999 {
            appear = 1
        }
        
        appear += step
        
        stretchVelocity += -stretch * stiffness * dt
        stretchVelocity *= damping
        stretch += stretchVelocity * dt
        
        let maxStretch: Float = 0.35
        stretch = max(-maxStretch, min(maxStretch, stretch))
        
        switch appearTarget {
        case .showing:
            followVelX = 0

        case .dismissing(_, let targetXPosition):
            let target = targetXPosition
            let x = bubbleCenter.x
            
            followVelX += (target - x) * followStiffness * dt
            followVelX *= followDamping
            bubbleCenter.x += followVelX * dt
            
            if abs(target - bubbleCenter.x) < 0.0015 {
                bubbleCenter.x = target
                followVelX = 0
            }

            bubbleCenter.x = min(max(bubbleCenter.x, 0), 1)
        }
        
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = msaaTexture
        renderPass.colorAttachments[0].resolveTexture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .multisampleResolve
        
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(backgroundTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var size = SIMD2<Float>(Float(renderSize.width),
                                Float(renderSize.height))
        
        encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<Float>>.size, index: 4)
        
        var stretchCopy = stretch
        encoder.setFragmentBytes(&stretchCopy,
                                 length: MemoryLayout<Float>.size,
                                 index: 5)
        
        var center = bubbleCenter
        encoder.setFragmentBytes(&center,
                                 length: MemoryLayout<SIMD2<Float>>.size,
                                 index: 6)
        
        var appearValue = appear
        encoder.setFragmentBytes(
            &appearValue,
            length: MemoryLayout<Float>.stride,
            index: 7
        )
        
        var bubbleSize = SIMD2<Float>(
            Float(bubbleViewSize.width),
            Float(bubbleViewSize.height)
        )
        
        encoder.setFragmentBytes(&bubbleSize,
                                 length: MemoryLayout<SIMD2<Float>>.stride,
                                 index: 8)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            self.semaphore.signal()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
