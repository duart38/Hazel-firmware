#!/bin/sh
# Catkin: at startup, run the setup the memory card brings along.
#
# On the camera as /media/data/x1d-card-loader/boot.sh (the writable data partition), started once,
# about 10 s after power-on, by x1d-card-loader.service (both keep the name they had before the
# project was called Catkin: the service is on the system partition). It looks for CATKIN.TAR and
# CATKIN.SIG at the top of a card, copies them into /tmp, and checks the seal: a SHA-256 of this
# camera's key wrapped around the archive's own SHA-256, made by `catkin pack` on the Mac that
# holds the same key. Only then is the archive unpacked into a fresh folder in /tmp and its load.sh
# run, as  sh load.sh <that folder> <card>  (for example /SD0).
#
# No card, no archive, or a seal that doesn't match: nothing happens, the camera stays stock.
# Everything the archive sets up should live in /tmp and /run, so a restart without the card is a
# stock camera again. Deleting this file switches the loader off; the service then does nothing.
# Log: /tmp/catkin.log
exec >>/tmp/catkin.log 2>&1
say() { echo "$(date +%T) $*"; }
HOME_DIR=${CATKIN_HOME:-/media/data/x1d-card-loader}
S="--system com.hasselblad.storage / com.hasselblad.storage"
V="--system com.hasselblad.video / com.hasselblad.video"
WORK=/tmp/catkin
TAR=CATKIN.TAR
SIG=CATKIN.SIG
say "start"

key=$(cat "$HOME_DIR/key" 2>/dev/null)
if [ ${#key} -lt 32 ]; then say "no key in $HOME_DIR/key: not loading anything"; exit 0; fi

# size of a file in a card folder, from the storage service's listing ("" when it isn't there)
size_of() {
  echo "$1" | tr '"' '\n' | grep -A4 -xF "$2" | sed -n 's/^ t \([0-9]*\) $/\1/p' | head -n 1
}

# The storage service takes a few seconds after startup to see the cards, and a card can only be
# read while live view is off (they share the video device).
card=""; tries=0; stopped_live_view=""
while [ -z "$card" ] && [ $tries -lt 60 ]; do
  tries=$((tries + 1))
  cards=$(busctl get-property $S volumes 2>/dev/null | tr '"' '\n' | grep -xE '/SD[0-9]+')
  if [ -n "$cards" ]; then
    if [ "$(busctl get-property $S browsingPossible 2>/dev/null)" != "b true" ]; then
      busctl call $V setLiveviewState bbs false false "" >/dev/null 2>&1 && stopped_live_view=1
    else
      listed=""
      for c in $cards; do
        list=$(busctl --timeout=15 call $S Browse sii "$c" 0 500 2>/dev/null) || continue
        listed=1
        tar_size=$(size_of "$list" $TAR)
        sig_size=$(size_of "$list" $SIG)
        if [ -n "$tar_size" ] && [ -n "$sig_size" ]; then card=$c; break; fi
      done
      # the cards can be read and none has the pair: stay stock
      [ -z "$card" ] && [ -n "$listed" ] && break
    fi
  fi
  [ -z "$card" ] && sleep 1
done
if [ -z "$card" ]; then
  say "no $TAR and $SIG on the cards ($(echo $cards)): camera stays stock"
  [ -n "$stopped_live_view" ] && busctl call $V setLiveviewState bbs true false "" >/dev/null 2>&1
  exit 0
fi

rm -rf $WORK; mkdir -p $WORK/unpacked
busctl --timeout=60 call $S File stis "$card/$TAR" 0 "$tar_size" $WORK/$TAR >/dev/null
busctl --timeout=15 call $S File stis "$card/$SIG" 0 "$sig_size" $WORK/$SIG >/dev/null
digest=$(sha256sum <$WORK/$TAR | cut -d' ' -f1)
seal=$(printf '%s\n%s\n%s\n' "$key" "$digest" "$key" | sha256sum | cut -d' ' -f1)
if [ "$seal" != "$(head -n 1 $WORK/$SIG | cut -c1-64)" ]; then
  say "$card/$TAR isn't sealed with this camera's key: not loading it"
  rm -rf $WORK
  [ -n "$stopped_live_view" ] && busctl call $V setLiveviewState bbs true false "" >/dev/null 2>&1
  exit 0
fi
tar -x -f $WORK/$TAR -C $WORK/unpacked || { say "unpacking failed"; exit 1; }
rm -f $WORK/$TAR
say "$card/$TAR ($tar_size bytes) sealed with this camera's key, running its load.sh"
exec sh $WORK/unpacked/load.sh $WORK/unpacked "$card"
