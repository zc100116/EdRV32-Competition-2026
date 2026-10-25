# Rounded shadow seed mask

运行 `make case-sim CASE=vision/render-shadow-mask`。验证 `BOX_SHADOW` 使用的圆角 A8 原始蒙版：内容矩形向内留出模糊半径，像素按圆角几何写 0/255，行尾按 WSTRB 保留区域外字节。测试覆盖矩形、非整 beat 宽度、圆角、随机 AXI 停顿及非法几何拒绝。
