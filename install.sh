#!/usr/bin/env bash
set -euo pipefail

# vexpax2 bootstrap. This installer is independent of the existing vexpax panel.
if [[ $EUID -ne 0 ]]; then
  echo 'Запустите команду с sudo.' >&2
  exit 1
fi
if [[ ! -f /etc/os-release ]]; then
  echo 'Нужен Ubuntu/Debian с systemd.' >&2
  exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != ubuntu && "${ID:-}" != debian ]]; then
  echo 'Пока поддерживаются только Ubuntu и Debian.' >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo 'На сервере необходим systemd.' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends php-cli stunnel4 openssl ca-certificates curl acl

home_dir="$(pwd -P)/vexpax2"
if [[ "$home_dir" == *$'\n'* ]]; then
  echo 'Путь установки не должен содержать перенос строки.' >&2
  exit 1
fi
if [[ -f /etc/systemd/system/vexpax2-php.service ]] &&
   ! grep -Fq -- "$home_dir" /etc/systemd/system/vexpax2-php.service; then
  echo 'vexpax2 уже установлен в другом каталоге. Используйте прежнюю папку.' >&2
  exit 1
fi
umask 077

if ! id -u vexpax2 >/dev/null 2>&1; then
  useradd --system --home-dir /opt/vexpax2-worker --shell /usr/sbin/nologin vexpax2
fi
parent_dir=$(dirname "$home_dir")
while [[ "$parent_dir" != / ]]; do
  setfacl -m u:vexpax2:x "$parent_dir"
  parent_dir=$(dirname "$parent_dir")
done
install -d -m 0700 -o vexpax2 -g vexpax2 "$home_dir"
install -d -m 0700 -o vexpax2 -g vexpax2 "$home_dir/configuration" "$home_dir/plugins"
install -d -m 0755 -o vexpax2 -g vexpax2 "$home_dir/public"

if [[ ! -s "$home_dir/configuration/token" ]]; then
  openssl rand -hex 32 > "$home_dir/configuration/token"
fi
chmod 0600 "$home_dir/configuration/token"
chown vexpax2:vexpax2 "$home_dir/configuration/token"

if [[ ! -s "$home_dir/configuration/server.pem" ]]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
    -subj '/CN=vexpax2-worker' \
    -keyout "$home_dir/configuration/server.key" \
    -out "$home_dir/configuration/server.crt" >/dev/null 2>&1
  cat "$home_dir/configuration/server.key" "$home_dir/configuration/server.crt" \
    > "$home_dir/configuration/server.pem"
fi
chmod 0600 "$home_dir/configuration/server.key" "$home_dir/configuration/server.pem"
chown vexpax2:vexpax2 "$home_dir/configuration/server.key" "$home_dir/configuration/server.crt" "$home_dir/configuration/server.pem"

printf '%s' 'PD9waHAKZGVjbGFyZShzdHJpY3RfdHlwZXM9MSk7CgpoZWFkZXIoJ0NvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOCcpOwpoZWFkZXIoJ0NhY2hlLUNvbnRyb2w6IG5vLXN0b3JlJyk7CmhlYWRlcignWC1Db250ZW50LVR5cGUtT3B0aW9uczogbm9zbmlmZicpOwoKJHBhdGggPSBwYXJzZV91cmwoJF9TRVJWRVJbJ1JFUVVFU1RfVVJJJ10gPz8gJy8nLCBQSFBfVVJMX1BBVEgpOwppZiAoJHBhdGggIT09ICcvcGluZycgfHwgKCRfU0VSVkVSWydSRVFVRVNUX01FVEhPRCddID8/ICcnKSAhPT0gJ0dFVCcpIHsKICAgIGh0dHBfcmVzcG9uc2VfY29kZSg0MDQpOwogICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAnbm90X2ZvdW5kJ10pOwogICAgZXhpdDsKfQoKJGV4cGVjdGVkID0gdHJpbSgoc3RyaW5nKSBAZmlsZV9nZXRfY29udGVudHMoZGlybmFtZShfX0RJUl9fKSAuICcvY29uZmlndXJhdGlvbi90b2tlbicpKTsKJGF1dGhvcml6YXRpb24gPSAoc3RyaW5nKSAoJF9TRVJWRVJbJ0hUVFBfQVVUSE9SSVpBVElPTiddID8/ICcnKTsKJHByb3ZpZGVkID0gc3RybmNtcCgkYXV0aG9yaXphdGlvbiwgJ0JlYXJlciAnLCA3KSA9PT0gMAogICAgPyBzdWJzdHIoJGF1dGhvcml6YXRpb24sIDcpCiAgICA6ICcnOwppZiAoJGV4cGVjdGVkID09PSAnJyB8fCAhaGFzaF9lcXVhbHMoJGV4cGVjdGVkLCAkcHJvdmlkZWQpKSB7CiAgICBodHRwX3Jlc3BvbnNlX2NvZGUoNDAxKTsKICAgIGVjaG8ganNvbl9lbmNvZGUoWydlcnJvcicgPT4gJ3VuYXV0aG9yaXplZCddKTsKICAgIGV4aXQ7Cn0KCmVjaG8ganNvbl9lbmNvZGUoWwogICAgJ29rJyA9PiB0cnVlLAogICAgJ3NlcnZpY2UnID0+ICd2ZXhwYXgyLXdvcmtlcicsCiAgICAndmVyc2lvbicgPT4gMSwKICAgICdzZXJ2ZXJfdGltZScgPT4gZ21kYXRlKCdjJyksCl0sIEpTT05fVU5FU0NBUEVEX1NMQVNIRVMpOwo=' | base64 -d > "$home_dir/public/index.php"
chmod 0644 "$home_dir/public/index.php"
chown vexpax2:vexpax2 "$home_dir/public/index.php"

cat > "$home_dir/configuration/stunnel.conf" <<EOF
foreground = yes
client = no
cert = $home_dir/configuration/server.pem
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[worker]
accept = 0.0.0.0:18443
connect = 127.0.0.1:18787
EOF
chmod 0644 "$home_dir/configuration/stunnel.conf"
chown vexpax2:vexpax2 "$home_dir/configuration/stunnel.conf"

cat > /etc/systemd/system/vexpax2-php.service <<EOF
[Unit]
Description=vexpax2 private PHP worker
After=network.target

[Service]
Type=simple
User=vexpax2
Group=vexpax2
WorkingDirectory=$home_dir
ExecStart=/usr/bin/php -S 127.0.0.1:18787 -t "$home_dir/public" "$home_dir/public/index.php"
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadOnlyPaths=$home_dir

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vexpax2-tls.service <<EOF
[Unit]
Description=vexpax2 pinned TLS endpoint
After=network.target vexpax2-php.service
Requires=vexpax2-php.service

[Service]
Type=simple
User=vexpax2
Group=vexpax2
ExecStart=/usr/bin/stunnel4 "$home_dir/configuration/stunnel.conf"
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadOnlyPaths=$home_dir

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vexpax2-php.service vexpax2-tls.service >/dev/null
systemctl restart vexpax2-php.service vexpax2-tls.service

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow 18443/tcp comment 'vexpax2 worker' >/dev/null
fi

token=$(cat "$home_dir/configuration/token")
fingerprint=$(openssl x509 -in "$home_dir/configuration/server.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
if [[ -s "$home_dir/configuration/host" ]]; then
  host=$(cat "$home_dir/configuration/host")
else
  host=${VEXPAX2_HOST:-$(curl -fsS4 --max-time 8 https://api.ipify.org || true)}
  if [[ -n "$host" ]]; then
    printf '%s' "$host" > "$home_dir/configuration/host"
  fi
fi
if [[ -z "$host" ]]; then
  echo 'Не удалось определить публичный IP. Повторите с VEXPAX2_HOST=ваш_ip.' >&2
  exit 1
fi
if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo 'VEXPAX2_HOST должен быть IP-адресом или именем хоста.' >&2
  exit 1
fi
for attempt in 1 2 3 4 5; do
  if curl -ksSf --max-time 2 -H "Authorization: Bearer $token" \
    https://127.0.0.1:18443/ping | grep -q '"ok":true'; then
    break
  fi
  if [[ $attempt -eq 5 ]]; then
    echo 'Воркер не ответил: проверьте systemctl status vexpax2-php vexpax2-tls.' >&2
    exit 1
  fi
  sleep 1
done

key="vexpax2:v1:${host}:18443:${token}:${fingerprint}"
printf '%s\n' "$key" > "$home_dir/configuration/connection.key"
chmod 0600 "$home_dir/configuration/host" "$home_dir/configuration/connection.key"
chown vexpax2:vexpax2 "$home_dir/configuration/host" "$home_dir/configuration/connection.key"

cat > "$home_dir/manage.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
home_dir='$home_dir'
case "\${1:-}" in
  start) systemctl start vexpax2-php.service vexpax2-tls.service ;;
  stop) systemctl stop vexpax2-tls.service vexpax2-php.service ;;
  restart) systemctl restart vexpax2-php.service vexpax2-tls.service ;;
  status) systemctl --no-pager status vexpax2-php.service vexpax2-tls.service ;;
  key) cat "\$home_dir/configuration/connection.key" ;;
  uninstall)
    case "\$home_dir" in /*/vexpax2) ;; *) echo 'Небезопасный путь удаления.' >&2; exit 1 ;; esac
    systemctl disable --now vexpax2-tls.service vexpax2-php.service >/dev/null || true
    rm -f /etc/systemd/system/vexpax2-php.service /etc/systemd/system/vexpax2-tls.service
    systemctl daemon-reload
    rm -rf -- "\$home_dir"
    parent_dir=\$(dirname "\$home_dir")
    while [[ "\$parent_dir" != / ]]; do
      setfacl -x u:vexpax2 "\$parent_dir" 2>/dev/null || true
      parent_dir=\$(dirname "\$parent_dir")
    done
    echo 'vexpax2 удалён. Системные пакеты PHP/stunnel оставлены для других программ.' ;;
  *) echo 'Использование: sudo ./vexpax2/manage.sh {start|stop|restart|status|key|uninstall}' >&2; exit 2 ;;
esac
EOF
chmod 0700 "$home_dir/manage.sh"

echo
echo 'vexpax2 установлен. Вставьте этот ключ в приложение:'
echo "$key"
echo 'Управление: sudo ./vexpax2/manage.sh {start|stop|restart|status|key|uninstall}'
echo

