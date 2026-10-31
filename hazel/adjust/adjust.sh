#!/bin/sh
# Hazel, adjusting a recipe on the camera: does what the adjust view (Adjust.qml) asks when it
# closes, because QML can write a file but not rename one, run busctl, or write to the card.
# Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
#
#   adjust.sh watch            keep going, five times a second: act on /tmp/x1d/adjust-request
#   adjust.sh once [DIR]       act on a request once (the Mac tests use this, with DIR for /tmp/x1d)
#
# The request: its first line "use", "discard" or "save C1".."save C7", then the recipe, then the
# line "# end of recipe" (a file without it is still being written, and is left for next time).
#   use        the recipe becomes the live one (/tmp/x1d/recipe, which the sidecar writer copies
#              next to each photo), not saved anywhere; /tmp/x1d/edited holds the slot it came
#              from until a save, a discard, or another slot (slots.sh leaves an edited recipe be)
#   discard    the live one goes back to the slot's own
#   save Cn    into the slot (/tmp/x1d/slots/Cn.txt, its name in slots/names), the card's
#              HAZEL/recipes/Cn.txt, and the live one; Cn becomes the active slot
# Then "done" goes into /tmp/x1d/adjusting, which hands live view back from the adjust view's
# recipe to the live one. Each file is written beside its place and renamed into it, so the
# live-view hook never reads half a recipe.
# Log: /tmp/x1d/adjust.log.
DIR=${2:-/tmp/x1d}
S="--system com.hasselblad.storage / com.hasselblad.storage"
END="# end of recipe"
say() { echo "$(date +%T) $*"; }

put() {  # put FILE: stdin into FILE, renamed into place
  cat >"$1.new" && mv "$1.new" "$1"
}

names() {  # as slots.sh does it: "Cn<tab>name", the name being the recipe's first "#" line
  : >$DIR/slots/names.new
  for f in $DIR/slots/C?.txt; do
    [ -f "$f" ] || continue
    name=$(tr -d '\r' <"$f" | sed -n '/^#/{s/^[# ]*//;s/[ \t]*$//;p;q}' | cut -c1-28)
    printf '%s\t%s\n' "$(basename "$f" .txt)" "$name" >>$DIR/slots/names.new
  done
  mv $DIR/slots/names.new $DIR/slots/names
}

cards() { busctl get-property $S volumes 2>/dev/null | tr '"' '\n' | grep -xE '/SD[0-9]+'; }

# The card keeps the slots the app wrote (HAZEL/recipes); the storage service can't make folders
# and never shortens a file, so the old one goes first. Without a card or that folder the save
# still holds until the camera restarts, and the log says so.
to_card() {
  slot=$1
  for c in $(cards); do
    dest=$c/HAZEL/recipes/$slot.txt
    busctl --timeout=15 call $S Remove s "$dest" >/dev/null 2>&1
    if busctl --timeout=30 call $S WriteFile sis "$DIR/slots/$slot.txt" "$(wc -c <"$DIR/slots/$slot.txt")" "$dest" >/dev/null 2>&1; then
      say "saved $slot to $dest"
      return 0
    fi
  done
  say "saved $slot on the camera only: no card took $slot.txt (it holds until a restart)"
  return 1
}

once() {
  req=$DIR/adjust-request
  [ -f "$req" ] || return 1
  tail -n 1 "$req" | grep -qx "$END" || return 1
  action=$(head -n 1 "$req")
  card_slot=""
  body=$DIR/adjust-recipe
  sed '1d;$d' "$req" >"$body"
  rm -f "$req"
  case "$action" in
    use)
      put $DIR/recipe <"$body"
      # tells slots.sh not to put the slot's own recipe back when the menu opens
      cat $DIR/active 2>/dev/null | put $DIR/edited
      say "using the adjusted recipe (not saved)" ;;
    discard)
      active=$(cat $DIR/active 2>/dev/null)
      if [ -f "$DIR/slots/$active.txt" ]; then put $DIR/recipe <"$DIR/slots/$active.txt"; else put $DIR/recipe <"$body"; fi
      rm -f $DIR/edited
      say "discarded the changes to ${active:-the recipe}" ;;
    "save C"[1-7])
      slot=${action#save }
      mkdir -p $DIR/slots
      put $DIR/slots/$slot.txt <"$body"
      names
      put $DIR/recipe <"$body"
      # slots.sh sees the new active slot and remembers it for the next start
      echo "$slot" | put $DIR/active
      rm -f $DIR/edited
      card_slot=$slot
      say "saved to $slot" ;;
    *)
      say "unknown request: $action" ;;
  esac
  rm -f "$body"
  # live view first; the card can take a while
  echo done | put $DIR/adjusting
  [ -n "$card_slot" ] && to_card "$card_slot"
  return 0
}

case "$1" in
  once) once ;;
  watch)
    say "watching for adjust requests"
    while true; do
      once
      usleep 200000 2>/dev/null || sleep 1
    done ;;
  *) echo "usage: adjust.sh watch | once [dir]" ;;
esac
