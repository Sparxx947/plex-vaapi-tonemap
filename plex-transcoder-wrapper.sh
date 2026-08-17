#!/bin/bash
# Plex Transcoder Wrapper — VAAPI-Tonemapping statt OpenCL
#
# Warum: Plex' Transcoder kann auf Intel-Arc-Karten kein OpenCL-Gerät oeffnen
# ("Failed to get number of OpenCL platforms: -1001"), obwohl clinfo die Karte
# im selben Container einwandfrei findet. Folge: tonemap_opencl scheitert und
# HDR wird ungemappt als SDR ausgegeben -> grell ueberstrahltes Bild.
#
# Was der Wrapper tut: Er schreibt in der -filter_complex-Kette den
# OpenCL-Zweig auf den VAAPI-Filter um, den dieselbe Karte problemlos kann:
#
#   [x]hwmap=derive_device=opencl[a];[a]tonemap_opencl=...[b];[b]hwmap=derive_device=vaapi:reverse=1[y]
#     ->  [x]tonemap_vaapi=format=<fmt>:matrix=<m>:primaries=<p>:transfer=<p>[y]
#
# Alles andere wird unveraendert durchgereicht.

REAL="/usr/lib/plexmediaserver/Plex Transcoder.orig"
LOG="${PLEX_TONEMAP_LOG:-}"

args=()
umgeschrieben=0

for a in "$@"; do
  if [[ "$a" == *"tonemap_opencl"* ]]; then
    neu=$(printf '%s' "$a" | sed -E '
      s/\[([^]]+)\]hwmap=derive_device=opencl\[[^]]+\];\[[^]]+\]tonemap_opencl=[^][]*\bformat=([A-Za-z0-9]+)[^][]*\[[^]]+\];\[[^]]+\]hwmap=derive_device=vaapi:reverse=1\[([^]]+)\]/[\1]tonemap_vaapi=format=\2:matrix=bt709:primaries=bt709:transfer=bt709[\3]/g
    ')
    if [[ "$neu" != "$a" ]]; then
      umgeschrieben=1
      a="$neu"
    fi
  fi
  args+=("$a")
done

if [[ -n "$LOG" ]]; then
  {
    printf '%s tonemap-umgeschrieben=%s\n' "$(date '+%F %T')" "$umgeschrieben"
    [[ $umgeschrieben -eq 1 ]] && printf '  neu: %s\n' "${args[@]}" | grep -m1 tonemap_vaapi
  } >> "$LOG" 2>/dev/null
fi

exec "$REAL" "${args[@]}"
