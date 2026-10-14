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

installer_log=$(mktemp)
exec 3>&1 4>&2
trap 'status=$?; if (( status != 0 )); then cat "$installer_log" >&4; fi; rm -f "$installer_log"' EXIT
exec >"$installer_log" 2>&1

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

printf '%s' 'PD9waHAKZGVjbGFyZShzdHJpY3RfdHlwZXM9MSk7CgpoZWFkZXIoJ0NvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOCcpOwpoZWFkZXIoJ0NhY2hlLUNvbnRyb2w6IG5vLXN0b3JlJyk7CmhlYWRlcignWC1Db250ZW50LVR5cGUtT3B0aW9uczogbm9zbmlmZicpOwoKJHBhdGggPSBwYXJzZV91cmwoJF9TRVJWRVJbJ1JFUVVFU1RfVVJJJ10gPz8gJy8nLCBQSFBfVVJMX1BBVEgpOwokbWV0aG9kID0gJF9TRVJWRVJbJ1JFUVVFU1RfTUVUSE9EJ10gPz8gJyc7CmlmICghaW5fYXJyYXkoJHBhdGgsIFsnL3BpbmcnLCAnL3BsdWdpbnMnLCAnL3BsdWdpbnMvdG9nZ2xlJ10sIHRydWUpIHx8CiAgICAhaW5fYXJyYXkoJG1ldGhvZCwgWydHRVQnLCAnUE9TVCddLCB0cnVlKSkgewogICAgaHR0cF9yZXNwb25zZV9jb2RlKDQwNCk7CiAgICBlY2hvIGpzb25fZW5jb2RlKFsnZXJyb3InID0+ICdub3RfZm91bmQnXSk7CiAgICBleGl0Owp9CgokZXhwZWN0ZWQgPSB0cmltKChzdHJpbmcpIEBmaWxlX2dldF9jb250ZW50cyhkaXJuYW1lKF9fRElSX18pIC4gJy9jb25maWd1cmF0aW9uL3Rva2VuJykpOwokYXV0aG9yaXphdGlvbiA9IChzdHJpbmcpICgkX1NFUlZFUlsnSFRUUF9BVVRIT1JJWkFUSU9OJ10gPz8gJycpOwokcHJvdmlkZWQgPSBzdHJuY21wKCRhdXRob3JpemF0aW9uLCAnQmVhcmVyICcsIDcpID09PSAwCiAgICA/IHN1YnN0cigkYXV0aG9yaXphdGlvbiwgNykKICAgIDogJyc7CiRzaG9ydFRva2VuID0gc3Vic3RyKCRleHBlY3RlZCwgMCwgMzIpOwppZiAoJGV4cGVjdGVkID09PSAnJyB8fCAhKGhhc2hfZXF1YWxzKCRleHBlY3RlZCwgJHByb3ZpZGVkKSB8fCBoYXNoX2VxdWFscygkc2hvcnRUb2tlbiwgJHByb3ZpZGVkKSkpIHsKICAgIGh0dHBfcmVzcG9uc2VfY29kZSg0MDEpOwogICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAndW5hdXRob3JpemVkJ10pOwogICAgZXhpdDsKfQoKaWYgKCRwYXRoID09PSAnL3BpbmcnICYmICRtZXRob2QgPT09ICdHRVQnKSB7CiAgICBlY2hvIGpzb25fZW5jb2RlKFsKICAgICAgICAnb2snID0+IHRydWUsCiAgICAgICAgJ3NlcnZpY2UnID0+ICd2ZXhwYXgyLXdvcmtlcicsCiAgICAgICAgJ3ZlcnNpb24nID0+IDIsCiAgICAgICAgJ3NlcnZlcl90aW1lJyA9PiBnbWRhdGUoJ2MnKSwKICAgIF0sIEpTT05fVU5FU0NBUEVEX1NMQVNIRVMpOwogICAgZXhpdDsKfQoKJHBsdWdpbnMgPSBbCiAgICAgICAgWydpZCcgPT4gJ3JlbnRfc3RlYW0nLCAndGl0bGUnID0+ICfQkNGA0LXQvdC00LAgU3RlYW0nLCAnY2F0ZWdvcnknID0+ICfQn9GA0L7QtNCw0LbQuCDQuCDQstGL0LTQsNGH0LAnLCAnZGVzY3JpcHRpb24nID0+ICfQkNGA0LXQvdC00LAgU3RlYW0t0LDQutC60LDRg9C90YLQvtCyINC/0L4g0LfQsNC60LDQt9Cw0LwgRnVuUGF5LicsICd0YWJzJyA9PiBbJ9CQ0YDQtdC90LTRiycsICfQkNC60LrQsNGD0L3RgtGLJywgJ9Cb0L7RgtGLJywgJ9Co0LDQsdC70L7QvdGLJywgJ9Cd0LDQu9C40YfQuNC1INCw0LrQutCw0YPQvdGC0L7QsicsICfQn9GA0LDQstC40LvQviDQtNC70Y8g0YfQsNGB0L7QsicsICfQn9GA0L7QutGB0LggU3RlYW0nXV0sCiAgICAgICAgWydpZCcgPT4gJ3JlbnRfcm9ja3N0YXInLCAndGl0bGUnID0+ICfQkNGA0LXQvdC00LAg0LjQs9GAIFJvY2tzdGFyJywgJ2NhdGVnb3J5JyA9PiAn0J/RgNC+0LTQsNC20Lgg0Lgg0LLRi9C00LDRh9CwJywgJ2Rlc2NyaXB0aW9uJyA9PiAn0JDRgNC10L3QtNCwIEdUQSBWINC4IFJEUjIg0L/QviDQt9Cw0LrQsNC30LDQvCBGdW5QYXkuJywgJ3RhYnMnID0+IFsn0JDRgNC10L3QtNGLJywgJ9CQ0LrQutCw0YPQvdGC0YsnLCAn0JvQvtGC0YsnLCAn0KjQsNCx0LvQvtC90YsnLCAn0J3QsNC70LjRh9C40LUg0LDQutC60LDRg9C90YLQvtCyJywgJ9Cf0YDQsNCy0LjQu9C+INC00LvRjyDRh9Cw0YHQvtCyJywgJ9Cf0YDQvtC60YHQuCBTdGVhbSddXSwKICAgICAgICBbJ2lkJyA9PiAnaXNzdWVfc3RlYW1fb2ZmbGluZScsICd0aXRsZScgPT4gJ9CS0YvQtNCw0YfQsCDQvtGE0LvQsNC50L0g0LDQutGC0LjQstCw0YbQuNC4IFN0ZWFtJywgJ2NhdGVnb3J5JyA9PiAn0J/RgNC+0LTQsNC20Lgg0Lgg0LLRi9C00LDRh9CwJywgJ2Rlc2NyaXB0aW9uJyA9PiAn0JHQtdGB0YHRgNC+0YfQvdCw0Y8g0LLRi9C00LDRh9CwIFN0ZWFtLdCw0LrQutCw0YPQvdGC0L7Qsi4nLCAndGFicycgPT4gWyfQktGL0LTQsNGH0LgnLCAn0JDQutC60LDRg9C90YLRiycsICfQm9C+0YLRiycsICfQqNCw0LHQu9C+0L3RiyddXSwKICAgICAgICBbJ2lkJyA9PiAnYXV0b3RpY2tldCcsICd0aXRsZScgPT4gJ9CQ0LLRgtC+0LfQsNGP0LLQutC4INC90LAg0L/QvtC00YLQstC10YDQttC00LXQvdC40LUg0LfQsNC60LDQt9C+0LInLCAnY2F0ZWdvcnknID0+ICfQkNCy0YLQvtC80LDRgtC40LfQsNGG0LjRjyDQuCDRg9C/0YDQsNCy0LvQtdC90LjQtScsICdkZXNjcmlwdGlvbicgPT4gJ9Ce0YLQv9GA0LDQstC60LAg0LfQsNGP0LLQvtC6INC90LAg0L/QvtC00YLQstC10YDQttC00LXQvdC40LUg0L7Qv9C70LDRh9C10L3QvdGL0YUg0LfQsNC60LDQt9C+0LIuJywgJ3RhYnMnID0+IFsn0J3QsNGB0YLRgNC+0LnQutC4JywgJ9Co0LDQsdC70L7QvdGLJywgJ9CW0YPRgNC90LDQuycsICfQn9GA0L7QstC10YDQutCwINGB0LXQudGH0LDRgSddXSwKICAgICAgICBbJ2lkJyA9PiAnb3JkZXJfcmVtaW5kZXInLCAndGl0bGUnID0+ICfQndCw0L/QvtC80LjQvdCw0L3QuNC1INC+INC/0L7QtNGC0LLQtdGA0LbQtNC10L3QuNC4INC30LDQutCw0LfQsCcsICdjYXRlZ29yeScgPT4gJ9CQ0LLRgtC+0LzQsNGC0LjQt9Cw0YbQuNGPINC4INGD0L/RgNCw0LLQu9C10L3QuNC1JywgJ2Rlc2NyaXB0aW9uJyA9PiAn0J3QsNC/0L7QvNC40L3QsNC90LjRjyDQv9C+0LrRg9C/0LDRgtC10LvRj9C8INC+INC/0L7QtNGC0LLQtdGA0LbQtNC10L3QuNC4LicsICd0YWJzJyA9PiBbJ9Cd0LDRgdGC0YDQvtC50LrQuCcsICfQqNCw0LHQu9C+0L3RiycsICfQltGD0YDQvdCw0LsnXV0sCiAgICAgICAgWydpZCcgPT4gJ3Jldmlld19yZXF1ZXN0JywgJ3RpdGxlJyA9PiAn0J/RgNC+0YHRjNCx0LAg0L7RgdGC0LDQstC40YLRjCDQvtGC0LfRi9CyJywgJ2NhdGVnb3J5JyA9PiAn0JDQstGC0L7QvNCw0YLQuNC30LDRhtC40Y8g0Lgg0YPQv9GA0LDQstC70LXQvdC40LUnLCAnZGVzY3JpcHRpb24nID0+ICfQn9GA0L7RgdGM0LHQsCDQvtGB0YLQsNCy0LjRgtGMINC+0YLQt9GL0LIg0L/QvtGB0LvQtSDQt9Cw0LrQsNC30LAuJywgJ3RhYnMnID0+IFsn0J3QsNGB0YLRgNC+0LnQutC4JywgJ9Co0LDQsdC70L7QvdGLJywgJ9CW0YPRgNC90LDQuyddXSwKXTsKCiRzdGF0ZVBhdGggPSBkaXJuYW1lKF9fRElSX18pIC4gJy9jb25maWd1cmF0aW9uL3BsdWdpbl9zdGF0ZS5qc29uJzsKJGxvY2tQYXRoID0gZGlybmFtZShfX0RJUl9fKSAuICcvY29uZmlndXJhdGlvbi9wbHVnaW5fc3RhdGUubG9jayc7CiRlbmdpbmVSZWFkeSA9IGlzX2ZpbGUoZGlybmFtZShfX0RJUl9fKSAuICcvY29uZmlndXJhdGlvbi9lbmdpbmUucmVhZHknKTsKJGxvY2sgPSBmb3BlbigkbG9ja1BhdGgsICdjKycpOwppZiAoJGxvY2sgPT09IGZhbHNlIHx8ICFmbG9jaygkbG9jaywgTE9DS19FWCkpIHsKICAgIGh0dHBfcmVzcG9uc2VfY29kZSg1MDApOwogICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAnc3RvcmFnZV91bmF2YWlsYWJsZSddKTsKICAgIGV4aXQ7Cn0KdHJ5IHsKICAgICRzdGF0ZSA9IGpzb25fZGVjb2RlKChzdHJpbmcpIEBmaWxlX2dldF9jb250ZW50cygkc3RhdGVQYXRoKSwgdHJ1ZSk7CiAgICBpZiAoIWlzX2FycmF5KCRzdGF0ZSkpICRzdGF0ZSA9IFtdOwogICAgaWYgKCRwYXRoID09PSAnL3BsdWdpbnMvdG9nZ2xlJyAmJiAkbWV0aG9kID09PSAnUE9TVCcpIHsKICAgICAgICBpZiAoISRlbmdpbmVSZWFkeSkgewogICAgICAgICAgICBodHRwX3Jlc3BvbnNlX2NvZGUoNDA5KTsKICAgICAgICAgICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAncGx1Z2luX2VuZ2luZV91bmF2YWlsYWJsZSddKTsKICAgICAgICAgICAgZXhpdDsKICAgICAgICB9CiAgICAgICAgJGlucHV0ID0ganNvbl9kZWNvZGUoKHN0cmluZykgZmlsZV9nZXRfY29udGVudHMoJ3BocDovL2lucHV0JyksIHRydWUpOwogICAgICAgICRpZCA9IGlzX2FycmF5KCRpbnB1dCkgPyAoJGlucHV0WydpZCddID8/IG51bGwpIDogbnVsbDsKICAgICAgICAkZW5hYmxlZCA9IGlzX2FycmF5KCRpbnB1dCkgPyAoJGlucHV0WydlbmFibGVkJ10gPz8gbnVsbCkgOiBudWxsOwogICAgICAgICRpZHMgPSBhcnJheV9jb2x1bW4oJHBsdWdpbnMsICdpZCcpOwogICAgICAgIGlmICghaXNfc3RyaW5nKCRpZCkgfHwgIWluX2FycmF5KCRpZCwgJGlkcywgdHJ1ZSkgfHwgIWlzX2Jvb2woJGVuYWJsZWQpKSB7CiAgICAgICAgICAgIGh0dHBfcmVzcG9uc2VfY29kZSg0MDApOwogICAgICAgICAgICBlY2hvIGpzb25fZW5jb2RlKFsnZXJyb3InID0+ICdpbnZhbGlkX3BsdWdpbl9zdGF0ZSddKTsKICAgICAgICAgICAgZXhpdDsKICAgICAgICB9CiAgICAgICAgJHN0YXRlWyRpZF0gPSAkZW5hYmxlZDsKICAgICAgICAkZW5jb2RlZCA9IGpzb25fZW5jb2RlKCRzdGF0ZSwgSlNPTl9VTkVTQ0FQRURfVU5JQ09ERSB8IEpTT05fVEhST1dfT05fRVJST1IpOwogICAgICAgICR0ZW1wb3JhcnkgPSAkc3RhdGVQYXRoIC4gJy50bXAuJyAuIGJpbjJoZXgocmFuZG9tX2J5dGVzKDUpKTsKICAgICAgICBpZiAoZmlsZV9wdXRfY29udGVudHMoJHRlbXBvcmFyeSwgJGVuY29kZWQsIExPQ0tfRVgpID09PSBmYWxzZSB8fCAhcmVuYW1lKCR0ZW1wb3JhcnksICRzdGF0ZVBhdGgpKSB7CiAgICAgICAgICAgIEB1bmxpbmsoJHRlbXBvcmFyeSk7CiAgICAgICAgICAgIGh0dHBfcmVzcG9uc2VfY29kZSg1MDApOwogICAgICAgICAgICBlY2hvIGpzb25fZW5jb2RlKFsnZXJyb3InID0+ICdzdG9yYWdlX3VuYXZhaWxhYmxlJ10pOwogICAgICAgICAgICBleGl0OwogICAgICAgIH0KICAgICAgICBlY2hvIGpzb25fZW5jb2RlKFsnb2snID0+IHRydWUsICdpZCcgPT4gJGlkLCAnZW5hYmxlZCcgPT4gJGVuYWJsZWRdKTsKICAgICAgICBleGl0OwogICAgfQogICAgaWYgKCRwYXRoICE9PSAnL3BsdWdpbnMnIHx8ICRtZXRob2QgIT09ICdHRVQnKSB7CiAgICAgICAgaHR0cF9yZXNwb25zZV9jb2RlKDQwNCk7CiAgICAgICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAnbm90X2ZvdW5kJ10pOwogICAgICAgIGV4aXQ7CiAgICB9CiAgICBmb3JlYWNoICgkcGx1Z2lucyBhcyAmJHBsdWdpbikgewogICAgICAgICRwbHVnaW5bJ2VuYWJsZWQnXSA9ICRlbmdpbmVSZWFkeSAmJiAoJHN0YXRlWyRwbHVnaW5bJ2lkJ11dID8/IGZhbHNlKSA9PT0gdHJ1ZTsKICAgICAgICAkcGx1Z2luWydhdmFpbGFibGUnXSA9ICRlbmdpbmVSZWFkeTsKICAgIH0KICAgIHVuc2V0KCRwbHVnaW4pOwogICAgZWNobyBqc29uX2VuY29kZShbJ3BsdWdpbnMnID0+ICRwbHVnaW5zXSwgSlNPTl9VTkVTQ0FQRURfVU5JQ09ERSB8IEpTT05fVU5FU0NBUEVEX1NMQVNIRVMpOwp9IGZpbmFsbHkgewogICAgZmxvY2soJGxvY2ssIExPQ0tfVU4pOwogICAgZmNsb3NlKCRsb2NrKTsKfQo=' | base64 -d > "$home_dir/public/index.php"
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

key_body=$(php -r '$bytes = hex2bin($argv[1] . $argv[2]); if ($bytes === false || strlen($bytes) !== 48) { exit(1); } echo rtrim(strtr(base64_encode($bytes), "+/", "-_"), "=");' "${token:0:32}" "$fingerprint")
key="vx2:${host}:18443:${key_body}"
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

printf 'Готово, введите этот ключ в приложение:\n%s\n' "$key" >&3

