#!/usr/bin/env bash
# Краш-тест WorkDesk на эмуляторе (вызывается из play-screenshots.yml после shoot.sh при crash=true).
# Сценарии: пустой ID, неверный пароль, обрыв сети во время сеанса, принудительный перезапуск, повторные нажатия.
# Итог — $OUT/crash-report.txt; код выхода 1, если приложение упало (FATAL/ANR) или не поднялось.
set -x
OUT="$GITHUB_WORKSPACE/shots"
UI="python3 $GITHUB_WORKSPACE/.github/play-screens/ui.py"
PKG=kz.workdesk.app
REPORT="$OUT/crash-report.txt"
shot() { sleep "${2:-2}"; adb exec-out screencap -p > "$OUT/crash-$1.png"; }
alive() { adb shell pidof $PKG >/dev/null 2>&1; }
check() { if alive; then echo "OK   $1" >> "$REPORT"; else echo "FAIL $1 (процесс не запущен)" >> "$REPORT"; fi; }
home() { adb shell am force-stop $PKG; sleep 2; adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 12; }
enter_id() { $UI tap "Удалённый ID|Удаленный ID|Remote ID" || adb shell input tap 400 324; sleep 1; [ -n "$1" ] && adb shell input text "$1"; adb shell input keyevent 4; sleep 1; adb shell input tap 970 324; }
: > "$REPORT"
adb logcat -c

# 1. Пустой ID и повторные нажатия на кнопку подключения
home
enter_id ""
for i in 1 2 3 4 5; do adb shell input tap 970 324; done
shot 01-empty-id 3
check "пустой ID и 5 нажатий подряд"

# 2. Несуществующий ID
home
enter_id "999999999"
shot 02-unknown-id 12
check "несуществующий ID"
adb shell input keyevent 4

# 3. Неверный пароль
home
enter_id "$PEER_ID"
sleep 10
adb shell input text "wrong-password-123"
$UI tap "OK|ОК" || adb shell input keyevent 66
shot 03-wrong-password 8
check "неверный пароль"
adb shell input keyevent 4

# 4. Обрыв сети во время сеанса и восстановление
home
enter_id "$PEER_ID"
sleep 10
adb shell input text "$PEER_PASS"
$UI tap "OK|ОК" || adb shell input keyevent 66
sleep 15
shot 04-session 1
adb shell svc wifi disable; adb shell svc data disable
shot 05-offline 15
check "обрыв сети в сеансе"
adb shell svc wifi enable; adb shell svc data enable
shot 06-online 20
check "сеть вернулась"

# 5. Принудительная остановка и холодный запуск, поворот экрана
home
check "холодный запуск после force-stop"
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1; sleep 3
adb shell settings put system user_rotation 0; sleep 3
shot 07-rotated 1
check "поворот экрана"

adb logcat -d > "$OUT/crash-logcat.txt"
if grep -E "FATAL EXCEPTION|ANR in $PKG|Fatal signal .*$PKG|>>> $PKG <<<" "$OUT/crash-logcat.txt" > "$OUT/crash-fatal.txt"; then
  echo "FAIL в журнале есть падение или ANR (crash-fatal.txt)" >> "$REPORT"
fi
cat "$REPORT"
! grep -q '^FAIL' "$REPORT"
