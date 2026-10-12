// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

//! gw-yomi: the reading core shared by glyphwire's gw-read and the
//! wns-reader Android app. Everything a manga reader needs that doesn't
//! depend on how it draws: comic archives and their page order, mokuro
//! OCR sidecars, Yomitan dictionaries with Yomitan-style deinflection
//! and ranking, the crop-and-encode behind an Anki card's image, the
//! Anki note itself, and the prompt, request and reply of asking an AI
//! about a bubble (the network calls are the app's).
//!
//! Each module's doc comment explains its own design; most were written
//! as part of gw-read and still mention its UI as the caller they were
//! shaped around.

pub const archive = @import("archive.zig");
pub const pages = @import("pages.zig");
pub const mokuro = @import("mokuro.zig");
pub const kana = @import("kana.zig");
pub const dict = @import("dict.zig");
pub const sqlite = @import("sqlite.zig");
pub const crop = @import("crop.zig");
pub const ai = @import("ai.zig");
pub const ai_cache = @import("ai_cache.zig");
pub const anki = @import("anki.zig");

