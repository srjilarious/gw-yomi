// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const kana = @import("gw_yomi").kana;

// ─── kana: Yomitan's text variants ──────────────────────────────────────

pub fn kanaToHiraganaTurnsTheLongVowelMarkIntoItsVowelTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.toHiragana(alloc, "スーパー");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "すうぱあ");
    // An o-row kana lengthens with う, the way a long o is spelled.
    const o = try kana.toHiragana(alloc, "コーヒー");
    defer alloc.free(o);
    try testz.expectEqualStr(o, "こうひい");
}

pub fn kanaToHiraganaLeavesCounterKeAloneTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.toHiragana(alloc, "一ヶ月");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "一ヶ月");
}

pub fn kanaToKatakanaConvertsOnlyHiraganaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.toKatakana(alloc, "猫すごいA");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "猫スゴイA");
}

pub fn kanaCollapseEmphaticPartialAndFullTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const partial = try kana.collapseEmphatic(alloc, "すっっごーーい", false);
    defer alloc.free(partial);
    try testz.expectEqualStr(partial, "すっごーい");
    const full = try kana.collapseEmphatic(alloc, "すっっごーーい", true);
    defer alloc.free(full);
    try testz.expectEqualStr(full, "すごい");
}

pub fn kanaCollapseEmphaticKeepsLeadingAndTrailingRunsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.collapseEmphatic(alloc, "ーあっー", true);
    defer alloc.free(out);
    try testz.expectEqualStr(out, "ーあっー");
    const all = try kana.collapseEmphatic(alloc, "っっ", true);
    defer alloc.free(all);
    try testz.expectEqualStr(all, "っっ");
}

pub fn kanaVariantsPutTheOriginalFirstAndCountStepsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const vs = try kana.variants(arena.allocator(), "スッゴイ");
    try testz.expectEqualStr(vs[0].text, "スッゴイ");
    try testz.expectEqual(vs[0].steps, 0);

    var found_full = false;
    for (vs) |v| {
        // Script change plus full collapse: two steps.
        if (std.mem.eql(u8, v.text, "すごい")) {
            found_full = true;
            try testz.expectEqual(v.steps, 2);
        }
        // Distinct spellings only.
        var n: usize = 0;
        for (vs) |w| if (std.mem.eql(u8, v.text, w.text)) {
            n += 1;
        };
        try testz.expectEqual(n, 1);
    }
    try testz.expectTrue(found_full);
}

pub fn kanaVariantsOfPlainKanjiIsJustTheOriginalTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const vs = try kana.variants(arena.allocator(), "猫");
    try testz.expectEqual(vs.len, 1);
}

pub fn kanaNormalizeConvertsHalfWidthKatakanaWithItsMarksTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.normalize(alloc, "ｶﾞｯｺｳﾊﾟﾝ");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "ガッコウパン");
}

pub fn kanaNormalizeLeavesAMarkThatCannotAttachTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // ﾅ takes no dakuten, so the ﾞ is kept rather than swallowed.
    const out = try kana.normalize(alloc, "ﾅﾞ");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "ナﾞ");
}

pub fn kanaNormalizeFoldsCombiningMarksTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.normalize(alloc, "か\u{3099}は\u{309A}ト\u{3099}");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "がぱド");
    // Half-width kana then a *combining* mark: converted, then folded.
    const mixed = try kana.normalize(alloc, "ｶ\u{3099}");
    defer alloc.free(mixed);
    try testz.expectEqualStr(mixed, "ガ");
}

pub fn kanaNormalizeExpandsCompatibilitySquaresComposedTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // NFKC, not Yomitan's NFKD: パ comes back composed.
    const out = try kana.normalize(alloc, "㌀と㍿");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "アパートと株式会社");
}

pub fn kanaNormalizeMapsRadicalsIncludingTheSupplementTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // ⼀ (KangXi, NFKD) and ⺼ (Radicals Supplement, which NFKD leaves
    // alone and only Equivalent_Unified_Ideograph maps).
    const out = try kana.normalize(alloc, "⼀⺼");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "一肉");
}

pub fn kanaNormalizeLeavesOrdinaryTextAloneTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try kana.normalize(alloc, "猫がすごいＴシャツA");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "猫がすごいＴシャツA");
}

pub fn kanaAlphanumericWidthConvertsBothWaysTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const ascii = try kana.toAsciiAlphanumeric(alloc, "Ｔシャツ０９ａｚ");
    defer alloc.free(ascii);
    try testz.expectEqualStr(ascii, "Tシャツ09az");
    const full = try kana.toFullWidthAlphanumeric(alloc, "Tシャツ09az!");
    defer alloc.free(full);
    try testz.expectEqualStr(full, "Ｔシャツ０９ａｚ!");
}

pub fn kanaVariantsStartFromTheNormalizedTextTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const vs = try kana.variants(arena.allocator(), "ｶﾞｯｺｳ");
    try testz.expectEqualStr(vs[0].text, "ガッコウ");
    try testz.expectEqual(vs[0].steps, 1);
    // The half-width original is never searched as such.
    for (vs) |v| try testz.expectFalse(std.mem.eql(u8, v.text, "ｶﾞｯｺｳ"));
    var found = false;
    for (vs) |v| if (std.mem.eql(u8, v.text, "がっこう")) {
        found = true;
        // Normalized, then hiragana.
        try testz.expectEqual(v.steps, 2);
    };
    try testz.expectTrue(found);
}

pub fn kanaVariantsTryBothAlphanumericWidthsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const vs = try kana.variants(arena.allocator(), "Tシャツ");
    var full = false;
    for (vs) |v| if (std.mem.eql(u8, v.text, "Ｔシャツ")) {
        full = true;
        try testz.expectEqual(v.steps, 1);
    };
    try testz.expectTrue(full);
}

