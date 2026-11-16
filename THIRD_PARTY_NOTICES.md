# Third-party notices

## Cua Spaces notch

The `ContourNotchShape` implementation in
`Sources/HooenasNotches/Geometry/ContourNotchShape.swift` is adapted from Cua AI's
`NotchShape`. It keeps the concept of independently animatable shoulder and
lower-corner radii, with custom cubic contours, softer default radii and a public
shape API. The SDK adds its own graphite-to-indigo surface and motion values.

- Upstream: https://github.com/trycua/cua
- Observed commit: `1f9b3184d3978c11ca06b121aee27e4b284275f9`
- Shape source: https://github.com/trycua/cua/blob/1f9b3184d3978c11ca06b121aee27e4b284275f9/libs/spaces-notch-swift/Sources/CuaSpacesNotchUI/NotchContentView.swift
- Animation reference: https://github.com/trycua/cua/blob/1f9b3184d3978c11ca06b121aee27e4b284275f9/libs/spaces-notch-swift/Sources/CuaSpacesNotchUI/NotchStage.swift
- Motion and layout reference: https://github.com/trycua/cua/blob/1f9b3184d3978c11ca06b121aee27e4b284275f9/libs/cua/crates/cua-spaces-app-core/src/notch/mod.rs
- Copyright (c) 2026 Cua AI, Inc.
- License: Functional Source License, Version 1.1, MIT Future License
  (`FSL-1.1-MIT`), reproduced in full at
  `LICENSES/Cua-Spaces-Notch-LICENSE.txt`.

The adapted Cua source is currently subject to FSL terms, including its
Permitted Purpose and redistribution clauses. The license's future MIT grant
applies on the second anniversary of the date the relevant upstream software
version was made available. Hooenas Notches does not relicense the Cua source
as MIT today. Cua's name appears here only to identify the upstream source.

## DynamicNotchKit

Cua's source attributes the two-radius notch path to DynamicNotchKit's
`NotchShape`, under MIT:

- Project: https://github.com/MrKai77/DynamicNotchKit
- Upstream revision recorded by Cua: `cd0b3e5`
- Copyright (c) 2025 Kai Azim
- Attribution evidence: https://github.com/trycua/cua/blob/1f9b3184d3978c11ca06b121aee27e4b284275f9/apps/cua-spaces-macos/THIRD_PARTY_NOTICES.md

### MIT License

Copyright (c) 2025 Kai Azim

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
