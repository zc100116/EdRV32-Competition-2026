/* File: windows.c (based on the shared GPU PC frontend)
 * Spec: ember_isles tech 2; PC design 4.5 Win32 frontend.
 * Description: GDI 720p display, keyboard and 48 kHz stereo waveOut playback.
 * Clock domain: host wall clock, paced at 60 Hz.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include "pc_soc.h"
#include "plat.h"
#include "game.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static HWND window;
static HWAVEOUT audio;
static WAVEHDR headers[16];
static int16_t audio_buffers[16][512];
static unsigned next_buffer;
static uint32_t keys;
static uint16_t game_keys;
static struct plat_pointer_state pointer;
static int running = 1;
static LARGE_INTEGER frequency, origin, deadline, previous;
static uint64_t sample_remainder;
static double frame_times[600], work_times[600];
static unsigned timing_count;
static int timing_order(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static void report_timing(void)
{
    if (!timing_count) return;
    double total = 0, work = 0;
    for (unsigned i = 0; i < timing_count; ++i) {
        total += frame_times[i];
        work += work_times[i];
    }
    qsort(frame_times, timing_count, sizeof(*frame_times), timing_order);
    qsort(work_times, timing_count, sizeof(*work_times), timing_order);
    struct gpu_emu_usage usage = pc_soc_gpu_usage();
    printf("PC frames=%u fps=%.2f frame_ms(mean/p95/max)=%.3f/%.3f/%.3f "
           "game_gdi_ms(mean/p95/max)=%.3f/%.3f/%.3f tex_end=%u obj_slots=%u particles=%u\n",
           timing_count, timing_count * 1000.0 / total, total / timing_count,
           frame_times[timing_count * 95 / 100], frame_times[timing_count - 1],
           work / timing_count, work_times[timing_count * 95 / 100],
           work_times[timing_count - 1], usage.texture_bytes, usage.object_slots,
           usage.objects_alive);
    timing_count = 0;
}
static _Noreturn void win_error(const char *operation, unsigned long code)
{
    fprintf(stderr, "%s failed: %lu\n", operation, code);
    exit(1);
}
static void messages(void)
{
    MSG message;
    while (PeekMessage(&message, NULL, 0, 0, PM_REMOVE)) {
        if (message.message == WM_QUIT) running = 0;
        TranslateMessage(&message);
        DispatchMessage(&message);
    }
}
static LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_DESTROY) { running = 0; PostQuitMessage(0); return 0; }
    if (message == WM_KILLFOCUS) {
        keys = game_keys = pointer.buttons = 0;
        pc_soc_game_input(game_keys, pointer);
    }
    if (message == WM_MOUSEMOVE || message == WM_LBUTTONDOWN ||
        message == WM_LBUTTONUP || message == WM_RBUTTONDOWN || message == WM_RBUTTONUP ||
        message == WM_MBUTTONDOWN || message == WM_MBUTTONUP) {
        RECT client;
        GetClientRect(hwnd, &client);
        pointer.x = (int16_t)((int16_t)LOWORD(lparam) * 640 / client.right);
        pointer.y = (int16_t)((int16_t)HIWORD(lparam) * 360 / client.bottom);
        pointer.buttons = ((wparam & MK_LBUTTON) ? 1 : 0) |
            ((wparam & MK_RBUTTON) ? 2 : 0) | ((wparam & MK_MBUTTON) ? 4 : 0);
        if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN ||
            message == WM_MBUTTONDOWN) SetCapture(hwnd);
        if (!pointer.buttons) ReleaseCapture();
        pc_soc_game_input(game_keys, pointer);
        return 0;
    }
    if (message == WM_CAPTURECHANGED) {
        pointer.buttons = 0;
        pc_soc_game_input(game_keys, pointer);
    }
    if (message == WM_KEYDOWN || message == WM_KEYUP) {
        uint32_t bit = 0;
        switch (wparam) {
        case VK_UP: bit = PLAT_UP; break;
        case VK_DOWN: bit = PLAT_DOWN; break;
        case VK_LEFT: bit = PLAT_LEFT; break;
        case VK_RIGHT: bit = PLAT_RIGHT; break;
        case 'Z': bit = PLAT_A; break;
        case 'X': bit = PLAT_B; break;
        case VK_RETURN: bit = PLAT_START; break;
        case VK_ESCAPE: bit = PLAT_SELECT; break;
        default: break;
        }
        uint16_t game_bit = 0;
        switch (wparam) {
        case 'W': case VK_UP: game_bit = PLAT_KEY_W; break;
        case 'A': case VK_LEFT: game_bit = PLAT_KEY_A; break;
        case 'S': case VK_DOWN: game_bit = PLAT_KEY_S; break;
        case 'D': case VK_RIGHT: game_bit = PLAT_KEY_D; break;
        case 'J': game_bit = PLAT_KEY_J; break;
        case 'K': game_bit = PLAT_KEY_K; break;
        case 'L': game_bit = PLAT_KEY_L; break;
        case 'U': game_bit = PLAT_KEY_U; break;
        case 'Q': game_bit = PLAT_KEY_Q; break;
        case 'F': game_bit = PLAT_KEY_F; break;
        case VK_SPACE: game_bit = PLAT_KEY_SPACE; break;
        case VK_ESCAPE: game_bit = PLAT_KEY_ESC; break;
        case VK_RETURN: game_bit = PLAT_KEY_ENTER; break;
        default: break;
        }
        if (message == WM_KEYDOWN) game_keys |= game_bit;
        else game_keys &= (uint16_t)~game_bit;
        pc_soc_game_input(game_keys, pointer);
        if (message == WM_KEYDOWN) keys |= bit;
        else keys &= ~bit;
        return 0;
    }
    if (message == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(hwnd, &paint);
        RECT rect;
        GetClientRect(hwnd, &rect);
        BITMAPINFO info = {0};
        info.bmiHeader.biSize = sizeof(info.bmiHeader);
        info.bmiHeader.biWidth = 1280;
        info.bmiHeader.biHeight = -720;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        int result = StretchDIBits(dc, 0, 0, rect.right, rect.bottom, 0, 0, 1280, 720,
                                  pc_soc_pixels(), &info, DIB_RGB_COLORS, SRCCOPY);
        EndPaint(hwnd, &paint);
        if (result == (int)GDI_ERROR) win_error("StretchDIBits", GetLastError());
        return 0;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
}
uint32_t pc_frontend_wait(void)
{
    deadline.QuadPart += frequency.QuadPart / 60;
    LARGE_INTEGER now;
    for (;;) {
        messages();
        QueryPerformanceCounter(&now);
        if (!running || now.QuadPart >= deadline.QuadPart) break;
        Sleep(1);
    }
    /* Render time is part of wall time; audio consumption follows 48 kHz even
     * when a complex frame takes longer than one display interval. */
    uint64_t elapsed = (uint64_t)(now.QuadPart - previous.QuadPart) * 48000 + sample_remainder;
    uint32_t frames = (uint32_t)(elapsed / (uint64_t)frequency.QuadPart);
    sample_remainder = elapsed % (uint64_t)frequency.QuadPart;
    previous = now;
    /* Keep an absolute cadence: Sleep's rounding must not accumulate each frame. */
    return frames;
}
uint32_t pc_frontend_keys(void) { messages(); return keys; }
uint32_t pc_frontend_millis(void)
{
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (uint32_t)((now.QuadPart - origin.QuadPart) * 1000 / frequency.QuadPart);
}
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    WAVEHDR *header = &headers[next_buffer];
    while ((header->dwFlags & WHDR_INQUEUE) && running) { messages(); Sleep(1); }
    if (!running) return;
    if (header->dwFlags & WHDR_PREPARED) {
        MMRESULT result = waveOutUnprepareHeader(audio, header, sizeof(*header));
        if (result) win_error("waveOutUnprepareHeader", result);
    }
    memcpy(audio_buffers[next_buffer], samples, frames * 4);
    memset(header, 0, sizeof(*header));
    header->lpData = (char *)audio_buffers[next_buffer];
    header->dwBufferLength = frames * 4;
    MMRESULT result = waveOutPrepareHeader(audio, header, sizeof(*header));
    if (result) win_error("waveOutPrepareHeader", result);
    result = waveOutWrite(audio, header, sizeof(*header));
    if (result) win_error("waveOutWrite", result);
    next_buffer = (next_buffer + 1) % 16;
}
int main(int argc, char **argv)
{
    unsigned scale = 1;
    if (argc == 2 && !strcmp(argv[1], "--half")) scale = 2;
    else if (argc != 1) { fputs("ember_isles.exe [--half]\n", stderr); return 1; }
    HINSTANCE instance = GetModuleHandle(NULL);
    WNDCLASS cls = {0};
    cls.lpfnWndProc = procedure;
    cls.hInstance = instance;
    cls.lpszClassName = "EmberIsles";
    cls.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClass(&cls)) win_error("RegisterClass", GetLastError());
    RECT rect = {0, 0, (LONG)(1280 / scale), (LONG)(720 / scale)};
    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    if (!AdjustWindowRect(&rect, style, FALSE)) win_error("AdjustWindowRect", GetLastError());
    window = CreateWindow(cls.lpszClassName, "Ember Isles", style,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top,
        NULL, NULL, instance, NULL);
    if (!window) win_error("CreateWindow", GetLastError());
    WAVEFORMATEX format = {WAVE_FORMAT_PCM, 2, 48000, 192000, 4, 16, 0};
    MMRESULT result = waveOutOpen(&audio, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL);
    if (result) win_error("waveOutOpen", result);
    result = timeBeginPeriod(1);
    if (result) win_error("timeBeginPeriod", result);
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&origin);
    ember_game_init();
    QueryPerformanceCounter(&deadline);
    previous = deadline;
    ShowWindow(window, SW_SHOW);
    for (unsigned frame = 1; running; ++frame) {
        LARGE_INTEGER begin, submitted, composed, finished;
        QueryPerformanceCounter(&begin);
        messages();
        ember_game_realtime(frame);
        QueryPerformanceCounter(&submitted);
        plat_wait_vsync();
        QueryPerformanceCounter(&composed);
        InvalidateRect(window, NULL, FALSE);
        UpdateWindow(window);
        QueryPerformanceCounter(&finished);
        frame_times[timing_count] = (finished.QuadPart - begin.QuadPart) * 1000.0 /
            frequency.QuadPart;
        work_times[timing_count] = ((submitted.QuadPart - begin.QuadPart) +
            (finished.QuadPart - composed.QuadPart)) * 1000.0 / frequency.QuadPart;
        if (++timing_count == 600) report_timing();
    }
    report_timing();
    waveOutReset(audio);
    for (unsigned i = 0; i < 16; ++i) if (headers[i].dwFlags & WHDR_PREPARED)
        waveOutUnprepareHeader(audio, &headers[i], sizeof(headers[i]));
    waveOutClose(audio);
    timeEndPeriod(1);
    pc_soc_destroy();
    return 0;
}
