#!/bin/sh
# Hazel, debug logging. Off unless /tmp/x1d/debug says "on" (the Extras page's "Debug logging"
# switch, or a HAZEL-DEBUG file at the top of the card at power-on; see load.sh).
#   debug.sh watch   keep going: while on, every 10 s add a snapshot to
#                    /media/data/x1d/logs/debug.log (time, load, memory, temperatures, battery,
#                    the hook's frame rate, slot and look, service restarts, new lines from the
#                    slot keeper), and follow the interface's and live view's journal into
#                    journal.log (the Extras page logs every choice there as "film-menu.js: ...").
# Past 512 KB a log moves to <name>.1 (replacing the one before), so each takes at most 1 MB.
# /media/data survives restarts;
# `tools/cam logs` fetches the logs over USB, and slots.sh copies them to the card as HAZEL-DEBUG.LOG
# when the menu opens.
DIR=/tmp/x1d
LOGS=/media/data/x1d/logs
MAX=524288
BATTERY=/sys/class/power_supply/bq28z610
say() { echo "$(date '+%F %T') $*" >>$LOGS/debug.log; }

on() { [ "$(cut -c1-2 $DIR/debug 2>/dev/null)" = on ]; }

size() { wc -c <"$1" 2>/dev/null || echo 0; }

rotate() {
  [ "$(size "$1")" -gt $MAX ] || return 1
  mv "$1" "$1.1"
}

battery() {
  for f in capacity status voltage_now current_now power_avg; do
    printf '%s=%s ' $f "$(cat $BATTERY/$f 2>/dev/null)"
  done
}

follow_journal() {
  stop_journal
  journalctl -f -n 0 -o short -u victory-gui -u video-daemon >>$LOGS/journal.log 2>&1 &
  journal=$!
}

stop_journal() {
  [ -n "$journal" ] && kill $journal 2>/dev/null
  journal=""
}

snapshot() {
  say "load $(cut -d' ' -f1-3 /proc/loadavg), free $(free | awk '/Mem:/{print $4}') KB, temps $(cat $DIR/temps 2>/dev/null | tr '\n' ' ')"
  say "battery $(battery)"
  # the hook writes stats every 150 live-view frames, so none until live view first runs
  hook=$(grep -E '^(fps|look|table_builds|write_failures)' $DIR/stats 2>/dev/null | tr '\n' ' ')
  say "slot $(cat $DIR/active 2>/dev/null), look $(cat $DIR/look 2>/dev/null), hook ${hook:-no stats (no live view yet)}"
  pids="video-daemon $(pidof video-daemon), victory-gui $(pidof victory-gui)"
  [ "$pids" != "$last_pids" ] && say "processes: $pids" && last_pids=$pids
  lines=$(wc -l <$DIR/slots.log 2>/dev/null || echo 0)
  [ "$lines" -lt "$slot_lines" ] && slot_lines=0
  [ "$lines" -gt "$slot_lines" ] && sed -n "$((slot_lines + 1)),${lines}p" $DIR/slots.log | sed 's/^/slots.sh: /' | while read -r line; do say "$line"; done
  slot_lines=$lines
  # the playback looks' log, which is in /tmp and would be gone after a restart
  lines=$(wc -l <$DIR/playhook.log 2>/dev/null || echo 0)
  [ "$lines" -lt "$play_lines" ] && play_lines=0
  [ "$lines" -gt "$play_lines" ] && sed -n "$((play_lines + 1)),${lines}p" $DIR/playhook.log | sed 's/^/playback: /' | while read -r line; do say "$line"; done
  play_lines=$lines
}

watch() {
  mkdir -p $LOGS
  journal=""; last_pids=""; slot_lines=0; play_lines=0; was=off
  trap 'stop_journal; exit 0' TERM INT
  while true; do
    if on; then
      if [ $was = off ]; then
        say "debug logging on, film setup $(cat $DIR/VERSION 2>/dev/null)"
        sed 's/^/loader: /' /tmp/catkin.log 2>/dev/null | while read -r line; do say "$line"; done
        last_pids=""
        follow_journal
        was=on
      fi
      snapshot
      rotate $LOGS/debug.log
      rotate $LOGS/journal.log && follow_journal
    elif [ $was = on ]; then
      say "debug logging off"
      stop_journal
      was=off
    fi
    sleep 10
  done
}

case "$1" in
  watch) watch ;;
  *)     echo "usage: debug.sh watch" ;;
esac
