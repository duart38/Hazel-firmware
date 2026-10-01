#!/bin/sh
# Every 15 s, write "cpu image-chip sensor" temperatures (degrees C) to /tmp/x1d/temps, for the
# live-view readout (filmhook.c) and `x.sh temp`. The processor's is read directly; the image
# chip (FPGA) and sensor unit (SPC) are only in the system manager's log, once a minute.
# Started by `x.sh temps` (and tools/cam setup).
while true; do
  cpu=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
  log=$(journalctl --no-pager -n 60 -o cat -u system-manager 2>/dev/null)
  chip=$(echo "$log" | sed -n 's/.*FPGA temp: *\([0-9]*\).*/\1/p' | tail -n 1)
  sensor=$(echo "$log" | sed -n 's/.*SPC temp: *\([0-9]*\).*/\1/p' | tail -n 1)
  echo "$cpu ${chip:-0} ${sensor:-0}" >/tmp/x1d/temps.part && mv /tmp/x1d/temps.part /tmp/x1d/temps
  sleep 15
done
