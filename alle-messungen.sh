#!/usr/bin/env bash
# Reproduziert die Messreihen der Folien (Median aus 50 Durchläufen, TCP-Startfenster 32 wie QUIC):
#  ergebnis-ttfb.txt  sehr kleine Seite (nur HTML)  => Time to first byte
#  ergebnis-seite.txt ganze Seite (HTML + CSS + 5 Bilder) => Gesamtladezeit, Zeit je Ressource
# je Verlust 0 / 2 / 5 / 10 % pro Round Trip bei 100 ms RTT. Dauer: ca. 1 Stunde.
cd "$(dirname "$0")"
for L in 0 2 5 10; do ./run.sh -n 50 -l $L -p "/"; echo; done > ergebnis-ttfb.txt 2>&1
for L in 0 2 5 10; do ./run.sh -n 50 -l $L; echo; done > ergebnis-seite.txt 2>&1
