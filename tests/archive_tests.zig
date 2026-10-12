// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const archive = @import("gw_yomi").archive;
const mokuro = @import("gw_yomi").mokuro;

// ─── archive: recognising the sidecar's name ────────────────────────────

pub fn mokuroSidecarNameIsRecognisedCaseInsensitivelyTest(_: std.Io, _: std.mem.Allocator) !void {
    try testz.expectTrue(archive.isMokuroName("Vol1.mokuro"));
    try testz.expectTrue(archive.isMokuroName("Vol1.MOKURO"));
    try testz.expectFalse(archive.isMokuroName("Vol1.mokuro.bak"));
    try testz.expectFalse(archive.isMokuroName("mokuro"));
    try testz.expectFalse(archive.isMokuroName(""));
}

