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
    # Консоль Windows в CI — cp1252: без этого print с русским текстом падает
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8")
        except AttributeError:
            pass
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
    linux_package()
    print(f"{APP}: --mcp (cargo ai), вкладка Claude, Android {ANDROID_ID}, Linux-пакет {PKG}")


PKG = "workdesk-ai"


def linux_package():
    """Linux: свой пакет workdesk-ai вместо workdesk. Файлы, служба и команда те же (/usr/share/workdesk,
    workdesk.service, workdesk), поэтому WorkDesk AI ставится вместо WorkDesk, а обновления обычного пакета
    workdesk из репозитория workdesk.kz/repo его не заменяют."""
    bp = SRC / "build.py"
    sub_once(bp, r'^    content = """Package: workdesk\n',
             f'    content = """Package: {PKG}\nConflicts: workdesk\nReplaces: workdesk\nProvides: workdesk\n',
             f'"""Package: {PKG}\n')
    sub_once(bp, r"^Description: WorkDesk remote desktop", f"Description: {APP} remote desktop", f"Description: {APP} remote desktop")
    sub_once(bp, r"os\.rename\('workdesk\.deb', '\.\./workdesk-%s\.deb' % version\)",
             f"os.rename('workdesk.deb', '../{PKG}-%s.deb' % version)", f"'../{PKG}-%s.deb' % version)")
    for spec in ("rpm-flutter.spec", "rpm-flutter-suse.spec"):
        sub_once(SRC / "res" / spec, r"^Name:       workdesk\n",
                 f"Name:       {PKG}\nConflicts:  workdesk\nObsoletes:  workdesk\nProvides:   workdesk\n", f"Name:       {PKG}\n")


if __name__ == "__main__":
    main()
