#!/usr/bin/env bash
# Misst die Ladezeit einer kleinen Website über HTTP/1.1, HTTP/2 und HTTP/3 (QUIC)
# in einem simulierten Netz (Verzögerung und Paketverlust per tc/netem).

usage() {
cat <<USAGE
Aufruf: $0 [Optionen]

Startet in Docker einen Server (Caddy) und einen Client (curl mit HTTP/3), schaltet
dazwischen ein simuliertes Netz und misst, wie lange das Laden der Seite dauert.

Optionen:
  -n ANZAHL   Durchläufe pro Protokoll (Standard: 20)
  -r MS       Round-Trip-Time in ms (Standard: 100)
  -l PROZENT  Paketverlust je Round Trip in % (Standard: 2)
  -w FENSTER  TCP-Startfenster des Servers in Segmenten (Standard: 32, wie bei QUIC;
              Linux-Standard wäre 10)
  -p PFADE    zu ladende Pfade, durch Leerzeichen getrennt (Standard: HTML, CSS und 5 Bilder)
              Beispiel: -p "/"  lädt nur die sehr kleine HTML-Seite
  -h          diese Hilfe

Ausgabe (je Protokoll, in ms):
  min, median, mean, max, p90  Gesamtladezeit aller Pfade (letzte Ressource komplett da)
  conn_ms                  Dauer bis Handshake fertig (TCP + TLS bzw. QUIC), Median
  ttfb_ms                  Time to first byte, Median
  erste_ms                 Zeit bis zur ersten komplett geladenen Ressource, Median
  Zweite Tabelle: Fertigstellungszeit je Ressource als Median/90. Perzentil. Das P90
  zeigt, wie stark einzelne Durchläufe ausreißen (z. B. durch Paketverlust).

Beispiele:
  $0                              # Standard: 100 ms RTT, 2 % Verlust, 20 Durchläufe
  $0 -l 0                         # ohne Paketverlust
  $0 -r 20 -l 5 -n 50             # 20 ms RTT, 5 % Verlust, 50 Durchläufe
  $0 -p "/" -l 0                  # nur HTML: Time to first byte = 3 RTT (TCP+TLS) bzw. 2 RTT (QUIC)
  $0 -w 10                        # TCP mit Linux-Standardfenster (10 statt 32 Segmente)

Hinweise:
  - Voraussetzung: Docker (laufender Daemon). Der erste Aufruf baut die Images
    und kann einige Minuten dauern (curl wird mit HTTP/3-Unterstützung gebaut).
  - Der Verlust wird je Richtung zur Hälfte angewendet (-l 2 => 1 % hin, 1 % zurück),
    die Verzögerung ebenfalls (-r 100 => 50 ms je Richtung).
  - Jede Messung baut neue Verbindungen auf (kein Wiederverwenden). Bei Verlust
    schwanken die Werte stark, deshalb den Median betrachten und -n erhöhen.
  - Inhalte der Testseite: Verzeichnis www/ (HTML, CSS, Bild). Eigene Dateien
    dort ablegen und mit -p laden.
USAGE
}

RUNS=20; RTT=100; LOSS=2; CWND=32; PATHS_ARG="/ /style.css /bild1.png /bild2.png /bild3.png /bild4.png /bild5.png"
while getopts ":n:r:l:w:p:h" opt; do
  case $opt in
    n) RUNS=$OPTARG ;;
    r) RTT=$OPTARG ;;
    l) LOSS=$OPTARG ;;
    w) CWND=$OPTARG ;;
    p) PATHS_ARG=$OPTARG ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG braucht einen Wert." >&2; usage >&2; exit 1 ;;
    \?) echo "Unbekannte Option: -$OPTARG" >&2; usage >&2; exit 1 ;;
  esac
done

num='^[0-9]+([.][0-9]+)?$'
for v in "$RUNS" "$RTT" "$LOSS" "$CWND"; do
  [[ $v =~ $num ]] || { echo "Ungültiger Zahlenwert: $v" >&2; exit 1; }
done
awk -v l="$LOSS" 'BEGIN{exit !(l<100)}' || { echo "Verlust muss kleiner als 100 % sein." >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker nicht gefunden." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker-Daemon läuft nicht." >&2; exit 1; }

set -euo pipefail
cd "$(dirname "$0")"
DELAY_MS=$(LC_ALL=C awk -v r="$RTT" 'BEGIN{print r/2}')
LOSS_DIR=$(LC_ALL=C awk -v l="$LOSS" 'BEGIN{print l/2}')

docker build -q --target server -t quic-server . >/dev/null
docker build -q --target client -t quic-client . >/dev/null
docker network inspect quic-net >/dev/null 2>&1 || docker network create quic-net >/dev/null
docker rm -f server >/dev/null 2>&1 || true
cleanup() { docker rm -f server >/dev/null 2>&1 || true; docker network rm quic-net >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name server --network quic-net --network-alias server --cap-add NET_ADMIN \
  -e DELAY_MS="$DELAY_MS" -e LOSS_PCT="$LOSS_DIR" -e INITCWND="$CWND" quic-server >/dev/null
sleep 4
echo "RTT ${RTT} ms, Verlust ${LOSS} % je Round Trip, TCP-Startfenster ${CWND}, Pfade: ${PATHS_ARG}"
# PATHS_ARG bewusst ohne Anführungszeichen: wird in einzelne Pfade zerlegt
# shellcheck disable=SC2086
docker run --rm --network quic-net --cap-add NET_ADMIN \
  -e DELAY_MS="$DELAY_MS" -e LOSS_PCT="$LOSS_DIR" quic-client /measure.sh https://server "$RUNS" $PATHS_ARG
