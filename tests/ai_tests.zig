// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// Moved from glyphwire's tests/read_tests.zig with the modules they cover.

const std = @import("std");
const testz = @import("testz");
const ai = @import("gw_yomi").ai;
const ai_cache = @import("gw_yomi").ai_cache;

// ─── ai: prompt, request and response ───────────────────────────────────

pub fn aiPromptLabelsTheBubbleAndItsContextTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "Brief, N3.", .{
        .dialog = "何だと？",
        .highlight = "何",
        .previous = "お前が犯人だ",
        .next = "証拠はある",
        .title = "Dragon Ball v01",
        .page = 12,
    });
    defer p.deinit(alloc);
    try testz.expectEqualStr(p.user,
        \\Book: Dragon Ball v01, page 12
        \\Previous bubble: お前が犯人だ
        \\Current bubble: 何だと？
        \\Next bubble: 証拠はある
        \\Highlighted: 何
        \\
    );
    // The fixed rules first, then the user's style.
    try testz.expectTrue(std.mem.startsWith(u8, p.instructions, ai.app_rules));
    try testz.expectTrue(std.mem.endsWith(u8, p.instructions, "\n\nBrief, N3."));
}

pub fn aiPromptLeavesOutWhatWasNotAskedForTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "よし" });
    defer p.deinit(alloc);
    try testz.expectEqualStr(p.user, "Current bubble: よし\n");
    try testz.expectEqualStr(p.instructions, ai.app_rules);
}

pub fn aiBookTitleIsTheFileNameNeverThePathTest(_: std.Io, _: std.mem.Allocator) !void {
    try testz.expectEqualStr(ai.bookTitle("/home/me/manga/Narutaru v01-05.cbz"), "Narutaru v01-05");
    try testz.expectEqualStr(ai.bookTitle("/home/me/manga/Dragon Ball v01-05/"), "Dragon Ball v01-05");
    // Only archive extensions are dropped.
    try testz.expectEqualStr(ai.bookTitle("/x/Vol 1.5"), "Vol 1.5");
    try testz.expectEqualStr(ai.bookTitle("Book.CBR"), "Book");
}

pub fn aiOpenAiBodyIsAResponsesRequestTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "やあ" });
    defer p.deinit(alloc);
    const body = try ai.buildBody(alloc, .openai, "gpt-5", p);
    defer alloc.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{});
    defer parsed.deinit();
    const o = parsed.value.object;
    try testz.expectEqualStr(o.get("model").?.string, "gpt-5");
    try testz.expectEqualStr(o.get("instructions").?.string, p.instructions);
    try testz.expectEqualStr(o.get("input").?.string, p.user);
}

pub fn aiOllamaBodyIsANonStreamingChatTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "やあ" });
    defer p.deinit(alloc);
    const body = try ai.buildBody(alloc, .ollama, "qwen2.5", p);
    defer alloc.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{});
    defer parsed.deinit();
    const o = parsed.value.object;
    try testz.expectEqualStr(o.get("model").?.string, "qwen2.5");
    try testz.expectFalse(o.get("stream").?.bool);
    const msgs = o.get("messages").?.array.items;
    try testz.expectEqual(msgs.len, 2);
    try testz.expectEqualStr(msgs[0].object.get("role").?.string, "system");
    try testz.expectEqualStr(msgs[1].object.get("content").?.string, p.user);
}

pub fn aiAnthropicBodyIsAMessagesRequestTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "やあ" });
    defer p.deinit(alloc);

    const body = try ai.buildBody(alloc, .anthropic, "claude-opus-5", p);
    defer alloc.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, body, .{});
    defer parsed.deinit();
    const o = parsed.value.object;
    try testz.expectEqualStr(o.get("model").?.string, "claude-opus-5");
    try testz.expectEqualStr(o.get("system").?.string, p.instructions);
    try testz.expectEqual(o.get("max_tokens").?.integer, 16000);
    const msgs = o.get("messages").?.array.items;
    try testz.expectEqual(msgs.len, 1);
    try testz.expectEqualStr(msgs[0].object.get("role").?.string, "user");
    try testz.expectEqualStr(msgs[0].object.get("content").?.string, p.user);
    // Opus 5 takes server-side refusal fallbacks...
    try testz.expectEqualStr(o.get("fallbacks").?.string, "default");

    // ...a model that doesn't publish fallback models would 400 on it.
    const older = try ai.buildBody(alloc, .anthropic, "claude-haiku-4-5", p);
    defer alloc.free(older);
    const parsed_older = try std.json.parseFromSlice(std.json.Value, alloc, older, .{});
    defer parsed_older.deinit();
    try testz.expectTrue(parsed_older.value.object.get("fallbacks") == null);
}

pub fn aiParsesAnAnthropicAnswerSkippingThinkingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const body =
        \\{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5",
        \\ "content":[
        \\   {"type":"thinking","thinking":"","signature":"x"},
        \\   {"type":"text","text":"\"What?!\""},
        \\   {"type":"text","text":" (surprised)"}
        \\ ],"stop_reason":"end_turn"}
    ;
    const ans = try ai.parseAnswer(alloc, .anthropic, 200, body);
    defer ans.deinit(alloc);
    try testz.expectEqualStr(ans.text, "\"What?!\" (surprised)");
}

pub fn aiReportsAnAnthropicRefusalAndErrorTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // A decline is HTTP 200: `stop_reason` has to be checked first.
    const refusal = try ai.parseAnswer(alloc, .anthropic, 200,
        \\{"type":"message","content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":null}}
    );
    defer refusal.deinit(alloc);
    try testz.expectTrue(refusal == .failure);

    const err = try ai.parseAnswer(alloc, .anthropic, 401,
        \\{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
    );
    defer err.deinit(alloc);
    try testz.expectEqualStr(err.failure, "HTTP 401: invalid x-api-key");
}

pub fn aiParsesTheClaudeCliResultTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const ok = try ai.parseAnswer(alloc, .claude_code, 200,
        \\{"type":"result","subtype":"success","is_error":false,"result":"Alright.","stop_reason":"end_turn"}
    );
    defer ok.deinit(alloc);
    try testz.expectEqualStr(ok.text, "Alright.");

    // The CLI's own failures come back as a result with `is_error`.
    const failed = try ai.parseAnswer(alloc, .claude_code, 500,
        \\{"type":"result","subtype":"success","is_error":true,"result":"Not logged in - Please run /login"}
    );
    defer failed.deinit(alloc);
    try testz.expectEqualStr(failed.failure, "Not logged in - Please run /login");
}

pub fn aiClaudeArgvIsHeadlessToollessAndPositionalLastTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "-やあ" });
    defer p.deinit(alloc);
    var buf: [13][]const u8 = undefined;
    const argv = ai.claudeArgv(&buf, "claude", "claude-opus-5", p);
    try testz.expectEqualStr(argv[0], "claude");
    try testz.expectEqualStr(argv[1], "-p");
    // No --bare: it would refuse the user's Claude Code login.
    for (argv) |a| try testz.expectFalse(std.mem.eql(u8, a, "--bare"));
    // Tools off, the app's instructions replacing Claude Code's prompt.
    try testz.expectEqualStr(argv[5], "--tools");
    try testz.expectEqualStr(argv[6], "");
    try testz.expectEqualStr(argv[9], "--system-prompt");
    try testz.expectEqualStr(argv[10], p.instructions);
    // `--` first, so a message starting with `-` is never read as a flag.
    try testz.expectEqualStr(argv[argv.len - 2], "--");
    try testz.expectEqualStr(argv[argv.len - 1], p.user);
}

pub fn aiParsesAnOpenAiResponsesAnswerTest(_: std.Io, alloc: std.mem.Allocator) !void {
    // Reasoning models put a `reasoning` item before the message; only
    // `output_text` parts are the answer.
    const body =
        \\{"id":"resp_1","output":[
        \\  {"type":"reasoning","summary":[]},
        \\  {"type":"message","role":"assistant","content":[
        \\    {"type":"output_text","text":"\"What?!\"\n","annotations":[]}
        \\  ]}
        \\]}
    ;
    const ans = try ai.parseAnswer(alloc, .openai, 200, body);
    defer ans.deinit(alloc);
    try testz.expectEqualStr(ans.text, "\"What?!\"");
}

pub fn aiParsesAnOllamaAnswerAndDropsThinkingTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const body =
        \\{"model":"qwen","message":{"role":"assistant","content":"<think>hmm</think>\n\nWhat?!"},"done":true}
    ;
    const ans = try ai.parseAnswer(alloc, .ollama, 200, body);
    defer ans.deinit(alloc);
    try testz.expectEqualStr(ans.text, "What?!");
}

pub fn aiReportsTheProvidersErrorMessageTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const openai_err = try ai.parseAnswer(alloc, .openai, 401,
        \\{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}
    );
    defer openai_err.deinit(alloc);
    try testz.expectEqualStr(openai_err.failure, "HTTP 401: Incorrect API key provided");

    const ollama_err = try ai.parseAnswer(alloc, .ollama, 404,
        \\{"error":"model 'qwen2.5' not found"}
    );
    defer ollama_err.deinit(alloc);
    try testz.expectEqualStr(ollama_err.failure, "HTTP 404: model 'qwen2.5' not found");

    const not_json = try ai.parseAnswer(alloc, .openai, 502, "<html>Bad Gateway</html>");
    defer not_json.deinit(alloc);
    try testz.expectEqualStr(not_json.failure, "HTTP 502: response was not JSON");
}

pub fn aiPlainTextStripsMarkdownTheModelSentAnywayTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const out = try ai.plainText(alloc, "## Translation\n**What?!**\n\n\n\nNotes: `何` = what");
    defer alloc.free(out);
    try testz.expectEqualStr(out, "Translation\nWhat?!\n\nNotes: 何 = what");
}

// ─── ai_cache: the answer cache ─────────────────────────────────────────

pub fn aiCacheKeyFollowsModelAndPromptTest(_: std.Io, alloc: std.mem.Allocator) !void {
    const a = try ai.buildPrompt(alloc, "brief", .{ .dialog = "よし" });
    defer a.deinit(alloc);
    const b = try ai.buildPrompt(alloc, "verbose", .{ .dialog = "よし" });
    defer b.deinit(alloc);

    const k1 = ai_cache.key(.openai, "gpt-5", a);
    try testz.expectEqualStr(&k1, &ai_cache.key(.openai, "gpt-5", a));
    // A different style, model or provider is a different answer.
    try testz.expectFalse(std.mem.eql(u8, &k1, &ai_cache.key(.openai, "gpt-5", b)));
    try testz.expectFalse(std.mem.eql(u8, &k1, &ai_cache.key(.openai, "gpt-5-mini", a)));
    try testz.expectFalse(std.mem.eql(u8, &k1, &ai_cache.key(.ollama, "gpt-5", a)));
}

pub fn aiCacheRoundTripsAnAnswerTest(_: std.Io, alloc: std.mem.Allocator) !void {
    var c = try ai_cache.Cache.open(":memory:");
    defer c.close();
    const p = try ai.buildPrompt(alloc, "", .{ .dialog = "よし" });
    defer p.deinit(alloc);
    const k = ai_cache.key(.openai, "gpt-5", p);

    try testz.expectTrue((try c.get(alloc, k)) == null);
    try c.put(k, "\"All right!\"", .{ .title = "Book", .page = 3, .block = 1, .provider = .openai, .model = "gpt-5" });
    const got = (try c.get(alloc, k)).?;
    defer alloc.free(got);
    try testz.expectEqualStr(got, "\"All right!\"");
}


// ─── ai: request headers ────────────────────────────────────────────────

pub fn requestHeadersForAnthropicCarryVersionBetaAndKeyTest(_: std.Io, _: std.mem.Allocator) !void {
    var buf: [256]u8 = undefined;
    var out: [3]ai.Header = undefined;
    const headers = try ai.requestHeaders(.anthropic, "claude-opus-5-5", "sk-test", &buf, &out);
    try testz.expectEqual(headers.len, 3);
    try testz.expectEqualStr(headers[0].name, "anthropic-version");
    try testz.expectEqualStr(headers[1].value, ai.anthropic_fallback_beta);
    try testz.expectEqualStr(headers[2].name, "x-api-key");
    try testz.expectEqualStr(headers[2].value, "sk-test");
    try testz.expectTrue(headers[2].secret);
}

pub fn requestHeadersSkipTheFallbackBetaForOlderModelsTest(_: std.Io, _: std.mem.Allocator) !void {
    var buf: [256]u8 = undefined;
    var out: [3]ai.Header = undefined;
    const headers = try ai.requestHeaders(.anthropic, "claude-opus-4-8", null, &buf, &out);
    try testz.expectEqual(headers.len, 1);
    try testz.expectEqualStr(headers[0].name, "anthropic-version");
}

pub fn requestHeadersUseABearerTokenForOpenAiTest(_: std.Io, _: std.mem.Allocator) !void {
    var buf: [256]u8 = undefined;
    var out: [3]ai.Header = undefined;
    const headers = try ai.requestHeaders(.openai, "gpt-5", "sk-test", &buf, &out);
    try testz.expectEqual(headers.len, 1);
    try testz.expectEqualStr(headers[0].name, "Authorization");
    try testz.expectEqualStr(headers[0].value, "Bearer sk-test");

    const none = try ai.requestHeaders(.ollama, "qwen2.5", null, &buf, &out);
    try testz.expectEqual(none.len, 0);
}

pub fn anthropicFallbacksCoverTheCurrentModelsTest(_: std.Io, _: std.mem.Allocator) !void {
    try testz.expectTrue(ai.anthropicFallbacks("claude-opus-5-5"));
    try testz.expectTrue(ai.anthropicFallbacks("claude-sonnet-5-5"));
    try testz.expectTrue(ai.anthropicFallbacks("claude-fable-5-1"));
    try testz.expectFalse(ai.anthropicFallbacks("claude-haiku-5-5"));
    try testz.expectEqualStr(ai.Provider.anthropic.defaultModel(), "claude-opus-5-5");
}
