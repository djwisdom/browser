// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const builtin = @import("builtin");

const JsObject = @import("../env.zig").Env.JsObject;
const SessionState = @import("../env.zig").SessionState;

const log = if (builtin.is_test) &test_capture else std.log.scoped(.console);

pub const Console = struct {
    // TODO: configurable writer
    timers: std.StringHashMapUnmanaged(u32) = .{},
    counts: std.StringHashMapUnmanaged(u32) = .{},

    pub fn _log(_: *const Console, values: []JsObject, state: *SessionState) !void {
        if (values.len == 0) {
            return;
        }
        log.info("{s}", .{try serializeValues(values, state)});
    }

    pub fn _info(console: *const Console, values: []JsObject, state: *SessionState) !void {
        return console._log(values, state);
    }

    pub fn _debug(_: *const Console, values: []JsObject, state: *SessionState) !void {
        if (values.len == 0) {
            return;
        }
        log.debug("{s}", .{try serializeValues(values, state)});
    }

    pub fn _warn(_: *const Console, values: []JsObject, state: *SessionState) !void {
        if (values.len == 0) {
            return;
        }
        log.warn("{s}", .{try serializeValues(values, state)});
    }

    pub fn _error(_: *const Console, values: []JsObject, state: *SessionState) !void {
        if (values.len == 0) {
            return;
        }
        log.err("{s}", .{try serializeValues(values, state)});
    }

    pub fn _clear(_: *const Console) void {}

    pub fn _count(self: *Console, label_: ?[]const u8, state: *SessionState) !void {
        const label = label_ orelse "default";
        const gop = try self.counts.getOrPut(state.arena, label);

        var current: u32 = 0;
        if (gop.found_existing) {
            current = gop.value_ptr.*;
        } else {
            gop.key_ptr.* = try state.arena.dupe(u8, label);
        }

        const count = current + 1;
        gop.value_ptr.* = count;

        log.info("{s}: {d}", .{ label, count });
    }

    pub fn _countReset(self: *Console, label_: ?[]const u8) !void {
        const label = label_ orelse "default";
        const kv = self.counts.fetchRemove(label) orelse {
            log.warn("Counter \"{s}\" doesn't exist.", .{label});
            return;
        };

        log.info("{s}: {d}", .{ label, kv.value });
    }

    pub fn _time(self: *Console, label_: ?[]const u8, state: *SessionState) !void {
        const label = label_ orelse "default";
        const gop = try self.timers.getOrPut(state.arena, label);

        if (gop.found_existing) {
            log.warn("Timer \"{s}\" already exists.", .{label});
            return;
        }
        gop.key_ptr.* = try state.arena.dupe(u8, label);
        gop.value_ptr.* = timestamp();
    }

    pub fn _timeLog(self: *Console, label_: ?[]const u8) void {
        const elapsed = timestamp();
        const label = label_ orelse "default";
        const start = self.timers.get(label) orelse {
            log.warn("Timer \"{s}\" doesn't exist.", .{label});
            return;
        };

        log.info("\"{s}\": {d}ms", .{ label, elapsed - start });
    }

    pub fn _timeStop(self: *Console, label_: ?[]const u8) void {
        const elapsed = timestamp();
        const label = label_ orelse "default";
        const kv = self.timers.fetchRemove(label) orelse {
            log.warn("Timer \"{s}\" doesn't exist.", .{label});
            return;
        };

        log.info("\"{s}\": {d}ms - timer ended", .{ label, elapsed - kv.value });
    }

    pub fn _assert(_: *Console, assertion: JsObject, values: []JsObject, state: *SessionState) !void {
        if (assertion.isTruthy()) {
            return;
        }
        var serialized_values: []const u8 = "";
        if (values.len > 0) {
            serialized_values = try serializeValues(values, state);
        }
        log.err("Assertion failed: {s}", .{serialized_values});
    }

    fn serializeValues(values: []JsObject, state: *SessionState) ![]const u8 {
        const arena = state.call_arena;
        var arr: std.ArrayListUnmanaged(u8) = .{};
        try arr.appendSlice(arena, try values[0].toString());
        for (values[1..]) |value| {
            try arr.append(arena, ' ');
            try arr.appendSlice(arena, try value.toString());
        }
        return arr.items;
    }
};

fn timestamp() u32 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    return @intCast(ts.sec);
}

var test_capture = TestCapture{};
const testing = @import("../../testing.zig");
test "Browser.Console" {
    var runner = try testing.jsRunner(testing.tracking_allocator, .{});
    defer runner.deinit();

    defer testing.reset();

    {
        try runner.testCases(&.{
            .{ "console.log('a')", "undefined" },
            .{ "console.warn('hello world', 23, true, new Object())", "undefined" },
        }, .{});

        const captured = test_capture.captured.items;
        try testing.expectEqual("a", captured[0]);
        try testing.expectEqual("hello world 23 true [object Object]", captured[1]);
    }

    {
        test_capture.reset();
        try runner.testCases(&.{
            .{ "console.countReset()", "undefined" },
            .{ "console.count()", "undefined" },
            .{ "console.count('teg')", "undefined" },
            .{ "console.count('teg')", "undefined" },
            .{ "console.count('teg')", "undefined" },
            .{ "console.count()", "undefined" },
            .{ "console.countReset('teg')", "undefined" },
            .{ "console.countReset()", "undefined" },
            .{ "console.count()", "undefined" },
        }, .{});

        const captured = test_capture.captured.items;
        try testing.expectEqual("Counter \"default\" doesn't exist.", captured[0]);
        try testing.expectEqual("default: 1", captured[1]);
        try testing.expectEqual("teg: 1", captured[2]);
        try testing.expectEqual("teg: 2", captured[3]);
        try testing.expectEqual("teg: 3", captured[4]);
        try testing.expectEqual("default: 2", captured[5]);
        try testing.expectEqual("teg: 3", captured[6]);
        try testing.expectEqual("default: 2", captured[7]);
        try testing.expectEqual("default: 1", captured[8]);
    }

    {
        test_capture.reset();
        try runner.testCases(&.{
            .{ "console.assert(true)", "undefined" },
            .{ "console.assert('a', 2, 3, 4)", "undefined" },
            .{ "console.assert('')", "undefined" },
            .{ "console.assert('', 'x', true)", "undefined" },
            .{ "console.assert(false, 'x')", "undefined" },
        }, .{});

        const captured = test_capture.captured.items;
        try testing.expectEqual("Assertion failed: ", captured[0]);
        try testing.expectEqual("Assertion failed: x true", captured[1]);
        try testing.expectEqual("Assertion failed: x", captured[2]);
    }
}

const TestCapture = struct {
    captured: std.ArrayListUnmanaged([]const u8) = .{},

    fn reset(self: *TestCapture) void {
        self.captured = .{};
    }

    fn debug(self: *TestCapture, comptime fmt: []const u8, args: anytype) void {
        const str = std.fmt.allocPrint(testing.arena_allocator, fmt, args) catch unreachable;
        self.captured.append(testing.arena_allocator, str) catch unreachable;
    }

    fn info(self: *TestCapture, comptime fmt: []const u8, args: anytype) void {
        self.debug(fmt, args);
    }

    fn warn(self: *TestCapture, comptime fmt: []const u8, args: anytype) void {
        self.debug(fmt, args);
    }

    fn err(self: *TestCapture, comptime fmt: []const u8, args: anytype) void {
        self.debug(fmt, args);
    }
};
