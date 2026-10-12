// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const mokuro = @import("gw_yomi").mokuro;
const pages = @import("gw_yomi").pages;

// ─── mokuro: parsing ────────────────────────────────────────────────────

/// A minimal but realistic `.mokuro` file: two pages, three bubbles.
const mokuro_sample =
    \\{
    \\  "version": "0.1.7",
    \\  "title": "テスト巻",
    \\  "pages": [
    \\    {
    \\      "version": "0.1.7",
    \\      "img_width": 1200,
    \\      "img_height": 1700,
    \\      "img_path": "001.jpg",
    \\      "blocks": [
    \\        { "box": [800, 100, 1100, 500], "vertical": true, "font_size": 30,
    \\          "lines": ["おはよう", "ございます"] },
    \\        { "box": [100, 150, 400, 520], "vertical": true, "font_size": 28,
    \\          "lines": ["いってきます"] },
    \\        { "box": [300, 1100, 900, 1500], "vertical": false, "font_size": 24,
    \\          "lines": ["hello", "world"] }
    \\      ]
    \\    },
    \\    {
    \\      "img_width": 1200,
    \\      "img_height": 1700,
    \\      "img_path": "002.jpg",
    \\      "blocks": []
    \\    }
    \\  ]
    \\}
;

pub fn mokuroParsesPagesBlocksAndBoxesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();

    try testz.expectEqualStr(vol.title, "テスト巻");
    try testz.expectEqual(vol.pages.len, 2);
    try testz.expectEqual(vol.pages[0].img_width, 1200);
    try testz.expectEqual(vol.pages[0].img_height, 1700);
    try testz.expectEqual(vol.pages[0].blocks.len, 3);
    try testz.expectEqual(vol.pages[1].blocks.len, 0);

    const b = vol.pages[0].blocks[0];
    try testz.expectEqual(b.box.x1, 800);
    try testz.expectEqual(b.box.y2, 500);
    try testz.expectTrue(b.vertical);
    try testz.expectEqual(b.lines.len, 2);
    try testz.expectEqualStr(b.lines[1], "ございます");
    // Only one of the two pages carries text.
    try testz.expectEqual(vol.pagesWithText(), 1);
}

pub fn mokuroDropsBlocksWithNoBoxOrNoTextTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Per the module's error policy: a bad block is dropped, the volume
    // still opens. Four blocks in, one survives.
    const json =
        \\{"pages": [{"img_path": "a.png", "blocks": [
        \\  {"lines": ["no box"]},
        \\  {"box": [1, 2, 3], "lines": ["short box"]},
        \\  {"box": [0, 0, 10, 10], "lines": []},
        \\  {"box": [0, 0, 10, 10], "lines": ["kept"]}
        \\]}]}
    ;
    var vol = try mokuro.parse(alloc, json);
    defer vol.deinit();
    try testz.expectEqual(vol.pages.len, 1);
    try testz.expectEqual(vol.pages[0].blocks.len, 1);
    try testz.expectEqualStr(vol.pages[0].blocks[0].lines[0], "kept");
}

pub fn mokuroTreatsGarbageAsAnEmptyVolumeRatherThanAnErrorTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const bad = [_][]const u8{ "", "not json at all", "[1,2,3]", "{}", "{\"pages\": 7}" };
    for (bad) |src| {
        var vol = try mokuro.parse(alloc, src);
        defer vol.deinit();
        try testz.expectEqual(vol.pages.len, 0);
    }
}

pub fn mokuroNormalisesAnInvertedBoxTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A box written bottom-right first still describes the same region.
    const json =
        \\{"pages": [{"img_path": "a.png", "blocks": [
        \\  {"box": [90, 80, 10, 20], "lines": ["x"]}
        \\]}]}
    ;
    var vol = try mokuro.parse(alloc, json);
    defer vol.deinit();
    const box = vol.pages[0].blocks[0].box;
    try testz.expectEqual(box.x1, 10);
    try testz.expectEqual(box.y1, 20);
    try testz.expectEqual(box.x2, 90);
    try testz.expectEqual(box.y2, 80);
    try testz.expectTrue(box.contains(50, 50));
    try testz.expectFalse(box.contains(5, 50));
}

// ─── mokuro: matching a page to an archive entry ────────────────────────

pub fn mokuroMatchesAPageByPathThenBasenameThenStemTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();

    // Exact, as mokuro wrote it.
    try testz.expectTrue(vol.pageFor("001.jpg") != null);
    // The archive nests its pages under a folder; mokuro doesn't.
    try testz.expectTrue(vol.pageFor("Vol1/images/001.jpg") != null);
    // Re-encoded to PNG after the OCR run: the stem still matches.
    try testz.expectTrue(vol.pageFor("Vol1/001.png") != null);
    // A page the sidecar simply doesn't cover.
    try testz.expectTrue(vol.pageFor("cover.jpg") == null);
}

pub fn mokuroPageMatchIsExactNotAPrefixTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();
    // `0010.jpg` shares a prefix with `001.jpg` and must not match it --
    // a fuzzy match here would put the wrong page's text on the screen.
    try testz.expectTrue(vol.pageFor("0010.jpg") == null);
    try testz.expectTrue(vol.pageFor("001.jpg.bak") == null);
}

// ─── mokuro: reading order ──────────────────────────────────────────────

pub fn mokuroReadingOrderGoesRightToLeftThenDownForMangaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();
    const pg = &vol.pages[0];

    var buf: [8]usize = undefined;
    var bands: [8]u32 = undefined;
    const order = mokuro.readingOrder(pg, .rtl, &buf, &bands);
    try testz.expectEqual(order.len, 3);
    // Blocks 0 and 1 share a band near the top: their tops are 100 and
    // 150, a 50px gap against a ~106px tolerance on a 1700px page --
    // and note a *quantising* band would have split them, since 106
    // falls between the two. Block 0 is further right, so it leads.
    // Block 2 is far down the page and gets its own band.
    try testz.expectEqual(order[0], 0);
    try testz.expectEqual(order[1], 1);
    try testz.expectEqual(order[2], 2);
}

pub fn mokuroReadingOrderFlipsForALeftToRightBookTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();
    const pg = &vol.pages[0];

    var buf: [8]usize = undefined;
    var bands: [8]u32 = undefined;
    const order = mokuro.readingOrder(pg, .ltr, &buf, &bands);
    // Same band, opposite sweep: the left-hand bubble now leads.
    try testz.expectEqual(order[0], 1);
    try testz.expectEqual(order[1], 0);
    try testz.expectEqual(order[2], 2);
}

pub fn mokuroReadingOrderIsBandedNotPurelyHorizontalTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A bubble low on the page but far right must not jump ahead of one
    // high up and slightly left: reading order is across-then-down, and
    // the banding is what encodes that.
    const json =
        \\{"pages": [{"img_path": "a.png", "img_width": 1000, "img_height": 1600,
        \\ "blocks": [
        \\   {"box": [10, 1400, 300, 1550], "lines": ["low left"]},
        \\   {"box": [700, 1400, 990, 1550], "lines": ["low right"]},
        \\   {"box": [400, 20, 600, 200], "lines": ["high middle"]}
        \\]}]}
    ;
    var vol = try mokuro.parse(alloc, json);
    defer vol.deinit();

    var buf: [8]usize = undefined;
    var bands: [8]u32 = undefined;
    const order = mokuro.readingOrder(&vol.pages[0], .rtl, &buf, &bands);
    try testz.expectEqual(order[0], 2); // the top band first...
    try testz.expectEqual(order[1], 1); // ...then across the bottom one,
    try testz.expectEqual(order[2], 0); // right to left.
}

// ─── mokuro: hit testing ────────────────────────────────────────────────

pub fn mokuroBlockAtFindsTheBubbleUnderAPixelTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var vol = try mokuro.parse(alloc, mokuro_sample);
    defer vol.deinit();
    const pg = &vol.pages[0];

    try testz.expectEqual(mokuro.blockAt(pg, 900, 200).?, 0);
    try testz.expectEqual(mokuro.blockAt(pg, 200, 300).?, 1);
    try testz.expectEqual(mokuro.blockAt(pg, 500, 1200).?, 2);
    // The gutter between bubbles is nobody's.
    try testz.expectTrue(mokuro.blockAt(pg, 600, 800) == null);
    // The exclusive far edge belongs to the next pixel, not this box.
    try testz.expectTrue(mokuro.blockAt(pg, 1100, 100) == null);
}

pub fn mokuroBlockAtPrefersTheSmallestContainingBoxTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // mokuro nests boxes; the inner one is the text you were pointing at
    // and would be unreachable if the first or largest match won.
    const json =
        \\{"pages": [{"img_path": "a.png", "blocks": [
        \\  {"box": [0, 0, 1000, 1000], "lines": ["outer"]},
        \\  {"box": [400, 400, 600, 600], "lines": ["inner"]}
        \\]}]}
    ;
    var vol = try mokuro.parse(alloc, json);
    defer vol.deinit();
    const pg = &vol.pages[0];
    try testz.expectEqual(mokuro.blockAt(pg, 500, 500).?, 1);
    try testz.expectEqual(mokuro.blockAt(pg, 100, 100).?, 0);
}

// ─── mokuro: joining and wrapping ───────────────────────────────────────

pub fn mokuroJoinsJapaneseColumnsWithNoSeparatorTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const lines = [_][]const u8{ "おはよう", "ございます" };
    const joined = try mokuro.joinLines(alloc, &lines);
    defer alloc.free(joined);
    // A space here would be wrong: the columns are one sentence.
    try testz.expectEqualStr(joined, "おはようございます");
}

pub fn mokuroJoinsAsciiLinesWithASpaceTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const lines = [_][]const u8{ "hello", "world" };
    const joined = try mokuro.joinLines(alloc, &lines);
    defer alloc.free(joined);
    try testz.expectEqualStr(joined, "hello world");
}

pub fn mokuroDoesNotDoubleASpaceAtALineSeamTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const lines = [_][]const u8{ "hello ", "world" };
    const joined = try mokuro.joinLines(alloc, &lines);
    defer alloc.free(joined);
    try testz.expectEqualStr(joined, "hello world");
}

pub fn mokuroJoinsAMixedSeamWithoutASpaceTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // One side CJK: no space. Japanese sets no space against a Latin
    // word inside a bubble either.
    const lines = [_][]const u8{ "です", "ne" };
    const joined = try mokuro.joinLines(alloc, &lines);
    defer alloc.free(joined);
    try testz.expectEqualStr(joined, "ですne");
}


// ─── mokuro: vertical layout ────────────────────────────────────────────
//
// A vertical dialog counts characters, not display columns: every
// character takes one slot down a column, whatever its width.

pub fn mokuroWrapVerticalSplitsIntoColumnsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const text = "面白いねabc";
    const cols = try mokuro.wrapVertical(alloc, text, 3);
    defer alloc.free(cols);
    try testz.expectEqual(cols.len, 3);
    try testz.expectEqualStr("面白い", cols[0]);
    try testz.expectEqualStr("ねab", cols[1]);
    try testz.expectEqualStr("c", cols[2]);
    // Slices into the text, like `wrap`'s rows.
    try testz.expectEqual(mokuro.rowOffset(text, cols[1]), 9);
}

pub fn mokuroWrapVerticalHangsClosingMarksTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A full column followed by 。 keeps it rather than starting the next
    // column with it; only one mark hangs.
    const cols = try mokuro.wrapVertical(alloc, "そうだ。」ね", 3);
    defer alloc.free(cols);
    try testz.expectEqual(cols.len, 2);
    try testz.expectEqualStr("そうだ。", cols[0]);
    try testz.expectEqualStr("」ね", cols[1]);
}

pub fn mokuroCharToByteCountsCharactersTest(_: std.Io, _: std.mem.Allocator) !void {
    const text = "猫aい";
    try testz.expectEqual(mokuro.charCount(text), 3);
    try testz.expectEqual(mokuro.charToByte(text, 0), 0);
    try testz.expectEqual(mokuro.charToByte(text, 1), 3);
    try testz.expectEqual(mokuro.charToByte(text, 2), 4);
    try testz.expectEqual(mokuro.charToByte(text, 9), text.len);
}

pub fn mokuroSpanCharsCrossesAColumnTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Columns 面白 / いね; 白い runs from the end of one into the next,
    // and a wide character is one slot, not two.
    const joined = "面白いね";
    const cols = try mokuro.wrapVertical(alloc, joined, 2);
    defer alloc.free(cols);
    const span = mokuro.spanChars(joined, cols, 3, 9).?;
    try testz.expectEqual(span.first.row, 0);
    try testz.expectEqual(span.first.col, 1);
    try testz.expectEqual(span.last.row, 1);
    try testz.expectEqual(span.last.col, 0);
}

pub fn mokuroVerticalFormsTest(_: std.Io, _: std.mem.Allocator) !void {
    try testz.expectEqualStr("︒", mokuro.verticalForm('。').?);
    try testz.expectEqualStr("﹁", mokuro.verticalForm('「').?);
    try testz.expectEqualStr("︱", mokuro.verticalForm('ー').?);
    try testz.expectTrue(mokuro.verticalForm('あ') == null);
    try testz.expectTrue(mokuro.verticalForm('a') == null);
}

