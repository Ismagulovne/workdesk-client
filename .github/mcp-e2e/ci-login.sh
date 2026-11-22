#!/usr/bin/env bash
# Вход программы WorkDesk AI в служебную учетную запись CI: компания «CI e2e» с подпиской WorkDesk AI.
# Секреты WORKDESK_CI_USER / WORKDESK_CI_PASSWORD. Свежий токен (живет 30 дней) пишется в локальные настройки
# программы этого пользователя — так же, как его сохраняет вход в окне программы (LocalConfig, access_token).
set -euo pipefail
: "${WORKDESK_CI_USER:?нет секрета WORKDESK_CI_USER}"
: "${WORKDESK_CI_PASSWORD:?нет секрета WORKDESK_CI_PASSWORD}"
API="${WORKDESK_API:-https://workdesk.kz}"
APP="${WORKDESK_APP:-WorkDesk}"
# Одно устройство на задачу CI: повторный вход заменяет прошлый токен, а не копит новые
UUID="ci-e2e-${GITHUB_JOB:-local}"
BODY=$(UUID="$UUID" python3 -c 'import json,os; print(json.dumps({"username": os.environ["WORKDESK_CI_USER"], "password": os.environ["WORKDESK_CI_PASSWORD"], "id": "", "uuid": os.environ["UUID"], "autoLogin": True, "type": "account"}))')
TOKEN=$(curl -fsS -H 'Content-Type: application/json' --data-binary "$BODY" "$API/api/login" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
echo "::add-mask::$TOKEN"
# Папка настроек на Linux — ~/.config/<имя программы строчными> (directories-next), файл <Имя>_local.toml.
# Клиент получает свой HOME (MCP_HOME): служба WorkDesk от root хранит настройки в домашней папке пользователя
# (~/.config/workdesk), и клиент с тем же каталогом подключался бы к хосту с его же ID и ключами.
H="${MCP_HOME:-$HOME}"
DIR="$H/.config/${APP,,}"
mkdir -p "$DIR"
printf '[options]\naccess_token = "%s"\n' "$TOKEN" > "$DIR/${APP}_local.toml"
STATUS=$(curl -fsS -H "Authorization: Bearer $TOKEN" "$API/api/workdesk-ai/status")
echo "Подписка WorkDesk AI: $STATUS"
echo "$STATUS" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("active") else "подписка WorkDesk AI у учетной записи CI не активна")'
