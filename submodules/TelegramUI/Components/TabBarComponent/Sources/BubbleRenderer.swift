import Metal
import MetalKit
import simd

struct Vertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

final class BubbleRenderer {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue

    private var vertexBuffer: MTLBuffer!
    
    var bubbleCenter: SIMD2<Float>
    
    var stretch: Float = 0
    
    private var stretchVelocity: Float = 0
    private let stiffness: Float = 25
    private let damping : Float = 0.9
    
    private var sampler: MTLSamplerState?
    private var msaaTexture: MTLTexture?
    private let renderSize: CGSize
    private let textureLoader: MTKTextureLoader
    
    init?(device: MTLDevice, renderSize: CGSize) {
        self.device = device
        self.renderSize = renderSize
        self.bubbleCenter = .init(x: 0.5, y: 0.5)
        
        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue

        let mainBundle = Bundle(for: BubbleRenderer.self)
        
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
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
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
    
    private func setBackground(from view: UIView) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        
        let size = view.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
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
        commandBuffer.waitUntilCompleted()
        
        backgroundTexture = tex
    }
    
    func setBackgroundTexture(from view: UIView) {
        let t = Date.timeIntervalSinceReferenceDate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setBackgroundTexture(from: view)
            
            print("setBackgroundTexture time !! \(Date.timeIntervalSinceReferenceDate - t)")
        }
    }
    
    func draw(to drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let backgroundTexture else { return }
        
        let dt: Float = 1.0 / 60.0
        
        stretchVelocity += -stretch * stiffness * dt
        stretchVelocity *= damping
        stretch += stretchVelocity * dt
        
        let maxStretch: Float = 0.35
        stretch = max(-maxStretch, min(maxStretch, stretch))
        
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
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
