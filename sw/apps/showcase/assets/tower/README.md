# 物理积木美术

从 `a1b6fd783` 恢复的原创 ARGB8888 零度积木素材，供独立自由玩法使用。

- 六种材质：wood、stone、ice、metal、rubber、glass。
- 六种形状：square、plank、brick、triangle、arch、circle，共 36 种。
- 形状轮廓与 `ui/tower.c` 的碰撞几何一致。
- `textures/` 保留原始材质；`tools/sw/compose_tower_blocks.py` 合成积木图。
- 平台、手形光标、旋转提示、扬尘和玻璃碎片随页使用。
- GEO 每次开机首次进入时生成 1632 个角度帧；再次进入使用同一图集。
- 积木架、标尺和纪录徽章素材已随对应玩法删除。
