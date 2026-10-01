#!/bin/sh
# Short verbs for the USB shell, which only takes commands of up to 231 bytes. Lives in /tmp/x1d.
V="--system com.hasselblad.video / com.hasselblad.video"
S="--system com.hasselblad.storage / com.hasselblad.storage"
case "$1" in
  lv)    busctl call $V setLiveviewState bbs true false "" ;;
  lvoff) busctl call $V setLiveviewState bbs false false "" ;;
  state) busctl get-property $V pipelineState ;;
  look)  echo "$2" >/tmp/x1d/look ;;
  stats) cat /tmp/x1d/stats ;;
  pid)   systemctl show video-daemon -p MainPID -p NRestarts -p ActiveState ;;
  hooked) grep -c filmhook /proc/$(systemctl show video-daemon -p MainPID | cut -d= -f2)/maps ;;
  grab)  rm -f /tmp/x1d/frame-*.nv12; touch /tmp/x1d/grab; sleep 1; ls -l /tmp/x1d/frame-*.nv12 ;;
  fb)    # visible page of fb0, gzipped, for tools/fb_to_png.py
         off=$(cut -d, -f2 /sys/class/graphics/fb0/pan)
         dd if=/dev/fb0 bs=2560 skip="$off" count=480 2>/dev/null | gzip -1 >/tmp/x1d/fb0.gz; ls -l /tmp/x1d/fb0.gz ;;
  unhook) rm -f /run/systemd/system/video-daemon.service.d/film.conf; systemctl daemon-reload; systemctl restart video-daemon ;;
  rehook) systemctl daemon-reload; systemctl restart video-daemon ;;
  cpu)   # video-daemon CPU use over 5 s, percent of one core (clock ticks are 100 Hz)
         pid=$(systemctl show video-daemon -p MainPID | cut -d= -f2)
         a=$(cut -d' ' -f14,15 /proc/$pid/stat | tr ' ' '+'); sleep 5; b=$(cut -d' ' -f14,15 /proc/$pid/stat | tr ' ' '+')
         echo "video-daemon $(( ( ($b) - ($a) ) / 5 ))% of one core" ;;
  cards) # the cards the camera sees, one per line: /SD0 is slot 1, /SD1 is slot 2
         busctl get-property $S volumes | tr '"' '\n' | grep -xE '/SD[0-9]+' ;;
  ls)    # list a card folder (live view must be off: it shares the video device with storage).
         # Default: the top of the first card.
         busctl --timeout=15 call $S Browse sii "${2:-$($0 cards | head -n 1)}" 0 "${3:-50}" | tr '"' '\n' | grep -A2 -E '^name$' | grep -vE '^(name|--| s )$' ;;
  cardget) # cardget /SD0/file /tmp/x1d/dest [bytes]: copy a card file into Linux
         size=${4:-$(busctl --timeout=15 call $S Browse sii "$(dirname "$2")" 0 500 | tr '"' '\n' | grep -A4 -xF "$(basename "$2")" | sed -n 's/^ t \([0-9]*\) $/\1/p' | head -n 1)}
         busctl --timeout=60 call $S File stis "$2" 0 "$size" "$3" && ls -l "$3" ;;
  cardput) # cardput /tmp/x1d/file /SD0/dir/file: copy a Linux file onto the card in one call (live
         # view must be off). The folder must exist: the storage service can't make one. It never
         # shortens a file it overwrites, so an old copy is removed first.
         busctl --timeout=15 call $S Remove s "$3" >/dev/null 2>&1
         busctl --timeout=60 call $S WriteFile sis "$2" "$(wc -c <"$2")" "$3" >/dev/null && echo "$3 $(wc -c <"$2") bytes" ;;
  sidecar) # (re)start the sidecar writer in the background
         for pid in $(ps | grep -E "[s]idecar.sh|[m]ember=Added" | awk '{print $1}'); do kill $pid; done
         (sh /tmp/x1d/sidecar.sh >>/tmp/x1d/sidecar.log 2>&1 &) ; sleep 1
         ps | grep -q "[s]idecar.sh" && echo "sidecar running" || echo "sidecar NOT running" ;;
  top)   top -b -n 1 | head -n 12 ;;
  temps) # (re)start the temperature reader in the background (feeds the live-view readout)
         for pid in $(ps | grep "[t]emps.sh" | awk '{print $1}'); do kill $pid; done
         (sh /tmp/x1d/temps.sh >/dev/null 2>&1 &) ; sleep 1
         ps | grep -q "[t]emps.sh" && echo "temps running" || echo "temps NOT running" ;;
  temp)  # temperatures now: processor (live), image chip and sensor unit (logged once a minute)
         echo "processor $(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 )) C (throttles at 85 C)"
         journalctl --no-pager -n 60 -o cat -u system-manager | sed -n 's/.*FPGA temp: *\([0-9]*\).*/image chip \1 C/p; s/.*SPC temp: *\([0-9]*\).*/sensor unit \1 C/p' | tail -n 2 ;;
  overlay) # overlay on|off: the temperature readout at the top of live view
         echo "$2" >/tmp/x1d/overlay ;;
  buttons) # buttons [stop]: log every button message (time and name) to /tmp/x1d/buttons.log
         for pid in $(ps | grep "[b]uttons-monitor" | awk '{print $1}'); do kill $pid; done
         [ "$2" = stop ] && { echo "buttons stopped"; exit 0; }
         (sh -c 'dbus-monitor --system "type=signal" 2>/dev/null | grep --line-buffered -o "member=btn[A-Za-z]*\|member=keyClick[A-Za-z]*\|member=[a-zA-Z]*[Pp]ress[a-zA-Z]*" | while read m; do echo "$(date +%T) $m"; done # buttons-monitor' >>/tmp/x1d/buttons.log 2>&1 &)
         echo "logging buttons to /tmp/x1d/buttons.log" ;;
  framelog) # framelog [stop]: every 2 s, append the time and each frame size's rate to /tmp/x1d/framelog
         for pid in $(ps | grep "[f]ramelog-loop" | awk '{print $1}'); do kill $pid; done
         [ "$2" = stop ] && { echo "framelog stopped"; exit 0; }
         (sh -c 'while true; do echo "$(date +%T) $(grep -E "^(screen|viewfinder|other)" /tmp/x1d/stats | tr "\n" " ")"; sleep 2; done # framelog-loop' >>/tmp/x1d/framelog 2>&1 &)
         echo "framelog running: /tmp/x1d/framelog" ;;
  evf)   # evf [N]: copy what the viewfinder shows, N times about 0.2 s apart (default 10), to
         # /tmp/x1d/evf-<i>.gz (its visible page of fb4, 1024x768, 4 bytes a pixel), for tools/fb_to_png.py
         rm -f /tmp/x1d/evf-*.gz; i=0
         while [ $i -lt ${2:-10} ]; do
           off=$(cut -d, -f2 /sys/class/graphics/fb4/pan)
           dd if=/dev/fb4 bs=4096 skip="$off" count=768 2>/dev/null | gzip -1 >/tmp/x1d/evf-$i.gz
           i=$((i + 1)); usleep 200000
         done; ls /tmp/x1d/evf-*.gz | wc -l ;;
  evftest) # the viewfinder with our look off, black and white only, then the full look, 8 s each:
         # 200 samples of what it shows (fbscore), then which look is restored. Needs the viewfinder on.
         was=$(cat /tmp/x1d/look 2>/dev/null)
         for l in n b f; do
           echo "== look $l"; echo $l >/tmp/x1d/look; sleep 2
           /tmp/x1d/fbscore /dev/fb4 1024 768 4096 200 20 >/tmp/x1d/evftest-$l
           awk '{c+=$3; if ($3>1.5) col++; if ($9!=last) ch++; last=$9} END {printf "samples %d over %d ms, picture changed %d times (%.1f a second), colour mean %.1f, colourful samples %d\n", NR, $1, ch, ch*1000/$1, c/NR, col}' /tmp/x1d/evftest-$l
         done
         echo "$was" >/tmp/x1d/look; echo "look back to $was" ;;
  gui)   # load the Extras menu page, and the playback looks (libplayhook.so) when it's there, into
         # the camera's interface (restarts the interface, about 5 s)
         libs=/tmp/x1d/libfilmgui.so; [ -f /tmp/x1d/libplayhook.so ] && libs="$libs /tmp/x1d/libplayhook.so"
         D=/run/systemd/system/victory-gui.service.d; mkdir -p $D
         printf "[Service]\nEnvironment=\"LD_PRELOAD=$libs\"\n" >$D/film.conf
         systemctl daemon-reload; systemctl restart victory-gui ;;
  guioff) # back to the stock interface (restarts it)
         rm -f /run/systemd/system/victory-gui.service.d/film.conf; systemctl daemon-reload; systemctl restart victory-gui ;;
  guihooked) # 1 if the interface has the Extras page library loaded, 1 if the playback looks, then any
         # "film-menu.js not added" lines
         grep -c filmgui /proc/$(pidof victory-gui)/maps
         grep -c playhook /proc/$(pidof victory-gui)/maps
         journalctl -u victory-gui -n 2000 --no-pager -o cat | grep "film-menu" | tail -n 3 ;;
  *)     echo "usage: x.sh lv|lvoff|state|look X|stats|pid|hooked|grab|fb|unhook|rehook|cpu|ls|cardget|sidecar|top|framelog [stop]|temps|temp|overlay on|off|buttons [stop]|evf [N]|evftest|gui|guioff|guihooked" ;;
esac
