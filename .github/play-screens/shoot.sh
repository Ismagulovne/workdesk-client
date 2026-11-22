#!/usr/bin/env bash
# Скриншоты WorkDesk для Google Play на эмуляторе (вызывается из play-screenshots.yml).
# Режим probe: установить, запустить, снять главный экран и разметку интерфейса.
set -x
OUT="$GITHUB_WORKSPACE/shots"
mkdir -p "$OUT"
APK=$(ls "$GITHUB_WORKSPACE"/apk/*.apk | head -1)

shot() { adb exec-out screencap -p > "$OUT/$1.png"; adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1 || true; }

# русский интерфейс
adb root || true
sleep 3
adb shell "setprop persist.sys.locale ru-RU; setprop ctl.restart zygote" || true
sleep 20
adb wait-for-device
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 2; done
sleep 5
adb shell getprop persist.sys.locale

adb install -r -g "$APK"
adb shell monkey -p kz.workdesk.app -c android.intent.category.LAUNCHER 1
sleep 25
shot 01-home
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" || true
adb logcat -d | grep -iE "flutter|workdesk|FATAL|AndroidRuntime" | tail -40 > "$OUT/logcat.txt" || true
ls -la "$OUT"
