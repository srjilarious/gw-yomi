// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

//! AI translation lookup for a whole OCR bubble: prompt construction,
//! the per-provider request/response JSON, and the background job that
//! does the round trip.
//!
//! **What gets sent.** OCR text only -- the current bubble, optionally
//! its neighbours in reading order, the highlighted word when there is
//! one, and (only when `ai_include_book_info` is set) the book's file
//! name and page number. Never an image, never a path.
//!
//! **Providers.** Three speak HTTP -- OpenAI's Responses API,
//! Anthropic's Messages API, Ollama's `/api/chat` -- and differ only in
//! the JSON body they want (`buildBody`), where the answer sits in the
//! JSON they return (`parseAnswer`) and how they authenticate
//! (`Provider.needsKey`, `requestHeaders`). The fourth, `claude_code`, runs
//! the `claude` CLI headless instead (`claude -p`), so it answers on the
//! user's own Claude Code login rather than on API credits.
//!
//! **No transport here.** This module builds requests and reads replies;
//! sending them is the app's job -- gw-read's `ai_job.zig` with
//! `std.http` (and the `claude` CLI), wns-reader's Kotlin with OkHttp.
//! `requestHeaders` is the one place the per-provider headers are
//! decided, so both send the same request.

const std = @import("std");

pub const Provider = enum {
    openai,
    anthropic,
    claude_code,
    ollama,

    pub fn parse(text: []const u8) ?Provider {
        if (std.mem.eql(u8, text, "openai")) return .openai;
        if (std.mem.eql(u8, text, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, text, "claude_code") or std.mem.eql(u8, text, "claude-code")) return .claude_code;
        if (std.mem.eql(u8, text, "ollama")) return .ollama;
        return null;
    }

    /// For the confirm/sending panels: who the text is going to.
    pub fn label(self: Provider) []const u8 {
        return switch (self) {
            .openai => "OpenAI",
            .anthropic => "Anthropic",
            .claude_code => "Claude Code",
            .ollama => "Ollama",
        };
    }

    pub fn defaultModel(self: Provider) []const u8 {
        return switch (self) {
            .openai => "gpt-5",
            .anthropic, .claude_code => "claude-opus-5-5",
            // Qwen handles Japanese far better than most local models of
            // its size; a user with something else pulled sets `ai_model`.
            .ollama => "qwen2.5",
        };
    }

    /// The URL posted to -- or, for `claude_code`, the executable run
    /// (looked up on PATH).
    pub fn defaultEndpoint(self: Provider) []const u8 {
        return switch (self) {
            .openai => "https://api.openai.com/v1/responses",
            .anthropic => "https://api.anthropic.com/v1/messages",
            .claude_code => "claude",
            .ollama => "http://localhost:11434/api/chat",
        };
    }

    /// The environment variable the key is read from when
    /// `ai_api_key_env` isn't set.
    pub fn defaultKeyEnv(self: Provider) []const u8 {
        return switch (self) {
            .openai => "OPENAI_API_KEY",
            .anthropic => "ANTHROPIC_API_KEY",
            .claude_code, .ollama => "",
        };
    }

    /// Whether a send without an API key is pointless. Ollama is local
    /// and unauthenticated; the `claude` CLI brings its own login.
    pub fn needsKey(self: Provider) bool {
        return self == .openai or self == .anthropic;
    }
};

/// Anthropic's `max_tokens`: generous, since hitting the cap truncates
/// the answer mid-sentence, and the panel scrolls anyway.
const anthropic_max_tokens = 16000;

/// Whether an Anthropic request for `model` carries `fallbacks:
/// "default"` -- a declined request is re-run server-side on the model
/// Anthropic recommends for that refusal category rather than coming
/// back empty. Only the models that publish fallback models accept it;
/// on any other the parameter is a 400.
pub fn anthropicFallbacks(model: []const u8) bool {
    const with_fallbacks = [_][]const u8{ "claude-opus-5", "claude-opus-5-5", "claude-sonnet-5-5" };
    for (with_fallbacks) |m| {
        if (std.mem.eql(u8, model, m)) return true;
    }
    return std.mem.startsWith(u8, model, "claude-fable-5");
}

/// The beta header an Anthropic request with `fallbacks: "default"`
/// needs alongside it.
pub const anthropic_fallback_beta = "server-side-fallback-2026-07-01";

/// One header of an HTTP provider request. `secret` marks the one
/// carrying the API key: a client drops it if a redirect leaves the host,
/// and never logs it.
pub const Header = struct {
    name: []const u8,
    value: []const u8,
    secret: bool = false,
};

/// Every header an HTTP `provider` request needs besides
/// `Content-Type: application/json`: Anthropic's API version and, for a
/// model taking refusal fallbacks, the beta that enables them; and the API
/// key, as Anthropic's `x-api-key` or everyone else's bearer token.
/// `bearer_buf` holds the `Bearer <key>` value; the returned slices
/// borrow from it, `api_key` and `out`.
pub fn requestHeaders(
    provider: Provider,
    model: []const u8,
    api_key: ?[]const u8,
    bearer_buf: []u8,
    out: *[3]Header,
) error{ApiKeyTooLong}![]const Header {
    var n: usize = 0;
    if (provider == .anthropic) {
        out[n] = .{ .name = "anthropic-version", .value = "2023-06-01" };
        n += 1;
        if (anthropicFallbacks(model)) {
            out[n] = .{ .name = "anthropic-beta", .value = anthropic_fallback_beta };
            n += 1;
        }
    }
    if (api_key) |key| {
        if (provider == .anthropic) {
            out[n] = .{ .name = "x-api-key", .value = key, .secret = true };
        } else {
            const bearer = std.fmt.bufPrint(bearer_buf, "Bearer {s}", .{key}) catch return error.ApiKeyTooLong;
            out[n] = .{ .name = "Authorization", .value = bearer, .secret = true };
        }
        n += 1;
    }
    return out[0..n];
}

/// `ai_prompt`'s default: the reading-level/style instruction a user
/// replaces with their own.
pub const default_style =
    "Translate this for an intermediate (around JLPT N3) Japanese learner. " ++
    "Keep the explanations brief.";

/// The fixed half of the instructions, before the user's style. This is
/// the response contract: the answer is drawn into a small character-cell
/// panel, so anything but short plain text reads badly.
pub const app_rules =
    "You help someone read a Japanese manga. You are given the OCR text of one speech bubble, " ++
    "sometimes with the bubbles before and after it for context. " ++
    "Give a natural English translation of the current bubble first, then brief notes on any " ++
    "words or grammar a learner might miss. If a highlighted word is given, explain it in this " ++
    "context. The text comes from OCR and may contain recognition errors; if something looks " ++
    "garbled, say what it most likely says. " ++
    "Answer in short plain text: no markdown tables, headings, bold or bullet symbols, and no " ++
    "romanization unless asked.";

pub const PromptInput = struct {
    dialog: []const u8,
    highlight: ?[]const u8 = null,
    previous: ?[]const u8 = null,
    next: ?[]const u8 = null,
    /// The book's name -- a file name, never a path.
    title: ?[]const u8 = null,
    /// 1-based, as the reader shows it.
    page: ?usize = null,
};

/// The book's name as the prompt (and the cache's `title` column) gives
/// it: the last path component, never the path, with a comic-archive
/// extension dropped. Only the archive extensions -- a directory named
/// `Vol 1.5` keeps its `.5`.
pub fn bookTitle(path: []const u8) []const u8 {
    const base = std.fs.path.basename(std.mem.trimEnd(u8, path, "/"));
    const ext = std.fs.path.extension(base);
    const archives = [_][]const u8{ ".cbz", ".cbr", ".cb7", ".zip", ".rar", ".7z" };
    for (archives) |a| {
        if (std.ascii.eqlIgnoreCase(ext, a)) return base[0 .. base.len - ext.len];
    }
    return base;
}

pub const Prompt = struct {
    /// The developer/system message: `app_rules` then the user's style.
    instructions: []u8,
    /// The user message: the bubble text, labelled.
    user: []u8,

    pub fn deinit(self: Prompt, alloc: std.mem.Allocator) void {
        alloc.free(self.instructions);
        alloc.free(self.user);
    }
};

/// Builds the two messages a request carries. Every piece is labelled
/// so the model can tell the bubble it is asked about from its context.
pub fn buildPrompt(alloc: std.mem.Allocator, style: []const u8, in: PromptInput) !Prompt {
    const instructions = if (style.len > 0)
        try std.fmt.allocPrint(alloc, "{s}\n\n{s}", .{ app_rules, style })
    else
        try alloc.dupe(u8, app_rules);
    errdefer alloc.free(instructions);

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    const w = &out.writer;
    if (in.title) |t| {
        try w.print("Book: {s}", .{t});
        if (in.page) |p| try w.print(", page {d}", .{p});
        try w.writeAll("\n");
    } else if (in.page) |p| {
        try w.print("Page {d}\n", .{p});
    }
    if (in.previous) |p| try w.print("Previous bubble: {s}\n", .{p});
    try w.print("Current bubble: {s}\n", .{in.dialog});
    if (in.next) |n| try w.print("Next bubble: {s}\n", .{n});
    if (in.highlight) |h| try w.print("Highlighted: {s}\n", .{h});

    return .{ .instructions = instructions, .user = try out.toOwnedSlice() };
}

/// The request body for an HTTP `provider`. `claude_code` has none -- it
/// takes the prompt on its command line (`claudeArgv`).
pub fn buildBody(alloc: std.mem.Allocator, provider: Provider, model: []const u8, prompt: Prompt) ![]u8 {
    return switch (provider) {
        // Responses API: `instructions` is the developer message and
        // `input` may be a bare string for a single user turn.
        .openai => std.json.Stringify.valueAlloc(alloc, .{
            .model = model,
            .instructions = prompt.instructions,
            .input = prompt.user,
        }, .{}),
        // Messages API: the instructions are the top-level `system`.
        .anthropic => if (anthropicFallbacks(model))
            std.json.Stringify.valueAlloc(alloc, .{
                .model = model,
                .max_tokens = anthropic_max_tokens,
                .system = prompt.instructions,
                .messages = .{.{ .role = "user", .content = prompt.user }},
                .fallbacks = "default",
            }, .{})
        else
            std.json.Stringify.valueAlloc(alloc, .{
                .model = model,
                .max_tokens = anthropic_max_tokens,
                .system = prompt.instructions,
                .messages = .{.{ .role = "user", .content = prompt.user }},
            }, .{}),
        .claude_code => error.NotAnHttpProvider,
        .ollama => std.json.Stringify.valueAlloc(alloc, .{
            .model = model,
            .stream = false,
            .messages = .{
                .{ .role = "system", .content = prompt.instructions },
                .{ .role = "user", .content = prompt.user },
            },
        }, .{}),
    };
}

/// How a job ended. Both payloads are owned.
pub const Answer = union(enum) {
    text: []u8,
    /// Shown in the panel as-is: an HTTP status, a provider's own error
    /// message, or a transport error name.
    failure: []u8,

    pub fn deinit(self: Answer, alloc: std.mem.Allocator) void {
        switch (self) {
            inline else => |s| alloc.free(s),
        }
    }
};

/// Pulls the answer (or the provider's error message) out of a response
/// body. `status` decides which one is expected, but an error object is
/// honoured whatever the status says.
pub fn parseAnswer(alloc: std.mem.Allocator, provider: Provider, status: u16, body: []const u8) !Answer {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, body, .{}) catch {
        return .{ .failure = try std.fmt.allocPrint(alloc, "HTTP {d}: response was not JSON", .{status}) };
    };
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return .{ .failure = try std.fmt.allocPrint(alloc, "HTTP {d}: unexpected response", .{status}) };

    if (errorMessage(root)) |msg| return .{ .failure = try std.fmt.allocPrint(alloc, "HTTP {d}: {s}", .{ status, msg }) };
    // Not for `claude_code`: its "status" is only an exit code, and the
    // CLI's own message (`is_error` + `result`) says far more than it.
    if (provider != .claude_code and (status < 200 or status >= 300))
        return .{ .failure = try std.fmt.allocPrint(alloc, "HTTP {d}", .{status}) };

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    switch (provider) {
        // `output` is a list of items; the answer is every `output_text`
        // part of every `message` item, in order. (`output_text` at the
        // top level is an SDK convenience, not part of the wire format.)
        .openai => {
            const output = root.object.get("output") orelse return noText(alloc);
            if (output != .array) return noText(alloc);
            for (output.array.items) |item| {
                if (item != .object) continue;
                const content = item.object.get("content") orelse continue;
                if (content != .array) continue;
                for (content.array.items) |part| {
                    if (part != .object) continue;
                    const kind = part.object.get("type") orelse continue;
                    if (kind != .string or !std.mem.eql(u8, kind.string, "output_text")) continue;
                    const text = part.object.get("text") orelse continue;
                    if (text == .string) try out.writer.writeAll(text.string);
                }
            }
        },
        // `content` is a list of blocks; the answer is every `text` block
        // in order. Thinking blocks (Opus 5 thinks by default) and a
        // `fallback` marker are skipped. A policy decline comes back as
        // HTTP 200 with `stop_reason: "refusal"` and must be checked
        // before `content` is trusted.
        .anthropic => {
            if (root.object.get("stop_reason")) |sr| {
                if (sr == .string and std.mem.eql(u8, sr.string, "refusal"))
                    return .{ .failure = try alloc.dupe(u8, "Claude declined to answer this one") };
            }
            const content = root.object.get("content") orelse return noText(alloc);
            if (content != .array) return noText(alloc);
            for (content.array.items) |block| {
                if (block != .object) continue;
                const kind = block.object.get("type") orelse continue;
                if (kind != .string or !std.mem.eql(u8, kind.string, "text")) continue;
                const text = block.object.get("text") orelse continue;
                if (text == .string) try out.writer.writeAll(text.string);
            }
        },
        // `claude -p --output-format json`: one result object, the answer
        // in `result`, `is_error` set when the CLI itself failed (not
        // logged in, usage limit) -- `result` then says why.
        .claude_code => {
            const result = root.object.get("result") orelse return noText(alloc);
            if (result != .string) return noText(alloc);
            if (root.object.get("is_error")) |e| {
                if (e == .bool and e.bool) return .{ .failure = try alloc.dupe(u8, result.string) };
            }
            try out.writer.writeAll(result.string);
        },
        .ollama => {
            const message = root.object.get("message") orelse return noText(alloc);
            if (message != .object) return noText(alloc);
            const content = message.object.get("content") orelse return noText(alloc);
            if (content == .string) try out.writer.writeAll(stripThink(content.string));
        },
    }
    const text = std.mem.trim(u8, out.written(), " \t\r\n");
    if (text.len == 0) return noText(alloc);
    return .{ .text = try alloc.dupe(u8, text) };
}

fn noText(alloc: std.mem.Allocator) !Answer {
    return .{ .failure = try alloc.dupe(u8, "the response had no answer text") };
}

/// OpenAI: `{"error": {"message": ...}}`. Ollama: `{"error": "..."}`.
fn errorMessage(root: std.json.Value) ?[]const u8 {
    const err = root.object.get("error") orelse return null;
    return switch (err) {
        .string => |s| s,
        .object => |o| if (o.get("message")) |m| (if (m == .string) m.string else "error") else "error",
        else => null,
    };
}

/// A local reasoning model (deepseek-r1, qwq) puts its chain of thought
/// in a leading `<think>...</think>` block. That is not the answer.
fn stripThink(text: []const u8) []const u8 {
    const trimmed = std.mem.trimStart(u8, text, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "<think>")) return text;
    const end = std.mem.find(u8, trimmed, "</think>") orelse return text;
    return trimmed[end + "</think>".len ..];
}

/// Makes answer text safe for a character-cell panel: markdown emphasis
/// markers and heading hashes the model sent despite being asked not to
/// are dropped, and runs of blank lines collapse to one. Returned slice
/// is owned.
pub fn plainText(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    var blank_run: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |raw| {
        var line = std.mem.trimEnd(u8, raw, " \t\r");
        const lead = std.mem.trimStart(u8, line, "#");
        if (lead.len != line.len and (lead.len == 0 or lead[0] == ' ')) line = std.mem.trimStart(u8, lead, " ");
        if (line.len == 0) {
            blank_run += 1;
            if (blank_run > 1) continue;
        } else blank_run = 0;
        if (!first) try out.append(alloc, '\n');
        first = false;
        var i: usize = 0;
        while (i < line.len) : (i += 1) {
            if (line[i] == '*' or line[i] == '`') continue;
            try out.append(alloc, line[i]);
        }
    }
    return out.toOwnedSlice(alloc);
}

/// The `claude` CLI's command line for `claude_code`. Headless (`-p`),
/// one JSON result object on stdout, no session saved, no tools (a
/// translation needs none, and a tool-less run can't touch the disk), and
/// the app's own instructions *replacing* Claude Code's system prompt.
/// The user message is the last, positional argument. Deliberately not
/// `--bare`: that mode only accepts an API key, and the point of this
/// provider is the user's Claude Code login. Slices borrow from the
/// arguments.
pub fn claudeArgv(buf: *[13][]const u8, exe: []const u8, model: []const u8, prompt: Prompt) []const []const u8 {
    buf.* = .{
        exe,
        "-p",
        "--output-format",
        "json",
        "--no-session-persistence",
        // Variadic: an empty list disables every built-in tool. The next
        // flag ends it.
        "--tools",
        "",
        "--model",
        model,
        "--system-prompt",
        prompt.instructions,
        "--",
        prompt.user,
    };
    return buf;
}
