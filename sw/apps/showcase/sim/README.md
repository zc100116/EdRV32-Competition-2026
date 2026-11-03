# Showcase 风格样板（P1a，一次性）

1280×720 RGB565；三套界面共用 `style_samples.c`，只有入口不同。
先初始化子模块：`git submodule update --init third_party/lvgl`。
工具需要 C11 编译器、Python 3、Node.js/npx 和 Zig 0.17.0。
执行 `. ~/.local/opt/edrv32/env.sh` 加载工具环境。
Linux 截图：`make -C sw/apps/showcase/sim shots`。
截图输出：`build/sim/shots/`（三套首页、监控页和一次焦点移动）。
Windows 构建：`make -C sw/apps/showcase/sim win`。
程序输出：`build/sim/showcase_sim.exe`，直接双击启动。
字体首次构建时由 `npx lv_font_conv@1.5.3` 生成到 `build/sim/fonts/`。
字体使用 Noto Sans SC（OFL）和 LVGL 自带 FontAwesome 符号字体。
按 `1` / `2` / `3` 切换 A 深色科技 / B 浅色简洁 / C 深紫仪表。
按左右箭头移动卡片焦点，包含置灰卡片。
选中“系统监控”按 Enter，或直接点击该卡片进入。
其他卡片保留为视觉样板，点击及 Enter 均不进入页面。
按 Esc 返回首页；模拟统计每 0.5 秒更新。
样板选定风格后删除，不作为板上 UI 框架。
