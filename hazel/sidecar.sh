#!/bin/sh
# Writes the active look next to every new photo on the card: B0000001.3FR -> B0000001.look
# Listens for the storage service's "Added" signal. Runs from /tmp, so a restart stops it.
# Log: /tmp/x1d/sidecar.log. Manual: sidecar.sh --write <card folder> <photo name>
S="--system com.hasselblad.storage / com.hasselblad.storage"

write_sidecar() {
  dir=$1; photo=$2
  case "$photo" in
    *.3FR|*.3fr|*.JPG|*.jpg) ;;
    *) return ;;   # includes our own .look files, which also raise "Added"
  esac
  out=/tmp/x1d/sidecar.txt
  look=$(cut -c1 /tmp/x1d/look 2>/dev/null)
  number=$(echo "$photo" | tr -cd 0-9 | sed 's/^0*//')   # leading zeros would read as octal
  {
    echo "x1d-look = 1"
    echo "photo = $photo"
    echo "written = $(date -u '+%Y-%m-%d %H:%M:%S')"
    # the camera's shell does 32-bit arithmetic: keep every step below 2^31
    echo "seed = $(( ($(date +%s) % 1000003) * 2003 + $$ + ${number:-0} % 100000 ))"
    case "$look" in
      # the recipe without its notes (the "#" lines after the name), which can be long
      f) echo "look = recipe"; grep -v '^seed' /tmp/x1d/recipe | awk 'NR == 1 || !/^#/' ;;
      b) echo "look = mono"; echo "mono = 1" ;;
      *) echo "look = none" ;;
    esac
  } >$out
  # The storage service never shortens a file it overwrites, so every sidecar is exactly
  # 1024 bytes, padded with blank lines (which the recipe reader skips).
  count=$(wc -c <$out)
  if [ "$count" -gt 1024 ]; then echo "$(date -u '+%H:%M:%S') FAILED $photo: sidecar over 1024 bytes"; return; fi
  while [ "$count" -lt 1024 ]; do echo >>$out; count=$((count + 1)); done
  # BusyBox od only offers octal: convert each byte to decimal for busctl's "ay"
  bytes=""
  for o in $(od -v -b $out | sed 's/^[0-7]*//'); do bytes="$bytes $((0$o))"; done
  if busctl --timeout=20 call $S WriteFile ayts $count $bytes 0 "$dir/${photo%.*}.look" >/dev/null; then
    echo "$(date -u '+%H:%M:%S') $dir/${photo%.*}.look ($count bytes, look $look)"
  else
    echo "$(date -u '+%H:%M:%S') FAILED $dir/${photo%.*}.look"
  fi
}

# Manual mode for a photo already on the card: sidecar.sh --write /SD1/DCIM/100HASBL B0000002.3FR
if [ "$1" = --write ]; then write_sidecar "$2" "$3"; exit; fi

want=""
dbus-monitor --system "type=signal,interface=com.hasselblad.storage,member=Added" | while read -r line; do
  case "$line" in
    *member=Added*) want=dir ;;
    string\ \"*|variant*string\ \"*)
      value=${line#*string \"}; value=${value%\"}
      case "$want" in
        dir) dir=$value; want=key ;;
        key) [ "$value" = name ] && want=name ;;
        name) write_sidecar "$dir" "$value"; want="" ;;
      esac ;;
  esac
done
