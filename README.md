# QUIC-Messung

Vergleicht die Ladezeit einer kleinen Website über HTTP/1.1, HTTP/2 (TCP + TLS 1.3) und HTTP/3 (QUIC) bei einstellbarer RTT und einstellbarem Paketverlust.

Zwei Docker-Container, Server (Caddy) und Client (curl 8.14.1 mit ngtcp2/nghttp3). Auf beiden läuft `tc netem`, das Verzögerung und Verlust je Richtung zur Hälfte anwendet. `-l 2` heißt also 1 % hin und 1 % zurück. Das Zertifikat ist selbstsigniert, der Client prüft es nicht.

## Benutzung

Docker muss laufen. Der erste Aufruf baut curl und dauert ein paar Minuten.

```
./run.sh                    # 100 ms RTT, 2 % Verlust, 20 Läufe je Protokoll
./run.sh -l 0 -n 50         # ohne Verlust, 50 Läufe
./run.sh -p "/" -l 0        # nur HTML (Time to first byte)
./run.sh -w 10              # TCP-Startfenster 10 statt 32
./alle-messungen.sh         # beide Messreihen neu erzeugen, ca. 1 h
```

Optionen: `-n` Läufe, `-r` RTT in ms, `-l` Verlust in %, `-w` TCP-Startfenster (Standard 32, wie QUIC), `-p` Pfade.

## Dateien

- `run.sh` baut und startet alles, `measure.sh` misst und wertet aus (läuft im Client)
- `alle-messungen.sh` schreibt `ergebnis-ttfb.txt` (nur HTML) und `ergebnis-seite.txt` (HTML, CSS, 5 Bilder)
- `Dockerfile`, `Caddyfile`, `entrypoint-netem.sh` für die Container
- `www/` ist die Testseite

## Messung

Jeder Lauf baut eine neue Verbindung auf, ohne 0-RTT. Alle Ressourcen werden parallel geladen. Gewertet werden nur Läufe, in denen alle Antworten 200 sind. Ausgegeben werden Gesamtladezeit (min, Median, Mittel, max, P90), Handshake-Dauer, Time to first byte und die Fertigstellungszeit je Ressource.

## Ergebnisse

Median aus 50 Läufen, RTT 100 ms, Zeiten in ms.

| Verlust | TTFB HTTP/2 | TTFB HTTP/3 | CSS HTTP/2 | CSS HTTP/3 | Gesamt HTTP/2 | Gesamt HTTP/3 |
|---|---|---|---|---|---|---|
| 0 % | 318 | 218 | 534 | 459 | 644 | 544 |
| 2 % | 321 | 220 | 645 | 463 | 751 | 640 |
| 5 % | 321 | 220 | 646 | 578 | 957 | 1002 |
| 10 % | 322 | 218 | 796 | 758 | 1645 | 1423 |

- Time to first byte: 3 RTT bei TCP + TLS 1.3, 2 RTT bei QUIC. Der Unterschied von etwa 100 ms ist der eingesparte Handshake und hängt nicht vom Verlust ab.
- Beim CSS ist HTTP/3 bei 2 % Verlust deutlich schneller (P90 639 gegen 955 ms), bei 10 % ist der Abstand kleiner als die Streuung.
- Bei der Gesamtladezeit ist HTTP/3 bei 5 % Verlust nicht schneller.

Die Rohwerte inklusive HTTP/1.1 stehen in den `ergebnis-*.txt`.

## Einschränkungen

- Simuliertes Netz auf einem Rechner, ohne gemeinsamen Engpass. Der Verlust ist zufällig und gleichverteilt.
- Nur curl. Browser verhalten sich anders.
- curl öffnet bei HTTP/1.1 je Ressource eine Verbindung, das kostet hier fast nichts. Deshalb ist HTTP/1.1 bei 0 % Verlust am schnellsten und nur als Referenz zu lesen.
- Bei Verlust streuen die Werte stark. Für belastbare Zahlen `-n` erhöhen.
- `caddy:alpine` und `alpine:edge` sind nicht auf eine Version festgelegt.
