#!/bin/sh
# Hazel, recipe slots C1 ... C7, the ones the Extras page offers.
#   slots.sh refresh [/SD0]  copy the card's HAZEL/recipes/C*.txt into /tmp/x1d/slots, with their
#                            names in /tmp/x1d/slots/names ("C3<tab>name" a line). Without that
#                            folder on any card, the slots packed with the card setup stay.
#   slots.sh watch           keep going, once a second: when the Extras page picks a slot (it writes
#                            /tmp/x1d/active), make that slot's recipe the live one; remember the
#                            slot, the film look and debug logging switches in /media/data/x1d for
#                            the next start; re-read the card's slots when the menu opens (the card
#                            is readable then, live view is off), so slots written by the app show
#                            up, and with debug logging on copy the logs to the card as HAZEL-DEBUG.LOG.
# Reading the card needs live view off; while it's on, only the refresh waits.
S="--system com.hasselblad.storage / com.hasselblad.storage"
DIR=/tmp/x1d
KEEP=/media/data/x1d
say() { echo "$(date +%T) $*"; }

cards() { busctl get-property $S volumes 2>/dev/null | tr '"' '\n' | grep -xE '/SD[0-9]+'; }

names() {
  : >$DIR/slots/names.new
  for f in $DIR/slots/C?.txt; do
    [ -f "$f" ] || continue
    # the recipe's name is its first "#" line, as in the app
    name=$(tr -d '\r' <"$f" | sed -n '/^#/{s/^[# ]*//;s/[ \t]*$//;p;q}' | cut -c1-28)
    printf '%s\t%s\n' "$(basename "$f" .txt)" "$name" >>$DIR/slots/names.new
  done
  mv $DIR/slots/names.new $DIR/slots/names
}

# recipes are text: no NUL bytes and no control characters other than tab, line feed, carriage return
is_text() {
  tr -d '\000' <"$1" | cmp -s - "$1" && ! grep -q "$(printf '[\001-\010\016-\037\177]')" "$1"
}

refresh() {
  mkdir -p $DIR/slots
  from=""
  for c in $1 $(cards); do
    dir=$c/HAZEL/recipes
    list=$(busctl --timeout=15 call $S Browse sii "$dir" 0 50 2>/dev/null) || continue
    new=$DIR/slots.new; rm -rf $new; mkdir -p $new
    for n in 1 2 3 4 5 6 7; do
      size=$(echo "$list" | tr '"' '\n' | grep -A4 -xF "C$n.txt" | sed -n 's/^ t \([0-9]*\) $/\1/p' | head -n 1)
      # the hook reads up to 2 KB of recipe
      [ -n "$size" ] && [ "$size" -gt 0 ] && [ "$size" -le 2048 ] || continue
      busctl --timeout=15 call $S File stis "$dir/C$n.txt" 0 "$size" "$new/C$n.txt" >/dev/null && is_text "$new/C$n.txt" && continue
      # a read that fails or hands back binary (seen once, while live view was starting) keeps the
      # slot's last good copy
      rm -f "$new/C$n.txt"
      [ -f "$DIR/slots/C$n.txt" ] && cp "$DIR/slots/C$n.txt" "$new/C$n.txt" && say "slot C$n: bad read, kept the last copy"
    done
    rm -rf $DIR/slots; mv $new $DIR/slots
    from=$dir
    break
  done
  names
  say "slots from ${from:-the card setup}: $(cut -f1 $DIR/slots/names | tr '\n' ' ')"
}

use() {
  cp "$DIR/slots/$1.txt" $DIR/recipe.new && mv $DIR/recipe.new $DIR/recipe
}

# the debug logs (debug.sh), both parts of each, into one file at the top of the first card; the
# storage service can't make folders, and never shortens a file it overwrites, so remove it first
card_log() {
  card=$(cards | head -n 1)
  [ -n "$card" ] || return
  out=$DIR/HAZEL-DEBUG.LOG
  { cat $KEEP/logs/debug.log.1 $KEEP/logs/debug.log
    echo "----- journal (the interface and live view)"
    cat $KEEP/logs/journal.log.1 $KEEP/logs/journal.log; } >$out 2>/dev/null
  busctl --timeout=15 call $S Remove s "$card/HAZEL-DEBUG.LOG" >/dev/null 2>&1
  busctl --timeout=60 call $S WriteFile sis $out "$(wc -c <$out)" "$card/HAZEL-DEBUG.LOG" >/dev/null &&
    say "logs copied to $card/HAZEL-DEBUG.LOG ($(wc -c <$out) bytes)"
  rm -f $out
}

watch() {
  mkdir -p $KEEP
  was=""; refreshed=0
  last_active=$(cat $DIR/active 2>/dev/null)
  last_look=$(cut -c1 $DIR/look 2>/dev/null)
  last_debug=$(cat $DIR/debug 2>/dev/null)
  say "watching (slot ${last_active:-none}, look $last_look)"
  while true; do
    active=$(cat $DIR/active 2>/dev/null)
    browsing=$(busctl get-property $S browsingPossible 2>/dev/null)
    now=$(date +%s)
    if [ "$browsing" = "b true" ] && [ "$was" != "b true" ] && [ $((now - refreshed)) -ge 10 ]; then
      refresh ""
      refreshed=$now
      # the app may have changed the recipe in the chosen slot
      [ -f "$DIR/slots/$active.txt" ] && ! cmp -s "$DIR/slots/$active.txt" $DIR/recipe && use "$active" && say "slot $active changed on the card"
      [ "$(cat $DIR/debug 2>/dev/null)" = on ] && card_log
    fi
    was=$browsing
    if [ "$active" != "$last_active" ]; then
      [ -f "$DIR/slots/$active.txt" ] && use "$active"
      echo "$active" >$KEEP/active
      last_active=$active
      say "slot ${active:-none}"
    fi
    look=$(cut -c1 $DIR/look 2>/dev/null)
    if [ "$look" != "$last_look" ]; then
      case "$look" in f|n|b) echo "$look" >$KEEP/look; say "look $look" ;; esac
      last_look=$look
    fi
    debug=$(cat $DIR/debug 2>/dev/null)
    if [ "$debug" != "$last_debug" ]; then
      case "$debug" in on|off) echo "$debug" >$KEEP/debug; say "debug logging $debug" ;; esac
      last_debug=$debug
    fi
    sleep 1
  done
}

case "$1" in
  refresh) refresh "$2" ;;
  watch)   watch ;;
  *)       echo "usage: slots.sh refresh [/SD0] | watch" ;;
esac
