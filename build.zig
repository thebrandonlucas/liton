const std = @import("std");

const SourceTree = struct {
    roc_files: []const []const u8,
    // Apps and packages: what `roc check` and `roc test` take.
    roc_roots: []const []const u8,
    zig_files: []const []const u8,
};

const excluded_source_dirs = [_][]const u8{
    ".direnv",
    ".git",
    ".kai",
    ".zig-cache",
    "vendor",
    "zig-out",
    "zig-pkg",
};

fn isExcludedSourceDir(name: []const u8) bool {
    for (excluded_source_dirs) |excluded| {
        if (std.mem.eql(u8, name, excluded)) return true;
    }
    return false;
}

// Kaifile.roc is an app on kai's platform, which `kai check` checks.
fn isRocRoot(path: []const u8, contents: []const u8) bool {
    if (std.mem.eql(u8, path, "Kaifile.roc")) return false;
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        return std.mem.startsWith(u8, line, "app ") or std.mem.startsWith(u8, line, "package");
    }
    return false;
}

// The Roc target for a native binary on the machine running the build, from
// the native targets roc-signals's platform has: x64musl, arm64mac, x64mac.
fn nativeRocTarget(b: *std.Build) []const u8 {
    const host = b.graph.host.result;
    return switch (host.os.tag) {
        .linux => switch (host.cpu.arch) {
            .x86_64 => "x64musl",
            else => @panic("roc-signals has no native spec runner for this Linux architecture"),
        },
        .macos => switch (host.cpu.arch) {
            .aarch64 => "arm64mac",
            .x86_64 => "x64mac",
            else => @panic("roc-signals has no native spec runner for this macOS architecture"),
        },
        else => @panic("roc-signals has no native spec runner for this OS"),
    };
}

fn sortPaths(paths: [][]const u8) void {
    std.mem.sort([]const u8, paths, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);
}

fn discoverSources(b: *std.Build) SourceTree {
    const allocator = b.allocator;
    const io = b.graph.io;

    var roc_files = std.ArrayList([]const u8).empty;
    var roc_roots = std.ArrayList([]const u8).empty;
    var zig_files = std.ArrayList([]const u8).empty;

    var source_dir = std.Io.Dir.cwd().openDir(
        io,
        b.build_root.path orelse ".",
        .{ .iterate = true, .follow_symlinks = false },
    ) catch @panic("failed to open source tree");
    defer source_dir.close(io);

    var walker = source_dir.walk(allocator) catch @panic("failed to scan source tree");
    defer walker.deinit();

    while (walker.next(io) catch @panic("failed to scan source tree")) |entry| {
        if (entry.kind == .directory and isExcludedSourceDir(entry.basename)) {
            walker.leave(io);
            continue;
        }
        if (entry.kind != .file) continue;

        const path = allocator.dupe(u8, entry.path) catch @panic("out of memory");
        if (std.mem.endsWith(u8, path, ".roc")) {
            roc_files.append(allocator, path) catch @panic("out of memory");
            const contents = source_dir.readFileAlloc(
                io,
                path,
                allocator,
                .limited(10 * 1024 * 1024),
            ) catch @panic("failed to read Roc source");
            defer allocator.free(contents);
            if (isRocRoot(path, contents)) {
                roc_roots.append(allocator, path) catch @panic("out of memory");
            }
        } else if (std.mem.endsWith(u8, path, ".zig")) {
            zig_files.append(allocator, path) catch @panic("out of memory");
        } else {
            allocator.free(path);
        }
    }

    sortPaths(roc_files.items);
    sortPaths(roc_roots.items);
    sortPaths(zig_files.items);

    return .{
        .roc_files = roc_files.toOwnedSlice(allocator) catch @panic("out of memory"),
        .roc_roots = roc_roots.toOwnedSlice(allocator) catch @panic("out of memory"),
        .zig_files = zig_files.toOwnedSlice(allocator) catch @panic("out of memory"),
    };
}

// Runs prefix over files, or nothing when there are none, since `roc fmt`
// given no files formats the current directory.
fn addFilesCommand(
    b: *std.Build,
    step: *std.Build.Step,
    prefix: []const []const u8,
    files: []const []const u8,
) void {
    if (files.len == 0) return;
    var args = std.ArrayList([]const u8).empty;
    args.appendSlice(b.allocator, prefix) catch @panic("out of memory");
    args.appendSlice(b.allocator, files) catch @panic("out of memory");
    step.dependOn(&b.addSystemCommand(args.items).step);
}

// The UI's sources, which the UI's Roc compiler owns.
fn isUi(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "ui/");
}

// Checks root with roc, and tests it after all checks.
fn addRocRoot(
    b: *std.Build,
    check_step: *std.Build.Step,
    test_step: *std.Build.Step,
    roc: []const u8,
    root: []const u8,
) void {
    check_step.dependOn(&b.addSystemCommand(&.{ roc, "check", root }).step);
    const test_roc = b.addSystemCommand(&.{ roc, "test", root });
    test_roc.step.dependOn(check_step);
    test_step.dependOn(&test_roc.step);
}

pub fn build(b: *std.Build) void {
    const sources = discoverSources(b);

    // The UI's Roc compiler and the daemon's, as Kaifile.roc provides them.
    // With one compiler again, roc-ui's default becomes "roc".
    const roc = b.option([]const u8, "roc", "The daemon's Roc compiler") orelse "roc";
    const roc_ui = b.option([]const u8, "roc-ui", "The UI's Roc compiler") orelse "roc-ui";

    var roc_files = std.ArrayList([]const u8).empty;
    var ui_roc_files = std.ArrayList([]const u8).empty;
    for (sources.roc_files) |path| {
        const files = if (isUi(path)) &ui_roc_files else &roc_files;
        files.append(b.allocator, path) catch @panic("out of memory");
    }

    // The UI's platform's release bundle, the one ui/main.roc names, for the
    // runtime.mjs and worker.mjs the page loads.
    const roc_signals = b.dependency("roc_signals_platform", .{});

    const check_step = b.step("check", "Run formatting and static checks");
    addFilesCommand(b, check_step, &.{ roc, "fmt", "--check" }, roc_files.items);
    addFilesCommand(b, check_step, &.{ roc_ui, "fmt", "--check" }, ui_roc_files.items);
    addFilesCommand(b, check_step, &.{ "zig", "fmt", "--check" }, sources.zig_files);

    // Mutating format step for devs without editor support for Roc and Zig.
    const fmt_step = b.step("fmt", "Format all source code files");
    addFilesCommand(b, fmt_step, &.{ roc, "fmt" }, roc_files.items);
    addFilesCommand(b, fmt_step, &.{ roc_ui, "fmt" }, ui_roc_files.items);
    addFilesCommand(b, fmt_step, &.{ "zig", "fmt" }, sources.zig_files);

    // The capabilities package is imported by the UI and the daemon, so both
    // compilers check and test it.
    const test_step = b.step("test", "Run checks and Roc tests");
    test_step.dependOn(check_step);
    for (sources.roc_roots) |root| {
        const shared = std.mem.startsWith(u8, root, "capabilities/");
        if (shared or !isUi(root)) addRocRoot(b, check_step, test_step, roc, root);
        if (shared or isUi(root)) addRocRoot(b, check_step, test_step, roc_ui, root);
    }

    // The UI's .scm specs, in the native runner roc-signals's release builds
    // the UI into for the machine running the build.
    const spec_step = b.step("spec", "Run the UI's specs natively");
    const run_specs = b.addSystemCommand(&.{
        "sh",               "-c",
        \\set -e
        \\mkdir -p zig-out/bin
        \\"$1" build --target="$2" ui/main.roc --output=zig-out/bin/liton-specs
        \\zig-out/bin/liton-specs ui/specs/*.scm
        ,
        "sh",               roc_ui,
        nativeRocTarget(b),
    });
    run_specs.has_side_effects = true;
    spec_step.dependOn(&run_specs.step);
    test_step.dependOn(&run_specs.step);

    // The browser UI, its page and the roc-signals runtime, into zig-out/www.
    const ui_step = b.step("ui", "Build the browser UI into zig-out/www");
    const build_ui = b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\mkdir -p zig-out/www
        \\"$1" build --target=wasm32 ui/main.roc --output=zig-out/www/app.wasm
        \\cp ui/index.html ui/style.css "$2" "$3" zig-out/www/
        ,
        "sh", roc_ui,
    });
    build_ui.addFileArg(roc_signals.path("runtime.mjs"));
    build_ui.addFileArg(roc_signals.path("worker.mjs"));
    build_ui.has_side_effects = true;
    ui_step.dependOn(&build_ui.step);

    const daemon_step = b.step("daemon", "Build the daemon into zig-out/bin/liton-daemon");
    const build_daemon = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/bin && \"$1\" build daemon/main.roc --output=zig-out/bin/liton-daemon", "sh", roc });
    build_daemon.has_side_effects = true;
    daemon_step.dependOn(&build_daemon.step);

    // Serves the UI and the API at http://127.0.0.1:8095 (LITON_HOST and
    // LITON_PORT to change it).
    const run_step = b.step("run", "Build the UI and the daemon, and run the daemon");
    const run_daemon = b.addSystemCommand(&.{"zig-out/bin/liton-daemon"});
    run_daemon.has_side_effects = true;
    run_daemon.step.dependOn(&build_ui.step);
    run_daemon.step.dependOn(&build_daemon.step);
    run_step.dependOn(&run_daemon.step);

    // Drives the UI in headless Chrome (CHROME, or chromium on PATH) against
    // a daemon of its own serving the mock provider, through the DevTools
    // client in roc-signals's source, which its release bundle leaves out.
    const e2e_step = b.step("e2e", "Drive the UI in headless Chrome against the daemon");
    const run_e2e = b.addSystemCommand(&.{ "node", "e2e/journey.mjs" });
    run_e2e.addFileArg(b.dependency("roc_signals_source", .{}).path("tests/browser/cdp.mjs"));
    run_e2e.has_side_effects = true;
    run_e2e.step.dependOn(&build_ui.step);
    run_e2e.step.dependOn(&build_daemon.step);
    e2e_step.dependOn(&run_e2e.step);
}
