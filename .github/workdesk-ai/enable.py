"""Сборка WorkDesk AI: включает связку с Claude Code в исходниках перед сборкой (вход edition: ai в CI).

python3 .github/workdesk-ai/enable.py

- cargo-фича ai по умолчанию: режим --mcp на компьютере (проверяет подписку WorkDesk AI на сервере);
- kWorkdeskAi = true во Flutter: вкладка «Claude» на телефоне, проверка обновлений из файлов WorkDesk AI;
- Android: отдельное приложение kz.workdesk.ai с названием «WorkDesk AI» (ставится рядом с обычным WorkDesk).

Обычный WorkDesk собирается без этого скрипта: без --mcp и без вкладки «Claude».
Повторный запуск ничего не портит.
"""
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[2]
APP = "WorkDesk AI"
ANDROID_ID = "kz.workdesk.ai"


def sub_once(path: Path, pattern: str, repl: str, done: str):
    t = path.read_text(encoding="utf-8")
    if done in t:
        return
    t2, n = re.subn(pattern, repl, t, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path.relative_to(SRC)}: не найдено {pattern!r}")
    path.write_text(t2, encoding="utf-8", newline="\n")


def main():
    sub_once(SRC / "Cargo.toml", r'^default = \["use_dasp"\]$', 'default = ["use_dasp", "ai"]', 'default = ["use_dasp", "ai"]')
    sub_once(SRC / "flutter/lib/common/workdesk_edition.dart", r"^const bool kWorkdeskAi = false;$",
             "const bool kWorkdeskAi = true;", "const bool kWorkdeskAi = true;")
    a = SRC / "flutter/android/app"
    sub_once(a / "build.gradle", r'applicationId "kz\.workdesk\.app"', f'applicationId "{ANDROID_ID}"', f'applicationId "{ANDROID_ID}"')
    sub_once(a / "src/main/AndroidManifest.xml", r'android:label="WorkDesk"', f'android:label="{APP}"', f'android:label="{APP}"')
    for strings in (a / "src/main/res").glob("values*/strings.xml"):
        t = strings.read_text(encoding="utf-8")
        t2 = re.sub(r'(<string name="app_name">)WorkDesk(</string>)', rf"\g<1>{APP}\g<2>", t)
        if t2 != t:
            strings.write_text(t2, encoding="utf-8", newline="\n")
    print(f"{APP}: --mcp (cargo ai), вкладка Claude, Android {ANDROID_ID}")


if __name__ == "__main__":
    main()
