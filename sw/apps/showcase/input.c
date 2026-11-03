/* input.c — P5 3.7/8.5; release before delivery to a new input owner.
 * State-only module, no GPIO/UART/MMIO; clk_sys cooperative foreground. */
#include "board/input.h"
static enum input_owner owner;
static uint32_t raw_keys, blocked_keys, snapshot, pending_pressed, pressed;
static uint16_t blocked_virtual;
static uint8_t blocked_mouse, wheel;
static int16_t wheel_delta;
static uint64_t received;
static struct virtual_input_state virtual;
static void update(void)
{
    blocked_keys &= raw_keys;
    uint32_t keys = raw_keys & ~blocked_keys;
    pending_pressed |= keys & ~snapshot;
    snapshot = keys;
}
void showcase_input_sample(uint32_t keys) { raw_keys = keys; update(); }
void showcase_input_owner(enum input_owner next)
{
    /* Also called on GUI page changes, including GUI -> GUI. */
    blocked_keys = raw_keys;
    blocked_virtual = virtual.keys;
    blocked_mouse = virtual.mouse;
    snapshot = pending_pressed = pressed = 0;
    wheel_delta = 0;
    owner = next;
}
enum input_owner showcase_input_current_owner(void) { return owner; }
void showcase_input_virtual(struct virtual_input_state input, uint64_t now)
{
    wheel_delta += (int8_t)(input.wheel - wheel);
    wheel = input.wheel;
    virtual = input;
    blocked_virtual &= input.keys;
    blocked_mouse &= input.mouse;
    received = now;
}
void showcase_input_expire(uint64_t now, uint64_t timeout)
{
    if (now - received >= timeout) {
        virtual.keys = virtual.mouse = virtual.active = 0;
        blocked_virtual = blocked_mouse = 0;
        wheel_delta = 0;
    }
}
struct virtual_input_state showcase_input_view(enum input_owner who)
{
    struct virtual_input_state result = virtual;
    result.keys &= ~blocked_virtual;
    result.mouse &= ~blocked_mouse;
    if (who != owner) result.keys = result.mouse = result.active = 0;
    return result;
}
uint32_t showcase_input_keys(enum input_owner who) { return who == owner ? snapshot : 0; }
int16_t showcase_input_wheel(void)
{
    int16_t result = owner == INPUT_GUI ? wheel_delta : 0;
    wheel_delta = 0;
    return result;
}
void showcase_input_dispatch(void) { pressed = pending_pressed; pending_pressed = 0; }
uint32_t platform_keys(void) { return snapshot; }
uint32_t platform_pressed(void) { return pressed; }
