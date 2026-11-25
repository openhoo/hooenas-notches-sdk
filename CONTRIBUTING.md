# Contributing

The public repository owns the reusable SwiftUI/AppKit SDK, JSON Lines protocol,
native host, TypeScript client and Tauri example. The utility application is
maintained separately in the private `openhoo/hooenas-notches` repository.

## Development checks

Use macOS 14+, Swift 6.2+, Xcode, Node.js 22.12+, Python 3.11+ and Rust with
Clippy/rustfmt. Run the same gate as CI from any working directory:

```sh
./scripts/check.sh
```

The gate checks formatting, compiler warnings, native tests, the TypeScript
client against the real Swift host, the open-stdin protocol regression, a full
Tauri app build, Clippy, local documentation links and media metadata. Development
tools are pinned; Python tools live in `output/quality-tools`. Generated output
and local dependencies are ignored by Git.

Native attachment and interaction tests require a running macOS desktop. Tests
that require an unavailable display report an explicit skip. Before release,
smoke-test the showcase and Tauri app on a real desktop as well as running CI.

## Formatting

```sh
xcrun swift-format format --in-place --recursive Package.swift Sources Tests
npm ci --ignore-scripts
npm run format
output/quality-tools/bin/ruff check scripts
output/quality-tools/bin/ruff format scripts
cargo fmt --manifest-path examples/tauri/src-tauri/Cargo.toml
```

Keep protocol version 1 backward compatible. Add focused regressions for fixes
that affect framing, lifecycle, interaction or geometry. Preserve the physical
top-edge attachment and the camera-aware default content spacing.

When the Contour GIF changes, rebuild the landing page's user-controlled video
and still frame from the same recording:

```sh
ffmpeg -y -i docs/showcase/contour.gif -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart docs/showcase/contour.mp4
ffmpeg -y -i docs/showcase/contour.gif -vf 'select=eq(n\,55)' -frames:v 1 -q:v 2 docs/showcase/contour-poster.jpg
```

## Prepare release assets

Update the component versions and lockfiles, record the changes in
`CHANGELOG.md`, and run the quality gate. On a Mac, run:

```sh
python3 scripts/package-host.py
```

The script builds both architectures from this checkout, applies an ad-hoc
signature, and writes the helper archive and `SHA256SUMS.txt` to
`output/release/v<version>/`. Run `shasum -a 256 -c SHA256SUMS.txt` there,
extract the archive, then run `scripts/test-host-stream.py` with
`HOOENAS_NOTCHES_HOST` pointing to that extracted executable. Publish the
verified archive and checksum with the source tag. Published tags remain
immutable. The TypeScript client is distributed from this repository; there
is no npm release pipeline.

## License

Retain `LICENSE`, `THIRD_PARTY_NOTICES.md`, the preserved upstream license and
source copyright notices in redistributions. See those files for the current
FSL-1.1-MIT terms.
