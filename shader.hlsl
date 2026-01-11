Texture2D pixelTex : register(t0);
Texture2D palette  : register(t1);
SamplerState samp0 : register(s0);

struct VSOut {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

cbuffer TicksBuffer : register(b0) {
    uint ticks;
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
    // Sample pixel index from the pixel texture
    int pixel = int(pixelTex.Sample(samp0, i.uv).r * 255.0);

    // Lookup color from pre-cycled palette
    return palette.Load(uint3(pixel, 0, 0));
}
