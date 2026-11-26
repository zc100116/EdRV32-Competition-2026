/* File: windows.c (adapted from gpu_hello Win32 frontend)
 * Spec: PC design 4.5; S-0b Win32 frontend.
 * Description: GDI 720p display, keyboard and 48 kHz stereo waveOut playback.
 * Clock domain: host wall clock, paced at 60 Hz.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include "pc_soc.h"
#include "plat.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static HWND window;
static HWAVEOUT audio;
static WAVEHDR headers[16];
static int16_t audio_buffers[16][512];
static unsigned next_buffer;
static uint32_t keys;
static int running = 1;
static LARGE_INTEGER frequency, origin, deadline, previous;
static uint64_t sample_remainder;
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
    if (message == WM_KILLFOCUS) keys = 0;
    if (message == WM_KEYDOWN || message == WM_KEYUP) {
        uint32_t bit = 0;
        switch (wparam) {
        case VK_UP: bit = PLAT_UP; break;
        case VK_DOWN: bit = PLAT_DOWN; break;
        case VK_LEFT: bit = PLAT_LEFT; break;
        case VK_RIGHT: bit = PLAT_RIGHT; break;
        case 'Z': bit = PLAT_A; break;
        case 'X': bit = PLAT_B; break;
        case VK_RETURN: bit = PLAT_A; break;
        case VK_ESCAPE: bit = PLAT_START; break;
        default: break;
        }
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
    if (now.QuadPart > deadline.QuadPart + frequency.QuadPart / 60) deadline = now;
    return frames;
}
uint32_t test_input_keys(void) { return plat_keys(); }
uint32_t pc_frontend_keys(void) { messages(); return keys; }
uint64_t test_clock_us(void)
{
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (uint64_t)((now.QuadPart - origin.QuadPart) * 1000000 / frequency.QuadPart);
}
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
    else if (argc != 1) { fputs("gpu_test.exe [--half]\n", stderr); return 1; }
    HINSTANCE instance = GetModuleHandle(NULL);
    WNDCLASS cls = {0};
    cls.lpfnWndProc = procedure;
    cls.hInstance = instance;
    cls.lpszClassName = "EdRV32GpuTest";
    cls.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClass(&cls)) win_error("RegisterClass", GetLastError());
    RECT rect = {0, 0, (LONG)(1280 / scale), (LONG)(720 / scale)};
    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    if (!AdjustWindowRect(&rect, style, FALSE)) win_error("AdjustWindowRect", GetLastError());
    window = CreateWindow(cls.lpszClassName, "Prism Patrol / Candy Canyon - GPU Test", style,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top,
        NULL, NULL, instance, NULL);
    if (!window) win_error("CreateWindow", GetLastError());
    WAVEFORMATEX format = {WAVE_FORMAT_PCM, 2, 48000, 192000, 4, 16, 0};
    MMRESULT result = waveOutOpen(&audio, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL);
    if (result) win_error("waveOutOpen", result);
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&origin);
    deadline = previous = origin;
    test_init();
    ShowWindow(window, SW_SHOW);
    while (running) {
        messages();
        test_frame();
        plat_wait_vsync();
        InvalidateRect(window, NULL, FALSE);
        UpdateWindow(window);
    }
    waveOutReset(audio);
    for (unsigned i = 0; i < 16; ++i) if (headers[i].dwFlags & WHDR_PREPARED)
        waveOutUnprepareHeader(audio, &headers[i], sizeof(headers[i]));
    waveOutClose(audio);
    pc_soc_destroy();
    return 0;
}
