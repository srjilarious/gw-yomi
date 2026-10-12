// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

//! Exposes the `gw_yomi` module, with SQLite and stb compiled into it,
//! and `zig build test` for gw-yomi's own tests.
//!
//! **Android.** A dependent building for Android passes an Android
//! `target` and sets the NDK libc file on its own final compile step;
//! the C sources here pick up the two API-level defines NDK r30's headers
//! insist on (`android_defines`), since Zig hands clang an unversioned
//! triple and the headers refuse to compile without them.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_dep = b.dependency("sqlite", .{});
    const stb_dep = b.dependency("zstbi", .{});

    // sqlite3.h includes only <stdarg.h>, which comes with the compiler,
    // so it translates without a libc -- for Android as for the host.
    const sqlite_c = b.addTranslateC(.{
        .root_source_file = sqlite_dep.path("sqlite3.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });

    const mod = b.addModule("gw_yomi", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("sqlite_c", sqlite_c.createModule());

    const cflags = std.mem.concat(b.allocator, []const u8, &.{
        &.{"-fno-sanitize=undefined"},
        androidDefines(b, target),
    }) catch @panic("OOM");
    mod.addCSourceFile(.{ .file = sqlite_dep.path("sqlite3.c"), .flags = cflags });
    mod.addCSourceFile(.{ .file = b.path("src/sqlite_shim.c"), .flags = cflags });
    mod.addIncludePath(sqlite_dep.path(""));
    // stb_image + stb_image_write for crop.zig, compiled `static` in their
    // own C unit -- see the comment in src/image_io.c.
    mod.addCSourceFile(.{ .file = b.path("src/image_io.c"), .flags = cflags });
    mod.addIncludePath(stb_dep.path("libs/stbi"));

    // Tests only when gw-yomi is the root build: asking for the lazy
    // testz dependency from a dependent's build would fetch it there.
    if (b.isRoot()) {
        if (b.lazyDependency("testz", .{ .target = target, .optimize = optimize })) |testz_dep| {
            const tests_mod = b.createModule(.{
                .root_source_file = b.path("tests/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            tests_mod.addImport("gw_yomi", mod);
            tests_mod.addImport("testz", testz_dep.module("testz"));
            const tests_exe = b.addExecutable(.{ .name = "tests", .root_module = tests_mod });

            const run = b.addRunArtifact(tests_exe);
            const test_step = b.step("test", "Run gw-yomi's tests");
            test_step.dependOn(&run.step);
        }
    }
}

fn androidDefines(b: *std.Build, target: std.Build.ResolvedTarget) []const []const u8 {
    if (!target.result.abi.isAndroid()) return &.{};
    const api = target.result.os.version_range.linux.android;
    return b.allocator.dupe([]const u8, &.{
        b.fmt("-D__ANDROID_API__={d}", .{api}),
        b.fmt("-D__ANDROID_MIN_SDK_VERSION__={d}", .{api}),
    }) catch @panic("OOM");
}
