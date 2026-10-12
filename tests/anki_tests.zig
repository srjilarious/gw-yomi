// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const anki = @import("gw_yomi").anki;

// ─── anki ───────────────────────────────────────────────────────────────

fn expectFurigana(alloc: std.mem.Allocator, term: []const u8, reading: []const u8, want: []const u8) !void {
    const got = try anki.furigana(alloc, term, reading);
    defer alloc.free(got);
    try testz.expectEqualStr(got, want);
}

pub fn ankiFuriganaKeepsOkuriganaOutsideTheBracketTest(_: std.Io, alloc: std.mem.Allocator) !void {
    try expectFurigana(alloc, "見張る", "みはる", "見張[みは]る");
    try expectFurigana(alloc, "食べ物", "たべもの", "食[た]べ 物[もの]");
    try expectFurigana(alloc, "大人しい", "おとなしい", "大人[おとな]しい");
}

pub fn ankiFuriganaSpacesAKanjiRunAfterKanaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Without the space Anki would take お as part of the ruby base.
    try expectFurigana(alloc, "お茶", "おちゃ", "お 茶[ちゃ]");
}

pub fn ankiFuriganaWholeWordAndKanaOnlyCasesTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // One kanji run: the whole reading, however irregular.
    try expectFurigana(alloc, "犯罪集団", "はんざいしゅうだん", "犯罪集団[はんざいしゅうだん]");
    try expectFurigana(alloc, "今日", "きょう", "今日[きょう]");
    // Kana only, or no reading: no furigana at all, rather than the
    // Term field over again.
    try expectFurigana(alloc, "すごい", "すごい", "");
    try expectFurigana(alloc, "どいつもこいつも", "どいつもこいつも", "");
    try expectFurigana(alloc, "テレビ", "てれび", "");
    try expectFurigana(alloc, "尊敬", "", "");
}

pub fn ankiFuriganaFallsBackWhenTheKanaDisagreeTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // The term's own る isn't in the reading: bracket the whole word.
    try expectFurigana(alloc, "見張る", "みはった", "見張る[みはった]");
}

pub fn ankiSourceParsesEveryTagNameTest(_: std.Io, _: std.mem.Allocator) !void {
    for (anki.Source.all) |s| try testz.expectTrue(anki.Source.parse(@tagName(s)).? == s);
    try testz.expectTrue(anki.Source.parse("definition") == null);
}

pub fn ankiAudioUrlPercentEncodesTermAndReadingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const url = try anki.audioUrl(alloc, anki.jpod_audio_url, "尊敬", "そんけい");
    defer alloc.free(url);
    try testz.expectEqualStr(url, "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kanji=%E5%B0%8A%E6%95%AC&kana=%E3%81%9D%E3%82%93%E3%81%91%E3%81%84");
    try testz.expectTrue(anki.isJpodUrl(url));

    // No reading: the term stands in for it.
    const kana_only = try anki.audioUrl(alloc, "x?k={term}&r={reading}", "すごい", "");
    defer alloc.free(kana_only);
    try testz.expectEqualStr(kana_only, "x?k=%E3%81%99%E3%81%94%E3%81%84&r=%E3%81%99%E3%81%94%E3%81%84");
}

fn testNote(alloc: std.mem.Allocator) !anki.Note {
    return anki.Note.create(alloc, .{
        .term = "見張る",
        .reading = "みはる",
        .sentence = "変なコトしないか見張ってんのよ",
        // 見張っ
        .span_start = "変なコトしないか".len,
        .span_end = "変なコトしないか見張っ".len,
        .glossary = &.{ "to stand watch", "to keep an eye on <someone>" },
        .ai = "Line one\nLine two",
        .book = "Souten no Ken v01",
        .page = 12,
        .audio_template = anki.jpod_audio_url,
    });
}

pub fn ankiNoteSplitsTheClozeAroundTheWordTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var note = try testNote(alloc);
    defer note.deinit(alloc);
    try testz.expectEqualStr(note.cloze_before, "変なコトしないか");
    try testz.expectEqualStr(note.cloze_inside, "見張っ");
    try testz.expectEqualStr(note.cloze_after, "てんのよ");
    try testz.expectTrue(note.audio == .unknown);
}

pub fn ankiFieldValuesAreHtmlTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var note = try testNote(alloc);
    defer note.deinit(alloc);

    const meaning = try anki.fieldValue(alloc, &note, .meaning);
    defer alloc.free(meaning);
    try testz.expectEqualStr(meaning, "\u{25e6}  to stand watch<br>\u{25e6}  to keep an eye on &lt;someone&gt;");

    const notes = try anki.fieldValue(alloc, &note, .ai);
    defer alloc.free(notes);
    try testz.expectEqualStr(notes, "Line one<br>Line two");

    const page_no = try anki.fieldValue(alloc, &note, .page);
    defer alloc.free(page_no);
    try testz.expectEqualStr(page_no, "12");
}

pub fn ankiSentenceCardPutsTheAnswerInMeaningOnlyTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var note = try anki.Note.create(alloc, .{
        .kind = .sentence,
        .term = "すごいなぁ",
        .sentence = "すごいなぁ",
        .ai = "Wow.",
        .audio_template = anki.jpod_audio_url,
    });
    defer note.deinit(alloc);
    // No single word, so no audio.
    try testz.expectTrue(note.audio == .off);

    const meaning = try anki.fieldValue(alloc, &note, .meaning);
    defer alloc.free(meaning);
    try testz.expectEqualStr(meaning, "Wow.");
    const notes = try anki.fieldValue(alloc, &note, .ai);
    defer alloc.free(notes);
    try testz.expectEqualStr(notes, "");
}

pub fn ankiAddNoteCarriesFieldsAndMediaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var note = try testNote(alloc);
    defer note.deinit(alloc);
    note.setImage(alloc, .{ .jpeg = try alloc.dupe(u8, "JPEG"), .width = 4, .height = 2 });

    const body = try anki.buildAddNote(alloc, &note, .{
        .deck = "NihingoMine",
        .model = anki.default_model,
        .fields = &anki.default_fields,
        .tags = "gw-read manga",
        .stamp = "1234",
    });
    defer alloc.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try testz.expectEqualStr(root.get("action").?.string, "addNote");
    const n = root.get("params").?.object.get("note").?.object;
    try testz.expectEqualStr(n.get("deckName").?.string, "NihingoMine");
    const fields = n.get("fields").?.object;
    try testz.expectEqualStr(fields.get("Term").?.string, "見張る");
    try testz.expectEqualStr(fields.get("Furigana").?.string, "見張[みは]る");
    try testz.expectEqualStr(fields.get("Cloze Inside").?.string, "見張っ");
    try testz.expectEqualStr(fields.get("Context").?.string, "Souten no Ken v01");
    // Media fields are filled by AnkiConnect, not sent as text.
    try testz.expectTrue(fields.get("Image") == null);
    try testz.expectTrue(fields.get("Term Audio") == null);
    try testz.expectEqual(n.get("tags").?.array.items.len, 2);

    const pic = n.get("picture").?.array.items[0].object;
    try testz.expectEqualStr(pic.get("data").?.string, "SlBFRw==");
    try testz.expectEqualStr(pic.get("filename").?.string, "gw-read-1234.jpg");
    try testz.expectEqualStr(pic.get("fields").?.array.items[0].string, "Image");

    const audio = n.get("audio").?.array.items[0].object;
    try testz.expectEqualStr(audio.get("skipHash").?.string, anki.jpod_missing_md5);
    try testz.expectEqualStr(audio.get("fields").?.array.items[0].string, "Term Audio");
}

pub fn ankiAddNoteLeavesOutMissingMediaTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var note = try testNote(alloc);
    defer note.deinit(alloc);
    // The probe said there's no clip, and no image was taken.
    note.audio = .missing;

    const body = try anki.buildAddNote(alloc, &note, .{
        .deck = "d",
        .model = "m",
        .fields = &anki.default_fields,
        .stamp = "1",
    });
    defer alloc.free(body);
    try testz.expectTrue(std.mem.indexOf(u8, body, "\"picture\"") == null);
    try testz.expectTrue(std.mem.indexOf(u8, body, "\"audio\"") == null);
}

pub fn ankiParseReplyReadsResultAndErrorTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const ok = try anki.parseReply(alloc, 200, "{\"result\": 1496198395707, \"error\": null}");
    try testz.expectTrue(ok == .ok and ok.ok == 1496198395707);

    const dup = try anki.parseReply(alloc, 200, "{\"result\": null, \"error\": \"cannot create note because it is a duplicate\"}");
    defer alloc.free(dup.failure);
    try testz.expectEqualStr(dup.failure, "cannot create note because it is a duplicate");

    const junk = try anki.parseReply(alloc, 200, "<html>");
    defer alloc.free(junk.failure);
    try testz.expectTrue(junk == .failure);
}

