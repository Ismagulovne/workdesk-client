"""Нажатия в приложении на эмуляторе по тексту из разметки интерфейса (uiautomator).
python3 ui.py tap "Настройки|Settings"   — нажать на первый найденный текст (через | варианты)
python3 ui.py has "Пароль|Password"      — код возврата 0, если текст есть на экране
python3 ui.py dump имя                   — сохранить разметку в shots/имя.xml"""
import os
import re
import subprocess
import sys
import time

OUT = os.path.join(os.environ.get("GITHUB_WORKSPACE", "."), "shots")


def adb(*args):
    return subprocess.run(["adb", *args], capture_output=True, text=True)


def dump(name="ui"):
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        r = adb("exec-out", "cat", "/sdcard/ui.xml")
        if "<hierarchy" in r.stdout:
            os.makedirs(OUT, exist_ok=True)
            with open(os.path.join(OUT, f"{name}.xml"), "w", encoding="utf-8") as f:
                f.write(r.stdout)
            return r.stdout
        time.sleep(1)
    return ""


def nodes(xml):
    for m in re.finditer(r"<node [^>]*>", xml):
        n = m.group(0)
        text = re.search(r' text="([^"]*)"', n).group(1)
        desc = re.search(r' content-desc="([^"]*)"', n).group(1)
        b = re.search(r' bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        yield (text + " " + desc).strip(), tuple(map(int, b.groups()))


def find(variants, xml):
    for v in variants.split("|"):
        for label, (x0, y0, x1, y1) in nodes(xml):
            if v and v.lower() in label.lower() and x1 > x0 and y1 > y0:
                return label, ((x0 + x1) // 2, (y0 + y1) // 2)
    return None, None


if __name__ == "__main__":
    cmd, arg = sys.argv[1], sys.argv[2]
    if cmd == "dump":
        dump(arg)
        sys.exit(0)
    for attempt in range(6):
        xml = dump("last")
        label, pos = find(arg, xml)
        if pos:
            if cmd == "tap":
                adb("shell", "input", "tap", str(pos[0]), str(pos[1]))
                print(f"tap {label!r} at {pos}")
            else:
                print(f"has {label!r}")
            sys.exit(0)
        time.sleep(2)
    print(f"not found: {arg}")
    sys.exit(1)
