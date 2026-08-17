# plex-vaapi-tonemap

Plex-Media-Server-Images, die **VAAPI-Tonemapping statt OpenCL** verwenden,
damit HDR→SDR-Transkodierung auf Intel-Arc-Grafikkarten funktioniert.

## Das Problem

Auf Intel-Arc-Karten kann Plex kein OpenCL-Gerät öffnen:

```
[AVHWDeviceContext] Failed to get number of OpenCL platforms: -1001.
```

Und zwar obwohl die OpenCL-Umgebung im selben Container einwandfrei arbeitet —
`clinfo` meldet die Karte ohne Beanstandung:

```
Number of platforms   1
  Platform Name       Intel(R) OpenCL Graphics
  Device Name         Intel(R) Arc(TM) A310 LP Graphics
  Device Type         GPU
```

Weil `tonemap_opencl` scheitert, liefert Plex HDR-Material am Ende **ohne
Tonemapping** aus. Auf einem SDR-Bildschirm sieht das grell überstrahlt aus,
ausgebleicht ins Gelbgrüne, Gesichter verlieren jede Zeichnung.

Das ist ein alter Plex-Fehler, [seit Plex 1.22 gemeldet](https://forums.plex.tv/t/pms-bug-hardware-accelerated-hdr-tone-mapping-broken-again-opencl-is-broken-in-plex-but-not-in-system/732462)
(„OpenCL is broken in Plex but not in system"). Die einzige dort dokumentierte
Lösung ist ein Downgrade auf 1.22.0.4163 — eine fünf Jahre alte Fassung. Der
übliche Rat lautet, HDR-Tonemapping ganz abzuschalten; das tauscht ein kaputtes
Bild gegen ein flaues.

### Was die Ursache *nicht* ist

Alles einzeln geprüft und ausgeschlossen:

| Verdacht | Befund |
|---|---|
| Die Mediendateien | Farbtags korrekt (`bt2020nc`/`smpte2084`/`bt2020`, 10 bit) |
| Die Grafikkarte | `tonemap_opencl` läuft außerhalb von Plex auf denselben Karten |
| AV1-Dekodierung | VAAPI-Ergebnis bit-identisch zur Software-Dekodierung |
| Die OpenCL-Treiberversion | Austausch von Plex' Runtime ändert nichts |
| Das Container-Image | `binhex/arch-plex` und `linuxserver/plex` scheitern gleich |

Der Fehler steckt in Plex' Transcoder-Binary selbst.

## Die Lösung

Plex bringt `tonemap_vaapi` mit, und die Karte beherrscht es einwandfrei — Plex
benutzt es nur nie. Dieses Image legt einen Wrapper um den Plex-Transcoder, der
den OpenCL-Zweig der Filterkette umschreibt, bevor das echte Binary sie sieht:

```
[2]hwmap=derive_device=opencl[3];[3]tonemap_opencl=tonemap=hable:format=nv12:m=bt709:p=bt709:r=tv[4];[4]hwmap=derive_device=vaapi:reverse=1[5]
```

wird zu

```
[2]tonemap_vaapi=format=nv12:matrix=bt709:primaries=bt709:transfer=bt709[5]
```

Alles andere — Skalierung, eingebrannte Untertitel über `overlay_vaapi`, Ton,
Ausgabeoptionen — wird unverändert durchgereicht. Enthält ein Aufruf kein
`tonemap_opencl`, geht er wortgleich weiter.

## Verwendung

Auf dem bisherigen Plex-Image aufbauen:

```bash
# binhex (Vorgabe)
docker build -t plex-vaapi-tonemap .

# linuxserver
docker build --build-arg BASE_IMAGE=lscr.io/linuxserver/plex:latest -t plex-vaapi-tonemap .
```

Danach genau wie das bisherige Plex-Image betreiben — gleiche Einbindungen,
gleiche Umgebung, gleiches appdata. An Plex' Konfiguration ändert sich nichts.

Voraussetzungen:

* Eine Intel-GPU mit VAAPI-Tonemapping (getestet auf Arc A310)
* `/dev/dri` in den Container durchgereicht
* **HDR-Tonemapping in Plex eingeschaltet**: *Einstellungen → Transcoder → HDR-
  Tonemapping aktivieren*. Der Wrapper hat nur dann etwas umzuschreiben, wenn
  Plex überhaupt Tonemapping anfordert.

Optionales Protokoll jeder Umschreibung:

```bash
-e PLEX_TONEMAP_LOG=/config/tonemap-wrapper.log
```

## Nachweis

Füttert man den Wrapper mit Plex' originaler OpenCL-Filterkette — jener, die mit
`-1001` scheitert — entsteht ein Bild, das **bit-identisch** zu einem manuellen
`tonemap_vaapi`-Lauf ist:

```
b441e9830364ccd4c15862e4e1cb8bf3  Ausgabe des Wrappers
b441e9830364ccd4c15862e4e1cb8bf3  manuelles tonemap_vaapi
```

## Aktuell bleiben

Fertige Images liegen in der GitHub Container Registry und werden **täglich neu
gebaut**:

```
ghcr.io/sparxx947/plex-vaapi-tonemap:latest               # auf Basis binhex/arch-plex
ghcr.io/sparxx947/plex-vaapi-tonemap:latest-linuxserver   # auf Basis linuxserver/plex
```

Da das Image `FROM` dem Upstream-Plex-Image gebaut wird, übernimmt jeder
nächtliche Neubau die Plex-Fassung, die Upstream gerade ausliefert. Das Image zu
ziehen ist damit gleichbedeutend mit einem Plex-Update — die gewohnte
Container-Aktualisierung greift unverändert weiter, es ist nichts Zusätzliches
nötig.

Jeder Build prüft vor der Freigabe, dass der Wrapper wirklich sitzt: Das
Original muss als `.orig` vorhanden sein, an seiner Stelle das Wrapper-Skript
stehen, und dieses muss die Umschreiberegel enthalten. Ein fehlgeschlagener Bau
bricht ab, statt stillschweigend ein Plex ohne die Reparatur auszuliefern.

Wer lokal baut, baut immer dann neu, wenn er sonst Plex aktualisieren würde.

## Grenzen

* `tonemap_vaapi` nutzt Intels Fixed-Function-LUT und kennt keinen einstellbaren
  Algorithmus. Plex' Einstellung *Tonemapping Algorithm* (`hable`, `reinhard`, …)
  bleibt bei aktivem Wrapper wirkungslos.
* Nur Intel unter Linux. AMD und NVIDIA sind davon nicht berührt.
* Aktualisiert sich Plex im Container, muss das Image neu gebaut werden, damit
  der Wrapper auf dem neuen Binary sitzt.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
