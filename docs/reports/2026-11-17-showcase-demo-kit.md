# 平板 AI 演示素材包验证（T-DEMO-KIT）

- 代码：本报告所在提交，基于并最终 rebase 到 `origin/zc100116/b3`（`59a42f890`）；农场原文件未修改，仅按原文嵌入。
- 主机：Chromium 1248 / Playwright 1.65.1；板端同权重 INT8 描述符参考执行及整数后处理，confidence >0.25、同类 NMS IoU >0.45；未改模型或阈值。
- 拍屏：2000×1200 舞台，素材 2000×1125、控制区在素材外；沿用农场投影四角 (220,100)/(1052,112)/(1044,614)/(228,603)，输出 1280×720；模糊 σ=1 px（7×7）、亮度 0.85、噪声 σ=2，种子 17。视频每秒一帧，含末尾不足一秒。

| 场景 | 素材数与来源 | 最终验证 |
|---|---|---|
| 智慧农场 | 现有原创离线网页 1 份 | 原文件 srcdoc 嵌入、进入与返回通过 |
| 马路车流 | Mixkit 免费商用视频 2 段 | 每段 20/20 帧检出至少 2 辆车，均 100% |
| 动物园 | imagegen 原创照片 6 张 | 6/6 类别与每类数量完全一致，共 9 只动物 |
| 舞蹈 | Mixkit 免费商用视频 2 段 | 每段 20/20 帧检出该舞者且至少 12/17 点 confidence >0.5，均 100% |
| 手势 | imagegen 原创照片 13 张 | 13/13 分类正确；抓紧更换 1 次后通过，无删去的手势 |
| 工地 | Mixkit 免费商用视频 1 段 | 19/20 帧有检出（95%），戴帽/未戴帽均出现 |
| 人脸 | imagegen 虚构成人照片 4 张 | 4/4 人数正确，分别 1、1、2、3 人 |

- 视频作者与来源：`dubassy` / busy-street-in-the-city-4000；`rubenvelasco` / traffic-jam-on-a-highway-in-a-pine-forest-3304；`franklandgrave` / man-breakdancing-452 与 man-dancing-under-changing-lights-1240；`joshjanssen` / man-puts-on-hard-hat-1440；来源页前缀均为 `https://mixkit.co/free-stock-video/`。
- 5 段均为 Mixkit Stock Video Free License（`https://mixkit.co/license/#videoFree`），逐项来源页、公开文件 URL、截取与慢放参数见 `tools/demo/kit/clips.json`；网页来源页同样逐项展示作者和许可，地址只作文字。
- 视频均为 1280×720、H.264 Main / yuv420p、25 fps、无音轨、faststart；每段 19.52 s，3,127,490–3,381,535 字节（均 <6 MB），循环接缝交叉淡化 0.5 s；竖幅保留全身并留边。
- HTML：28,611,819 字节（28.61 MB，27.29 MiB），低于 45 MB；全部素材内嵌。截图回归 PASS：七场景、零网络请求、暂停/播放、前后切换、图片 5 秒切换、Blob URL 释放、竖屏鼠标/触摸滑动、全屏；尚未做微信/QQ/iPad 真机测试。
- 交付：`SOC系统设计/outputs/demo-kit/` 内含 `demo-kit.html`、首页与七场景 2560×1600 截图、首页 1080×1728 竖屏截图、六张 `*-contact.png` 联系表及来源页截图；本 worktree 同名 `outputs/demo-kit/` 保留截图。
- 数字与日志：`build/demo-kit/{traffic,zoo,dance,gesture,helmet,face}-results.json`、`validate.log`、`capture.log`；原片、转码和拍屏中间帧均未入库。无 RTL 改动，Verilator/Verilog 风格检查不适用；Python/JS 语法、源文件行宽与 git diff 空白检查通过。

复现（仓库根目录）：
```sh
~/.local/opt/edrv32-py/bin/python tools/demo/kit/fetch.py
~/.local/opt/edrv32-py/bin/python tools/demo/kit/build.py
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/demo/kit/validate.py
npm install --prefix build/farm-sim playwright-core@1.65.1
node tools/demo/kit/capture.mjs
```
