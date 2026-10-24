运行 `make case-sim CASE=vision/render-board-telemetry`。测试将 UART 分频加速，模拟板级各阶段事件与 AXI 计数，逐字检查一次性 `RPERF` 和周期性 `RSTAT` 记录。板上时钟仍为 125 MHz，UART 为 115200。
