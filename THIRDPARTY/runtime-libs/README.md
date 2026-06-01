# Runtime dylib attribution

The following dynamic libraries are bundled inside calimocho's engine
under `out/engine/lib/external/runtime/` (and inside
`Calimocho.app/Contents/Resources/Engine/lib/external/runtime/` once
Phase 2 ships). They are Wine's runtime `dlopen` targets, populated
by `scripts/bundle-deps.sh` from the x86_64 Homebrew prefix
(`/usr/local/`).

Each entry below points at the upstream project home for license
text. Calimocho ships these unmodified.

| dylib | upstream | license |
|---|---|---|
| libdbus-1.3.dylib   | https://www.freedesktop.org/wiki/Software/dbus/ | AFL-2.1 OR GPL-2.0+ |
| libfreetype.6.dylib | https://freetype.org/                            | FTL OR GPL-2.0      |
| libgnutls.30.dylib  | https://www.gnutls.org/                          | LGPL-2.1+           |
| libSDL2-2.0.0.dylib | https://www.libsdl.org/                          | zlib                |
| libpng16.16.dylib   | http://www.libpng.org/pub/png/libpng.html        | libpng license      |
| libintl.8.dylib     | https://www.gnu.org/software/gettext/            | LGPL-2.1+           |
| libp11-kit.0.dylib  | https://p11-glue.github.io/p11-glue/p11-kit.html | BSD-3-Clause        |
| libidn2.0.dylib     | https://www.gnu.org/software/libidn/             | LGPL-3.0+ OR GPL-2.0+ |
| libunistring.5.dylib| https://www.gnu.org/software/libunistring/       | LGPL-3.0+ OR GPL-2.0+ |
| libtasn1.6.dylib    | https://www.gnu.org/software/libtasn1/           | LGPL-2.1+           |
| libnettle.9.dylib   | https://www.lysator.liu.se/~nisse/nettle/        | LGPL-3.0+ OR GPL-2.0+ |
| libhogweed.7.dylib  | https://www.lysator.liu.se/~nisse/nettle/        | LGPL-3.0+ OR GPL-2.0+ |
| libgmp.10.dylib     | https://gmplib.org/                              | LGPL-3.0+ OR GPL-2.0+ |

All of these allow free redistribution provided the license terms are
reproduced. The above README satisfies the source-availability /
attribution requirement; the license texts live at the upstream URLs
linked above and inside each dylib's `__TEXT,__copyright` section
(visible with `strings <dylib> | grep -i copyright`).

If you redistribute calimocho, keep this README alongside the dylibs.
