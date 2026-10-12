// Copyright (c) 2026 Jeff DeWall
// SPDX-License-Identifier: GPL-3.0-or-later

// SQLITE_TRANSIENT is `((sqlite3_destructor_type)-1)`: a function pointer
// with an address no function could have. Zig won't construct one on a
// target whose function pointers must be aligned (aarch64 -- the Android
// build), so the one call that needs it is made from C.

#include "sqlite3.h"

int gwy_bind_text_transient(sqlite3_stmt *stmt, int idx, const char *text, int len) {
    return sqlite3_bind_text(stmt, idx, text, len, SQLITE_TRANSIENT);
}
