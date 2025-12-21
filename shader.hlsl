Texture2D pixelTex : register(t0);
Texture2D palette  : register(t1);
SamplerState samp0 : register(s0);

#define HALF_PIXEL 0.001953125f // 0.5/255

#define CYCLE_SPEED 0.00125f // 1/8192

cbuffer TimeBuffer : register(b0) {
    float cycle_time[16];
};

cbuffer CycleBuffer : register(b1) {
    // Cycles are jagged and disjoint
    // [...:16, high_idx:8, low_idx:8] ==> (high_idx << 8 + low_idx)
    uint c_range [16];  // range of k

    #define low(j) (c_range[j] & 0xFF)
    #define high(j) (c_range[j] >> 8)
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
    // Sample pixel index from the pixel texture

    

    int pixel = int(pixelTex.Sample(samp0, i.uv).r * 255.0);

    // debug: pixel
    if (i.uv.y < 0.05) {
        pixel = int(i.uv.x * 255.0);
    }
    // Loop through cycles to find if this pixel is in a cycle range

    for (int j = 0; j < 16; j++) {
        // monotonic --> break if low 
        if (pixel < low(j)) break;
        if (pixel <= high(j)) {
            // get cycle progress as an integer normalised to the cycle range
            int   cycle_progress_int    = int(floor(frac(cycle_time[j]) * float(high(j) - low(j) + 1)));
            int cycle_index = cycle_progress_int + pixel;
            if (cycle_index < low(j)) cycle_index = high(j) - (low(j) - cycle_index);
            // load the colors with the macro timing
            float color1 = palette.Load(uint3(cycle_index, 0, 0));
            int next_index = ++cycle_index <= high(j) ? cycle_index : low(j);

            float color2 = palette.Load(uint3(next_index, 0, 0));

            // lerp it with the fractional part
            float cycle_progress_frac   = frac(cycle_time[j]);
            return lerp(color1, color2, cycle_progress_frac);
        }
    }
    
    // Not in any cycle, load palette directly
    return palette.Load(uint3(pixel, 0, 0));
}
