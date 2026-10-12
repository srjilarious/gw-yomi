// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const dict = @import("gw_yomi").dict;

// ─── dict: term bank parsing ────────────────────────────────────────────
//
// `dict.openMemory` builds an in-memory (`:memory:`) SQLite database the
// same way `loadFromDir` builds a real one on disk -- see `dict.zig`'s
// module doc comment -- so these pin the parse by querying it straight
// back out with `dict.lookup` rather than reading an in-memory entries
// array (there is no longer one to read).

pub fn dictParsesTermBankRowsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{
        \\[["食べる","たべる","","v1",0,["to eat"],1,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べる")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].entry.reading, "たべる");
    try testz.expectEqualStr(m.hits[0].entry.rules, "v1");
    try testz.expectEqual(m.hits[0].entry.glossary.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.glossary[0], "to eat");
    try testz.expectEqual(m.hits[0].entry.sequence, 1);
}

pub fn dictDropsRowsShorterThanEightFieldsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{
        \\[["short","","","",0]]
    }, &.{}, null);
    defer d.deinit();
    const m = try dict.lookup(alloc, &d, null, .rank, "short");
    try testz.expectTrue(m == null);
}

pub fn dictFlattensStructuredContentGlossaryTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Jitendex-style structured content: a tagged object wrapping the
    // real text rather than a plain string.
    var d = try dict.openMemory(alloc, &.{
        \\[["優しい","やさしい","","adj-i",0,[{"content":"kind, gentle"}],5,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "優しい")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits[0].entry.glossary.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.glossary[0], "kind, gentle");
}

pub fn dictKeepsOnlyTheGlossesOfJitendexSensesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Trimmed from Jitendex's 何奴も此奴も: badges, a glossary list, a
    // note, an example with ruby, the forms table and the credit line.
    var d = try dict.openMemory(alloc, &.{
        \\[["何奴も此奴も","どいつもこいつも","","exp",0,[{"type":"structured-content","content":[
        \\ {"tag":"div","data":{"content":"sense-group"},"content":[
        \\  {"tag":"span","data":{"class":"tag","content":"part-of-speech-info"},"content":"exp"},
        \\  {"tag":"span","data":{"class":"tag","content":"misc-info"},"content":"kana"},
        \\  {"tag":"div","data":{"content":"sense"},"content":[
        \\   {"tag":"ul","data":{"content":"glossary"},"content":[{"tag":"li","content":"everybody"},{"tag":"li","content":"all"}]},
        \\   {"tag":"div","data":{"content":"extra-info"},"content":[
        \\    {"tag":"div","data":{"content":"sense-note"},"content":"usu. negative nuance"},
        \\    {"tag":"span","content":[{"tag":"ruby","content":["正",{"tag":"rt","content":"しょう"}]}]}]}]}]},
        \\ {"tag":"ul","data":{"content":"glossary"},"content":{"tag":"li","content":"one and all"}},
        \\ {"tag":"div","data":{"content":"forms"},"content":"forms 何奴も此奴も"},
        \\ {"tag":"div","data":{"content":"attribution"},"content":["JMdict"," | ","Tatoeba"]}]}],1,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "何奴も此奴も")).?;
    defer m.deinit(alloc);
    const g = m.hits[0].entry.glossary;
    try testz.expectEqual(g.len, 2);
    try testz.expectEqualStr(g[0], "everybody; all");
    // A second list -- a second sense -- is a second string.
    try testz.expectEqualStr(g[1], "one and all");
}

pub fn dictFallbackFlattenSkipsRubyAndBadgesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // No glossary lists: every text leaf, minus readings and badges.
    var d = try dict.openMemory(alloc, &.{
        \\[["正直","しょうじき","","n",0,[{"type":"structured-content","content":[
        \\ {"tag":"span","data":{"class":"tag"},"content":"n"},
        \\ {"tag":"ruby","content":["正",{"tag":"rt","content":"しょう"}]},
        \\ "honesty"]}],1,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "正直")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.glossary[0], "正 honesty");
}

// ─── dict: tags ─────────────────────────────────────────────────────────

/// Trimmed from Jitendex's 生 (なま): a sense group's part-of-speech tags
/// ahead of its senses, a third sense with its own misc tag, and a forms
/// table whose row labels are tag spans too.
const tagged_sense_json =
    \\[["生","なま","★","",0,[{"type":"structured-content","content":[
    \\ {"tag":"ul","data":{"content":"sense-groups"},"content":[
    \\  {"tag":"li","data":{"content":"sense-group"},"content":[
    \\   {"tag":"span","data":{"class":"tag","code":"adj-no","content":"part-of-speech-info"},"content":"no-adj"},
    \\   {"tag":"span","data":{"class":"tag","code":"n","content":"part-of-speech-info"},"content":"noun"},
    \\   {"tag":"ol","content":[
    \\    {"tag":"li","data":{"content":"sense"},"content":[
    \\     {"tag":"ul","data":{"content":"glossary"},"content":[{"tag":"li","content":"raw"},{"tag":"li","content":"uncooked"}]}]},
    \\    {"tag":"li","data":{"content":"sense"},"content":
    \\     {"tag":"ul","data":{"content":"glossary"},"content":[{"tag":"li","content":"natural"}]}},
    \\    {"tag":"li","data":{"content":"sense"},"content":[
    \\     {"tag":"span","data":{"class":"tag","code":"col","content":"misc-info"},"content":"colloquial"},
    \\     {"tag":"ul","data":{"content":"glossary"},"content":[{"tag":"li","content":"unprotected (sex)"}]}]}]}]}]},
    \\ {"tag":"div","data":{"content":"forms"},"content":[
    \\  {"tag":"span","data":{"class":"tag","content":"forms-label"},"content":"forms"}]}]}],1378450,""]]
;

pub fn dictGivesASenseGroupsTagsToItsFirstSenseTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{tagged_sense_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "生")).?;
    defer m.deinit(alloc);
    const e = m.hits[0].entry;
    try testz.expectEqual(e.glossary.len, 3);
    try testz.expectEqual(e.sense_tags.len, 3);

    try testz.expectEqual(e.sense_tags[0].len, 2);
    try testz.expectEqualStr(e.sense_tags[0][0].label, "no-adj");
    try testz.expectEqualStr(e.sense_tags[0][0].category, "part-of-speech-info");
    try testz.expectEqualStr(e.sense_tags[0][1].label, "noun");
    // The group's tags are drawn once, not repeated on every sense.
    try testz.expectEqual(e.sense_tags[1].len, 0);
    try testz.expectEqual(e.sense_tags[2].len, 1);
    try testz.expectEqualStr(e.sense_tags[2][0].label, "colloquial");
    try testz.expectEqualStr(e.sense_tags[2][0].category, "misc-info");
    // The text itself is unchanged: badges never leak into the glosses.
    try testz.expectEqualStr(e.glossary[2], "unprotected (sex)");
}

pub fn dictLeavesPlainGlossariesWithEmptySenseTagsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{
        \\[["猫","ねこ","","n",0,["cat","shamisen"],4,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "猫")).?;
    defer m.deinit(alloc);
    const e = m.hits[0].entry;
    try testz.expectEqual(e.sense_tags.len, 2);
    try testz.expectEqual(e.sense_tags[0].len, 0);
    try testz.expectEqual(e.sense_tags[1].len, 0);
    try testz.expectEqual(e.tags.len, 0);
}

/// Jitendex's real `tag_bank_1.json` rows for the two tags used below --
/// note the no-break spaces inside "rarely used form".
const jitendex_tag_bank_json =
    \\[["★","popular",2,"high priority entry",2],
    \\ ["rarely used form","archaism",0,"rarely used form of this term",1]]
;

pub fn dictResolvesHeadwordTagsAgainstTheTagBankTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemoryWithTags(alloc, &.{
        // definitionTags and termTags both land on the headword; a name
        // in both is shown once, and one the bank doesn't list still shows.
        \\[["生","なま","★ rarely used form","",0,["raw"],1,"★ mystery"]]
    }, &.{}, &.{jitendex_tag_bank_json}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "生")).?;
    defer m.deinit(alloc);
    const tags = m.hits[0].entry.tags;
    try testz.expectEqual(tags.len, 3);
    // Sorted by the bank's order (archaism 0, unknown 0, popular 2), then
    // by name.
    try testz.expectEqualStr(tags[0].label, "mystery");
    try testz.expectEqualStr(tags[0].category, "");
    try testz.expectEqualStr(tags[1].label, "rarely\u{a0}used\u{a0}form");
    try testz.expectEqualStr(tags[1].category, "archaism");
    try testz.expectEqualStr(tags[1].notes, "rarely used form of this term");
    try testz.expectEqualStr(tags[2].label, "★");
    try testz.expectEqualStr(tags[2].category, "popular");
}

pub fn dictKeepsHeadwordTagsWithoutATagBankTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{tagged_sense_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "生")).?;
    defer m.deinit(alloc);
    const tags = m.hits[0].entry.tags;
    try testz.expectEqual(tags.len, 1);
    try testz.expectEqualStr(tags[0].label, "★");
}

pub fn dictTreatsGarbageAsAnEmptyBankTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{ "", "not json", "{}", "[1,2,3]" }, &.{}, null);
    defer d.deinit();
    const m = try dict.lookup(alloc, &d, null, .rank, "食べる");
    try testz.expectTrue(m == null);
}

// ─── dict: lookup ───────────────────────────────────────────────────────

const lookup_dict_json =
    \\[
    \\  ["食べる","たべる","","v1",0,["to eat"],1,""],
    \\  ["分かる","わかる","","v5",0,["to understand"],2,""],
    \\  ["ある","ある","","exp",0,["there is (inanimate)"],3,""],
    \\  ["猫","ねこ","","n",0,["cat"],4,""],
    \\  ["高い","たかい","","adj-i",0,["high; tall"],5,""],
    \\  ["書く","かく","","v5",0,["to write"],6,""],
    \\  ["待つ","まつ","","v5",0,["to wait"],7,""]
    \\]
;

/// The irregular classes, kept out of `lookup_dict_json` so the tests
/// above keep their exact `hits.len` assertions: adding する to that
/// fixture would make every form ending in した/して/しない find a second
/// entry. `rules` values here are the ones a real Jitendex build uses --
/// "vs" for する verbs, "vk" for 来る, "vz" for ずる verbs -- which is the
/// whole point, since no rule in the table could produce them before.
const irregular_dict_json =
    \\[
    \\  ["する","する","","vs",0,["to do"],1,""],
    \\  ["察する","さっする","","vs",0,["to guess; to sense"],2,""],
    \\  ["来る","くる","","vk",0,["to come"],3,""],
    \\  ["帰って来る","かえってくる","","vk",0,["to come back"],4,""],
    \\  ["信ずる","しんずる","","vz",0,["to believe"],5,""],
    \\  ["行く","いく","","v5",0,["to go"],6,""],
    \\  ["行う","おこなう","","v5",0,["to perform"],7,""]
    \\]
;

pub fn dictLookupFindsExactDictionaryFormTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "猫が好き")).?;
    defer m.deinit(alloc);
    try testz.expectTrue(m.hits[0].reason == null);
    try testz.expectEqualStr("猫が好き"[0..m.len()], "猫");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "猫");
}

pub fn dictLookupDeinflectsIchidanTeFormTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べてすぐ")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].reason.?, "te-form");
    try testz.expectEqualStr("食べてすぐ"[0..m.len()], "食べて");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
}

pub fn dictLookupDeinflectsGodanRuVerbPastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 分かった -- past of 分かる (godan, not ichidan -- the ambiguous
    // -る class the rows' `conditions_out` exists to resolve).
    const m = (try dict.lookup(alloc, &d, null, .rank, "分かった")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].reason.?, "past");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "分かる");
}

// ─── dict: text normalization ───────────────────────────────────────────

/// Spellings OCR produces and no dictionary files a word under:
/// half-width katakana, radicals for kanji, compatibility squares, and
/// an ASCII letter where JMdict writes a full-width one.
const normalize_dict_json =
    \\[
    \\  ["学校","がっこう","","n",0,["school"],1,""],
    \\  ["肉","にく","","n",0,["meat"],2,""],
    \\  ["株式会社","かぶしきがいしゃ","","n",0,["stock company"],3,""],
    \\  ["Ｔシャツ","ティーシャツ","","n",0,["T-shirt"],4,""]
    \\]
;

pub fn dictLookupFindsHalfWidthKatakanaAndSpansTheOriginalBytesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{normalize_dict_json}, &.{}, null);
    defer d.deinit();
    const text = "ｶﾞｯｺｳへ";
    const m = (try dict.lookup(alloc, &d, null, .rank, text)).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "学校");
    // The match covers all five half-width codepoints as written, not
    // the four-kana normalized spelling.
    try testz.expectEqualStr(text[0..m.len()], "ｶﾞｯｺｳ");
}

pub fn dictLookupFindsAKanjiOcrReadAsARadicalTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{normalize_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "⺼")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "肉");
}

pub fn dictLookupExpandsACompatibilitySquareTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{normalize_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "㍿")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "株式会社");
}

pub fn dictLookupMatchesAsciiAgainstAFullWidthHeadwordTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{normalize_dict_json}, &.{}, null);
    defer d.deinit();
    const text = "Tシャツを";
    const m = (try dict.lookup(alloc, &d, null, .rank, text)).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "Ｔシャツ");
    try testz.expectEqualStr(text[0..m.len()], "Tシャツ");
}

// ─── dict: chained deinflection ─────────────────────────────────────────
//
// These exercise `tryDeinflectAtDepth`'s multi-step search -- forms the
// old single-step `lookup` could never reach no matter how the rule
// table was widened, since it only ever tried one rule per candidate.

pub fn dictLookupChainsProgressiveThroughTeFormTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べている ("is eating") -- the progressive rule strips "ている"
    // down to the te-form "食べて", which isn't itself a headword (its
    // conditions are just `te`); the existing te-form rule then reduces that
    // to "食べる". Two chained rule applications, neither of which
    // resolves anything alone.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べている")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr("食べている"[0..m.len()], "食べている");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "te-form, progressive");
}

pub fn dictLookupChainsNegativePastThroughNegativeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 分からなかった -- negative-past of 分かる (godan). The dedicated
    // adjective past (`かった` -> `い`) collapses this to the plain
    // negative "分からない" one layer in; the existing godan negative rule
    // then reduces that to "分かる", correctly validated against its "v5"
    // tag (not the ichidan "v1" negative rule, which would also match
    // "ない" as a bare suffix but is rejected since 分かる isn't tagged v1).
    // Two chained rule applications.
    const m = (try dict.lookup(alloc, &d, null, .rank, "分からなかった")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr("分からなかった"[0..m.len()], "分からなかった");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "分かる");
}

pub fn dictLookupChainsCausativeThroughNegativeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べさせない ("doesn't make [someone] eat") -- the outer negative
    // rule strips "ない" down to the causative form "食べさせる", which
    // isn't itself a headword; the causative rule then reduces that to
    // "食べる", validated against its "v1" tag. Unlike the progressive
    // chain above, causative's own `conditions_out` is the real headword's
    // class, not an intermediate condition -- it only ever needs an
    // *outer* layer (negative/past/te-form) to strip first because a bare
    // causative form is rarely written alone, not because stripping
    // causative itself leaves something unfinished.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べさせない")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr("食べさせない"[0..m.len()], "食べさせない");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "causative, negative");
}

pub fn dictLookupResolvesBareCausativeInOneStepTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べさせる alone (no outer negative/past layer) -- causative is
    // terminal, so this resolves in exactly one rule application, same
    // shape as the polite-past test below.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べさせる")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "causative");
}

pub fn dictLookupResolvesPolitePastInOneStepTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べました -- polite past. Unlike the chains above, this is a
    // single terminal rule application: the conjunctive stem directly
    // matches the "v1" headword's rules, with nothing further to unwind.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べました")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr("食べました"[0..m.len()], "食べました");
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "polite past");
}

pub fn dictLookupRejectsADeinflectionWhoseTargetHasTheWrongRuleTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // "あった" strips to "ある" via the godan -た rule, but the only
    // "ある" entry in this dict is tagged "exp", not "v5" -- so the
    // guess must be rejected rather than treated as a hit.
    const m = try dict.lookup(alloc, &d, null, .rank, "あった");
    try testz.expectTrue(m == null);
}

pub fn dictLookupReturnsNullWhenNothingMatchesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    const m = try dict.lookup(alloc, &d, null, .rank, "xyz123");
    try testz.expectTrue(m == null);
}

// ─── dict: the irregular classes (vs / vk / vz) and 行く ─────────────────
//
// Every rule in the table used to produce only "v1", "v5" or "adj-i", so
// the index's "vs"/"vk"/"vz" rows were unreachable at any depth and a
// click on した found the noun 下 instead. These pin the classes rather
// than individual forms: one representative form per class plus the cases
// where the class interacts with a chain.

/// Finds the best hit whose term is `term`, so a test can assert that a
/// headword is *reachable* without also asserting it outranks every
/// depth-0 homograph -- ranking puts fewer rules first, which is Yomitan's
/// order too and not what these tests are about.
fn hitFor(m: dict.Match, term: []const u8) ?dict.Hit {
    for (m.hits) |h| {
        if (std.mem.eql(u8, h.entry.term, term)) return h;
    }
    return null;
}

pub fn dictLookupReachesSuruThroughItsIrregularStemTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // した / して / しない / します all strip a whole surface ending back
    // to する rather than swapping a final kana -- the stem is irregular,
    // so there is nothing for the godan/ichidan rows to work with.
    const cases = [_]struct { text: []const u8, reason: []const u8 }{
        .{ .text = "した", .reason = "past" },
        .{ .text = "して", .reason = "te-form" },
        .{ .text = "しない", .reason = "negative" },
        .{ .text = "します", .reason = "polite" },
        .{ .text = "しろ", .reason = "imperative" },
        .{ .text = "したい", .reason = "desiderative" },
        .{ .text = "すれば", .reason = "provisional" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, "する") orelse return error.SuruNotReached;
        try testz.expectEqualStr(hit.entry.rules, "vs");
        try testz.expectEqualStr(hit.reason.?, c.reason);
        try testz.expectEqual(hit.depth, 1);
    }
}

pub fn dictLookupReachesKanjiPlusSuruHeadwordsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // The bulk of the "vs" rows are kanji+する headwords (932 of 987 in a
    // real Jitendex build), and suffix matching reaches all of them from
    // one rule: 察した -> 察する.
    const m = (try dict.lookup(alloc, &d, null, .rank, "察した")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "察する");
    try testz.expectEqualStr(m.hits[0].reason.?, "past");
}

pub fn dictLookupChainsSuruThroughProgressiveAndNegativePastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // The する block deliberately has no している or しなかった row: the
    // existing non-terminal progressive and the conditional reduce them to
    // して / した, which the する rows then finish. Two rule applications.
    const progressive = (try dict.lookup(alloc, &d, null, .rank, "している")).?;
    defer progressive.deinit(alloc);
    const p = hitFor(progressive, "する") orelse return error.SuruNotReached;
    try testz.expectEqualStr(p.reason.?, "te-form, progressive");
    try testz.expectEqual(p.depth, 2);

    const conditional = (try dict.lookup(alloc, &d, null, .rank, "したら")).?;
    defer conditional.deinit(alloc);
    const c = hitFor(conditional, "する") orelse return error.SuruNotReached;
    try testz.expectEqualStr(c.reason.?, "past, conditional");
    try testz.expectEqual(c.depth, 2);
}

pub fn dictLookupReachesKuruInBothSpellingsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // Written with the kanji, 来 stays put and only the kana after it
    // change, so those rows look like ordinary suffix swaps. Written in
    // kana the stem vowel really does change (き-/こ-/く-), so each form
    // needs its own row -- both spellings land on the same headword.
    const forms = [_][]const u8{ "来た", "来ない", "来い", "来られる", "きた", "こない", "こい", "こられる" };
    for (forms) |f| {
        const m = (try dict.lookup(alloc, &d, null, .rank, f)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, "来る") orelse return error.KuruNotReached;
        try testz.expectEqualStr(hit.entry.rules, "vk");
        try testz.expectEqual(hit.depth, 1);
    }
}

pub fn dictLookupReachesKuruCompoundsBySuffixTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // 帰って来ない ends with 来ない, so the compound headword comes along
    // with no rows of its own -- and it must win over the bare 来る, being
    // the longer source match.
    const m = (try dict.lookup(alloc, &d, null, .rank, "帰って来ない")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "帰って来る");
    try testz.expectEqualStr("帰って来ない"[0..m.len()], "帰って来ない");
    try testz.expectEqualStr(m.hits[0].reason.?, "negative");
}

pub fn dictLookupReachesZuruVerbsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "信じた")).?;
    defer m.deinit(alloc);
    const hit = hitFor(m, "信ずる") orelse return error.ZuruNotReached;
    try testz.expectEqualStr(hit.entry.rules, "vz");
    try testz.expectEqualStr(hit.reason.?, "past");
}

pub fn dictLookupReachesIkuDespiteItsIrregularPastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{irregular_dict_json}, &.{}, null);
    defer d.deinit();
    // 行った is 行く's past, not the 行いた its -く ending predicts. Both
    // 行く and 行う(おこなう) are reachable and the generic った -> う route
    // to 行う is the one that ranks first (same depth, same score, and う
    // sorts before く) -- documented in the rule table as accepted, so
    // this test asserts reachability, not order.
    const m = (try dict.lookup(alloc, &d, null, .rank, "行った")).?;
    defer m.deinit(alloc);
    const iku = hitFor(m, "行く") orelse return error.IkuNotReached;
    try testz.expectEqualStr(iku.reason.?, "past");
    try testz.expectEqual(iku.depth, 1);
    try testz.expectTrue(hitFor(m, "行う") != null);
}

// ─── dict: the everyday forms added alongside the irregulars ────────────

pub fn dictLookupDeinflectsDesiderativeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べたい")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "desiderative");
}

pub fn dictLookupChainsDesiderativeThroughItsAdjectiveNegativeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // "-tai" is itself an i-adjective, so 食べたくない needs no rows of its
    // own: the existing adjective negative reduces it to 食べたい, which
    // the desiderative row then takes to 食べる.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べたくない")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "desiderative, negative");
    try testz.expectEqual(m.hits[0].depth, 2);
}

pub fn dictLookupTreatsConditionalAsThePastPlusRaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // Two non-terminal rows (たら -> た, だら -> だ) rather than one row
    // per conjugation class: "-tara" *is* the past form plus ら, so the
    // past rules finish every one of these.
    const cases = [_]struct { text: []const u8, term: []const u8 }{
        .{ .text = "食べたら", .term = "食べる" },
        .{ .text = "分かったら", .term = "分かる" },
        .{ .text = "高かったら", .term = "高い" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.ConditionalNotReached;
        try testz.expectEqualStr(hit.reason.?, "past, conditional");
        try testz.expectEqual(hit.depth, 2);
    }
}

pub fn dictLookupDeinflectsProvisionalTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べれば (ichidan) and 分かれば (godan -る) share the same "れば"
    // suffix, which is why that row accepts either tag -- the same
    // ambiguity "られる" already carries.
    const cases = [_]struct { text: []const u8, term: []const u8 }{
        .{ .text = "食べれば", .term = "食べる" },
        .{ .text = "分かれば", .term = "分かる" },
        .{ .text = "書けば", .term = "書く" },
        .{ .text = "高ければ", .term = "高い" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.ProvisionalNotReached;
        try testz.expectEqualStr(hit.reason.?, "provisional");
        try testz.expectEqual(hit.depth, 1);
    }
}

pub fn dictLookupChainsNegativeProvisionalWithNoRowOfItsOwnTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // There is deliberately no "なければ" row: the adjective "ければ" row
    // strips 食べなければ to 食べない, and the negative rows take it from
    // there. The chain reads "negative, provisional", which is what
    // 食べなければ is.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べなければ")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "negative, provisional");
}

pub fn dictLookupDeinflectsImperativeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // The only single-kana rules in the table. 待て also matches the
    // existing te-form "て" -> "る", which finds nothing here -- each rule
    // only ever resolves its own class.
    const cases = [_]struct { text: []const u8, term: []const u8 }{
        .{ .text = "食べろ", .term = "食べる" },
        .{ .text = "書け", .term = "書く" },
        .{ .text = "待て", .term = "待つ" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.ImperativeNotReached;
        try testz.expectEqualStr(hit.reason.?, "imperative");
        try testz.expectEqual(hit.depth, 1);
    }
}

pub fn dictLookupChainsPoliteVolitionalThroughMasuTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // One non-terminal row onto the polite non-past, which the -masu rules
    // then take to the headword.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べましょう")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "polite, polite volitional");
    try testz.expectEqual(m.hits[0].depth, 2);
}

pub fn dictLookupChainsFiveRulesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // 食べさせられたくなかった -- causative, passive/potential,
    // desiderative, negative, past: five rule applications, which was the
    // old depth cap exactly.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べさせられたくなかった")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqual(m.hits[0].depth, 5);
    try testz.expectEqualStr(
        m.hits[0].reason.?,
        "causative, passive/potential, desiderative, negative, past",
    );
}

pub fn dictLookupChainsPastTheOldDepthCapTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{}, null);
    defer d.deinit();
    // The same form plus -tara: six rules. Unreachable while the search
    // stopped at five; with conditions checked at every step there is no
    // grammar cap, only the `max_chain_rules` runaway guard.
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べさせられたくなかったら")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqual(m.hits[0].depth, 6);
    try testz.expectEqualStr(
        m.hits[0].reason.?,
        "causative, passive/potential, desiderative, negative, past, conditional",
    );
}

// ─── dict: derived forms, the copula, and the dialect negatives ──────────
//
// Its own fixture again, for the same reason `irregular_dict_json` has
// one: the na-adjectives and nouns here carry an *empty* `rules` column,
// which is exactly what the copula rows' empty `conditions_out` exists to
// accept, and adding them to the shared fixture would change the hit
// counts the tests above assert exactly.

const derived_dict_json =
    \\[
    \\  ["綺麗","きれい","","",0,["pretty; clean"],1,""],
    \\  ["静か","しずか","","",0,["quiet; calm"],2,""],
    \\  ["学生","がくせい","","",0,["student"],3,""],
    \\  ["高い","たかい","","adj-i",0,["high; tall"],4,""],
    \\  ["早い","はやい","","adj-i",0,["fast; early"],5,""],
    \\  ["食べる","たべる","","v1",0,["to eat"],6,""],
    \\  ["見る","みる","","v1",0,["to see"],7,""],
    \\  ["飲む","のむ","","v5",0,["to drink"],8,""],
    \\  ["書く","かく","","v5",0,["to write"],9,""],
    \\  ["泳ぐ","およぐ","","v5",0,["to swim"],10,""],
    \\  ["知る","しる","","v5",0,["to know"],11,""],
    \\  ["行く","いく","","v5",0,["to go"],12,""],
    \\  ["分かる","わかる","","v5",0,["to understand"],13,""],
    \\  ["話す","はなす","","v5",0,["to speak"],14,""],
    \\  ["降る","ふる","","v5",0,["to fall (rain)"],15,""]
    \\]
;

pub fn dictLookupStripsTheCopulaOffANaAdjectiveTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // A na-adjective has no class tag at all -- its `rules` column is
    // empty -- so these are the only rules in the table with an empty
    // `conditions_out`, meaning "any row will do". Nothing else could
    // validate 綺麗だった -> 綺麗.
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "綺麗だった", .term = "綺麗", .reason = "copula past" },
        .{ .text = "静かじゃない", .term = "静か", .reason = "negative copula" },
        .{ .text = "静かではない", .term = "静か", .reason = "negative copula" },
        .{ .text = "学生でした", .term = "学生", .reason = "polite copula past" },
        .{ .text = "学生です", .term = "学生", .reason = "polite copula" },
        .{ .text = "静かな", .term = "静か", .reason = "attributive" },
        .{ .text = "静かに", .term = "静か", .reason = "adverbial" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        try testz.expectEqualStr(m.hits[0].entry.term, c.term);
        try testz.expectEqualStr(m.hits[0].reason.?, c.reason);
    }
}

pub fn dictLookupChainsTheNegativePastCopulaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // No じゃなかった row is needed: "ない" is an i-adjective, so
    // じゃなかった is じゃない plus the adjective past, and the "かった" ->
    // "い" row reduces it to 静かじゃない for the copula row to strip.
    //
    // The chain therefore reads "past", not "negative past" -- the
    // dedicated なかった row produces the identical string but sits later
    // in the table and loses the tie. See its comment in `dict.zig`.
    const m = (try dict.lookup(alloc, &d, null, .rank, "静かじゃなかった")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "静か");
    try testz.expectEqualStr(m.hits[0].reason.?, "negative copula, past");
}

pub fn dictLookupDeinflectsAdjectiveDerivationsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // 高さ and 早く resolved before only because Jitendex lexicalizes
    // them; as rules they work for any i-adjective.
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "高さ", .term = "高い", .reason = "nominalizer" },
        .{ .text = "早く", .term = "早い", .reason = "adverbial" },
        .{ .text = "高そう", .term = "高い", .reason = "appearance" },
        .{ .text = "高すぎる", .term = "高い", .reason = "excessive" },
        .{ .text = "高かろう", .term = "高い", .reason = "presumptive" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        try testz.expectEqualStr(m.hits[0].entry.term, c.term);
        try testz.expectEqualStr(m.hits[0].reason.?, c.reason);
    }
}

pub fn dictLookupRejectsTheAdverbialRuleOnAVerbTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // The "く" -> "い" adverbial rule also matches 行く, which would
    // "deinflect" to 行い -- the `adj-i` filter is what stops that, since
    // no such row exists here and a noun row would not carry the tag. The
    // verb itself must still be found, at depth 0.
    const m = (try dict.lookup(alloc, &d, null, .rank, "行く")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "行く");
    try testz.expectTrue(m.hits[0].reason == null);
}

pub fn dictLookupDeinflectsVerbalAppearanceAndExcessiveTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "降りそう", .term = "降る", .reason = "appearance" },
        .{ .text = "食べそう", .term = "食べる", .reason = "appearance" },
        .{ .text = "飲みすぎる", .term = "飲む", .reason = "excessive" },
        .{ .text = "食べすぎる", .term = "食べる", .reason = "excessive" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.DerivationNotReached;
        try testz.expectEqualStr(hit.reason.?, c.reason);
    }
}

pub fn dictLookupChainsTeFormCompoundsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // Every one of these is non-terminal onto the te-form, so the existing
    // te-form rows finish it -- two rule applications, and the voiced で
    // variant matters for the -んで verbs (飲んじゃう, not 飲んちゃう).
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "食べちゃう", .term = "食べる", .reason = "te-form, completive" },
        .{ .text = "飲んじゃう", .term = "飲む", .reason = "te-form, completive" },
        .{ .text = "食べてしまう", .term = "食べる", .reason = "te-form, completive" },
        .{ .text = "書いておく", .term = "書く", .reason = "te-form, preparatory" },
        .{ .text = "書いとく", .term = "書く", .reason = "te-form, preparatory" },
        .{ .text = "見てくる", .term = "見る", .reason = "te-form, continuative" },
        .{ .text = "食べてみる", .term = "食べる", .reason = "te-form, attemptive" },
        .{ .text = "書いてある", .term = "書く", .reason = "te-form, resultative" },
        .{ .text = "食べてくれる", .term = "食べる", .reason = "te-form, benefactive" },
        .{ .text = "見とる", .term = "見る", .reason = "te-form, Kansai progressive" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.CompoundNotReached;
        try testz.expectEqualStr(hit.reason.?, c.reason);
        try testz.expectEqual(hit.depth, 2);
    }
}

pub fn dictLookupChainsClassicalAndDialectNegativesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // One rule each, straight to the verb -- Yomitan's rows. They used to
    // put ない back and chain through the negative rows, which conditions
    // can't express without also accepting the bare adjective ない; see
    // dictLookupNegativeEndingsNeverLandOnTheAdjectiveNaiTest.
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "知らぬ", .term = "知る", .reason = "classical negative" },
        .{ .text = "行かず", .term = "行く", .reason = "classical negative" },
        .{ .text = "分からん", .term = "分かる", .reason = "colloquial negative" },
        .{ .text = "分からへん", .term = "分かる", .reason = "Kansai negative" },
        .{ .text = "食べん", .term = "食べる", .reason = "colloquial negative" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.NegativeNotReached;
        try testz.expectEqualStr(hit.reason.?, c.reason);
        try testz.expectEqual(hit.depth, 1);
    }
}

pub fn dictLookupChainsClassicalNegativeThroughTheAdverbialTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // 行かずに -- the "に" row strips the adverbial, leaving 行かず in no
    // conditions at all, so the outermost-only かず row may still take it.
    // Two rules, and neither had to know about the combination.
    const m = (try dict.lookup(alloc, &d, null, .rank, "行かずに")).?;
    defer m.deinit(alloc);
    const hit = hitFor(m, "行く") orelse return error.NegativeNotReached;
    try testz.expectEqualStr(hit.reason.?, "classical negative, adverbial");
    try testz.expectEqual(hit.depth, 2);
}

// ─── dict: condition sets ────────────────────────────────────────────────
//
// Its own fixture: the bare adjective ない and a few homographs whose whole
// purpose is to be the *wrong* answer a looser search would offer.

const conditions_dict_json =
    \\[
    \\  ["無い","ない","","adj-i",0,["nonexistent"],1,""],
    \\  ["ん","ん","","",0,["yeah"],2,""],
    \\  ["変","へん","","",0,["strange"],3,""],
    \\  ["言う","いう","","v5",0,["to say"],4,""],
    \\  ["分かる","わかる","","v5",0,["to understand"],5,""],
    \\  ["上手い","うまい","","adj-i",0,["skilful"],6,""],
    \\  ["凄い","すごい","","adj-i",0,["amazing"],7,""],
    \\  ["駆る","かる","","v5",0,["to drive"],8,""],
    \\  ["から","から","","",0,["from"],9,""]
    \\]
;

pub fn dictConditionsMatchTest(_: std.Io, _: std.mem.Allocator) !void {
    const cond = dict.cond;
    // The text as written is in no conditions, and anything may apply to it.
    try testz.expectTrue(dict.conditionsMatch(cond.none, cond.ta));
    try testz.expectTrue(dict.conditionsMatch(cond.none, cond.none));
    // Otherwise the two must share a condition...
    try testz.expectTrue(dict.conditionsMatch(cond.ta, cond.ta));
    try testz.expectFalse(dict.conditionsMatch(cond.te, cond.ta));
    // ...so an outermost-only rule (empty `conditions_in`) never applies
    // deeper in a chain.
    try testz.expectFalse(dict.conditionsMatch(cond.v1, cond.none));
    // An umbrella class matches each of its subconditions.
    try testz.expectTrue(dict.conditionsMatch(cond.v1, cond.v1p));
    try testz.expectTrue(dict.conditionsMatch(cond.v5d, cond.v5));
    try testz.expectTrue(dict.conditionsMatch(cond.vs, cond.v));
    try testz.expectFalse(dict.conditionsMatch(cond.adj_i, cond.v));
}

pub fn dictConditionsForRulesTest(_: std.Io, _: std.mem.Allocator) !void {
    const cond = dict.cond;
    try testz.expectTrue(dict.conditionsForRules("v1").eql(cond.v1));
    try testz.expectTrue(dict.conditionsForRules("vs v5").eql(cond.vs.unionWith(cond.v5)));
    try testz.expectTrue(dict.conditionsForRules("adj-i").eql(cond.adj_i));
    // Only dictionary-form classes count; a noun's empty column and any
    // unknown tag are no conditions at all.
    try testz.expectTrue(dict.conditionsForRules("").eql(cond.none));
    try testz.expectTrue(dict.conditionsForRules("adj-na").eql(cond.none));
}

pub fn dictLookupNegativeEndingsNeverLandOnTheAdjectiveNaiTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{conditions_dict_json}, &.{}, null);
    defer d.deinit();
    // The ぬ/ず/ん/へん rows go straight to a verb class. When they put ない
    // back instead, ない was `adj-i` -- exactly the bare adjective's class --
    // so a lone ん or へん offered 無い as a deinflected hit.
    for ([_][]const u8{ "ん", "へん", "ず", "ぬ" }) |text| {
        if (try dict.lookup(alloc, &d, null, .rank, text)) |m| {
            defer m.deinit(alloc);
            try testz.expectTrue(hitFor(m, "無い") == null);
        }
    }
}

pub fn dictLookupChecksConditionsAtEveryStepTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{conditions_dict_json}, &.{}, null);
    defer d.deinit();
    // からね reached 駆る under the old search: ね -> ぬ "imperative", then
    // らぬ -> る "classical negative". The imperative leaves a godan verb,
    // and the -ぬ negative only ever applies to the text as written, so
    // checking conditions at each step rules the second rule out.
    const m = (try dict.lookup(alloc, &d, null, .rank, "からね")).?;
    defer m.deinit(alloc);
    try testz.expectTrue(hitFor(m, "駆る") == null);
    try testz.expectEqualStr(m.hits[0].entry.term, "から");
}

pub fn dictLookupDeinflectsSlangSoundChangesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{conditions_dict_json}, &.{}, null);
    defer d.deinit();
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "言わねえ", .term = "言う", .reason = "negative, slang" },
        .{ .text = "分からねぇ", .term = "分かる", .reason = "negative, slang" },
        .{ .text = "上手くねえ", .term = "上手い", .reason = "negative, slang" },
        .{ .text = "すげえ", .term = "凄い", .reason = "slang" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.SlangNotReached;
        try testz.expectEqualStr(hit.reason.?, c.reason);
    }
}

pub fn dictLookupChainsKansaiNegativePastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{conditions_dict_json}, &.{}, null);
    defer d.deinit();
    // Yomitan's へんかった -> なかった keeps the -た condition, so the
    // adjective past and the godan negative finish it.
    const m = (try dict.lookup(alloc, &d, null, .rank, "分からへんかった")).?;
    defer m.deinit(alloc);
    const hit = hitFor(m, "分かる") orelse return error.NegativeNotReached;
    try testz.expectEqualStr(hit.reason.?, "negative, past, Kansai negative");
    try testz.expectEqual(hit.depth, 3);
}

pub fn dictLookupPoliteNegativePastBeatsTheCopulaOnTableOrderTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // Two rules reduce 食べませんでした to 食べません at the same depth:
    // the specific "ませんでした" row and the copula's "でした" -> "".
    // `Search.offer` keeps whichever was offered first, which is whichever
    // comes first in `deinflect_rules` -- so the specific row has to stay
    // above the copula block. Below it, this reads "polite negative,
    // polite copula past".
    const m = (try dict.lookup(alloc, &d, null, .rank, "食べませんでした")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "食べる");
    try testz.expectEqualStr(m.hits[0].reason.?, "polite negative, polite negative past");
}

pub fn dictLookupResolvesGodanSuCausativeAndPotentialTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{derived_dict_json}, &.{}, null);
    defer d.deinit();
    // The two gaps the earlier phases left: the godan す causative row the
    // table's doc comment had been admitting was missing, and godan
    // potential, which is a different form from the passive/potential
    // -areru and only worked before where the dictionary lexicalized it.
    const cases = [_]struct { text: []const u8, term: []const u8, reason: []const u8 }{
        .{ .text = "話させる", .term = "話す", .reason = "causative" },
        .{ .text = "泳げる", .term = "泳ぐ", .reason = "potential" },
        .{ .text = "書ける", .term = "書く", .reason = "potential" },
        .{ .text = "書けない", .term = "書く", .reason = "potential, negative" },
    };
    for (cases) |c| {
        const m = (try dict.lookup(alloc, &d, null, .rank, c.text)).?;
        defer m.deinit(alloc);
        const hit = hitFor(m, c.term) orelse return error.GapNotClosed;
        try testz.expectEqualStr(hit.reason.?, c.reason);
    }
}

// ─── dict: frequency data (term_meta_bank) ───────────────────────────────
//
// A frequency list is just another Yomitan dictionary directory whose banks
// happen to be `term_meta_bank_*.json`, so `openMemory` takes them as a
// second list and the same build path indexes them. These pin the five
// `data` shapes the format allows, the term/reading matching rules, and the
// ranking change -- which is the whole reason to load the data.

/// Shaped like a real rank-based frequency list (JPDB, Innocent Corpus):
/// lower is more common. Covers all five `data` shapes from
/// `parseFrequency`, plus a "pitch" row that must be ignored.
const freq_meta_json =
    \\[
    \\  ["する","freq",38],
    \\  ["下","freq","910"],
    \\  ["面白い","freq",{"value":1200,"displayValue":"1200㋕"}],
    \\  ["今日","freq",{"reading":"きょう","frequency":52}],
    \\  ["猫","freq",{"reading":"ねこ","frequency":{"value":2400,"displayValue":"2400"}}],
    \\  ["する","pitch",{"reading":"する","pitches":[]}]
    \\]
;

const freq_terms_json =
    \\[
    \\  ["する","する","","vs",0,["to do"],1,""],
    \\  ["下","した","","",0,["below; down"],2,""],
    \\  ["面白い","おもしろい","","adj-i",0,["interesting"],3,""],
    \\  ["今日","きょう","","",0,["today"],4,""],
    \\  ["今日","こんにち","","",0,["these days"],5,""],
    \\  ["猫","ねこ","","",0,["cat"],6,""]
    \\]
;

pub fn dictFrequencyParsesEveryDataShapeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    try testz.expectTrue(dict.hasFrequency(&d));

    // A bare number, a numeric string, a value/displayValue object, and a
    // reading-specific object wrapping either shape.
    const bare = dict.frequencyFor(&d, .rank, "する", "する").?;
    try testz.expectEqual(bare.value, 38);
    const as_text = dict.frequencyFor(&d, .rank, "下", "した").?;
    try testz.expectEqual(as_text.value, 910);
    const with_display = dict.frequencyFor(&d, .rank, "面白い", "おもしろい").?;
    try testz.expectEqual(with_display.value, 1200);
    try testz.expectEqualStr(with_display.display, "1200㋕");
    const nested = dict.frequencyFor(&d, .rank, "猫", "ねこ").?;
    try testz.expectEqual(nested.value, 2400);
    try testz.expectEqualStr(nested.display, "2400");
}

pub fn dictFrequencyIgnoresNonFrequencyMetaRowsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{
        \\[["する","pitch",{"reading":"する","pitches":[{"position":0}]}],
        \\ ["する","ipa",{"reading":"する","transcriptions":[]}]]
    }, null);
    defer d.deinit();
    // Only "freq" rows are kept -- pitch accent is display-only and has
    // nowhere to go yet, and an ipa row is not a number at all.
    try testz.expectFalse(dict.hasFrequency(&d));
    try testz.expectTrue(dict.frequencyFor(&d, .rank, "する", "する") == null);
}

pub fn dictFrequencyAppliesAReadingSpecificRowToThatReadingOnlyTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    // 今日's row names きょう. The こんにち headword shares the kanji but is
    // a different word, so the row says nothing about it -- applying it
    // anyway would rank a rare reading as one of the commonest words.
    const kyou = dict.frequencyFor(&d, .rank, "今日", "きょう").?;
    try testz.expectEqual(kyou.value, 52);
    try testz.expectTrue(dict.frequencyFor(&d, .rank, "今日", "こんにち") == null);
}

pub fn dictFrequencyFallsBackToTheReadingColumnTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A frequency list files a kana-written word under the kana while
    // Jitendex files it under the kanji, so a row matching the *reading*
    // still counts -- otherwise a kana list and a kanji dictionary never
    // meet.
    var d = try dict.openMemory(alloc, &.{
        \\[["面白い","おもしろい","","adj-i",0,["interesting"],1,""]]
    }, &.{
        \\[["おもしろい","freq",300]]
    }, null);
    defer d.deinit();
    const got = dict.frequencyFor(&d, .rank, "面白い", "おもしろい").?;
    try testz.expectEqual(got.value, 300);
}

pub fn dictFrequencyPrefersTheTermRowOverTheReadingRowTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{
        \\[["面白い","おもしろい","","adj-i",0,["interesting"],1,""]]
    }, &.{
        \\[["おもしろい","freq",300],["面白い","freq",1200]]
    }, null);
    defer d.deinit();
    // Both match. The one filed under the headword itself wins, even
    // though the other names a "more common" number -- agreeing with the
    // headword beats agreeing with its reading.
    const got = dict.frequencyFor(&d, .rank, "面白い", "おもしろい").?;
    try testz.expectEqual(got.value, 1200);
}

pub fn dictFrequencyOrderDecidesWhichNumberIsCommonerTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{
        \\[["猫","ねこ","","",0,["cat"],1,""]]
    }, &.{
        \\[["猫","freq",100],["猫","freq",9000]]
    }, null);
    defer d.deinit();
    // Two rows for one word, which real lists do carry. Under "rank" the
    // smaller number is the commoner one; under "count" the larger is.
    // Nothing in the file says which, hence the config key.
    try testz.expectEqual(dict.frequencyFor(&d, .rank, "猫", "ねこ").?.value, 100);
    try testz.expectEqual(dict.frequencyFor(&d, .count, "猫", "ねこ").?.value, 9000);
}

pub fn dictLookupRanksByFrequencyAboveDeinflectionDepthTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    // The payoff, and the reason frequency outranks depth. した is the
    // past of する (one rule) and also the noun 下 "below" (no rules), so
    // "fewest rules wins" put 下 first -- confidently wrong for the
    // commonest verb in the language. With frequency loaded, する's 38
    // beats 下's 910 and the verb comes first.
    const ranked = (try dict.lookup(alloc, &d, &d, .rank, "した")).?;
    defer ranked.deinit(alloc);
    try testz.expectEqualStr(ranked.hits[0].entry.term, "する");
    try testz.expectEqualStr(ranked.hits[0].reason.?, "past");
    try testz.expectEqual(ranked.hits[0].frequency.?, 38);
    try testz.expectEqualStr(ranked.hits[1].entry.term, "下");

    // Without the frequency dictionary, the old order stands -- which is
    // what keeps every other test in this file valid.
    const plain = (try dict.lookup(alloc, &d, null, .rank, "した")).?;
    defer plain.deinit(alloc);
    try testz.expectEqualStr(plain.hits[0].entry.term, "下");
    try testz.expectTrue(plain.hits[0].frequency == null);
}

pub fn dictLookupSortsUnrankedHitsLastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    // 今日 has two headwords and the frequency list only ranks きょう.
    // Silence about こんにち is weak evidence of rarity, not a neutral
    // "unknown" -- so the ranked one leads and the unranked one follows,
    // rather than the unranked one jumping ahead on some other tiebreak.
    const m = (try dict.lookup(alloc, &d, &d, .rank, "今日")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 2);
    try testz.expectEqualStr(m.hits[0].entry.reading, "きょう");
    try testz.expectEqual(m.hits[0].frequency.?, 52);
    try testz.expectEqualStr(m.hits[1].entry.reading, "こんにち");
    try testz.expectTrue(m.hits[1].frequency == null);
}

pub fn dictLookupKeepsLongestSourceAheadOfFrequencyTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    // Frequency outranks depth but *not* source length: 面白い is rarer
    // than する by these numbers, and still has to win for the text
    // 面白いした, because it covers more of what was clicked. Otherwise a
    // common short word would swallow every longer match.
    const m = (try dict.lookup(alloc, &d, &d, .rank, "面白いした")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "面白い");
    try testz.expectEqualStr("面白いした"[0..m.len()], "面白い");
}

pub fn dictFrequencyCarriesItsDisplayTextOntoTheHitTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{freq_terms_json}, &.{freq_meta_json}, null);
    defer d.deinit();
    // The list's own rendering survives to the hit, for the panel to show
    // the way Yomitan does. It is owned by the lookup's allocator, not
    // SQLite's row buffer, which the next step would have overwritten.
    const m = (try dict.lookup(alloc, &d, &d, .rank, "面白い")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "面白い");
    try testz.expectEqual(m.hits[0].frequency.?, 1200);
    try testz.expectEqualStr(m.hits[0].frequency_display, "1200㋕");
}

// ─── dict: grouping spellings into one entry ──────────────────────────────
//
// `Match.groups` collapses hits that are the same *word* into one entry, so
// the lookup panel can list entries rather than rows. The key is the term
// bank's `sequence` -- the JMdict entry id -- for reasons the fixtures below
// make concrete.

/// Modelled on the real cases in a Jitendex build:
/// - する / 為る: different terms, **one** sequence, identical senses.
/// - ああ / ああ: same term and reading, **two** sequences, different senses.
/// - 合判 / 合い判: spelling variants sharing a sequence.
/// - 猫: no sequence at all (0).
const group_dict_json =
    \\[
    \\  ["する","する","","vs",200,["to do"],1157170,""],
    \\  ["為る","する","","vs",-101,["to do"],1157170,""],
    \\  ["ああ","ああ","","",200,["like that; so"],2085080,""],
    \\  ["ああ","ああ","","",200,["ah!; oh!"],1565440,""],
    \\  ["合判","あいばん","","",-4,["official seal"],2691870,""],
    \\  ["合い判","あいばん","","",-5,["official seal"],2691870,""],
    \\  ["猫","ねこ","","",0,["cat"],0,""]
    \\]
;

pub fn dictLookupGroupsSpellingsThatShareASequenceTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{group_dict_json}, &.{}, null);
    defer d.deinit();
    // する and 為る are one word written two ways: one sequence, identical
    // glossaries. Two hits, one entry -- which is also what stops the
    // frequency ranking showing the same word twice at the top of the list.
    const m = (try dict.lookup(alloc, &d, null, .rank, "する")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 2);
    try testz.expectEqual(m.groups.len, 1);
    // The better-scoring spelling leads and the other becomes an alternate.
    try testz.expectEqualStr(m.hits[m.groups[0].primary].entry.term, "する");
    try testz.expectEqual(m.groups[0].others.len, 1);
    try testz.expectEqualStr(m.hits[m.groups[0].others[0]].entry.term, "為る");
}

pub fn dictLookupKeepsDifferentSequencesApartTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{group_dict_json}, &.{}, null);
    defer d.deinit();
    // The case that rules out grouping on term+reading: both ああ rows have
    // the same term *and* the same reading, but they are different words
    // ("like that" vs "ah!") with different sequences. Fusing them would
    // merge two unrelated meanings into one entry.
    const m = (try dict.lookup(alloc, &d, null, .rank, "ああ")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 2);
    try testz.expectEqual(m.groups.len, 2);
    try testz.expectEqual(m.groups[0].others.len, 0);
    try testz.expectEqual(m.groups[1].others.len, 0);
}

pub fn dictLookupGroupsSpellingVariantsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{group_dict_json}, &.{}, null);
    defer d.deinit();
    // 合判 and 合い判 differ only by an okurigana い. One sequence, so one
    // entry -- reached here through the *reading*, which both share.
    const m = (try dict.lookup(alloc, &d, null, .rank, "あいばん")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.groups.len, 1);
    try testz.expectEqual(m.groups[0].others.len, 1);
}

pub fn dictLookupNeverMergesRowsWithNoSequenceTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A sequence of 0 means the term bank said nothing about which entry the
    // row belongs to, so there is no evidence two such rows are one word --
    // they each get their own entry rather than all collapsing into one.
    var d = try dict.openMemory(alloc, &.{
        \\[["猫","ねこ","","",0,["cat"],0,""],
        \\ ["寝子","ねこ","","",0,["sleeping child"],0,""]]
    }, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "ねこ")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 2);
    try testz.expectEqual(m.groups.len, 2);
}

pub fn dictLookupGroupOrderFollowsHitRankingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{group_dict_json}, &.{
        \\[["する","freq",38]]
    }, null);
    defer d.deinit();
    // Groups are built by walking `hits` in rank order, so the best hit
    // overall heads the first group and `groups[0].primary` is always hit 0.
    // That is what lets the panel focus entry 0 and get the best answer.
    const m = (try dict.lookup(alloc, &d, &d, .rank, "する")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.groups[0].primary, 0);
    try testz.expectEqualStr(m.hits[0].entry.term, "する");

    // Every hit belongs to exactly one group, as a primary or an alternate.
    var seen: usize = 0;
    for (m.groups) |g| seen += 1 + g.others.len;
    try testz.expectEqual(seen, m.hits.len);
}

pub fn dictLookupGroupsEveryHitOfARealisticLookupTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{group_dict_json}, &.{}, null);
    defer d.deinit();
    // The invariant the panel depends on across a lookup that reaches
    // several lengths and several words at once: no hit is dropped, none is
    // counted twice, and no group is empty.
    const m = (try dict.lookup(alloc, &d, null, .rank, "する")).?;
    defer m.deinit(alloc);
    var counted = try alloc.alloc(bool, m.hits.len);
    defer alloc.free(counted);
    @memset(counted, false);
    for (m.groups) |g| {
        try testz.expectFalse(counted[g.primary]);
        counted[g.primary] = true;
        for (g.others) |o| {
            try testz.expectFalse(counted[o]);
            counted[o] = true;
        }
    }
    for (counted) |c| try testz.expectTrue(c);
}

// ─── dict: Yomitan parity (reading column, all lengths, ranking) ────────

/// Shaped like Jitendex: kana-written words are filed under their kanji
/// headword, with the kana only in the reading.
const parity_dict_json =
    \\[
    \\  ["面白い","おもしろい","","adj-i",0,["interesting"],10,""],
    \\  ["お","","","",0,["o (interjection)"],11,""],
    \\  ["御","お","","",0,["honorific prefix"],12,""],
    \\  ["凄い","すごい","","adj-i",0,["amazing"],13,""],
    \\  ["猫","ねこ","","n",0,["cat"],14,""],
    \\  ["猫舌","ねこじた","","n",0,["sensitive to hot food"],15,""],
    \\  ["橋","はし","","n",5,["bridge"],16,""],
    \\  ["箸","はし","","n",9,["chopsticks"],17,""],
    \\  ["はし","","","n",0,["edge (kana)"],18,""]
    \\]
;

pub fn dictLookupMatchesTheReadingColumnTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    // The whole point: おもしろい is only a reading, and a term-only
    // search used to fall all the way back to the interjection お.
    const m = (try dict.lookup(alloc, &d, null, .rank, "おもしろいね")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "面白い");
    try testz.expectEqual(m.len(), "おもしろい".len);
    try testz.expectFalse(m.hits[0].exact);
}

pub fn dictLookupReadingMatchDeinflectsTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "おもしろくない")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "面白い");
    try testz.expectEqualStr(m.hits[0].reason.?, "negative");
}

pub fn dictLookupKeepsShorterLengthsBelowTheLongestTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "猫舌だ")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 2);
    try testz.expectEqualStr(m.hits[0].entry.term, "猫舌");
    try testz.expectEqual(m.hits[0].source_len, "猫舌".len);
    try testz.expectEqualStr(m.hits[1].entry.term, "猫");
    try testz.expectEqual(m.hits[1].source_len, "猫".len);
}

pub fn dictLookupRanksShortPrefixesBelowTheLongMatchTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "おもしろい")).?;
    defer m.deinit(alloc);
    // 面白い first, then the one-character お entries after it -- the
    // exact-term お (the interjection) ahead of 御, which only reads お.
    try testz.expectEqualStr(m.hits[0].entry.term, "面白い");
    try testz.expectEqualStr(m.hits[1].entry.term, "お");
    try testz.expectTrue(m.hits[1].exact);
    try testz.expectEqualStr(m.hits[2].entry.term, "御");
}

pub fn dictLookupRanksExactTermThenScoreTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "はし")).?;
    defer m.deinit(alloc);
    try testz.expectEqual(m.hits.len, 3);
    // Kana headword that *is* the text first, then the reading-only
    // matches by the dictionary's own score, higher first.
    try testz.expectEqualStr(m.hits[0].entry.term, "はし");
    try testz.expectEqualStr(m.hits[1].entry.term, "箸");
    try testz.expectEqual(m.hits[1].entry.score, 9);
    try testz.expectEqualStr(m.hits[2].entry.term, "橋");
}

pub fn dictLookupEmptyReadingIsStoredAsTheTermTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "はし")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.reading, "はし");
}

pub fn dictLookupFindsKatakanaSpellingOfAHiraganaReadingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "スゴイ!")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "凄い");
    try testz.expectEqual(m.len(), "スゴイ".len);
    try testz.expectEqual(m.hits[0].variant_steps, 1);
}

pub fn dictLookupCollapsesEmphaticSequencesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    const m = (try dict.lookup(alloc, &d, null, .rank, "すっっごーーい")).?;
    defer m.deinit(alloc);
    try testz.expectEqualStr(m.hits[0].entry.term, "凄い");
    try testz.expectEqual(m.len(), "すっっごーーい".len);
}

pub fn dictLookupKeepsEachEntryOnceFromItsBestRouteTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{parity_dict_json}, &.{}, null);
    defer d.deinit();
    // ねこ reaches 猫 at its own length, and 猫 again as a prefix of
    // ねこじた -- only once, from the longer route.
    const m = (try dict.lookup(alloc, &d, null, .rank, "ねこじた")).?;
    defer m.deinit(alloc);
    var cats: usize = 0;
    for (m.hits) |h| {
        if (std.mem.eql(u8, h.entry.term, "猫")) cats += 1;
    }
    try testz.expectEqual(cats, 1);
    try testz.expectEqualStr(m.hits[0].entry.term, "猫舌");
}

pub fn dictOpenMemoryReadsTitleFromIndexJsonTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var d = try dict.openMemory(alloc, &.{lookup_dict_json}, &.{},
        \\{"title":"Test Dict","format":3,"revision":"1"}
    );
    defer d.deinit();
    try testz.expectEqualStr(d.title, "Test Dict");
}

// ─── dict: loadFromDir builds then reuses index.sqlite3 ─────────────────

pub fn dictLoadFromDirBuildsThenReusesTheSqliteIndexTest(io: std.Io, alloc: std.mem.Allocator) !void {
    const dir_path = "zig-cache/tmp/dict_load_from_dir_test";
    std.Io.Dir.cwd().deleteTree(io, dir_path) catch {};
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    defer std.Io.Dir.cwd().deleteTree(io, dir_path) catch {};

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = dir_path ++ "/term_bank_1.json",
        .data = lookup_dict_json,
    });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = dir_path ++ "/index.json",
        .data =
        \\{"title":"Test Dict","format":3,"revision":"1"}
        ,
    });

    var d = try dict.loadFromDir(alloc, io, dir_path);
    try testz.expectEqualStr(d.title, "Test Dict");
    const m = (try dict.lookup(alloc, &d, null, .rank, "猫")).?;
    try testz.expectEqualStr(m.hits[0].entry.term, "猫");
    m.deinit(alloc);
    d.deinit();

    // A second open must find `index.sqlite3` already built and reuse it
    // rather than re-parsing the term bank -- deleting the term bank
    // first means a spurious rebuild would find nothing and this lookup
    // would fail.
    try std.Io.Dir.cwd().deleteFile(io, dir_path ++ "/term_bank_1.json");
    var d2 = try dict.loadFromDir(alloc, io, dir_path);
    defer d2.deinit();
    const m2 = (try dict.lookup(alloc, &d2, null, .rank, "猫")).?;
    defer m2.deinit(alloc);
    try testz.expectEqualStr(m2.hits[0].entry.term, "猫");
}

// ─── dict: incremental Builder (progress panel's backing state) ─────────

pub fn dictBuilderStepsOneFileAtATimeThenOpensReadyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    const dir_path = "zig-cache/tmp/dict_builder_step_test";
    std.Io.Dir.cwd().deleteTree(io, dir_path) catch {};
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    defer std.Io.Dir.cwd().deleteTree(io, dir_path) catch {};

    // Split across two term bank files -- the whole point of `Builder`
    // is that `ui.zig` can watch progress land one file at a time.
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = dir_path ++ "/term_bank_1.json",
        .data =
        \\[["食べる","たべる","","v1",0,["to eat"],1,""]]
        ,
    });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = dir_path ++ "/term_bank_2.json",
        .data =
        \\[["猫","ねこ","","n",0,["cat"],2,""]]
        ,
    });

    var load = try dict.openOrBeginBuild(alloc, io, dir_path);
    var b = switch (load) {
        .building => |built| built,
        .ready => return error.TestExpectedABuildToStart,
    };
    errdefer b.deinit();

    try testz.expectEqual(b.totalFiles(), 2);
    try testz.expectFalse(b.isDone());
    try testz.expectEqual(b.terms_indexed, 0);

    try b.step();
    try testz.expectEqual(b.file_idx, 1);
    try testz.expectEqual(b.terms_indexed, 1);
    try testz.expectFalse(b.isDone());

    try b.step();
    try testz.expectEqual(b.file_idx, 2);
    try testz.expectEqual(b.terms_indexed, 2);
    try testz.expectTrue(b.isDone());

    var d = try b.finish();
    defer d.deinit();

    const m1 = (try dict.lookup(alloc, &d, null, .rank, "食べる")).?;
    m1.deinit(alloc);
    const m2 = (try dict.lookup(alloc, &d, null, .rank, "猫")).?;
    m2.deinit(alloc);

    // A dictionary `finish`'d once is a dictionary `isBuilt` from here
    // on -- a second open must not start another build.
    load = try dict.openOrBeginBuild(alloc, io, dir_path);
    switch (load) {
        .ready => |ready| {
            var r = ready;
            r.deinit();
        },
        .building => return error.TestExpectedTheIndexToAlreadyBeBuilt,
    }
}
