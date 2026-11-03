# 示例场景

两张图由 Codex 内置 imagegen 生成，仅用于桌面界面；板上不使用。
构建时 `tools/sw/png2c.py` 转成 960×540 RGB565，输出在 `build/sim/`。

- `street-scene.png` 提示词：Use case: photorealistic-natural. Generate a natural daylight documentary photograph for an embedded vision demonstration, wide 16:9 composition. Urban street viewed at pedestrian eye level: a pedestrian in the left foreground, a bicycle and rider toward the middle, two cars on the right, trees and buildings behind. All main objects fully within the frame, distinct and easy to identify. Realistic proportions and everyday lighting. No labels, no detection boxes, no text, no watermark. Save the generated PNG image.
- `indoor-scene.png` 提示词：Use case: photorealistic-natural. Asset: image recognition demonstration sample photo. Wide 16:9 realistic indoor living room scene in soft daylight. A tan dog resting beside a blue sofa on the left, a wooden coffee table in the center with a book and cup, a potted plant at the right, a chair and window in the background. Show whole identifiable objects with no overlap hiding main subjects. No people, no text, no detection boxes, no watermark.
