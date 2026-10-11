# Local Latin Font Readiness — 2026-10-11

## Recommendation

Use the existing system file `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` as the Latin sans candidate for a later implementation. It is a regular/Book face, resolves from `sans-serif` on this host, and the existing screenshot helper already points to it by default. The repository currently has no Latin font asset; this is a local source candidate only and was not copied into the project.

| Property | Observed value |
| --- | --- |
| Absolute path | `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` |
| Debian package | `fonts-dejavu-core` `2.37-2build1` |
| Size | 757,076 bytes |
| SHA-256 | `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648` |
| Font family / subfamily | `DejaVu Sans` / `Book` |
| Version / PostScript name | `2.37` / `DejaVuSans` |
| `fontTools` cmap union | 5,955 code points |
| Printable ASCII U+0020–U+007E | 95/95 |
| Printable Latin-1 U+00A0–U+00FF | 96/96 |
| Latin Extended-A U+0100–U+017F | 128/128 |
| Checked common UI punctuation | 11/11: Euro, en/em dash, curly quotes, ellipsis, minus, NBSP, bullet |
| OpenType `OS/2.fsType` | 0 (no embedding restriction bit set; license terms still apply) |

Inspection used `fontTools` 4.62.1 on the font's actual name and cmap tables. `fc-match sans-serif` resolves to this DejaVu Sans file on this machine. `test/support/widget_polish_screenshot_font.dart` also uses this absolute path as its default Latin screenshot font. These are local metadata and source observations; no browser rendering or shipped-app behavior was verified.

## Existing CJK fallback

Keep the repository's existing CJK fallback at `assets/fonts/DroidSansFallbackFull.ttf` unchanged. Its embedded family is `Droid Sans Fallback`, style `Regular`; its cmap has 28,601 code points but only 1/95 printable ASCII characters (space). This confirms it is not a Latin fallback by itself.

| Property | Observed value |
| --- | --- |
| Absolute path | `/home/ubuntu/duoyi/assets/fonts/DroidSansFallbackFull.ttf` |
| Size | 4,033,420 bytes |
| SHA-256 | `acb6440a713d880a13a21b468ba7cd43f5a2b2934972e51be791c880730777b8` |
| License source | `/usr/share/doc/fonts-droid-fallback/copyright` |
| Installed package | `fonts-droid-fallback` `1:6.0.1r16-1.1build1`; Debian copyright identifies the font files as Apache-2.0 |

The existing family registration is in `pubspec.yaml`, and the current `sans-serif` plus CJK fallback configuration is in `lib/core/app_brand.dart`. The static contract is recorded by `test/core/web_cjk_font_static_test.dart`.

## DejaVu license provenance and notice requirements

The installed package is `fonts-dejavu-core` `2.37-2build1`. Its full Debian copyright/license source is `/usr/share/doc/fonts-dejavu-core/copyright`; that file identifies the upstream source as <https://dejavu-fonts.github.io/> and licenses the font files under the Bitstream Vera permission notice. The font's own OpenType name record 13 also carries the full notice text, including the Arev attribution and terms; name record 14 points to the older URL `http://dejavu.sourceforge.net/wiki/index.php/License`.

For a later redistribution of this unmodified TTF, retain the complete font copyright and permission notices from the package's `copyright` file and the embedded name record 13 in the app's third-party notices. In particular, the Bitstream Vera notice permits reproduction and distribution when its copyright, trademark, and permission notice are included; it allows inclusion in a larger software package but bars selling the typeface by itself. The notice requires a modified font to be renamed so its name does not contain “Bitstream” or “Vera”. The embedded Arev notice attributes imported glyphs to Tavmjong Bah and carries its own permission notice and naming/advertising conditions. Do not edit or subset the candidate under this readiness result.

The unmodified DejaVu family name does not contain those reserved names. The relevant sources to preserve with any later asset are:

- `/usr/share/doc/fonts-dejavu-core/copyright` — complete installed package copyright and Bitstream Vera terms.
- The complete OpenType name ID 13 legal notice in `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` — includes Bitstream Vera and Arev notices.
- Upstream source identified by the package: <https://dejavu-fonts.github.io/>.

This is a local readiness record, not an implementation or browser verification. No font was installed, downloaded, copied, or changed; no `assets/`, `pubspec.yaml`, or app source file was edited.

## Local inventory checked

- `assets/fonts/` contains only `DroidSansFallbackFull.ttf` as a font binary.
- Under `test/`, no bundled TTF, OTF, WOFF, or WOFF2 fixture was found. The screenshot font helper loads DejaVu from the system path above.
- The installed system's generic `sans-serif` resolves to DejaVu Sans; `Arial` resolves to Liberation Sans. DejaVu was selected because it already matches the host's generic sans resolution and is already used by the screenshot helper.
