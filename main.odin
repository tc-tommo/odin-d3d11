package d3d11_main

import "core:fmt"
import "core:mem"

import D3D11 "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import D3D "vendor:directx/d3d_compiler"
import SDL "vendor:sdl2"
import glm "core:math/linalg/glsl"
import win "core:sys/windows"
import strings "core:strings"

CYCLE_SPEED :: 0.00125;


// Based off https://gist.github.com/d7samurai/261c69490cce0620d0bfc93003cd1052

/*
  Reparent a window to the bottommost visible window in the desktop (i.e. on the desktop wallpaper)
  This is so we can render custom desktop wallpapers
 */
get_worker_handle :: proc(window: DXGI.HWND) -> win.HWND {

	// Some secret sauce for an extension to this project
	// LWA_ALPHA :: 0x02 // Missing flag
	// (window, color, alpha, flags)
    // win.SetLayeredWindowAttributes(window, 0x000, 255, LWA_ALPHA)
	
	///////////////////////////////////////////////////////////////////////////////////////////////
	// Move window to the bottom of the desktop
	// This is slightly different depending on windows 10 or 11
	// this win32 black magic summons a worker window
	// (used to move window to the bottom of the desktop)
	progman := win.FindWindowW("Progman", nil)
	if progman == nil {
		panic("Failed to find progman window")
	}
	fmt.println("progman: ", progman)
	SMTO_NORMAL :: 0x0000
	win.SendMessageTimeoutW(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, nil);
	win.Sleep(1000) // wait for the worker window to be created

	shelldll_defview := win.FindWindowExW(progman, nil, "SHELLDLL_DefView", nil)
	fmt.println("shelldll_defview: ", shelldll_defview)
	
	if shelldll_defview == nil {
		panic("Failed to find shelldll_defview window")
	}

	workerw := win.FindWindowExW(progman, nil, "WorkerW", nil)
	fmt.println("workerw: ", workerw)
	if workerw == nil {
		panic("Failed to find workerw window")
	}

	return workerw;
}


TEXTURE_WIDTH  :: 640
TEXTURE_HEIGHT :: 480

main :: proc() {
	// Allocate console for FPS diagnostics
	win.AllocConsole()
	
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	SDL.SetHintWithPriority(SDL.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)
	

	window := SDL.CreateWindow("D3D11 in Odin",
		0,0,0,0,
		{.BORDERLESS, .ALWAYS_ON_TOP, .SKIP_TASKBAR}
	)
	defer SDL.DestroyWindow(window)

	window_system_info: SDL.SysWMinfo
	SDL.GetVersion(&window_system_info.version)
	SDL.GetWindowWMInfo(window, &window_system_info)
	assert(window_system_info.subsystem == .WINDOWS)

	native_window := DXGI.HWND(window_system_info.info.win.window)
    fmt.println("win32 main window handle: ", native_window)

	// Store the window's original rect before modifying styles
	// This is needed for proper positioning after reparenting
	originalRect: win.RECT;
	win.GetWindowRect(native_window, &originalRect);
	fmt.println("Original window rect: left=", originalRect.left, " top=", originalRect.top, " right=", originalRect.right, " bottom=", originalRect.bottom)

	exstyles := win.GetWindowLongW(native_window, win.GWL_EXSTYLE)
	exstyles |= i32(win.WS_EX_LAYERED) // useful for transparency, but we don't want it here
	// exstyles |= i32(win.WS_EX_TRANSPARENT)
	exstyles |= i32(win.WS_EX_TOOLWINDOW | win.WS_EX_NOACTIVATE )
	win.SetWindowLongW(native_window, win.GWL_EXSTYLE, exstyles)

	LWA_COLORKEY :: 0x00000001 // Missing flag
	win.SetLayeredWindowAttributes(native_window, 0x00000000, 0, LWA_COLORKEY)
	
	desktopHWND: win.HWND = get_worker_handle(native_window);
	
	// Get desktop size in physical pixels using EnumDisplaySettings (non-DPI-aware)
	desktopWidth : u32 = 0
	desktopHeight: u32 = 0

	// Use EnumDisplaySettings to get actual physical resolution avoiding DPI scaling
	ENUM_CURRENT_SETTINGS :: u32(0xFFFFFFFF) // -1 cast to u32
	devmode: win.DEVMODEW
	devmode.dmSize = u16(size_of(win.DEVMODEW))
	
	if win.EnumDisplaySettingsW(nil, ENUM_CURRENT_SETTINGS, &devmode) {
		desktopWidth = u32(devmode.dmPelsWidth)
		desktopHeight = u32(devmode.dmPelsHeight)
	} else {
		panic("Failed to get display settings")
	}

	fmt.println("desktopWidth: ", desktopWidth, " desktopHeight: ", desktopHeight)
	
	if (desktopHWND != nil) {
		// Set window size and position via SDL before reparenting
		SDL.SetWindowSize(window, i32(desktopWidth), i32(desktopHeight));
		SDL.SetWindowPosition(window, 0, 0);

		// Now reparent to the desktop
		win.SetParent(native_window, desktopHWND);
		win.SetWindowLongW(native_window, win.GWL_STYLE, i32(win.WS_CHILD | win.WS_VISIBLE));

		// After reparenting, adjust position and size with the +10 height hack
		// According to the article, this adjustment is needed for proper rendering
		// Move to position 0, originalRect.top with width originalRect.right and height originalRect.bottom + 10
		win.MoveWindow(native_window, 0, 0, 1, 1, false);

		// Then move it to cover the entire desktop (this is the final desired position)
		win.MoveWindow(native_window, 0, 1, i32(desktopWidth), i32(desktopHeight), false);
	}

	renderer := SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED)

	if renderer == nil {
		panic("Failed to create renderer")
	}
	defer SDL.DestroyRenderer(renderer)

	SDL.RenderSetLogicalSize(renderer, i32(desktopWidth), i32(desktopHeight));
	SDL.RenderSetIntegerScale(renderer, true);

	feature_levels := [?]D3D11.FEATURE_LEVEL{._11_0}

	swapchain_desc := DXGI.SWAP_CHAIN_DESC1{
		Width  = desktopWidth,
		Height = desktopHeight,
		Format = DXGI.FORMAT.R8G8B8A8_UNORM,
		Stereo = false,
		SampleDesc = {
			Count   = 1,
			Quality = 0,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 1,
		Scaling     = .STRETCH,
		SwapEffect  = .DISCARD,
		AlphaMode   = .UNSPECIFIED,
		Flags       = {},
	}
	
	base_device: ^D3D11.IDevice
	base_device_context: ^D3D11.IDeviceContext

	D3D11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &feature_levels[0], len(feature_levels), D3D11.SDK_VERSION, &base_device, nil, &base_device_context)

	device: ^D3D11.IDevice
	base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&device))

	device_context: ^D3D11.IDeviceContext
	base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&device_context))

	dxgi_device: ^DXGI.IDevice
	device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device))

	dxgi_adapter: ^DXGI.IAdapter
	dxgi_device->GetAdapter(&dxgi_adapter)

	dxgi_factory: ^DXGI.IFactory2
	dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory))

	swapchain: ^DXGI.ISwapChain1
	dxgi_factory->CreateSwapChainForHwnd(device, native_window, &swapchain_desc, nil, nil, &swapchain)

	framebuffer: ^D3D11.ITexture2D
	swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&framebuffer))

	framebuffer_view: ^D3D11.IRenderTargetView
	device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)

	vs_blob: ^D3D11.IBlob
	D3D.Compile(raw_data(shaders_hlsl), len(shaders_hlsl), "shaders.hlsl", nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, nil)
	assert(vs_blob != nil)

	vertex_shader: ^D3D11.IVertexShader
	device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader)

	ps_blob: ^D3D11.IBlob
	D3D.Compile(raw_data(shaders_hlsl), len(shaders_hlsl), "shaders.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil)
	assert(ps_blob != nil)

	pixel_shader: ^D3D11.IPixelShader
	device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader)

	upscale_ps_blob: ^D3D11.IBlob
	D3D.Compile(raw_data(shaders_hlsl), len(shaders_hlsl), "shaders.hlsl", nil, nil, "upscale_ps_main", "ps_5_0", 0, 0, &upscale_ps_blob, nil)
	assert(upscale_ps_blob != nil)

	upscale_pixel_shader: ^D3D11.IPixelShader
	device->CreatePixelShader(upscale_ps_blob->GetBufferPointer(), upscale_ps_blob->GetBufferSize(), nil, &upscale_pixel_shader)

	///////////////////////////////////////////////////////////////////////////////////////////////

	rasterizer_desc := D3D11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .NONE,
	}
	rasterizer_state: ^D3D11.IRasterizerState
	device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)

	sampler_desc := D3D11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .CLAMP, // CLAMP is better for pixel art upscaling
		AddressV       = .CLAMP,
		AddressW       = .CLAMP,
		ComparisonFunc = .NEVER,
	}
	sampler_state: ^D3D11.ISamplerState
	device->CreateSamplerState(&sampler_desc, &sampler_state)

	pixel_data:	   []u8 = #load("raw/V01.bin")
	palette_data:  []u8 = #load("raw/V01_palette.bin")
	cycle_data:    []u8 = #load("raw/V01.cycles")
	
	cycle_struct :: struct { rate: i16, low: u8, high: u8 }
	cycles: []cycle_struct = transmute([]cycle_struct)cycle_data;

	lows  : [16]u8;
	highs : [16]u8;
	rates : [16]u32;
	for i in 0..<16 {
		lows[i]  = cycles[i].low;
		highs[i] = cycles[i].high;
		rates[i] = u32(cycles[i].rate);
	}

	fmt.println("lows: ", lows)
	fmt.println("highs: ", highs)
	fmt.println("rates: ", rates)
	
	// Create main pixel data texture (shared by all cycles)
	pixel_texture_desc := D3D11.TEXTURE2D_DESC{
		Width      = TEXTURE_WIDTH,
		Height     = TEXTURE_HEIGHT,
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .R8_UNORM,
		SampleDesc = {Count = 1},
		Usage      = .IMMUTABLE,
		BindFlags  = {.SHADER_RESOURCE},
	}

	pixel_init_data := D3D11.SUBRESOURCE_DATA{
		pSysMem     = &pixel_data[0],
		SysMemPitch = TEXTURE_WIDTH,
	}

	pixel_texture: ^D3D11.ITexture2D
	device->CreateTexture2D(&pixel_texture_desc, &pixel_init_data, &pixel_texture)

	pixel_texture_view: ^D3D11.IShaderResourceView
	device->CreateShaderResourceView(pixel_texture, nil, &pixel_texture_view)

	// Create palette texture
	PALETTE_SIZE :: 256 // Typically 256 colors
	fmt.printf("Loaded palette data: %d bytes (expected: %d for RGBA)\n", len(palette_data), PALETTE_SIZE * 4)

	palette_texture_desc := D3D11.TEXTURE2D_DESC{
		Width      = PALETTE_SIZE,
		Height     = 1,
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .B8G8R8X8_UNORM,
		SampleDesc = {Count = 1},
		Usage      = .IMMUTABLE,
		BindFlags  = {.SHADER_RESOURCE},
	}

	palette_init_data := D3D11.SUBRESOURCE_DATA{
		pSysMem     = &palette_data[0],
		SysMemPitch = PALETTE_SIZE * 4, // 4 bytes per pixel (RGBA)
	}

	palette_texture: ^D3D11.ITexture2D
	device->CreateTexture2D(&palette_texture_desc, &palette_init_data, &palette_texture)

	palette_texture_view: ^D3D11.IShaderResourceView
	device->CreateShaderResourceView(palette_texture, nil, &palette_texture_view)

	// Create intermediate render target at texture resolution for efficient rendering
	intermediate_texture_desc := D3D11.TEXTURE2D_DESC{
		Width      = TEXTURE_WIDTH,
		Height     = TEXTURE_HEIGHT,
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .R8G8B8A8_UNORM,
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.RENDER_TARGET, .SHADER_RESOURCE},
	}

	intermediate_texture: ^D3D11.ITexture2D
	device->CreateTexture2D(&intermediate_texture_desc, nil, &intermediate_texture)

	intermediate_rtv: ^D3D11.IRenderTargetView
	device->CreateRenderTargetView(intermediate_texture, nil, &intermediate_rtv)

	intermediate_srv: ^D3D11.IShaderResourceView
	device->CreateShaderResourceView(intermediate_texture, nil, &intermediate_srv)

	// Create linear sampler for smooth upscaling
	linear_sampler_desc := D3D11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_LINEAR,
		AddressU       = .CLAMP,
		AddressV       = .CLAMP,
		AddressW       = .CLAMP,
		ComparisonFunc = .NEVER,
	}
	linear_sampler_state: ^D3D11.ISamplerState
	device->CreateSamplerState(&linear_sampler_desc, &linear_sampler_state)

	// Create constant buffer for time
	TicksBuffer :: struct #align(16) {
		ticks: u32,
	}
	
	time_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth      = u32(size_of(TicksBuffer)),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	
	time_buffer: ^D3D11.IBuffer
	device->CreateBuffer(&time_buffer_desc, nil, &time_buffer)

	// Create constant buffer for cycles (lows, highs, rates)
	CycleBuffer :: struct #align(16) {
		c_low: u32,
		c_high: u32,
		c_rate: u32,
	}

	fmt.println("buffer size: ", size_of(CycleBuffer))

	cycle_buffer_data: [16]CycleBuffer
	for i in 0..<16 {
		cycle_buffer_data[i].c_low = u32(lows[i])
		cycle_buffer_data[i].c_high = u32(highs[i])
		cycle_buffer_data[i].c_rate = rates[i]
		// cycle_buffer_data[i]._pad = 0
	}
	
	cycle_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth      = u32(size_of([16]CycleBuffer)),
		Usage          = .IMMUTABLE, // Static data, won't change
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {},
	}
	
	cycle_init_data := D3D11.SUBRESOURCE_DATA{
		pSysMem = &cycle_buffer_data,
	}
	
	cycle_buffer: ^D3D11.IBuffer
	device->CreateBuffer(&cycle_buffer_desc, &cycle_init_data, &cycle_buffer)

	///////////////////////////////////////////////////////////////////////////////////////////////

	framebuffer_desc: D3D11.TEXTURE2D_DESC
	framebuffer->GetDesc(&framebuffer_desc)

	viewport := D3D11.VIEWPORT{
		0, 0,
		f32(framebuffer_desc.Width), f32(framebuffer_desc.Height),
		0, 1,
	}

	SDL.ShowWindow(window)

	time_ms : u32 = 0
	
	// FPS counter variables
	fps_frame_count: u32 = 0
	fps_last_update: u32 = SDL.GetTicks()
	
	for quit := false; !quit; {
		
		for e: SDL.Event; SDL.PollEvent(&e); {
			#partial switch e.type {
			case .QUIT:
				quit = true
			case .KEYDOWN:
				if e.key.keysym.sym == .ESCAPE {
					quit = true
				}
			}
		}

		current_time := SDL.GetTicks()

		// Update FPS counter
		fps_frame_count += 1
		elapsed_since_update := current_time - fps_last_update
		if elapsed_since_update >= 1000 {
			fps := fps_frame_count
			fmt.printf("\rFPS: %d   ", fps)
			fps_frame_count = 0
			fps_last_update = current_time
		}

		// Update time buffer
		time_data: TicksBuffer
		time_data.ticks = current_time
		
		mapped_resource: D3D11.MAPPED_SUBRESOURCE
		device_context->Map(time_buffer, 0, .WRITE_DISCARD, {}, &mapped_resource)
		mem.copy(mapped_resource.pData, &time_data, size_of(TicksBuffer))
		device_context->Unmap(time_buffer, 0)

		device_context->IASetPrimitiveTopology(.TRIANGLESTRIP)
		device_context->IASetInputLayout(nil)
		device_context->VSSetShader(vertex_shader, nil, 0)
		device_context->RSSetState(rasterizer_state)
		device_context->OMSetBlendState(nil, nil, u32(D3D11.COLOR_WRITE_ENABLE_ALL)) // default blend (none)

		// PASS 1: Render to intermediate texture at native resolution (640x480)
		intermediate_viewport := D3D11.VIEWPORT{
			0, 0,
			f32(TEXTURE_WIDTH), f32(TEXTURE_HEIGHT),
			0, 1,
		}

		device_context->ClearRenderTargetView(intermediate_rtv, &[4]f32{0, 0, 0, 1})
		device_context->RSSetViewports(1, &intermediate_viewport)
		device_context->OMSetRenderTargets(1, &intermediate_rtv, nil)

		device_context->PSSetShader(pixel_shader, nil, 0)
		device_context->PSSetConstantBuffers(0, 1, &cycle_buffer) // Bind cycle constant buffer (b0)
		device_context->PSSetConstantBuffers(1, 1, &time_buffer) // Bind time constant buffer (b1)
		device_context->PSSetShaderResources(0, 1, &pixel_texture_view)
		device_context->PSSetShaderResources(1, 1, &palette_texture_view)
		device_context->PSSetSamplers(0, 1, &sampler_state)

		device_context->Draw(4, 0)

		// Unbind intermediate render target before using it as shader resource
		null_rtv: ^D3D11.IRenderTargetView = nil
		device_context->OMSetRenderTargets(1, &null_rtv, nil)

		// PASS 2: Upscale intermediate texture to full screen
		device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{0, 0, 0, 1})
		device_context->RSSetViewports(1, &viewport)
		device_context->OMSetRenderTargets(1, &framebuffer_view, nil)

		device_context->PSSetShader(upscale_pixel_shader, nil, 0)
		device_context->PSSetShaderResources(0, 1, &intermediate_srv)
		device_context->PSSetSamplers(0, 1, &sampler_state) // Use point filtering for crisp pixel art

		device_context->Draw(4, 0)

		swapchain->Present(0, {})
	}
}

shaders_hlsl := #load("shader.hlsl")
