#!/usr/bin/env bash
# Скриншоты WorkDesk для Google Play на эмуляторе (вызывается из play-screenshots.yml).
# Демо-компьютер (PEER_ID, PEER_PASS) уже запущен на раннере.
set -x
OUT="$GITHUB_WORKSPACE/shots"
UI="python3 $GITHUB_WORKSPACE/.github/play-screens/ui.py"
mkdir -p "$OUT"
APK=$(ls "$GITHUB_WORKSPACE"/apk/*.apk | head -1)
shot() { sleep "${2:-3}"; adb exec-out screencap -p > "$OUT/$1.png"; $UI dump "$1"; }

# русский интерфейс
adb root || true
sleep 3
adb shell "setprop persist.sys.locale ru-RU; setprop ctl.restart zygote" || true
sleep 20
adb wait-for-device
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 2; done
sleep 5
adb shell settings put system screen_off_timeout 1800000

adb install -r -g "$APK"
adb shell monkey -p kz.workdesk.app -c android.intent.category.LAUNCHER 1
sleep 25
shot 00-start 1
adb logcat -d | grep -iE "FATAL|SIGILL|AndroidRuntime" | tail -20 > "$OUT/logcat-start.txt" || true

# Настройки и окно входа
$UI tap "Настройки|Settings" && shot 02-settings
$UI tap "Войти|Login" && shot 03-login 4
adb shell input keyevent 4
sleep 2

# Подключение к демо-компьютеру
$UI tap "Подключение|Connection|Подключиться|Connect" || true
sleep 2
$UI tap "Удалённый ID|Удаленный ID|Remote ID|ID" || true
adb shell input text "$PEER_ID"
sleep 1
shot 04-id 1
adb shell input keyevent 66
sleep 8
shot 05-password 1
$UI tap "Пароль|Password" || true
adb shell input text "$PEER_PASS"
$UI tap "OK|ОК" || adb shell input keyevent 66
sleep 15
shot 06-session 2
adb shell input tap 540 1200
sleep 3
shot 07-session-tap 1

# Выход из сеанса и главный экран с последним подключением
adb shell input keyevent 4
sleep 2
$UI tap "OK|ОК|Да|Yes" || true
sleep 4
shot 01-home 2
adb logcat -d | grep -iE "FATAL|SIGILL|AndroidRuntime|flutter" | tail -40 > "$OUT/logcat.txt" || true
ls -la "$OUT"
