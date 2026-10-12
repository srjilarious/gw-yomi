# gw-yomi

The reading core shared by glyphwire's `gw-read` and the wns-reader
Android app: everything a manga reader needs that doesn't depend on how
it draws.

| Module | What |
|---|---|
| `archive` | Opening a book (`.cbz`/`.zip` in process, `.cbr`/`.cb7` via an external extractor, or a folder of images) and finding its mokuro sidecar |
| `pages` | Which archive entries are pages, in natural order |
| `mokuro` | Parsing mokuro OCR, reading order, hit testing, joining a bubble's lines, vertical layout |
| `kana` | Yomitan's text normalizations and variants |
| `dict` | Yomitan dictionaries indexed into SQLite, with Yomitan-style deinflection, ranking, frequency and grouping |
| `sqlite` | The thin wrapper over SQLite `dict` uses |
| `crop` | An Anki card's image: crop box maths and decode, crop, downscale, JPEG |

These modules came out of glyphwire's `read/` directory, along with their
tests. The cell-width helpers that only gw-read's terminal UI uses
(`mokuro.wrap`, `displayWidth`, `columnToByte`, `spanCells`) stayed there.

## Using it

```zig
// build.zig.zon
.gw_yomi = .{ .path = "../gw-yomi" },

// build.zig
const yomi = b.dependency("gw_yomi", .{ .target = target, .optimize = optimize });
mod.addImport("gw_yomi", yomi.module("gw_yomi"));
```

SQLite (the amalgamation) and stb_image are compiled into the module, so
the final artifact needs a libc. For Android, pass an Android `target`
and set the NDK libc file on your own compile step; gw-yomi adds the API
level defines NDK r30's headers require. See wns-reader's
`native/build.zig` for a working setup.

## Tests

```sh
zig build test
```

Uses [testz](https://github.com/srjilarious/testz), fetched lazily, so
packages that depend on gw-yomi never fetch it.

## License

GPL-3.0-or-later. See `LICENSE`.
