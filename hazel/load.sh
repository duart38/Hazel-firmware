#!/bin/sh
# Hazel, set up from the card: what `tools/cam setup` does from the Mac, run on the camera.
# The card setup: `tools/cam bundle` packs this folder and Catkin (the loader) seals it into
# CATKIN.TAR at the top of the card. At startup Catkin checks the seal, unpacks it and runs
#   sh load.sh <unpacked folder> <card, e.g. /SD0>
#  - moves the files into /tmp/x1d, where everything else expects them
#  - the recipe slots: from the card's HAZEL/recipes (written by the app), else the copies
#    packed with this file
#  - the slot and film look chosen last time: /media/data/x1d/active and look (slots.sh keeps them)
#  - the live-view hook, the Extras menu page and the playback looks, through /run drop-ins, then
#    restarts both services
#  - debug logging (off unless switched on last time, or the card has a HAZEL-DEBUG file)
#  - the sidecar writer, the temperature reader, the slot keeper and debug.sh in the background
# Log: /tmp/catkin.log (the loader sends it there).
say() { echo "$(date +%T) $*"; }
from=$1
card=$2
if [ "$from" != /tmp/x1d ]; then rm -rf /tmp/x1d; cp -a "$from" /tmp/x1d || exit 1; fi
cd /tmp/x1d || exit 1
say "film setup $(cat VERSION 2>/dev/null)"
X=/tmp/x1d/x.sh
KEEP=/media/data/x1d
chmod 755 ./*.sh fbscore unb64 ./*.so

sh slots.sh refresh "$card"

active=$(cat $KEEP/active 2>/dev/null)
[ -n "$active" ] && [ ! -f "slots/$active.txt" ] && active=""
[ -z "$active" ] && active=$(ls slots 2>/dev/null | sed -n 's/^\(C[1-7]\)\.txt$/\1/p' | head -n 1)
look=$(cut -c1 $KEEP/look 2>/dev/null)
[ -z "$look" ] && look=f
echo "$active" >active
if [ -n "$active" ]; then
  cp "slots/$active.txt" recipe
else
  look=n
fi
echo "$look" >look
say "slot ${active:-none}, look $look"

# debug logging: as last time, or on when the card has a HAZEL-DEBUG (or HAZEL-DEBUG.TXT) at the top
debug=$(cut -c1-2 $KEEP/debug 2>/dev/null)
[ "$debug" = on ] || debug=off
if busctl --timeout=15 call --system com.hasselblad.storage / com.hasselblad.storage Browse sii "$card" 0 200 2>/dev/null |
   tr '"' '\n' | grep -qixE 'HAZEL-DEBUG(\.TXT)?'; then
  debug=on
  say "HAZEL-DEBUG on the card: debug logging on"
fi
mkdir -p $KEEP
echo $debug >debug
echo $debug >$KEEP/debug
say "debug logging $debug"

D=/run/systemd/system/video-daemon.service.d; mkdir -p $D
printf "[Service]\nEnvironment=LD_PRELOAD=/tmp/x1d/libfilmhook.so\n" >$D/film.conf
# the interface gets the Extras menu page and the playback looks (photos shown with their sidecar's look)
D=/run/systemd/system/victory-gui.service.d; mkdir -p $D
printf "[Service]\nEnvironment=\"LD_PRELOAD=/tmp/x1d/libfilmgui.so /tmp/x1d/libplayhook.so\"\n" >$D/film.conf
systemctl daemon-reload
systemctl restart video-daemon
systemctl restart victory-gui
sleep 4
gui=$(pidof victory-gui)
say "hook loaded: $($X hooked), menu page loaded: $(grep -c filmgui /proc/$gui/maps 2>/dev/null), playback looks loaded: $(grep -c playhook /proc/$gui/maps 2>/dev/null)"

$X sidecar
$X temps
for pid in $(ps | grep -E "[s]lots.sh watch|[d]ebug.sh watch" | awk '{print $1}'); do kill $pid; done
(sh /tmp/x1d/slots.sh watch >>/tmp/x1d/slots.log 2>&1 &)
(sh /tmp/x1d/debug.sh watch >>/tmp/x1d/debug.out 2>&1 &)
say "load.sh done"
