// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const testz = @import("testz");

const all_tests = blk: {
    // testz's per-module discovery walks every `pub` decl with an
    // `inline for`; the dictionary tests alone tip it past the default
    // 1000-branch comptime limit.
    @setEvalBranchQuota(20000);
    break :blk testz.discoverTests(.{
        testz.Group{ .name = "Pages Tests", .tag = "pages", .mod = @import("./pages_tests.zig") },
        testz.Group{ .name = "Archive Tests", .tag = "archive", .mod = @import("./archive_tests.zig") },
        testz.Group{ .name = "Mokuro Tests", .tag = "mokuro", .mod = @import("./mokuro_tests.zig") },
        testz.Group{ .name = "Kana Tests", .tag = "kana", .mod = @import("./kana_tests.zig") },
        testz.Group{ .name = "Dict Tests", .tag = "dict", .mod = @import("./dict_tests.zig") },
        testz.Group{ .name = "Crop Tests", .tag = "crop", .mod = @import("./crop_tests.zig") },
    }, .{});
};

pub fn main(init: std.process.Init) !void {
    try testz.testzRunner(all_tests, init.minimal.args);
}
