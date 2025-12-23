import Metal
import QuartzCore
import simd

final class LiquidGlassBackgroundRenderer {

    // MARK: - Types

    struct GlassElement {
        public var rect: SIMD4<Float>   // x,y,w,h in PIXELS (в координатах layer)
        public var radius: Float        // pixels
        public var intensity: Float     // 0..1
        public var kind: UInt32         // 0 roundedRect (на будущее)
        public var tint: SIMD4<Float>   // rgba 0..1

        public init(rect: SIMD4<Float>, radius: Float, intensity: Float = 1, kind: UInt32 = 0, tint: SIMD4<Float> = SIMD4(1,1,1,1)) {
            self.rect = rect
            self.radius = radius
            self.intensity = intensity
            self.kind = kind
            self.tint = tint
        }
    }

    private struct Uniforms {
        var viewSize: SIMD2<Float>
        var time: Float
        var count: UInt32
        var _pad: UInt32 = 0
    }

    // MARK: - Metal

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private let quadVB: MTLBuffer
    private let uniformsBuffer: MTLBuffer

    private var elementsBuffer: MTLBuffer?
    private var elementsCapacity: Int = 0
    
    private let semaphore = DispatchSemaphore(value: 3)
    
    // MARK: - State

    private(set) var elements: [GlassElement] = []
    
    // MARK: - Init

    init?(device: MTLDevice) {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue

        let quad: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0,
        ]
        guard let quadVB = device.makeBuffer(
            bytes: quad,
            length: quad.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            return nil
        }
        
        self.quadVB = quadVB
        guard let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        self.uniformsBuffer = uniformsBuffer
        
        let mainBundle = Bundle(for: LiquidGlassBackgroundRenderer.self)
        
        guard let path = mainBundle.path(forResource: "GlassBackgroundComponentBundle", ofType: "bundle") else {
            return nil
        }
        
        guard let bundle = Bundle(path: path) else {
            return nil
        }
        
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            return nil
        }
        
        guard let vertexFunction = library.makeFunction(name: "glassVS") else {
            return nil
        }
        
        guard let fragmentFunction = library.makeFunction(name: "glassFS") else {
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        
        let colorAttachment = desc.colorAttachments[0]!
        
        colorAttachment.pixelFormat = .bgra8Unorm
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }
    }

    // MARK: - Public API

    func setElements(_ elements: [GlassElement]) {
        self.elements = elements
        ensureElementsBufferCapacity(elements.count)
        if !elements.isEmpty, let buf = elementsBuffer {
            memcpy(buf.contents(), elements, elements.count * MemoryLayout<GlassElement>.stride)
        }
    }
    
    func render(drawable: any CAMetalDrawable, renderSize: CGSize, time: CFTimeInterval) {
        _ = semaphore.wait(timeout: .now())
        
        let sizePx = SIMD2<Float>(
            Float(renderSize.width),
            Float(renderSize.height)
        )
        
        var uniforms = Uniforms(viewSize: sizePx, time: Float(time), count: UInt32(elements.count))
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard
            let commandBuffer = queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(quadVB, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(elementsBuffer, offset: 0, index: 1)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            self.semaphore.signal()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Helpers

    private func ensureElementsBufferCapacity(_ count: Int) {
        let minCap = max(count, 1)
        if minCap <= elementsCapacity { return }
        elementsCapacity = max(minCap, elementsCapacity * 2, 16)
        elementsBuffer = device.makeBuffer(
            length: elementsCapacity * MemoryLayout<GlassElement>.stride,
            options: .storageModeShared
        )
    }
}
