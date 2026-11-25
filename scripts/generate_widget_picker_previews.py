#!/usr/bin/env python3
"""Generate localized Android launcher fallback previews (requires Pillow).

Run: python3 scripts/generate_widget_picker_previews.py
Check without writing: python3 scripts/generate_widget_picker_previews.py --check
These are example-data illustrations, not native launcher screenshots.
"""

import argparse
import calendar
import hashlib
import io
import itertools
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
MANIFEST = ROOT / "scripts/widget_picker_preview_manifest.json"
SCALE = 2
SIZE = (720, 480)
FONT_PATHS = {
    "latin": ROOT / "assets/fonts/DejaVuSans.ttf",
    "cjk": ROOT / "assets/fonts/DroidSansFallbackFull.ttf",
}
# Each row is a literal example title and supporting detail, never account data.
EXAMPLES = {
    "widget_preview": {
        "zh": ("今日概览", [("整理今日计划", "待办 · 09:00"), ("阅读 20 分钟", "习惯 · 今日待打卡"), ("项目讨论", "日历 · 14:00")]),
        "en": ("Today", [("Plan the day", "Todo · 09:00"), ("Read for 20 minutes", "Habit · Check in today"), ("Project discussion", "Calendar · 14:00")]),
    },
    "widget_todo_preview": {
        "zh": ("今日待办", [("整理今日计划", "09:00 · 重要"), ("写周报", "14:00 · 工作"), ("准备明日事项", "18:00 · 个人")]),
        "en": ("Today's todos", [("Plan the day", "09:00 · Important"), ("Write the weekly report", "14:00 · Work"), ("Prepare for tomorrow", "18:00 · Personal")]),
    },
    "widget_focus_habit_preview": {
        "zh": ("专注与习惯", [("阅读 20 分钟", "今日习惯 · 尚未打卡"), ("本周打卡", "已完成 5 / 7 天")]),
        "en": ("Focus & habits", [("Read for 20 minutes", "Today's habit · Not checked in"), ("This week's check-ins", "5 of 7 days completed")]),
    },
    "widget_habit_preview": {
        "zh": ("今日习惯", [("阅读 20 分钟", "本周 5 / 7 天"), ("喝水", "今日 3 / 8 杯"), ("散步", "连续坚持 6 天")]),
        "en": ("Today's habits", [("Read for 20 minutes", "5 of 7 days this week"), ("Drink water", "3 of 8 glasses today"), ("Take a walk", "6-day streak")]),
    },
    "widget_calendar_preview": {
        "zh": ("2026 年 10 月", []),
        "en": ("October 2026", []),
    },
    "widget_schedule_preview": {
        "zh": ("今日日程", [("09:00  整理计划", "待办 · 30 分钟"), ("14:00  项目讨论", "日历 · 会议"), ("19:00  阅读", "习惯 · 20 分钟")]),
        "en": ("Today's schedule", [("09:00  Plan the day", "Todo · 30 minutes"), ("14:00  Project discussion", "Calendar · Meeting"), ("19:00  Read", "Habit · 20 minutes")]),
    },
    "widget_goal_preview": {
        "zh": ("目标进度", [("本月读完一本书", "已完成 60%"), ("每周运动三次", "已完成 2 / 3 次"), ("整理个人项目", "下一步 · 完成第一章")]),
        "en": ("Goal progress", [("Finish a book this month", "60% completed"), ("Exercise three times a week", "2 of 3 sessions completed"), ("Organize a personal project", "Next · Finish chapter one")]),
    },
    "widget_course_preview": {
        "zh": ("今日课程", [("09:00  数学", "教室 201 · 第一节"), ("11:00  英语", "教室 302 · 第二节"), ("14:00  项目实践", "实验室 · 第三节")]),
        "en": ("Today's classes", [("09:00  Mathematics", "Room 201 · Period 1"), ("11:00  English", "Room 302 · Period 2"), ("14:00  Project workshop", "Lab · Period 3")]),
    },
    "widget_note_preview": {
        "zh": ("最近笔记", [("周末计划", "散步、阅读，留一点休息时间"), ("项目灵感", "把大目标拆成小步骤"), ("阅读摘记", "记录今天的新发现")]),
        "en": ("Recent notes", [("Weekend plans", "Walk, read and leave time to rest"), ("Project ideas", "Break big goals into small steps"), ("Reading notes", "Keep today's discoveries")]),
    },
    "widget_anniversary_preview": {
        "zh": ("纪念日", [("阅读计划", "还有 7 天 · 10 月 20 日"), ("项目里程碑", "还有 18 天 · 10 月 31 日"), ("开始记录", "已经 30 天")]),
        "en": ("Anniversaries", [("Reading plan", "7 days to go · Oct 20"), ("Project milestone", "18 days to go · Oct 31"), ("Started journaling", "30 days ago")]),
    },
    "widget_diary_preview": {
        "zh": ("今日日记", [("今天心情不错", "记录一件让自己开心的小事"), ("完成了一项计划", "给今天的努力留个纪念"), ("期待明天", "慢一点，也在向前走")]),
        "en": ("Today's journal", [("Feeling good today", "Remember one small happy moment"), ("Finished a planned task", "Keep a note of today's effort"), ("Looking ahead", "Small steps still move us forward")]),
    },
}


def palette():
    entries = json.loads((RES / "raw/widget_surface_palettes.json").read_text())
    entry = next(item for item in entries if item["key"] == "defaultBrand|plain_card")
    return {key.removeprefix("widget_theme_"): value for key, value in entry["palette"].items()}


def rgb(argb):
    return "#" + argb[-6:]


def render(kind, locale, colors):
    image = Image.new("RGBA", (SIZE[0] * SCALE, SIZE[1] * SCALE))
    draw = ImageDraw.Draw(image)
    primary = rgb(colors["primary"])
    text_color = rgb(colors["text"])
    background = rgb(colors["background"])
    surface = rgb(colors["surface"])
    muted = rgb(colors["muted_text"])
    fonts = {}

    def rounded(box, radius, fill, outline=None):
        draw.rounded_rectangle(tuple(int(v * SCALE) for v in box), radius * SCALE, fill=fill, outline=outline, width=SCALE)

    def text(value, x, y, size=25, color=text_color, max_width=620):
        # DroidSansFallback supplies CJK glyphs only. Keep Latin/digits in their
        # own runs and align both fonts on one baseline to avoid missing glyphs.
        runs = []
        for family, chars in itertools.groupby(value, lambda char: "latin" if ord(char) < 0x3000 else "cjk"):
            key = (family, size)
            if key not in fonts:
                fonts[key] = ImageFont.truetype(str(FONT_PATHS[family]), size * SCALE)
            runs.append(("".join(chars), fonts[key]))
        width = sum(draw.textlength(run, font=font) for run, font in runs) / SCALE
        if width > max_width:
            raise ValueError(f"{kind}/{locale}: text exceeds {max_width}px: {value}")
        top = min(draw.textbbox((0, 0), run, font=font, anchor="ls")[1] for run, font in runs)
        cursor = x * SCALE
        for run, font in runs:
            draw.text((cursor, y * SCALE - top), run, font=font, fill=color, anchor="ls")
            cursor += draw.textlength(run, font=font)

    rounded((12, 12, 708, 468), 32, background)
    title, rows = EXAMPLES[kind][locale]
    text(title, 40, 40, size=32, color=primary, max_width=635)
    text("示例数据" if locale == "zh" else "Example data", 40, 89, size=19, color=muted)

    if kind == "widget_calendar_preview":
        weekdays = ["一", "二", "三", "四", "五", "六", "日"] if locale == "zh" else ["M", "T", "W", "T", "F", "S", "S"]
        for col, day in enumerate(weekdays):
            text(day, 67 + col * 90, 128, size=20, color=muted)
        for row, week in enumerate(calendar.Calendar(firstweekday=0).monthdayscalendar(2026, 10)):
            for col, day in enumerate(week):
                if day == 0:
                    continue
                x, y = 61 + col * 90, 168 + row * 48
                if day == 13:
                    rounded((x - 12, y - 8, x + 48, y + 32), 14, primary)
                text(str(day), x, y, size=23, color="#FFFFFF" if day == 13 else text_color)
                if day in (16, 20, 29):
                    draw.ellipse(((x + 13) * SCALE, (y + 33) * SCALE, (x + 19) * SCALE, (y + 39) * SCALE), fill=primary)
    else:
        start_y = 136
        if kind == "widget_focus_habit_preview":
            rounded((32, 129, 688, 222), 20, surface)
            text("25:00", 54, 147, size=46, color=primary)
            text("专注计划" if locale == "zh" else "Focus plan", 310, 160, size=25)
            start_y = 244
        for index, (label, detail) in enumerate(rows):
            y = start_y + index * 92
            rounded((32, y - 8, 688, y + 72), 20, surface)
            draw.ellipse((51 * SCALE, (y + 11) * SCALE, 69 * SCALE, (y + 29) * SCALE), outline=primary, width=2 * SCALE)
            text(label, 88, y + 5, size=25, max_width=574)
            text(detail, 88, y + 41, size=20, color=muted, max_width=574)

    text("多仪" if locale == "zh" else "Duoyi", 40, 439, size=18, color=muted)
    text("桌面小组件" if locale == "zh" else "Home widget", 545 if locale == "zh" else 529, 439, size=18, color=muted, max_width=150)
    output = io.BytesIO()
    image.resize(SIZE, Image.Resampling.LANCZOS).save(output, format="PNG", optimize=True)
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    colors = palette()
    assets = []
    mismatches = []
    for locale, folder in (("zh", "drawable-nodpi"), ("en", "drawable-en-nodpi")):
        for kind in EXAMPLES:
            target = RES / folder / f"{kind}.png"
            payload = render(kind, locale, colors)
            assets.append({"resource": kind, "locale": locale, "path": str(target.relative_to(ROOT)), "sha256": hashlib.sha256(payload).hexdigest(), "title": EXAMPLES[kind][locale][0], "rows": EXAMPLES[kind][locale][1]})
            if args.check:
                if not target.exists() or target.read_bytes() != payload:
                    mismatches.append(str(target.relative_to(ROOT)))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
    manifest = {"size": list(SIZE), "kind": "example-data illustration", "palette": "defaultBrand|plain_card", "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "palette_sha256": hashlib.sha256((RES / "raw/widget_surface_palettes.json").read_bytes()).hexdigest(), "fonts": {key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in FONT_PATHS.items()}, "assets": assets}
    serialized = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not MANIFEST.exists() or MANIFEST.read_text() != serialized:
            mismatches.append(str(MANIFEST.relative_to(ROOT)))
        if mismatches:
            raise SystemExit("Outdated previews: " + ", ".join(mismatches))
        print(f"Verified {len(assets)} localized fallback previews.")
    else:
        MANIFEST.write_text(serialized)
        print(f"Generated {len(assets)} localized fallback previews.")


if __name__ == "__main__":
    main()
