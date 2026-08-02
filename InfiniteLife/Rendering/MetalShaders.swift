import Foundation

enum MetalShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        float2 uvs[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };
        VertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = uvs[vid];
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> cellTex [[texture(0)]],
                                  sampler samp [[sampler(0)]]) {
        float2 uv = in.uv;
        float v = cellTex.sample(samp, uv).r;
        float3 color = float3(v, v, v);
        return float4(color, 1.0);
    }
    """
}
