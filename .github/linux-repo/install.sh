#!/bin/sh
# Установка WorkDesk из подписанного репозитория (Ubuntu, Debian, Astra, Fedora, RHEL, РЕД ОС, ALT, openSUSE):
#   curl -fsSL https://workdesk.kz/repo/install.sh | sudo sh
# Подключает репозиторий и ключ подписи, затем ставит программу. Обновления приходят обычным обновлением системы.
set -e
BASE="${WORKDESK_REPO:-https://workdesk.kz/repo}"
KEY_FPR="BE9982B6842CD612148B54AA0DDC8DF694C15AB9"

if [ "$(id -u)" != 0 ]; then
  echo "Нужны права администратора: curl -fsSL $BASE/install.sh | sudo sh" >&2
  exit 1
fi
fetch() { if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"; else wget -qO- "$1"; fi; }

if command -v apt-get >/dev/null 2>&1; then
  install -d -m 755 /etc/apt/keyrings
  if command -v gpg >/dev/null 2>&1; then
    fetch "$BASE/workdesk.asc" | gpg --dearmor --yes -o /etc/apt/keyrings/workdesk.gpg
    KEYRING=/etc/apt/keyrings/workdesk.gpg
  else
    fetch "$BASE/workdesk.asc" > /etc/apt/keyrings/workdesk.asc
    KEYRING=/etc/apt/keyrings/workdesk.asc
  fi
  echo "deb [signed-by=$KEYRING] $BASE/deb ./" > /etc/apt/sources.list.d/workdesk.list
  apt-get update
  apt-get install -y workdesk
elif command -v zypper >/dev/null 2>&1; then
  fetch "$BASE/workdesk.asc" > /tmp/workdesk.asc && rpm --import /tmp/workdesk.asc && rm -f /tmp/workdesk.asc
  zypper --non-interactive removerepo workdesk >/dev/null 2>&1 || true
  zypper --non-interactive addrepo --refresh "$BASE/suse" workdesk
  zypper --non-interactive --gpg-auto-import-keys refresh workdesk
  zypper --non-interactive install workdesk
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
  fetch "$BASE/workdesk.asc" > /tmp/workdesk.asc && rpm --import /tmp/workdesk.asc && rm -f /tmp/workdesk.asc
  cat > /etc/yum.repos.d/workdesk.repo <<EOF
[workdesk]
name=WorkDesk
baseurl=$BASE/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE/workdesk.asc
EOF
  if command -v dnf >/dev/null 2>&1; then dnf install -y workdesk; else yum install -y workdesk; fi
else
  echo "Не нашла apt, dnf, yum или zypper. Скачайте пакет вручную: https://workdesk.kz/download" >&2
  exit 1
fi
echo "WorkDesk установлен. Ключ подписи репозитория: $KEY_FPR"
