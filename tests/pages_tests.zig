// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const pages = @import("gw_yomi").pages;
const archive = @import("gw_yomi").archive;

// ─── pages.isPage ───────────────────────────────────────────────────────

pub fn isPageAcceptsTheFourSupportedFormatsTest(_: std.Io, _: std.mem.Allocator) !void {
    try testz.expectTrue(pages.isPage("001.png"));
    try testz.expectTrue(pages.isPage("001.jpg"));
    try testz.expectTrue(pages.isPage("001.jpeg"));
    try testz.expectTrue(pages.isPage("001.bmp"));
    try testz.expectTrue(pages.isPage("001.gif"));
    // Case is folded: scanners emit .JPG as often as .jpg.
    try testz.expectTrue(pages.isPage("001.JPG"));
    try testz.expectTrue(pages.isPage("vol1/ch02/003.PNG"));
}

pub fn isPageRejectsUnsupportedAndNonImageEntriesTest(_: std.Io, _: std.mem.Allocator) !void {
    // stb_image has no WebP decoder, so a .webp page can't be shown.
    try testz.expectFalse(pages.isPage("001.webp"));
    try testz.expectFalse(pages.isPage("ComicInfo.xml"));
    try testz.expectFalse(pages.isPage("notes"));
    try testz.expectFalse(pages.isPage(""));
    // A directory entry, which every zip writes alongside its files.
    try testz.expectFalse(pages.isPage("chapter01/"));
}

pub fn isPageRejectsMacOsSidecarsAndResourceForksTest(_: std.Io, _: std.mem.Allocator) !void {
    // The two things a Mac-zipped archive adds that would otherwise
    // double every page in the book.
    try testz.expectFalse(pages.isPage("__MACOSX/001.png"));
    try testz.expectFalse(pages.isPage("__MACOSX/vol1/._001.jpg"));
    try testz.expectFalse(pages.isPage("._001.png"));
    try testz.expectFalse(pages.isPage(".hidden/001.png"));
    // ...but a leading `__` on the *file* is just an odd filename.
    try testz.expectTrue(pages.isPage("__cover.png"));
}

// ─── pages.order ────────────────────────────────────────────────────────

pub fn orderComparesDigitRunsAsNumbersTest(_: std.Io, _: std.mem.Allocator) !void {
    // The whole reason this isn't std.mem.order: byte-wise, "10" < "2".
    try testz.expectTrue(pages.order("page2.png", "page10.png") == .lt);
    try testz.expectTrue(pages.order("page10.png", "page2.png") == .gt);
    try testz.expectTrue(pages.order("page9.png", "page10.png") == .lt);
    try testz.expectTrue(pages.order("page100.png", "page99.png") == .gt);
}

pub fn orderHandlesZeroPaddingAndHugeNumbersTest(_: std.Io, _: std.mem.Allocator) !void {
    // Padding doesn't change the value, only the tie-break.
    try testz.expectTrue(pages.order("p007.png", "p8.png") == .lt);
    try testz.expectTrue(pages.order("p01.png", "p1.png") == .lt);
    try testz.expectTrue(pages.order("p1.png", "p01.png") == .gt);
    try testz.expectTrue(pages.order("p000.png", "p0.png") == .lt);
    // Runs longer than any integer type still compare correctly, which is
    // why the comparison never parses them.
    try testz.expectTrue(pages.order(
        "f99999999999999999999999999999999999998.png",
        "f99999999999999999999999999999999999999.png",
    ) == .lt);
}

pub fn orderFoldsCaseButStaysTotalTest(_: std.Io, _: std.mem.Allocator) !void {
    // Byte-wise, every uppercase name sorts ahead of every lowercase one,
    // which scatters a mixed-case archive. Folded, they interleave.
    // Byte-wise "Cover" sorts before *every* lowercase name; folded it
    // lands where a reader expects it, after "chapter1" and before "d".
    try testz.expectTrue(pages.order("Cover.png", "chapter1.png") == .gt);
    try testz.expectTrue(pages.order("Cover.png", "dregs.png") == .lt);
    try testz.expectTrue(pages.order("apple.png", "Banana.png") == .lt);
    // A pure-case difference is still an order, not a tie.
    try testz.expectTrue(pages.order("A.png", "a.png") != .eq);
    try testz.expectTrue(pages.order("a.png", "a.png") == .eq);
}

pub fn orderSortsARealisticArchiveListingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var names = [_][]const u8{
        "ch02/p10.jpg",
        "ch1/p2.jpg",
        "ch1/p10.jpg",
        "ch1/p1.jpg",
        "ch02/p9.jpg",
        "cover.jpg",
    };
    _ = alloc;
    std.mem.sort([]const u8, &names, {}, pages.lessThan);

    try testz.expectEqualStr(names[0], "ch1/p1.jpg");
    try testz.expectEqualStr(names[1], "ch1/p2.jpg");
    try testz.expectEqualStr(names[2], "ch1/p10.jpg");
    // "ch02" and "ch1" share the "ch" prefix, then compare 02 vs 1
    // numerically -- so chapter 1 really does come first.
    try testz.expectEqualStr(names[3], "ch02/p9.jpg");
    try testz.expectEqualStr(names[4], "ch02/p10.jpg");
    try testz.expectEqualStr(names[5], "cover.jpg");
}

