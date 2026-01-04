Texture2D pixelTex : register(t0);
Texture2D palette  : register(t1);
SamplerState samp0 : register(s0);

struct CycleBuffer {
    uint c_low;
    uint c_high;
    int c_rate;
    uint _pad; // pad
};

cbuffer CycleBufferCB : register(b0) {
    CycleBuffer cycle_buffer[16];
};

struct VSOut {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

VSOut vs_main(uint id : SV_VertexID)
{
    float2 positions[4] = { float2(-1,1), float2(1,1), float2(-1,-1), float2(1,-1) };
    float2 uvs      [4] = { float2(0,0),  float2(1,0), float2(0,1),   float2(1,1)  };
    VSOut o;
    o.pos = float4(positions[id], 0, 1);
    o.uv  = uvs[id];
    return o;
}



float4 ps_main(VSOut i) : SV_TARGET
{

    #define LOW(index) (cycle_buffer[index].c_low)
    #define HIGH(index) (cycle_buffer[index].c_high)
    #define RATE(index) (cycle_buffer[index].c_rate)

    // Sample pixel index from the pixel texture
    int pixel = int(pixelTex.Sample(samp0, i.uv).r * 255.0);

    // start at 8, (middle)
    int cycle_idx = 0;

    // small and concise binary search (hardcoded for 16 cycle values)
    // j ==> the subindex level going from 8 (top level) to 1 (item level)
    for (int j = 8; j != 0; j >>= 1) {
        cycle_idx |= (pixel >= LOW(cycle_idx | j)) ? j : 0;
    }

    if (pixel < LOW(cycle_idx) || pixel > HIGH(cycle_idx)) {
        return palette.Load(uint3(pixel, 0, 0));
    }

    float4 debug_color[16] = {
        float4(0, 1, 0, 1),
        float4(0, 0, 0.5, 1),
        float4(0, 0, 1, 1),
        float4(0, 0.5, 1, 1),
        float4(0, 1, 1, 1),
        float4(0.5, 1, 1, 1),
        float4(1, 1, 1, 1),
        float4(1, 1, 0.5, 1),
        float4(1, 1, 0, 1),
        float4(1, 0.5, 0, 1),
        float4(1, 0, 0, 1),
        float4(0.5, 0, 0, 1),
        float4(0, 0, 0, 1),
        float4(0, 0, 0.5, 1),
        float4(0, 0, 1, 1),
        float4(0, 0.5, 1, 1)
    };  

    return debug_color[cycle_idx];
}
