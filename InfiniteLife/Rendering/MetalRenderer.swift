import Foundation
import Metal
import MetalKit
import AppKit

final class MetalRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var texture: MTLTexture?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device else { return nil }
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue

        let options = MTLCompileOptions()
        options.languageVersion = .version2_4
        guard let library = try? device.makeLibrary(source: MetalShaders.source, options: options) else {
            return nil
        }
        guard let vfn = library.makeFunction(name: "vertex_main"),
              let ffn = library.makeFunction(name: "fragment_main") else {
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else {
            return nil
        }
        self.pipeline = pipeline

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .nearest
        sampDesc.magFilter = .nearest
        sampDesc.sAddressMode = .clampToEdge
        sampDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sampDesc) else {
            return nil
        }
        self.sampler = sampler
    }

    func ensureTexture(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if texture != nil, textureWidth == width, textureHeight == height { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        texture = device.makeTexture(descriptor: desc)
        textureWidth = width
        textureHeight = height
    }

    func upload(cells: UnsafePointer<UInt8>, width: Int, height: Int) {
        ensureTexture(width: width, height: height)
        guard let texture else { return }
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: cells,
            bytesPerRow: width
        )
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let texture else { return }

        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
