// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

//! A minimal Zig wrapper over the handful of SQLite C API calls
//! `dict.zig` and gw-read's AI cache need (open/close, exec, and prepared
//! statements' bind/step/column/reset/finalize). SQLite itself is the
//! public-domain amalgamation, fetched by `build.zig.zon` and compiled
//! into this package, so this file is the only place the raw C API is
//! touched; everything else goes through `Db` / `Stmt`.

const std = @import("std");
const c = @import("sqlite_c");

pub const Error = error{Sqlite};

/// `sqlite3_bind_text` with `SQLITE_TRANSIENT` -- SQLite copies the bound
/// bytes immediately rather than assume they outlive the call. In C
/// (src/sqlite_shim.c) because `SQLITE_TRANSIENT` is a misaligned
/// function pointer Zig refuses to build on aarch64.
extern fn gwy_bind_text_transient(stmt: *c.sqlite3_stmt, idx: c_int, text: [*]const u8, len: c_int) c_int;

pub const Db = struct {
    handle: *c.sqlite3,

    /// `path` must be a real OS path (or `:memory:`), null-terminated --
    /// SQLite does its own file I/O, outside `std.Io`.
    pub fn open(path: [:0]const u8, flags: c_int) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
        if (rc != c.SQLITE_OK or handle == null) {
            if (handle) |h| _ = c.sqlite3_close(h);
            return error.Sqlite;
        }
        return .{ .handle = handle.? };
    }

    pub fn close(self: *Db) void {
        _ = c.sqlite3_close(self.handle);
    }

    /// Runs `sql`, which may hold several `;`-separated statements taking
    /// no parameters -- schema creation, `BEGIN`/`COMMIT`, and the like.
    /// Anything that binds parameters goes through `prepare` instead.
    pub fn exec(self: *Db, sql: [:0]const u8) Error!void {
        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.handle, sql.ptr, null, null, &errmsg);
        if (errmsg != null) c.sqlite3_free(errmsg);
        if (rc != c.SQLITE_OK) return error.Sqlite;
    }

    pub fn prepare(self: *Db, sql: [:0]const u8) Error!Stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql.ptr, @intCast(sql.len + 1), &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return error.Sqlite;
        return .{ .handle = stmt.? };
    }
};

/// A prepared statement. 1-based column/parameter indices, matching the
/// C API directly rather than hiding it.
pub const Stmt = struct {
    handle: *c.sqlite3_stmt,

    pub fn bindText(self: Stmt, idx: c_int, text: []const u8) Error!void {
        const rc = gwy_bind_text_transient(self.handle, idx, text.ptr, @intCast(text.len));
        if (rc != c.SQLITE_OK) return error.Sqlite;
    }

    pub fn bindInt64(self: Stmt, idx: c_int, val: i64) Error!void {
        const rc = c.sqlite3_bind_int64(self.handle, idx, val);
        if (rc != c.SQLITE_OK) return error.Sqlite;
    }

    /// True if a row is now available (`SQLITE_ROW`), false at the end of
    /// the result set (`SQLITE_DONE`) -- for an INSERT/UPDATE, false is
    /// the normal outcome of the one `step` it takes.
    pub fn step(self: Stmt) Error!bool {
        const rc = c.sqlite3_step(self.handle);
        return switch (rc) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => error.Sqlite,
        };
    }

    pub fn columnText(self: Stmt, idx: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(self.handle, idx);
        const len = c.sqlite3_column_bytes(self.handle, idx);
        if (ptr == null or len <= 0) return "";
        const bytes: [*]const u8 = @ptrCast(ptr);
        return bytes[0..@intCast(len)];
    }

    pub fn columnInt64(self: Stmt, idx: c_int) i64 {
        return c.sqlite3_column_int64(self.handle, idx);
    }

    /// Rewinds a stepped statement so it can be re-bound and re-run --
    /// how the same INSERT statement is reused for every row of a term
    /// bank rather than re-preparing it each time.
    pub fn reset(self: Stmt) void {
        _ = c.sqlite3_reset(self.handle);
        _ = c.sqlite3_clear_bindings(self.handle);
    }

    pub fn finalize(self: Stmt) void {
        _ = c.sqlite3_finalize(self.handle);
    }
};

pub const OPEN_READONLY: c_int = c.SQLITE_OPEN_READONLY;
pub const OPEN_READWRITE: c_int = c.SQLITE_OPEN_READWRITE;
pub const OPEN_CREATE: c_int = c.SQLITE_OPEN_CREATE;
