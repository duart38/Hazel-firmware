#!/bin/sh
# Join a wifi network and accept SSH logins with a key only, so the camera can be reached without
# the USB cable while the Mac stays on the same network (and online).
#
#   wifi.sh up       join the network in $NET, get an address, start our SSH server on port 2222,
#                    and keep reconnecting in the background when the link drops
#   wifi.sh down     stop all of that and give the stock SSH service back
#   wifi.sh status   address, signal, and what is running
#
# $NET holds the network block (written by `cam wifi setup` with the password already hashed) and
# survives restarts, as do the SSH host key and the Mac's public key in $KEYS; load.sh runs `up` at
# startup when a network is configured. Everything else is in /tmp.
#
# The stock SSH service listens on every interface and allows root login with a password; it is
# stopped while we are on a network and started again by `down` (or by a restart).
# Hasselblad's own Wi-Fi (the camera's network) also uses the radio: leave it off while joined.

DIR=/tmp/x1d/wifi
KEYS=/media/data/x1d/ssh
NET=/media/data/x1d/wifi/home.conf
IF=wlp1s0
PORT=2222

say() { echo "wifi: $*"; }

# wait for it to exit: a wifi client still shutting down holds the control socket, and the next
# one then fails to start
stop_pid() {
  [ -f "$1" ] || return 0
  pid=$(cat "$1"); rm -f "$1"
  kill "$pid" 2>/dev/null || return 0
  i=0
  while kill -0 "$pid" 2>/dev/null && [ $i -lt 5 ]; do sleep 1; i=$((i + 1)); done
}

join() {
  stop_pid $DIR/wpa.pid
  /usr/sbin/wpa_supplicant -B -D nl80211 -i $IF -c "$1" -P $DIR/wpa.pid || { say "could not start the wifi client"; exit 1; }
}

joined_within() {
  i=0
  while [ $i -lt "$1" ]; do
    /usr/sbin/iw dev $IF link | grep -q '^Connected' && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

connect() {
  # Prefer 5 GHz: on 2.4 GHz the link crawled at 1-3 MB/s. A frequency list in the config is not
  # enough, because this chip's firmware picks the access point itself; it only obeys a named one.
  # So join on any band, find this network's strongest 5 GHz access point, and move to it.
  umask 077
  join "$NET"
  joined_within 20 || say "not joined yet, carrying on"
  ssid=$(/usr/sbin/iw dev $IF link | sed -n 's/^[[:space:]]*SSID: //p')
  best=$(/usr/sbin/iw dev $IF scan | awk -v s="$ssid" '
    /^BSS/ { b = substr($2, 1, 17) }
    /freq:/ { f = $2 }
    /signal:/ { g = $2 }
    /^[[:space:]]*SSID: / { n = $0; sub(/^[[:space:]]*SSID: /, "", n); if (n == s && f > 4900) print g, b }' |
    sort -rn | head -n 1 | cut -d" " -f2)
  if [ -n "$best" ]; then
    sed "/^network={/a\\  bssid=$best" "$NET" >$DIR/run.conf
    join $DIR/run.conf
    if joined_within 15; then say "on 5 GHz"; else say "5 GHz did not answer, back to any band"; join "$NET"; fi
  else
    say "no 5 GHz access point for this network in range"
  fi
}

# every 20 s: two misses in a row (40 s without a link, e.g. out of range) -> connect again. Leaves
# the radio alone while Hasselblad's own Wi-Fi (the camera's network) has it.
keep() {
  misses=0
  while true; do
    sleep 20
    pidof hostapd >/dev/null && continue
    # the stock service starts late in boot, possibly after up stopped it
    systemctl -q is-active sshd.socket && systemctl stop sshd.socket
    if /usr/sbin/iw dev $IF link | grep -q '^Connected'; then misses=0; continue; fi
    misses=$((misses + 1))
    [ $misses -ge 2 ] || continue
    say "$(date +%T) link lost, reconnecting"
    connect
    misses=0
  done
}

up() {
  [ -f "$NET" ] || { say "no network configured ($NET): run cam wifi setup on the Mac"; exit 1; }
  [ -f "$KEYS/authorized_keys" ] || { say "no Mac key in $KEYS/authorized_keys"; exit 1; }
  mkdir -p "$DIR" /var/run/sshd
  chmod 700 "$KEYS"
  [ -f "$KEYS/host_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$KEYS/host_ed25519"

  cat >"$DIR/sshd_config" <<EOF
Port $PORT
HostKey $KEYS/host_ed25519
AuthorizedKeysFile $KEYS/authorized_keys
PermitRootLogin without-password
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
UsePrivilegeSeparation sandbox
PidFile $DIR/sshd.pid
ClientAliveInterval 15
ClientAliveCountMax 4
Subsystem sftp internal-sftp
EOF

  cat >"$DIR/dhcp.sh" <<'EOF'
#!/bin/sh
case "$1" in
  deconfig) ip addr flush dev "$interface"; ip link set "$interface" up ;;
  bound|renew)
    ip addr flush dev "$interface"
    ip addr add "$ip/${mask:-24}" dev "$interface"
    [ -n "$router" ] && ip route replace default via "${router%% *}" dev "$interface"
    echo "$ip" >/tmp/x1d/wifi/ip ;;
esac
EOF
  chmod 755 "$DIR/dhcp.sh"

  systemctl stop sshd.socket

  ip link set $IF up
  connect
  stop_pid $DIR/dhcp.pid
  rm -f $DIR/ip
  udhcpc -b -i $IF -s $DIR/dhcp.sh -p $DIR/dhcp.pid -x hostname:hazel-x1d >/dev/null 2>&1

  stop_pid $DIR/sshd.pid
  /usr/sbin/sshd -f $DIR/sshd_config || { say "SSH server did not start"; exit 1; }

  # as its own unit, so it outlives the shell that started it (a USB command, or load.sh)
  systemctl stop hazel-wifi-keep 2>/dev/null
  systemd-run --unit=hazel-wifi-keep /bin/sh /tmp/x1d/wifi.sh keep >/dev/null 2>&1

  i=0
  while [ ! -s $DIR/ip ] && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
  if [ -s $DIR/ip ]; then say "joined, address $(cat $DIR/ip), SSH on port $PORT"
  else say "no address after 30 s (wrong password, or the network is out of reach); see: wifi.sh status"; fi
}

down() {
  systemctl stop hazel-wifi-keep 2>/dev/null
  stop_pid $DIR/sshd.pid
  stop_pid $DIR/dhcp.pid
  stop_pid $DIR/wpa.pid
  ip addr flush dev $IF
  ip link set $IF down
  rm -f $DIR/ip
  systemctl start sshd.socket
  say "off; stock SSH service back"
}

status() {
  echo "address: $(cat $DIR/ip 2>/dev/null || echo none)"
  /usr/sbin/iw dev $IF link 2>/dev/null | grep -E 'Not connected|SSID|freq|signal|tx bitrate'
  for p in wpa dhcp sshd; do
    if [ -f $DIR/$p.pid ] && kill -0 "$(cat $DIR/$p.pid)" 2>/dev/null; then echo "$p running"; else echo "$p stopped"; fi
  done
  echo "reconnect watcher: $(systemctl is-active hazel-wifi-keep)"
  echo "stock SSH service: $(systemctl is-active sshd.socket)"
}

case "$1" in
  up) up ;;
  down) down ;;
  status) status ;;
  keep) keep ;;
  *) echo "usage: wifi.sh up|down|status"; exit 2 ;;
esac
