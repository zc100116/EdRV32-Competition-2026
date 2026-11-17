# 平板农场演示

1. 把 `farm-sim.html` 拷贝到平板，用浏览器打开；所有素材均已内嵌，无需网络。
2. 或在本目录运行 `python3 -m http.server 8000`，平板访问电脑局域网 IP 的 8000 端口。
3. 舞台按屏幕等比缩放并留黑边；竖屏自动旋转 90°，建议横屏观看。支持时点击“全屏”；先让平板占摄像头画面宽度约 65%，再调距离和焦点。
4. 常见 10–13 英寸平板可从约 30–50 cm 试起，以取景比例和清晰度为准。
5. 开发板打开“智慧农场 → 看板 → 栏位对齐”，调左、右分界到平板两条栏间通道。
6. 调节会实时更新栏线和计数，默认 33% / 67%；本次开机内保留。
7. 确认牛 2、马 1、羊 3、鸟 3，按“盘点”；鸡鸭都属于 COCO 的鸟。
8. 话术：“先盘点存栏 → 羊离场，等待走失告警 → 羊归圈解除 → 羊串进牛栏 → 回圈解除”。
9. 点击右下“演示”自动完成上述顺序；等待为 3 / 6 / 4 / 6 秒，行走另计时。
10. 再点演示可停止；按“复位”回到初始栏位；也可用手指或鼠标拖动物制造事件。

素材：内置 imagegen 原创透明底照片，缩放后作为 PNG data URI 内嵌；动物生成参数 `transparent_background=true`，草地为 false。
第二头牛提示词：`Use case: photorealistic-natural. Original photographic transparent cutout of a real adult Hereford cow, stocky reddish brown body and broad white face, white lower legs, large visible udder, cloven hooves, broad ears, short horns. Full body side-on view facing right, head turned 45 degrees toward the viewer showing the clearly bovine face and wide pink muzzle. Real farm livestock photography, soft bright daylight, detailed natural fur, all four legs visible, full animal fills the frame. Transparent background with no ground, no shadow, no text, no scenery, no other animals.`
草地提示词：`Use case: photorealistic-natural. Background texture for farm simulator, landscape aspect ratio 5:3. An uninterrupted real green grassy pasture, photographed looking downward obliquely across short meadow grass, natural bright soft daylight, subtle variations in grass blades and small clover leaves. Ground fills entire image edge to edge; no horizon, no sky, no animals, no people, no fence, no buildings, no text. Real natural photographic texture at a scale that works under large photographic livestock cutouts.`
其余提示词模板：`Use case: photorealistic-natural. Single farm simulator sprite: {subject}. Real photographic cutout, full body, strict side profile facing right, all feet visible, standing naturally. Neutral daylight, highly realistic anatomy and texture. Transparent background, no ground, no shadow, no text, no other animals. Subject fills frame with small margin.`
`{subject}` 分别为 `A black and white Holstein dairy cow`、`A chestnut brown horse with black mane`、`A woolly white sheep with dark face`、`A red brown domestic chicken hen`、`A white domestic duck with orange beak`。

适配截图：`outputs/farm-sim/fit-{1080x1728,2400x1080,2560x1600,1280x800}.png`；手机竖屏 DPR 2.5。脚本同时检查三栏和九只动物完整可见、缩放/旋转后的鼠标及触摸拖动、窗口旋转和全屏按钮。

复现截图：`npm install --prefix build/farm-sim playwright-core@1.65.1 && node tools/demo/farm-sim/capture.mjs`。
识别：`PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/demo/farm-sim/validate.py`。
