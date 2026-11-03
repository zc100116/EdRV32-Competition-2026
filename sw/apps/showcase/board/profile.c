/* profile.c — showcase 4.5.7; CLINT 10 kHz PC samples and top 256 cache lines.
 * IRQ only increments preallocated counters; reporting is sliced in app context. */
#include "board.h"
#include "../platform.h"
#include "../app.h"
#include "../runtime.h"
#include "clint.h"
#include <stdlib.h>
#include <string.h>
extern const uint8_t __sram_code_start[],__sram_code_end[];
extern const uint8_t __ddr_code_start[],__ddr_code_end[];
static uint32_t *counts;
static unsigned sram_lines,ddr_lines;
static uint64_t until,next_sample;
static unsigned scan,report,top_count;
static struct { uint32_t address,count; } top[256];
static char command[32];
static unsigned command_length;
static unsigned active;
uint64_t board_prof_deadline(uint64_t deadline)
{ return active && next_sample<deadline ? next_sample : deadline; }
void board_prof_sample(uint32_t pc)
{
    if(!active) return;
    uint64_t now=platform_ticks();
    if(now<next_sample) return;
    if(now>=until) {
        active=0; scan=0; report=0; top_count=0;
        sched_signal(&application_task,0x100); return;
    }
    uintptr_t a=(uintptr_t)__sram_code_start,b=(uintptr_t)__ddr_code_start;
    if(pc>=a && pc<(uintptr_t)__sram_code_end) ++counts[(pc-a)/32];
    else if(pc>=b && pc<(uintptr_t)__ddr_code_end) ++counts[sram_lines+(pc-b)/32];
    next_sample=now+platform_clock_hz()/10000;
}
void board_serial_character(int byte)
{
    if(byte=='\r' || byte=='\n') {
        command[command_length]=0;
        if(!strncmp(command,"prof ",5)) {
            unsigned seconds=(unsigned)strtoul(command+5,0,10);
            if(!seconds) { platform_puts("prof: seconds must be positive\r\n"); }
            else {
                sram_lines=((uintptr_t)__sram_code_end-(uintptr_t)__sram_code_start+31)/32;
                ddr_lines=((uintptr_t)__ddr_code_end-(uintptr_t)__ddr_code_start+31)/32;
                if(!counts) counts=calloc(sram_lines+ddr_lines,sizeof(*counts));
                if(!counts) { platform_puts("prof allocation failed\r\n"); platform_stop(); }
                memset(counts,0,(sram_lines+ddr_lines)*sizeof(*counts));
                until=platform_ticks()+(uint64_t)seconds*platform_clock_hz();
                next_sample=platform_ticks()+platform_clock_hz()/10000; active=1;
                clint_set_compare(next_sample);
            }
        }
        command_length=0;
    } else if(command_length+1<sizeof(command)) command[command_length++]=(char)byte;
}
void board_prof_step(void)
{
    if(active || !counts) return;
    unsigned end=scan+256;
    unsigned lines=sram_lines+ddr_lines;
    if(end>lines) end=lines;
    while(scan<end) {
        uint32_t c=counts[scan];
        if(c && (top_count<256 || c>top[top_count-1].count)) {
            unsigned i=top_count<256 ? top_count++ : 255;
            while(i && top[i-1].count<c) { top[i]=top[i-1]; --i; }
            top[i].count=c;
            top[i].address=scan<sram_lines ? (uintptr_t)__sram_code_start+scan*32 :
                (uintptr_t)__ddr_code_start+(scan-sram_lines)*32;
        }
        ++scan;
    }
    if(scan<lines) app_wake_at(platform_ticks());
    else if(report<top_count) {
        platform_puts("PROF "); platform_put_hex(top[report].address);
        platform_puts(" "); platform_put_u32(top[report++].count); platform_puts("\r\n");
        app_wake_at(platform_ticks());
    } else { free(counts); counts=0; }
}
