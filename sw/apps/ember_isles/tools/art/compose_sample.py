#!/usr/bin/env python3
"""compose_sample.py — ART-2 / tech §7: compose AI sprites, APNG, embedded review page.
Host-only art sample; no game logic or GPU code changes. Standard library only.
"""
import base64
import json
import math
import struct
import zlib

from normalize_sample import ASSETS, OUTPUT, decode_png, png, chunk

IDLE_HANDS = [(34, 28), (34, 28), (34, 28), (34, 28)]
WALK_HANDS = [(34, 28), (34, 31), (32, 31), (34, 28), (34, 31), (32, 31)]
CAST_HANDS = [(34, 28), (35, 29), (35, 27), (36, 21), (36, 21), (34, 28)]
FRONT_HANDS = [(34, 28), (34, 29), (34, 30), (34, 28), (34, 29), (34, 30)]
BACK_HANDS = [(33, 29), (33, 30), (33, 29), (33, 29), (33, 30), (33, 29)]


def read(name):
    w, h, raw = decode_png((ASSETS / name).read_bytes())
    return w, h, [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]


def crop(image, x, y, w, h):
    iw, ih, p = image
    return w, h, [p[(y + j) * iw + x + i] for j in range(h) for i in range(w)]


def cell(image, column, row, w, h):
    return crop(image, column * w, row * h, w, h)


def hflip(sprite):
    w, h, pixels = sprite
    return w, h, [pixels[y * w + w - 1 - x] for y in range(h) for x in range(w)]


def rotate(sprite, angle):
    """Nearest-pixel inverse rotation into a 48-square cell for eight directions."""
    w, h, p = sprite
    c, s = math.cos(angle), math.sin(angle)
    output = []
    for y in range(48):
        for x in range(48):
            u = round((x - 23.5) * c + (y - 23.5) * s + (w - 1) / 2)
            v = round(-(x - 23.5) * s + (y - 23.5) * c + (h - 1) / 2)
            output.append(p[v * w + u] if 0 <= u < w and 0 <= v < h else (0, 0, 0, 0))
    return 48, 48, output


def paste(canvas, sprite, x, y, opacity=255, additive=False, flip=False):
    w, h, pixels = sprite
    for j in range(h):
        if not 0 <= y + j < 360:
            continue
        for i in range(w):
            if not 0 <= x + i < 640:
                continue
            s = pixels[j * w + (w - 1 - i if flip else i)]
            a = s[3] * opacity // 255
            if not a:
                continue
            index = (y + j) * 640 + x + i
            d = canvas[index]
            if additive:
                canvas[index] = tuple(min(255, d[k] + s[k] * a // 255)
                                      for k in range(3)) + (255,)
            else:
                canvas[index] = tuple((s[k] * a + d[k] * (255 - a)) // 255
                                      for k in range(3)) + (255,)


def apng(path, frames):
    width, height = 640, 360
    data = bytearray(b'\x89PNG\r\n\x1a\n')
    data.extend(chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)))
    data.extend(chunk(b'acTL', struct.pack('>II', len(frames), 0)))
    sequence = 0
    for n, packed in enumerate(frames):
        data.extend(chunk(b'fcTL', struct.pack('>IIIIIHHBB', sequence, width, height,
                                             0, 0, 1, 10, 0, 0)))
        sequence += 1
        if n == 0:
            data.extend(chunk(b'IDAT', packed))
        else:
            data.extend(chunk(b'fdAT', struct.pack('>I', sequence) + packed))
            sequence += 1
    data.extend(chunk(b'IEND', b''))
    path.write_bytes(data)


def main():
    hero = read('04-keeper-animation-native.png')
    directions = read('09-directions-native.png')
    enemy = read('05-enemies-native.png')
    terrain = read('06-terrain-native.png')
    props = read('07-props-native.png')
    effects = read('08-effects-native.png')
    shadow = cell(effects, 6, 2, 32, 32)
    staff = crop(props, 96, 64, 48, 64)
    actors = [
        (204, 128, 0), (270, 112, 0), (356, 102, 1), (451, 135, 0),
        (502, 188, 1), (425, 230, 0), (345, 262, 0), (249, 246, 1),
        (169, 216, 0), (565, 266, 0), (558, 102, 0), (389, 322, 1),
        (287, 319, 0), (470, 317, 0), (216, 303, 0), (589, 205, 0),
    ]
    decor = [
        (0, 0, 204, 78), (1, 0, 246, 74), (2, 0, 156, 313),
        (3, 0, 126, 141), (0, 1, 553, 66), (1, 1, 393, 89),
        (0, 0, 591, 340), (1, 0, 545, 342), (3, 0, 121, 271),
        (2, 0, 494, 75), (0, 1, 463, 87), (1, 1, 183, 236),
        (0, 0, 270, 78), (3, 0, 130, 348),
    ]
    background = [(242, 196, 117, 255)] * (640 * 360)
    for y in range(0, 360, 64):
        for x in range(0, 640, 64):
            variant = ((x // 64) * 5 + (y // 64) * 7) % 3
            if x >= 192 and x < 448 and variant == 2:
                variant = 0
            tile = cell(terrain, 0 if x >= 192 else 1, variant, 64, 64)
            if x < 128:
                water = crop(terrain, 192, variant * 64, 32, 64)
                paste(background, water, x, y)
                paste(background, water, x + 32, y, flip=True)
                continue
            if x == 128:
                tile = cell(terrain, 3, variant, 64, 64)
            if x >= 448 and y < 128:
                tile = cell(terrain, 2, variant, 64, 64)
            paste(background, tile, x, y, flip=(x >= 192 and (x // 64 + y // 64) % 2 == 0))
    for x in range(0, 192, 64):
        paste(background, cell(terrain, 4, x // 64, 64, 64), x, 192)
    for x in range(448, 640, 64):
        paste(background, cell(terrain, 6, (x // 64) % 3, 64, 64), x, 42)
        paste(background, cell(terrain, 5, (x // 64) % 3, 64, 64), x, -22)
    frames = []
    for frame in range(40):
        canvas = background[:]
        hero_x = 320 + (frame % 12 if frame < 12 else 0)
        hero_y = 199
        # Saturated navy dusk outside lamp regions, never black. Mask alpha is A4.
        for y in range(360):
            for x in range(640):
                distance = min(math.hypot(x - hero_x, y - hero_y) / 145,
                               math.hypot(x - 393, y - 70) / 116,
                               math.hypot(x - 183, y - 215) / 112)
                a4 = round(max(0, min(1, distance - .25)) * 6)
                a = a4 * 17
                p = canvas[y * 640 + x]
                canvas[y * 640 + x] = tuple((p[k] * (255 - a) + (21, 31, 66)[k] * a)
                                            // 255 for k in range(3)) + (255,)
        objects = []
        for column, row, x, y in decor:
            objects.append((y, cell(props, column, row, 48, 64), x - 24, y - 59))
            paste(canvas, shadow, x - 16, y - 21, 85)
        for number, (x, y, species) in enumerate(actors):
            phase = (frame + number) % 4
            offset = (0, 1, 2, 1)[phase]
            x += offset if x < 320 else -offset
            row = species * 2
            column = phase
            if number == 3 and 15 <= frame < 19:
                column = 4
            if number == 5 and frame >= 20:
                row += 1
                column = min(3, (frame - 20) // 3)
            sprite = cell(enemy, column, row, 64, 64)
            paste(canvas, shadow, x - 16, y - 24, 115)
            objects.append((y, sprite, x - 32, y - 59))
        if frame < 6:
            column, row = frame % 6, 0
            player = cell(directions, column, row, 48, 48)
            hand_x, hand_y = FRONT_HANDS[column]
        elif frame < 12:
            column, row = frame % 6, 1
            player = cell(directions, column, row, 48, 48)
            hand_x, hand_y = BACK_HANDS[column]
        elif frame < 24:
            column, row = frame % 6, 1
            player = cell(hero, column, row, 48, 48)
            hand_x, hand_y = WALK_HANDS[column]
        elif frame < 30 or frame >= 34:
            column, row = (frame - 24) % 6, 2
            player = cell(hero, column, row, 48, 48)
            hand_x, hand_y = CAST_HANDS[column]
        else:
            column, row = frame % 4, 0
            player = cell(hero, column, row, 48, 48)
            hand_x, hand_y = IDLE_HANDS[column]
        facing_left = 18 <= frame < 24
        if facing_left:
            player = hflip(player)
        paste(canvas, shadow, hero_x - 16, hero_y - 20, 130)
        objects.append((hero_y, player, hero_x - 24, hero_y - 45))
        for depth, sprite, x, y in sorted(objects, key=lambda entry: entry[0]):
            paste(canvas, sprite, x, y)
        if facing_left:
            hand_x = 47 - hand_x
        grip_x = 23 if facing_left else 24
        paste(canvas, staff, hero_x - 24 + hand_x - grip_x,
              hero_y - 45 + hand_y - 43, flip=facing_left)
        # Lamp halos: pixel-space radial alpha, ADD blending (Sa, ONE, ADD).
        for lx, ly, radius, strength in [(393, 48, 80, 42), (183, 195, 75, 42),
                                         (hero_x + 2, hero_y - 16, 40, 22)]:
            for y in range(max(0, ly - radius), min(360, ly + radius)):
                for x in range(max(0, lx - radius), min(640, lx + radius)):
                    t = max(0, 1 - math.hypot(x - lx, y - ly) / radius)
                    a = round(t * strength / 17) * 17
                    p = canvas[y * 640 + x]
                    canvas[y * 640 + x] = (min(255, p[0] + a),
                                            min(255, p[1] + a * 2 // 3), p[2], 255)
        for n in range(8):
            angle = n * math.pi / 4
            radius = 56 + (frame * 3) % 42
            px = round(hero_x + math.cos(angle) * radius) - 24
            py = round(hero_y - 12 + math.sin(angle) * radius) - 24
            projectile = rotate(cell(effects, (frame + n) % 4, 0, 32, 32), angle)
            paste(canvas, projectile, px, py,
                  additive=True)
        paste(canvas, cell(effects, 4 + frame % 4, 0, 32, 32), 436, 110, additive=True)
        paste(canvas, cell(effects, frame % 4, 1, 32, 32), 408, 183, additive=True)
        for x, y in [(443, 135), (425, 219), (345, 248)]:
            paste(canvas, cell(effects, 4 + frame % 4, 1, 32, 32), x - 16, y - 32,
                  additive=True)
        for column, (x, y) in enumerate([(248, 107), (442, 98), (406, 193), (501, 148)]):
            paste(canvas, cell(effects, column, 3, 32, 32), x, y - frame % 6)
        if frame == 26:
            screenshot = canvas[:]
        raw = b''.join(b'\0' + bytes(v for p in canvas[y * 640:(y + 1) * 640] for v in p)
                       for y in range(360))
        frames.append(zlib.compress(raw, 6))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    png(OUTPUT / 'art-sample.png', 640, 360, screenshot)
    png(OUTPUT / 'art-sample-2x.png', 1280, 720,
        [screenshot[(y // 2) * 640 + x // 2] for y in range(720) for x in range(1280)])
    apng(OUTPUT / 'art-sample.apng', frames)
    (ASSETS / 'hand-anchors.json').write_text(json.dumps({
        'cell': [48, 48], 'feet': [24, 43], 'staff_grip': [24, 43],
        'idle': IDLE_HANDS, 'walk': WALK_HANDS, 'cast': CAST_HANDS,
        'front_walk': FRONT_HANDS, 'back_walk': BACK_HANDS,
        'left_facing': 'horizontal flip, anchor_x = 47 - anchor_x',
    }, indent=2) + '\n')
    # Eight exact orientation previews; source fireball is the AI effect tile.
    rotation_sheet = [(0, 0, 0, 0)] * (384 * 48)
    for n in range(8):
        rw, rh, pixels = rotate(cell(effects, 2, 0, 32, 32), n * math.pi / 4)
        for y in range(48):
            rotation_sheet[y * 384 + n * 48:y * 384 + (n + 1) * 48] = pixels[y * 48:(y + 1) * 48]
    png(ASSETS / '11-fireball-eight-directions.png', 384, 48, rotation_sheet)
    page()
    print('640x360, 1280x720; APNG 40 frames / 10 fps = 4.0 s; 16 enemies; 14 props')


def embedded(path, width=None):
    data = base64.b64encode(path.read_bytes()).decode()
    style = f'width:{width}px;' if width else ''
    return f'<img style="{style}" src="data:image/png;base64,{data}" alt="{path.name}">'


def page():
    html = ['<!doctype html><html lang="zh"><meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width,initial-scale=1">',
            '<title>余烬群岛 · AI 像素样张</title><style>',
            'body{background:#eef1f5;color:#16263b;font:16px system-ui;margin:0}',
            'main{max-width:1320px;margin:auto;padding:32px}h1{font-size:32px}',
            'p{line-height:1.7}.grid{display:flex;gap:20px;flex-wrap:wrap}',
            'figure{margin:0 0 24px}figcaption{padding:10px 0}',
            'img{image-rendering:pixelated;max-width:100%;height:auto;display:block}',
            '.sheet{background:#c9d3df;padding:16px;border-radius:8px}',
            '.compare figure{width:640px}small{color:#53677d}',
            '</style><main><h1>余烬群岛 · 守火人的海岸</h1>',
            '<p>ART-2 AI 生图与像素规范化样张 · 原创守火人 / 潮啮 / 礁壳蟹<br>',
            '640 × 360 静态美术合成；16 只敌人，14 件摆件。未接入游戏，帧率不代表运行性能。</p>',
            '<figure>', embedded(OUTPUT / 'art-sample.png', 640),
            '<figcaption>原生 640 × 360 · 火球命中、点燃、四档飘字、随身与灯柱光区</figcaption></figure>',
            '<figure>', embedded(OUTPUT / 'art-sample-2x.png', 1280),
            '<figcaption>精确 2 倍 · 每个源像素对应 2 × 2 实心像素</figcaption></figure>',
            '<h2>4 秒动画</h2>', embedded(OUTPUT / 'art-sample.apng', 640),
            '<p>待机 / 移动 / 施法；敌人移动、闪白、死亡；火球、火花、爆炸与点燃。</p>',
            '<h2>升级三选一界面样张</h2>',
            embedded(ASSETS / '10-upgrade-native.png', 1280),
            '<p>余火杖强化 / 炉心 / 三星火；普通为银边，稀有为紫边；原创灯火与黄铜边框。</p>',
            '<h2>原生素材表（1:1）</h2><div class="grid">']
    for name, caption, width in [
        ('04-keeper-animation', '守火人：待机 4 / 移动 6 / 施法 6；48² 单元', 288),
        ('09-directions', '正面向下 / 背面向上：各 6 行走帧；侧面左右翻转', 288),
        ('05-enemies', '潮啮 / 礁壳蟹：各移动 4、闪白 1、死亡 4；64² 单元', 320),
        ('06-terrain', '沙滩 / 湿沙 / 礁石 / 浅水过渡 / 栈桥 / 墙顶 / 立面；各 3 变体', 448),
        ('07-props', '6 种摆件 + 独立法杖；48×64 单元（地影见效果表）', 192),
        ('08-effects', '火球 / 火花 / 小爆炸 / 点燃 / 光晕 / 椭圆影 / 四档数字', 256),
    ]:
        html += ['<figure class="sheet">', embedded(ASSETS / (name + '-native.png'), width),
                 '<figcaption>' + caption + '</figcaption></figure>']
    html += ['</div><h2>八方向火球</h2>',
             embedded(ASSETS / '11-fireball-eight-directions.png', 768),
             '<h2>与参考视频并排</h2><p>参考只用于视觉对照；素材全部原创。</p>',
             '<div class="grid compare"><figure>', embedded(OUTPUT / 'art-sample.png', 640),
             '<figcaption>本样张 · 正常人体比例，鲜艳海岸</figcaption></figure><figure>',
             embedded(__import__('pathlib').Path('/tmp/refcmp/ref_35.png'), 640),
             '<figcaption>参考视频 /tmp/refcmp/ref_35.png（仅内嵌输出页，不入库）</figcaption>',
             '</figure></div><h2>自评与纹理用量</h2><p>',
             '达到：清晰轮廓、角色与敌人脚下影、脸部朝向与眼位、服装细节、敌人剪影区分、',
             '一屏 14 件摆件、明显叠加发光、鲜艳明快、精确 2 倍无模糊。<br>',
             '未达到原清单：每种材质 3 层明暗加高光（皮肤仅 2 层，协调者已接受该例外）；',
             '地面不重复（镜像水面、64 像素方格与地砖接缝仍明显）。',
             '协调者认可本轮方向，以下留待 ART-3：无缝地形与栈桥收口、主角对比和尺度、',
             '光晕色带、步行动作幅度、UI 拆为边框/图标/实时文字、整关纹理分页方案。<br>',
             '样张战斗纹理实测 232 KiB，调色板独立 6 KiB；超 FPGA 192 KiB 40 KiB，',
             'PC 256 KiB 剩余 24 KiB。完整海岸估算约 966 KiB（含 20% 打包开销，不含独立调色板），',
             '未达到任一整关预算。升级整屏位图另需 I8 240 KiB，未与战斗纹理同驻。</p>',
             '<p>完整逐项自评与公式见仓库 docs/report-art-sample.md。',
             '本页图片全部内嵌，无网络字体、外部脚本或素材链接。</p></main></html>']
    (OUTPUT / 'art-sample.html').write_text(''.join(html))


if __name__ == '__main__':
    main()
