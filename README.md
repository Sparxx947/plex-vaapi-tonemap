# plex-vaapi-tonemap

Plex Media Server images that use **VAAPI tone mapping instead of OpenCL**, so
that HDR→SDR transcoding works on Intel Arc GPUs.

## The problem

On Intel Arc cards, Plex Media Server cannot open an OpenCL device:

```
[AVHWDeviceContext] Failed to get number of OpenCL platforms: -1001.
```

This happens even though the OpenCL runtime in the very same container is
perfectly healthy — `clinfo` reports the card without complaint:

```
Number of platforms   1
  Platform Name       Intel(R) OpenCL Graphics
  Device Name         Intel(R) Arc(TM) A310 LP Graphics
  Device Type         GPU
```

Because `tonemap_opencl` fails, Plex ends up delivering HDR content **without
tone mapping**. On an SDR display the picture looks blown out and washed into
yellow-green, with faces losing all detail.

This is a long-standing Plex regression, [reported since Plex 1.22](https://forums.plex.tv/t/pms-bug-hardware-accelerated-hdr-tone-mapping-broken-again-opencl-is-broken-in-plex-but-not-in-system/732462)
("OpenCL is broken in Plex but not in system"). The only fix documented there is
downgrading to 1.22.0.4163 — a five year old build. The usual advice is to turn
HDR tone mapping off entirely, which trades a broken picture for a flat one.

### What is *not* the cause

Each of these was tested and ruled out:

| Suspect | Verdict |
|---|---|
| The media files | Colour tags correct (`bt2020nc`/`smpte2084`/`bt2020`, 10 bit) |
| The GPU | `tonemap_opencl` runs fine on the same cards outside Plex |
| AV1 decoding | VAAPI output bit-identical to software decoding |
| The OpenCL runtime version | Replacing Plex' bundled runtime changes nothing |
| The container image | `binhex/arch-plex` and `linuxserver/plex` fail identically |

The fault is in Plex' transcoder binary itself.

## The fix

Plex ships `tonemap_vaapi` and the GPU handles it perfectly — Plex just never
uses it. This image wraps the Plex Transcoder with a script that rewrites the
OpenCL branch of the filter chain before handing it to the real binary:

```
[2]hwmap=derive_device=opencl[3];[3]tonemap_opencl=tonemap=hable:format=nv12:m=bt709:p=bt709:r=tv[4];[4]hwmap=derive_device=vaapi:reverse=1[5]
```

becomes

```
[2]tonemap_vaapi=format=nv12:matrix=bt709:primaries=bt709:transfer=bt709[5]
```

Everything else — scaling, subtitle burn-in via `overlay_vaapi`, audio, output
options — is passed through untouched. If a command line contains no
`tonemap_opencl`, it is forwarded verbatim.

## Usage

Build on top of your current Plex image:

```bash
# binhex (default)
docker build -t plex-vaapi-tonemap .

# linuxserver
docker build --build-arg BASE_IMAGE=lscr.io/linuxserver/plex:latest -t plex-vaapi-tonemap .
```

Then run it exactly like your previous Plex image — same volumes, same
environment, same appdata. Nothing about Plex' configuration changes.

Requirements:

* An Intel GPU with VAAPI tone mapping support (tested on Arc A310)
* `/dev/dri` passed into the container
* **HDR tone mapping enabled** in Plex: *Settings → Transcoder → Enable HDR tone
  mapping*. The wrapper only has something to rewrite when Plex asks for tone
  mapping in the first place.

Optional debug log of every rewrite:

```bash
-e PLEX_TONEMAP_LOG=/config/tonemap-wrapper.log
```

## Verification

Feeding the wrapper Plex' original OpenCL filter chain — the one that fails with
`-1001` — produces an image **bit-identical** to a manual `tonemap_vaapi` run:

```
b441e9830364ccd4c15862e4e1cb8bf3  wrapper output
b441e9830364ccd4c15862e4e1cb8bf3  manual tonemap_vaapi
```

## Staying up to date

Prebuilt images are published to GitHub Container Registry and **rebuilt daily**:

```
ghcr.io/sparxx947/plex-vaapi-tonemap:latest               # based on binhex/arch-plex
ghcr.io/sparxx947/plex-vaapi-tonemap:latest-linuxserver   # based on linuxserver/plex
```

Because the image is built `FROM` the upstream Plex image, each nightly rebuild
picks up whatever Plex version upstream currently ships. Pulling the image is
therefore the same as updating Plex — your normal container update routine keeps
working, no special handling required.

Every build verifies that the wrapper is actually in place before the tag is
considered good: the original binary must exist as `.orig`, the replacement must
be the wrapper script, and it must contain the rewrite rule. A broken build
fails instead of quietly shipping a Plex without the fix.

If you build locally instead, rebuild whenever you would otherwise update Plex.

## Limitations

* `tonemap_vaapi` uses Intel's fixed-function LUT. It has no tunable algorithm,
  so Plex' *Tonemapping Algorithm* setting (`hable`, `reinhard`, …) has no
  effect once the wrapper is active.
* Intel/Linux only. AMD and NVIDIA are untouched by this.
* When Plex updates inside the container, rebuild the image so the wrapper is
  reapplied to the new binary.

## License

MIT — see [LICENSE](LICENSE).

German documentation: [README.de.md](README.de.md)
