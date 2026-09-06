# Flash — app icon

**Cutout, teal, circle.** One fixed icon — no theme switching. A teal gradient disc with the
bolt cut into it.

Bolt path (512×512 art space, use this everywhere):

    M317 44 L144 286 L231 292 L198 468 L376 202 L287 198 Z

## Values

| Role | Value |
|---|---|
| Gradient start | `#8FEFD7` |
| Gradient end | `#14A08B` |
| Gradient axis | top-left → bottom-right, `x2="0.35" y2="1"` |
| Bolt (shipped) | `#0E1112` |
| Bolt (on dark surfaces) | `#F5F7F4` |
| Canvas | circle, full-bleed |

## Files

    svg/flash-teal-dark.svg     ← the icon. Ships everywhere.
    svg/flash-teal-light.svg    off-white bolt, for placing the mark on dark surfaces
    svg/flash-teal-open.svg     true knock-out, transparent bolt — web only
    svg/flash-mono.svg          white silhouette, Android themed icons
    png/flash-teal-dark-<48|72|96|144|192|512|1024>.png
    png/flash-teal-light-<48|72|96|144|192|512>.png
    png/flash-teal-open-<48|96|192|512|1024>.png
    png/flash-mono-<48|72|96|144|192|512>.png
    android/…

## Android install

Copy into `android/app/src/main/res/`:

    drawable/ic_launcher_background.xml
    drawable/ic_launcher_foreground.xml
    drawable/ic_launcher_monochrome.xml
    mipmap-anydpi-v26/ic_launcher.xml

Point `mipmap-anydpi-v26/ic_launcher_round.xml` at the same adaptive-icon XML. For API < 26,
drop the legacy PNGs in as `mipmap-<density>/ic_launcher.png`:

| Density | File |
|---|---|
| mdpi | `flash-teal-dark-48.png` |
| hdpi | `flash-teal-dark-72.png` |
| xhdpi | `flash-teal-dark-96.png` |
| xxhdpi | `flash-teal-dark-144.png` |
| xxxhdpi | `flash-teal-dark-192.png` |

Play Store listing: `flash-teal-dark-1024.png`.

The art sits on the centre 72dp of the 108dp canvas, keeping the bolt inside the 66dp safe
zone on every launcher mask.

## Two things baked in

**The cut is filled, not open.** Adaptive icons composite foreground *over* background, so a
true knock-out can only live inside one layer — that costs the parallax, and One UI draws its
own opaque backdrop straight through the hole. Filling the bolt with `#0E1112` keeps the
silhouette identical and works on every launcher. `svg/flash-teal-open.svg` is the
transparent version, for the website and marketing only.

**No amber glint.** At 48px the sliver was under two pixels. If you want it on the website
hero, it is a copy of the bolt path offset by `(-18, -9)` in `#F59E42`, masked to the bolt.

## Light and dark

The launcher icon does not follow the system theme on Android, so `flash-teal-dark` ships in
both modes — the near-black bolt reads on light and dark wallpapers alike. `flash-teal-light`
is for the mark on dark in-app surfaces and a dark website header, where a near-black bolt
would disappear.

## In-app and web

- Bottom-nav "Flash" tab: the bare bolt path in the theme's primary colour, no disc — so the
  tab still follows the user's chosen palette even though the launcher icon doesn't.
- Favicon: `svg/flash-teal-dark.svg`, with `png/flash-teal-dark-48.png` as fallback.
- Website lockup: mark at cap-height beside "Flash" in a bold grotesque, 14px gap.
