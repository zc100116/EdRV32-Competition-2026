/* coremark.c — CPU 7.1; Chinese event names for the two-round counter view. */
#include "coremark.h"
const char *const ui_hpm_names[16] = {
    "双退休周期", "单退休周期", "零退休周期", "已退休的分支和跳转数",
    "配对失败：组内 RAW", "配对失败：结构冲突",
    "配对失败：槽 1 类型不支持",
    "配对失败：第二条未取到", "load-use 停顿周期", "除法停顿周期",
    "设备/非缓存访问等待周期", "前端断流周期", "I$ 缺失次数", "D$ 缺失次数",
    "D$ 脏行写回次数", "分支和跳转误预测次数"
};
