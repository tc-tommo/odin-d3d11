This C++ Snippet demonstrates how to set up the wallpaper layering for an SDL window. How can I port this to the Odin application I'm working on with the D3D11 backend?

This snippet says this works for windows 10+, but I'm not 100% sure if it works for windows 11.

I'm fairly sure the layering is wrong in my current odin code, which is why it isn't visible.



```cpp
#include <SDL.h>
#include <SDL_syswm.h>
#include <SDL_image.h>
#include <windows.h>
#include <shellapi.h>
#include <CommCtrl.h>
#include <shobjidl.h>
#include <iostream>

#pragma comment(lib, "Comctl32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

#define WM_TRAYICON (WM_USER + 1)
#define ID_TRAY_EXIT 1001

/**
 * @brief Holds SDL window and renderer state, as well as logical and physical dimensions.
 */
struct SDLState {
    SDL_Window* window;
    SDL_Renderer* renderer;
    int width, height, logw, logh;
};

static NOTIFYICONDATA nid = {};
static HWND hwnd = nullptr;

static int frameRate = 60;
static bool isRunning = false;
static bool debugMode = false;

/**
 * @brief Initializes SDL, COM, and creates the main window and renderer.
 * @param state Reference to SDLState to populate.
 * @return true if initialization succeeded, false otherwise.
 */
bool Initialize(SDLState& state);

/**
 * @brief Cleans up SDL, COM, and removes the tray icon and window subclass.
 * @param state Reference to SDLState to clean up.
 */
void CleanUp(SDLState& state);

/**
 * @brief Allocates a console window and redirects stdout/stderr for debugging.
 */
void AttachConsole() {
    AllocConsole();

    FILE* fp;
    freopen_s(&fp, "CONOUT$", "w", stdout);
    freopen_s(&fp, "CONOUT$", "w", stderr);

    std::cout.clear();
    std::cerr.clear();
}

/**
 * @brief Adds a system tray icon for the application.
 * @param hwnd Handle to the main application window.
 */
void AddTrayIcon(HWND hwnd) {
    nid.cbSize = sizeof(NOTIFYICONDATA);
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    wcscpy_s(nid.szTip, L"Desktop Pet");
    Shell_NotifyIcon(NIM_ADD, &nid);
}

/**
 * @brief Removes the application's system tray icon.
 */
void RemoveTrayIcon() {
    Shell_NotifyIcon(NIM_DELETE, &nid);
}

/**
 * @brief Displays a context menu at the cursor position for the tray icon.
 * @param hwnd Handle to the main application window.
 */
void ShowContextMenu(HWND hwnd) {
    POINT pt;
    GetCursorPos(&pt);
    HMENU hMenu = CreatePopupMenu();
    InsertMenu(hMenu, -1, MF_BYPOSITION, ID_TRAY_EXIT, L"Exit");
    SetForegroundWindow(hwnd);
    TrackPopupMenuEx(hMenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x, pt.y, hwnd, nullptr);
    PostMessage(hwnd, WM_NULL, 0, 0);
    DestroyMenu(hMenu);
}

/**
 * @brief Window procedure for handling tray icon and menu commands.
 */
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam,
    UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
    if (msg == WM_TRAYICON && lParam == WM_RBUTTONUP) {
        ShowContextMenu(hWnd);
    }
    else if (msg == WM_COMMAND && LOWORD(wParam) == ID_TRAY_EXIT) {
        ExitProcess(0);
    }
    return DefSubclassProc(hWnd, msg, wParam, lParam);
}

/**
 * @brief Entry point. Initializes systems, runs the main loop, and cleans up.
 */
int main(int argc, char* argv[]) {
    if (debugMode) {
        AttachConsole();
    }

    SDLState state;
    if (!Initialize(state)) {
        return 1;
    }

    SDL_Texture* characterSpriteSheet = IMG_LoadTexture(state.renderer, "Resources/Spritesheets/Cat_Grey_White.png");
    SDL_SetTextureScaleMode(characterSpriteSheet, SDL_ScaleModeNearest);
    if (!characterSpriteSheet) {
        std::cout << "Failed to load texture. Error: " << SDL_GetError() << std::endl;
    }

    SDL_Event e;
    MSG msg;

    Uint32 lastTick = SDL_GetTicks();
    float deltaTime = 0.0f;

    isRunning = true;
    const float spriteSize = 128;

    // Main application loop: handles events, updates, and rendering.
    while (isRunning) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT)
                isRunning = false;
        }
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                isRunning = false;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        Uint32 currentTick = SDL_GetTicks();
        deltaTime = (currentTick - lastTick) / 1000.0f;
        lastTick = currentTick;

        SDL_SetRenderDrawBlendMode(state.renderer, SDL_BLENDMODE_BLEND);
        SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 0);
        SDL_RenderClear(state.renderer);

        SDL_Rect src{
            0,
            0,
            32,
            32
        };

        SDL_Rect dest{
            state.logw / 2,
            state.logh / 2,
            spriteSize,
            spriteSize
        };

        SDL_RenderCopy(state.renderer, characterSpriteSheet, &src, &dest);

        SDL_RenderPresent(state.renderer);

        SDL_Delay(1000 / frameRate);
    }

    SDL_DestroyTexture(characterSpriteSheet);
    CleanUp(state);
    return 0;
}

bool Initialize(SDLState& state) {
    bool success = true;

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::cerr << "SDL Init failed: " << SDL_GetError() << std::endl;
        CleanUp(state);
        success = false;
    }

    if (!(IMG_Init(IMG_INIT_PNG))) {
        std::cout << "SDL Image Init failed: " << SDL_GetError() << std::endl;
        CleanUp(state);
        success = false;
    }

    if (FAILED(CoInitialize(nullptr))) {
        std::cerr << "COM initialization failed\n";
        CleanUp(state);
        success = false;
    }

    SDL_Rect displayBounds;
    if (SDL_GetDisplayBounds(0, &displayBounds) != 0) {
        std::cerr << "SDL_GetDisplayBounds failed: " << SDL_GetError() << std::endl;
        CoUninitialize();
        IMG_Quit();
        SDL_Quit();
        return false;
    }
    state.width = displayBounds.w;
    state.height = displayBounds.h;
    state.logw = 1920;
    state.logh = 1080;

    state.window = SDL_CreateWindow(
        "Pet",
        0, 0, 0, 0,
        SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_SKIP_TASKBAR
    );
    if (!state.window) {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << "\n";
        CleanUp(state);
        success = false;
    }

    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo.version);
    if (!SDL_GetWindowWMInfo(state.window, &wmInfo)) {
        std::cerr << "SDL_GetWindowWMInfo failed: " << SDL_GetError() << "\n";
        CleanUp(state);
        success = false;
    }
    HWND hwnd = wmInfo.info.win.window;

    // Set window styles for transparency and click-through.
    LONG exStyle = GetWindowLong(hwSW_SHOWNOACTIVATEnd, GWL_EXSTYLE);
    SetWindowLong(hwnd, GWL_EXSTYLE,
        exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), 0, LWA_COLORKEY);

    // Set window as a child of the desktop window for proper layering.
    HWND desktopHWND = nullptr;
    EnumWindows([](HWND tophandle, LPARAM lParam) -> BOOL {
        HWND shellView = FindWindowEx(tophandle, nullptr, L"SHELLDLL_DefView", nullptr);
        if (shellView) {
            HWND* result = reinterpret_cast<HWND*>(lParam);
            *result = tophandle;
            return FALSE;
        }
        return TRUE;
        }, reinterpret_cast<LPARAM>(&desktopHWND));

    int desktopWidth;
    int desktopHeight;
    if (desktopHWND) {
        SetParent(hwnd, desktopHWND);
        SetWindowLong(hwnd, GWL_STYLE, WS_CHILD | WS_VISIBLE);
        RECT desktopRect;
        GetClientRect(desktopHWND, &desktopRect);

        desktopWidth = desktopRect.right - desktopRect.left;
        desktopHeight = desktopRect.bottom - desktopRect.top;

        SDL_SetWindowSize(state.window, desktopWidth, desktopHeight);
        SDL_SetWindowPosition(state.window, 0, 0);
        SetWindowPos(hwnd, HWND_TOP, 0, 0, desktopWidth, desktopHeight, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    state.renderer = SDL_CreateRenderer(state.window, -1, SDL_RENDERER_ACCELERATED);

    if (!state.renderer) {
        std::cout << "Failed to Initialize Renderer" << SDL_GetError() << "\n";
        CleanUp(state);
        success = false;
    }

    SDL_RenderSetLogicalSize(state.renderer, state.logw, state.logh);
    SDL_RenderSetIntegerScale(state.renderer, SDL_TRUE);

    SetWindowSubclass(hwnd, WndProc, 1, 0);
    AddTrayIcon(hwnd);
    SDL_ShowWindow(state.window);
    return success;
}

void CleanUp(SDLState& state) {
    SDL_DestroyRenderer(state.renderer);
    SDL_DestroyWindow(state.window);
    RemoveTrayIcon();
    CoUninitialize();
    RemoveWindowSubclass(hwnd, WndProc, 1);
    SDL_Quit();
}
```