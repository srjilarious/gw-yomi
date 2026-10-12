// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const crop = @import("gw_yomi").crop;

// ─── crop ───────────────────────────────────────────────────────────────

const page_size: crop.Size = .{ .w = 1000, .h = 1500 };

pub fn cropInitialFramesTheBubbleOnThePageTest(_: std.Io, _: std.mem.Allocator) !void {
    // A bubble in the middle grows by its longer side each way.
    const r = crop.initial(.{ .x = 400, .y = 600, .w = 100, .h = 200 }, page_size);
    try testz.expectEqual(r.x, 200);
    try testz.expectEqual(r.y, 400);
    try testz.expectEqual(r.w, 500);
    try testz.expectEqual(r.h, 600);

    // Near a corner it is slid back on, not cut down.
    const corner = crop.initial(.{ .x = 950, .y = 10, .w = 40, .h = 40 }, page_size);
    try testz.expectTrue(corner.x >= 0 and corner.right() <= page_size.w);
    try testz.expectTrue(corner.y >= 0 and corner.bottom() <= page_size.h);
    // ...and never smaller than a third of the page's width.
    try testz.expectTrue(corner.w >= @divTrunc(page_size.w, 3));
}

pub fn cropDragMovesAndStopsAtThePageEdgeTest(_: std.Io, _: std.mem.Allocator) !void {
    const start: crop.Rect = .{ .x = 100, .y = 100, .w = 200, .h = 200 };
    const moved = crop.dragged(start, .move, 50, -20, page_size);
    try testz.expectEqual(moved.x, 150);
    try testz.expectEqual(moved.y, 80);
    try testz.expectEqual(moved.w, 200);

    const pinned = crop.dragged(start, .move, -500, 0, page_size);
    try testz.expectEqual(pinned.x, 0);
    try testz.expectEqual(pinned.w, 200);
}

pub fn cropEdgePullStopsAtTheMinimumSizeTest(_: std.Io, _: std.mem.Allocator) !void {
    const start: crop.Rect = .{ .x = 100, .y = 100, .w = 200, .h = 200 };
    const wider = crop.dragged(start, .se, 40, 60, page_size);
    try testz.expectEqual(wider.x, 100);
    try testz.expectEqual(wider.w, 240);
    try testz.expectEqual(wider.h, 260);

    // Pulled past the opposite edge: pinned at min_side, not flipped.
    const crushed = crop.dragged(start, .w, 1000, 0, page_size);
    try testz.expectEqual(crushed.w, crop.min_side);
    try testz.expectEqual(crushed.right(), start.right());
}

pub fn cropHandleAtPicksEdgesCornersAndMoveTest(_: std.Io, _: std.mem.Allocator) !void {
    const r: crop.Rect = .{ .x = 100, .y = 100, .w = 200, .h = 200 };
    try testz.expectTrue(crop.handleAt(r, 200, 200, 8, 16) == .move);
    try testz.expectTrue(crop.handleAt(r, 102, 200, 8, 16) == .w);
    try testz.expectTrue(crop.handleAt(r, 298, 305, 8, 16) == .se);
    try testz.expectTrue(crop.handleAt(r, 200, 90, 8, 16) == .n);
    // Outside the box: its nearest corner.
    try testz.expectTrue(crop.handleAt(r, 20, 20, 8, 16) == .nw);
    try testz.expectTrue(crop.handleAt(r, 900, 20, 8, 16) == .ne);
}

pub fn cropScaledGrowsAboutTheCentreTest(_: std.Io, _: std.mem.Allocator) !void {
    const r: crop.Rect = .{ .x = 400, .y = 400, .w = 200, .h = 100 };
    const big = crop.scaled(r, 2.0, page_size);
    try testz.expectEqual(big.w, 400);
    try testz.expectEqual(big.h, 200);
    try testz.expectEqual(big.x + @divTrunc(big.w, 2), 500);
}

pub fn cropOutputSizeOnlyShrinksTest(_: std.Io, _: std.mem.Allocator) !void {
    const s = crop.outputSize(.{ .x = 0, .y = 0, .w = 1600, .h = 400 }, 800, 800);
    try testz.expectEqual(s.w, 800);
    try testz.expectEqual(s.h, 200);
    const small = crop.outputSize(.{ .x = 0, .y = 0, .w = 300, .h = 200 }, 800, 800);
    try testz.expectEqual(small.w, 300);
    try testz.expectEqual(small.h, 200);
}

/// A 24-bit BMP, left half red and right half blue -- the simplest image
/// format to write by hand, and one stb_image reads.
fn testBmp(alloc: std.mem.Allocator, w: u32, h: u32) ![]u8 {
    const row = (w * 3 + 3) / 4 * 4;
    const size = 54 + row * h;
    const buf = try alloc.alloc(u8, size);
    @memset(buf, 0);
    buf[0] = 'B';
    buf[1] = 'M';
    std.mem.writeInt(u32, buf[2..6], size, .little);
    std.mem.writeInt(u32, buf[10..14], 54, .little);
    std.mem.writeInt(u32, buf[14..18], 40, .little);
    std.mem.writeInt(i32, buf[18..22], @intCast(w), .little);
    std.mem.writeInt(i32, buf[22..26], @intCast(h), .little);
    std.mem.writeInt(u16, buf[26..28], 1, .little);
    std.mem.writeInt(u16, buf[28..30], 24, .little);
    for (0..h) |y| for (0..w) |x| {
        const p = 54 + y * row + x * 3;
        // BGR.
        if (x < w / 2) buf[p + 2] = 255 else buf[p] = 255;
    };
    return buf;
}

pub fn cropEncodeJpegCutsAndShrinksTheBoxTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const bmp = try testBmp(alloc, 64, 32);
    defer alloc.free(bmp);
    const out = try crop.encodeJpeg(alloc, bmp, .{ .x = 0, .y = 0, .w = 60, .h = 30 }, .{ .max_w = 30, .max_h = 30 });
    defer alloc.free(out.jpeg);
    try testz.expectEqual(out.width, 30);
    try testz.expectEqual(out.height, 15);
    // A real JPEG: SOI marker up front.
    try testz.expectTrue(out.jpeg.len > 100);
    try testz.expectTrue(out.jpeg[0] == 0xFF and out.jpeg[1] == 0xD8);
}

pub fn cropEncodeJpegRejectsNonImagesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    try testz.expectTrue(crop.encodeJpeg(alloc, "not an image", .{ .x = 0, .y = 0, .w = 10, .h = 10 }, .{}) == error.ImageDecodeFailed);
}

