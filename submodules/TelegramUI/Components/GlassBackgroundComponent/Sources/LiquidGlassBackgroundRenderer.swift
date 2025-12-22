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

    // MARK: - State

    private(set) var elements: [GlassElement] = []
    private var lastDrawableSize: SIMD2<Float> = .zero
   
    private let renderSize: CGSize
    
    // MARK: - Init

    init?(device: MTLDevice, renderSize: CGSize) {
        self.device = device
        self.renderSize = renderSize
        
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue

        // fullscreen quad (pos.xy, uv.xy)
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

        // Pipeline
        guard let library = device.makeDefaultLibrary(),
              let vs = library.makeFunction(name: "glassVS"),
              let fs = library.makeFunction(name: "glassFS")
        else {
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let a = desc.colorAttachments[0]!
        a.isBlendingEnabled = true
        a.rgbBlendOperation = .add
        a.alphaBlendOperation = .add
        a.sourceRGBBlendFactor = .sourceAlpha
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.sourceAlphaBlendFactor = .one
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha

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

    func render(drawable: any CAMetalDrawable, time: CFTimeInterval) {
        let sizePx = SIMD2<Float>(
            Float(renderSize.width),
            Float(renderSize.height)
        )
        lastDrawableSize = sizePx

        var u = Uniforms(viewSize: sizePx, time: Float(time), count: UInt32(elements.count))
        memcpy(uniformsBuffer.contents(), &u, MemoryLayout<Uniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(quadVB, offset: 0, index: 0)
        enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(elementsBuffer, offset: 0, index: 1)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
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
