"""Generate HarmonyPyIDE app icons (layered icon layers + start icon).

Reproducible: run with the bundled Python (Pillow required).
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA_DIRS = [
    os.path.join(ROOT, "AppScope", "resources", "base", "media"),
    os.path.join(ROOT, "entry", "src", "main", "resources", "base", "media"),
]
SIZE = 1024
BG_TOP = (35, 39, 48)
BG_BOTTOM = (24, 26, 32)
BLUE = (55, 118, 171)
BLUE_DARK = (41, 92, 135)
YELLOW = (255, 212, 59)
YELLOW_DARK = (222, 176, 32)
WHITE = (240, 244, 250)


def background():
    """纯渐变背景层。

    刻意不放任何装饰：背景层与前景层在系统里是分开绘制的，背景上的任何图案
    都会出现在 logo 之后，看起来像脏点。
    """
    img = Image.new("RGB", (SIZE, SIZE), BG_TOP)
    d = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (SIZE, y)], fill=color)
    # 中心一圈极弱的径向高光，让图标在浅色壁纸上也立得住
    glow = Image.new("L", (SIZE, SIZE), 0)
    gd = ImageDraw.Draw(glow)
    for r in range(SIZE // 2, 0, -8):
        alpha = int(14 * (1 - r / (SIZE // 2)))
        gd.ellipse([SIZE // 2 - r, SIZE // 2 - r, SIZE // 2 + r, SIZE // 2 + r], fill=alpha)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), (58, 64, 78)), img, glow)
    return img


def foreground():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 双蛇造型的几何简化：左上蓝色块 + 右下黄色块，中间留出呼吸间隙
    d.rounded_rectangle([300, 210, 640, 560], radius=90, fill=BLUE)
    d.rounded_rectangle([540, 400, 720, 520], radius=60, fill=BLUE_DARK)
    d.rounded_rectangle([384, 464, 724, 814], radius=90, fill=YELLOW)
    d.rounded_rectangle([304, 504, 484, 624], radius=60, fill=YELLOW_DARK)
    # 两个"眼睛"，让图标更像 Python
    d.ellipse([430, 292, 490, 352], fill=WHITE)
    d.ellipse([534, 672, 594, 732], fill=(35, 39, 48))
    # IDE 感：底部一条蓝色光标条
    d.rounded_rectangle([300, 860, 560, 900], radius=20, fill=(53, 116, 240))
    return img


def start_icon():
    img = background().convert("RGBA")
    fg = foreground()
    # 启动图标里前景需要缩小到安全区
    scale = 0.62
    small = fg.resize((int(SIZE * scale), int(SIZE * scale)), Image.LANCZOS)
    off = (SIZE - small.width) // 2
    img.alpha_composite(small, (off, off))
    return img.convert("RGB")


def main():
    bg = background()
    fg = foreground()
    start = start_icon()
    layered = (
        '{\n  "layered-image":\n  {\n'
        '    "background" : "$media:background",\n'
        '    "foreground" : "$media:foreground"\n'
        '  }\n}\n'
    )
    for media in MEDIA_DIRS:
        os.makedirs(media, exist_ok=True)
        bg.save(os.path.join(media, "background.png"))
        fg.save(os.path.join(media, "foreground.png"))
        start.save(os.path.join(media, "startIcon.png"))
        start.resize((512, 512), Image.LANCZOS).save(os.path.join(media, "app_icon.png"))
        with open(os.path.join(media, "layered_image.json"), "w", encoding="utf-8") as fp:
            fp.write(layered)
        print("written:", media)


if __name__ == "__main__":
    main()
