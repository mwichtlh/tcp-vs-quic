#!/usr/bin/env bash
# Misst die Ladezeit einer Seite (HTML + CSS + Bilder) per curl mit HTTP/1.1, HTTP/2 und HTTP/3.
# Aufruf: ./measure.sh <Basis-URL> [Durchläufe] [Pfad ...]
#   ./measure.sh https://server 20
#   ./measure.sh https://example.org 10 / /style.css
# Voraussetzung: curl mit HTTP/3-Unterstützung (sonst wird HTTP/3 übersprungen).
# Jeder Durchlauf = neuer curl-Prozess = neue Verbindung inkl. Handshake. Alle Pfade werden
# parallel geladen (curl --parallel; HTTP/2 und 3 multiplexen über eine Verbindung).
#
# Ausgabe 1 (je Protokoll, in ms):
#   min/median/mean/max/p90  Gesamtladezeit (bis die letzte Ressource komplett da ist)
#   conn_ms              Dauer bis zum fertigen Handshake (Median)
#   ttfb_ms              Time to first byte (Median)
#   erste_ms             Zeit bis zur ersten komplett geladenen Ressource (Median)
# Ausgabe 2: Fertigstellungszeit je Ressource als Median/90. Perzentil.
set -u
CURL_OPTS="${CURL_OPTS:-}"   # optional zusätzliche curl-Optionen, z. B. CURL_OPTS="-4"

TARGET="${1:?Aufruf: $0 <Basis-URL> [Durchläufe] [Pfad ...]}"
RUNS="${2:-20}"
shift 2 2>/dev/null || shift $#
PATHS=("$@")
[ ${#PATHS[@]} -eq 0 ] && PATHS=(/ /style.css /bild1.png /bild2.png /bild3.png /bild4.png /bild5.png)
TARGET="${TARGET%/}"

urls=(); outs=()
for p in "${PATHS[@]}"; do urls+=("$TARGET$p"); outs+=(-o /dev/null); done

# Hinweis: Bei HTTP/1.1 öffnet curl für jede Ressource eine eigene Verbindung (Browser: max. 6 pro Host).
# Eine Begrenzung per --parallel-max würde die Zeiten wartender Transfers verfälschen
# (curl zählt time_total dann erst ab deren Start).
declare -A FLAG=( [HTTP/1.1]=--http1.1 [HTTP/2]=--http2 [HTTP/3]=--http3-only )
HAS_H3=0; curl -V | grep -q HTTP3 && HAS_H3=1

# Warm-up: ARP/DNS-Cache füllen, sonst enthält der erste Durchlauf zusätzliche Wartezeit
curl -sk $CURL_OPTS --max-time 30 -o /dev/null "${urls[0]}" 2>/dev/null || true

RAW=$(mktemp); trap 'rm -f "$RAW"' EXIT
for proto in HTTP/1.1 HTTP/2 HTTP/3; do
  if [ "$proto" = HTTP/3 ] && [ $HAS_H3 -eq 0 ]; then
    echo "$proto: curl ohne HTTP/3, übersprungen" >&2; continue
  fi
  for ((i=0; i<RUNS; i++)); do
    # pro Transfer eine Zeile: URL, appconnect, total, http_code, starttransfer
    res=$(curl -sk $CURL_OPTS --parallel ${FLAG[$proto]} --max-time 30 \
          -w '%{url_effective} %{time_appconnect} %{time_total} %{http_code} %{time_starttransfer}\n' \
          "${outs[@]}" "${urls[@]}" 2>/dev/null) || continue
    # Durchlauf nur werten, wenn alle Antworten 200 sind
    [ "$(echo "$res" | awk '$4==200' | wc -l)" -eq ${#urls[@]} ] || continue
    echo "$res" | awk -v p="$proto" -v r="$i" '{print p, r, $1, $2, $3, $5}' >> "$RAW"
  done
done

echo "Ziel: $TARGET   Pfade: ${PATHS[*]}   Durchläufe: $RUNS"
LC_ALL=C awk -v target="$TARGET" -v paths="${PATHS[*]}" '
function isort(a,n,  i,j,t){ for(i=2;i<=n;i++){t=a[i]; for(j=i-1;j>=1&&a[j]>t;j--)a[j+1]=a[j]; a[j+1]=t} }
function stats(p,met,  n,i,t,s){            # setzt S_min S_med S_mean S_max S_p90 (ms)
  n=cnt[p]; s=0
  for(i=1;i<=n;i++){t[i]=m[p,met,i]; s+=t[i]}
  isort(t,n)
  S_min=t[1]; S_max=t[n]; S_mean=s/n
  S_med=(n%2)? t[(n+1)/2] : (t[n/2]+t[n/2+1])/2
  k=int(0.9*n); if(k<0.9*n)k++; if(k<1)k=1; S_p90=t[k]
}
{ p=$1; r=$2; u=$3; ap=$4; tot=$5; st=$6
  if(!((p,r) in ri)){ cnt[p]++; ri[p,r]=cnt[p] }
  i=ri[p,r]
  if(!((p,"tot",i) in m)){ m[p,"tot",i]=tot; m[p,"conn",i]=ap; m[p,"ttfb",i]=st; m[p,"first",i]=tot }
  else {
    if(tot>m[p,"tot",i])   m[p,"tot",i]=tot
    if(ap>m[p,"conn",i])   m[p,"conn",i]=ap
    if(st<m[p,"ttfb",i])   m[p,"ttfb",i]=st
    if(tot<m[p,"first",i]) m[p,"first",i]=tot
  }
  m[p,"u" substr(u,length(target)+1),i]=tot
}
END {
  np=split("HTTP/1.1 HTTP/2 HTTP/3",P," "); nq=split(paths,Q," ")
  printf "%-9s %4s %9s %9s %9s %9s %9s %9s %9s %9s\n","Protokoll","n","min_ms","median_ms","mean_ms","max_ms","p90_ms","conn_ms","ttfb_ms","erste_ms"
  for(a=1;a<=np;a++){ p=P[a]; if(!cnt[p]){ printf "%-9s %4d\n",p,0; continue }
    stats(p,"tot");  mn=S_min; md=S_med; me=S_mean; mx=S_max; q9=S_p90
    stats(p,"conn"); c=S_med
    stats(p,"ttfb"); f=S_med
    stats(p,"first"); e=S_med
    printf "%-9s %4d %9.0f %9.0f %9.0f %9.0f %9.0f %9.0f %9.0f %9.0f\n",p,cnt[p],mn*1000,md*1000,me*1000,mx*1000,q9*1000,c*1000,f*1000,e*1000 }
  printf "\nFertigstellungszeit je Ressource in ms (Median/P90):\n%-14s","Ressource"
  for(a=1;a<=np;a++) printf " %13s",P[a]
  printf "\n"
  for(b=1;b<=nq;b++){ printf "%-14s",Q[b]
    for(a=1;a<=np;a++){ p=P[a]
      if(!cnt[p]){ printf " %13s","-"; continue }
      stats(p,"u" Q[b]); printf " %13s",sprintf("%.0f/%.0f",S_med*1000,S_p90*1000) }
    printf "\n" }
}' "$RAW"
