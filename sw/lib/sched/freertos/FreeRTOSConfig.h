/* FreeRTOSConfig.h — T-VIS-RTOS single-core RV32IM; clk_sys/CLINT. */
#ifndef SHOWCASE_FREERTOS_CONFIG_H
#define SHOWCASE_FREERTOS_CONFIG_H
#include "soc_map.h"
#include "clint.h"

#define configCPU_CLOCK_HZ EDRV32_CLK_SYS_HZ
#define configMTIME_BASE_ADDRESS (EDRV32_CLINT_BASE + CLINT_MTIME_LO)
#define configMTIMECMP_BASE_ADDRESS (EDRV32_CLINT_BASE + CLINT_MTIMECMP_LO)
#define configTICK_RATE_HZ 1000
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 0
#define configMAX_PRIORITIES 4
#define configMINIMAL_STACK_SIZE 512
#define configMAX_TASK_NAME_LEN 24
#define configTOTAL_HEAP_SIZE (128 * 1024)
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configSUPPORT_STATIC_ALLOCATION 0
#define configUSE_MUTEXES 1
#define configUSE_RECURSIVE_MUTEXES 1
#define configUSE_TASK_NOTIFICATIONS 1
#define configUSE_IDLE_HOOK 1
#define configUSE_TIMERS 0
#define configUSE_TICK_HOOK 0
#define INCLUDE_xSemaphoreGetMutexHolder 1
#define configUSE_16_BIT_TICKS 0
#define configCHECK_FOR_STACK_OVERFLOW 0
#define configUSE_MALLOC_FAILED_HOOK 0
#define configISR_STACK_SIZE_WORDS 2048
#define INCLUDE_vTaskSuspend 1
#define INCLUDE_xTaskGetCurrentTaskHandle 1
#define INCLUDE_xTaskGetSchedulerState 1
void sched_assert(const char *file, unsigned line);
void sched_trace_out(void);
void sched_trace_in(void);
#define configASSERT(x) ((void)0)
#define traceTASK_SWITCHED_OUT() sched_trace_out()
#define traceTASK_SWITCHED_IN() sched_trace_in()
/* Pair kernel API traces around task execution; blocking time belongs to
 * whichever service runs next, never to the blocked caller's kernel time. */
void sched_kernel_enter(void);
void sched_kernel_leave(void);
#define traceENTER_xQueueGenericSend(...) sched_kernel_enter()
#define traceRETURN_xQueueGenericSend(...) sched_kernel_leave()
#define traceENTER_xQueueReceive(...) sched_kernel_enter()
#define traceRETURN_xQueueReceive(...) sched_kernel_leave()
#define traceENTER_xQueueSemaphoreTake(...) sched_kernel_enter()
#define traceRETURN_xQueueSemaphoreTake(...) sched_kernel_leave()
#define traceENTER_xQueueGiveMutexRecursive(...) sched_kernel_enter()
#define traceRETURN_xQueueGiveMutexRecursive(...) sched_kernel_leave()
#define traceENTER_xQueueTakeMutexRecursive(...) sched_kernel_enter()
#define traceRETURN_xQueueTakeMutexRecursive(...) sched_kernel_leave()
#define traceENTER_xQueueGetMutexHolder(...) sched_kernel_enter()
#define traceRETURN_xQueueGetMutexHolder(...) sched_kernel_leave()
#define traceENTER_ulTaskGenericNotifyTake(...) sched_kernel_enter()
#define traceRETURN_ulTaskGenericNotifyTake(...) sched_kernel_leave()
#define traceENTER_xTaskGenericNotify(...) sched_kernel_enter()
#define traceRETURN_xTaskGenericNotify(...) sched_kernel_leave()
#define traceENTER_vTaskGenericNotifyGiveFromISR(...) sched_kernel_enter()
#define traceRETURN_vTaskGenericNotifyGiveFromISR(...) sched_kernel_leave()
#define traceENTER_xQueueGiveFromISR(...) sched_kernel_enter()
#define traceRETURN_xQueueGiveFromISR(...) sched_kernel_leave()
#define traceENTER_xTaskGetCurrentTaskHandle(...) sched_kernel_enter()
#define traceRETURN_xTaskGetCurrentTaskHandle(...) sched_kernel_leave()
#endif
