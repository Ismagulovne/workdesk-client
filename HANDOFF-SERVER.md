# WorkDesk AI (WorkDesk + Claude Code) — передача на сервер, 25.11.2026

Сессия на ноутбуке: «WorkDesk клиент + Claude Code». Репозиторий `Ismagulovne/workdesk-client`, ветка **`workdesk-ai`** (последний рабочий коммит `feb33f7de` + этот файл). Работа продолжается в серверной сессии на main.worktime.kz (`~/projects/workdesk-client`).

## Что это

WorkDesk AI — отдельная сборка WorkDesk со связкой с Claude Code. Обычный WorkDesk собирается без нее.

- `--mcp` — MCP-сервер по stdio (`src/mcp.rs`): Claude Code подключается через WorkDesk к удаленным устройствам (снимок экрана, мышь, клавиатура, команды). Включается cargo-фичей `ai`.
- Вкладка «Claude» в Android-приложении (`kWorkdeskAi` в `flutter/lib/common/workdesk_edition.dart`). Отдельное приложение `kz.workdesk.ai` «WorkDesk AI».
- Доступ: только вошедшим в учетную запись WorkDesk. С 23.11 **бесплатно** (правило 25), сервер отвечает `GET /api/workdesk-ai/status`. Без входа `--mcp` отказывает до подключения.
- Linux-пакет `workdesk-ai` (Conflicts/Replaces|Obsoletes/Provides `workdesk`): ставится вместо обычного WorkDesk, обновления `workdesk` из репозитория workdesk.kz/repo его не заменяют.

## Как собрать

Workflow `workdesk-build.yml` и `workdesk-build-macos.yml`, вход **`edition: ai`**. Скрипт `.github/workdesk-ai/enable.py` включает фичу `ai`, `kWorkdeskAi`, Android-пакет `kz.workdesk.ai` и Linux-пакет `workdesk-ai`. Все проверки `mcp-*` (e2e на Linux, smoke на Windows и macOS) запускаются только при `edition: ai`.

Подключение к Claude Code (инструкция и в консоли workdesk.kz, блок «WorkDesk AI»):
```
Windows: claude mcp add --scope user workdesk -- "C:\Program Files\WorkDesk\WorkDesk.exe" --mcp
Linux:   claude mcp add --scope user workdesk -- workdesk --mcp
macOS:   claude mcp add --scope user workdesk -- /Applications/RustDesk.app/Contents/MacOS/RustDesk --mcp
```

## Где остановились

1. **25.11 выложено на workdesk.kz** (с «да» владельца). 9 файлов `workdesk-ai-1.5.3-*` в `/opt/workdesk/downloads` на main: MSI; DEB и RPM x86_64 и arm64; DMG Intel и ARM; APK arm64 и armv7. Собраны в runs 45378788302 и 45378793893, коммит `feb33f7de`. Видны только вошедшим. `builds.json` дополнен. Старые `workdesk-mcp-*` лежат в `/opt/workdesk/downloads.bak-ai-20261125-1048`.
2. Все e2e зеленые: основная `--mcp` на Linux; клиент, вошедший в учетную запись; закрытые порты (WebSocket); смена канала на ходу; smoke на Windows и macOS.
3. Найденный 23.11 общий баг «Failed to secure tcp» у вошедших клиентов исправлен главной сессией: hbbs шлет KeyExchange, клиент — `ac34ef461` в main. Ветка `workdesk-ai` содержит main на 24.11 (merge `d4196d70a`).
4. Стресс-тест (щадящий, прод) и краш-тест — результаты в отчете 25.11. Скрипты лежат в `.github/workdesk-ai/tests/`: `ai-stress.mjs`, `relay-stress.mjs`, `ai-crash.mjs`. **`ai-crash.mjs` написан до снятия платности**: проверки `ai_until` и «AI-файл без подписки → 404» нужно обновить под «доступ всем вошедшим».

## Что дальше, по шагам

1. **Сборки на main** (правило 10). Для `workdesk-client` нет self-hosted раннера. Нужно решить, регистрировать ли раннер на main для этого репо, и добавить `runs-on` для Linux и Android. Windows и macOS остаются на GitHub.
2. **Обновления только через магазин** (правило 16) для сборки `kz.workdesk.ai`, которая пойдет в Google Play: заменить `workdesk_update.dart` (проверка через консоль) на Play In-App Updates. Серверную проверку оставить только в сборках с сайта.
3. **Google Play**: карточка `kz.workdesk.ai` по образцу `docs/store-listing/google-play` (клиент `kz.workdesk.app`), AAB (вход `play` в workflow + `edition: ai`), закрытый тест в группе worktime-kz-testers@googlegroups.com. Риск: политика Play к Claude и удаленному управлению — проверить до подачи.
4. **iOS** (правило 14): `workdesk-build-ios.yml` еще не знает `edition: ai` (bundle `kz.workdesk.ai`). Ждет активации Apple Developer, TestFlight «WorkTime testers».
5. **Слить `workdesk-ai` в `main`** вместе с главной сессией «Проект WorkDesk.kz». После слияния обычные сборки WorkDesk выйдут без `--mcp` и без вкладки Claude. Сетевые e2e (blocked/switch) идут только с `edition: ai`.
6. Дизайн (правило 30): WorkDesk AI — та же тема WorkDesk. После перекраски клиентов (`brand-workdesk.mjs`) — проверить и AI-сборку.

## ⚠ Правило №33 (26.11): доступ к WorkDesk AI — только по допуску

Отменяет решение 23.11 «бесплатно всем вошедшим». ИИ-функции — только администраторам и тем, кого владелец допустил лично; остальные пишут на info@worktime.kz с пояснением, действия проходят модерацию. Сейчас (на 25.11) сборки WorkDesk AI, агент и релей Claude открыты **любому вошедшему** — это надо закрыть первым делом:

1. Консоль (`console/src/tenancy.js`, `aiStatus`): `active` только у администраторов (суперадмин и админы компаний — уточнить у владельца) и у пользователей с явным допуском. Нужен флаг допуска (например `users.ai_allowed` + журнал, кто и когда выдал) и управление им у суперадминистратора в консоли. Колонка `companies.ai_until` из прежней подписки есть в базе — решить, использовать или нет.
2. От `aiStatus` уже зависят: список и скачивание файлов `workdesk-ai-*` и `workdesk-claude-*` (`downloads.js`), релей Claude (`claude-relay.js`, отказ 402), `GET /api/workdesk-ai/status` — его проверяет `--mcp` перед каждым подключением (`src/mcp.rs`, `check_ai_subscription`, кэш 10 мин). Менять клиент не обязательно: он показывает `reason` от сервера. Текст отказа сделать понятным: «Доступ к WorkDesk AI выдаёт администратор WorkDesk. Напишите на info@worktime.kz».
3. Блок «WorkDesk AI» в консоли и на сайте: вместо «для вошедших» — «по допуску, запрос на info@worktime.kz».
4. Модерация действий: определить с владельцем, что модерируется (запуск `--mcp`, команды `workdesk_run`, сессии релея) и как (журнал + разбор, или подтверждение до выполнения).
5. Учётка CI `ci-e2e` — выдать ей допуск, иначе e2e WorkDesk AI упадут на отказе.
6. Перед выкладкой — стресс- и краш-тест, отчёт; выкладка консоли — с «да» владельца.

## Ждет решения владельца

- Кто считается «администратором» для правила №33 (только суперадмин или и админы компаний) и как выглядит допуск и модерация.

- «Да» на публикацию в Google Play (и позже App Store).
- Регистрация self-hosted раннера на main для `Ismagulovne/workdesk-client`.
- Удаление на сервере старого бэкапа `/opt/workdesk/downloads.bak-mcp-dmg-20261122-1505` (старые DMG, ~70 МБ). `backup-ai-20261122-1941` (консоль + БД) — точка отката, оставить.
- Слияние `workdesk-ai` в `main`.

## Что нужно

- Репозитории: `Ismagulovne/workdesk-client` (ветки `workdesk-ai`, `main`; временная `e2e-login-check` — можно удалить с «да»), `Ismagulovne/workdesk-claude-agent` (агент, ведет другая сессия).
- Сервер: main.worktime.kz (`/opt/workdesk/downloads`, `/opt/workdesk/console`, `/etc/workdesk/console.env`).
- Секретница (только имена): «workdesk.kz (консоль WorkDesk) / ci-e2e» — служебный пользователь CI, он же в секретах GitHub `WORKDESK_CI_USER` / `WORKDESK_CI_PASSWORD`. Ставить секрет через `gh secret set … --body "$X"` (из канала stdin под Windows записывается пусто).

## Только на ноутбуке

Ничего. Сборки — в GitHub Actions, выкладка — по ssh на main. Локальные копии этой ветки на ноутбуке не нужны.
