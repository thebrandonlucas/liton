const std = @import("std");

const SourceTree = struct {
    roc_files: []const []const u8,
    roc_references: []const RocReference,
    // Apps and packages: what `roc check` and `roc test` take.
    roc_roots: []const []const u8,
    zig_files: []const []const u8,
    // The UI's page, which its build copies beside the wasm.
    ui_page_files: []const []const u8,
};

// A local package a Roc file's header lists, by its directory, or a file it
// imports, as `import "x" as`, from the repository's root.
const RocReference = struct {
    from: []const u8,
    kind: enum { package, file },
    path: []const u8,
};

const excluded_source_dirs = [_][]const u8{
    // Claude Code's local state, which holds its agents' worktrees.
    ".claude",
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

// Local packages are "../x/main.roc" strings, which only a header holds.
fn appendRocReferences(
    allocator: std.mem.Allocator,
    references: *std.ArrayList(RocReference),
    path: []const u8,
    contents: []const u8,
) void {
    const directory = std.fs.path.dirname(path) orelse "";
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        var quoted = std.mem.splitScalar(u8, line, '"');
        _ = quoted.next();
        while (quoted.next()) |string| : (_ = quoted.next()) {
            const file_import = std.mem.startsWith(u8, line, "import \"");
            const package = std.mem.startsWith(u8, string, ".") and std.mem.endsWith(u8, string, ".roc");
            if (!file_import and !package) continue;
            const resolved = std.fs.path.resolvePosix(allocator, &.{ directory, string }) catch @panic("out of memory");
            references.append(allocator, if (file_import)
                .{ .from = path, .kind = .file, .path = resolved }
            else
                .{ .from = path, .kind = .package, .path = std.fs.path.dirname(resolved) orelse "" }) catch @panic("out of memory");
            if (file_import) break;
        }
    }
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
    var roc_references = std.ArrayList(RocReference).empty;
    var roc_roots = std.ArrayList([]const u8).empty;
    var zig_files = std.ArrayList([]const u8).empty;
    var ui_page_files = std.ArrayList([]const u8).empty;

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
        if (entry.kind != .file and entry.kind != .sym_link) continue;

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
            appendRocReferences(allocator, &roc_references, path, contents);
            if (isRocRoot(path, contents)) {
                roc_roots.append(allocator, path) catch @panic("out of memory");
            }
        } else if (std.mem.endsWith(u8, path, ".zig")) {
            zig_files.append(allocator, path) catch @panic("out of memory");
        } else if (isUi(path) and !std.mem.startsWith(u8, path, "ui/specs/")) {
            ui_page_files.append(allocator, path) catch @panic("out of memory");
        } else {
            allocator.free(path);
        }
    }

    sortPaths(roc_files.items);
    sortPaths(roc_roots.items);
    sortPaths(zig_files.items);
    sortPaths(ui_page_files.items);

    return .{
        .roc_files = roc_files.toOwnedSlice(allocator) catch @panic("out of memory"),
        .roc_references = roc_references.toOwnedSlice(allocator) catch @panic("out of memory"),
        .roc_roots = roc_roots.toOwnedSlice(allocator) catch @panic("out of memory"),
        .zig_files = zig_files.toOwnedSlice(allocator) catch @panic("out of memory"),
        .ui_page_files = ui_page_files.toOwnedSlice(allocator) catch @panic("out of memory"),
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

fn inDirectory(path: []const u8, directory: []const u8) bool {
    return path.len > directory.len and std.mem.startsWith(u8, path, directory) and path[directory.len] == '/';
}

// Makes run depend on what compiler reads to build the app at root, so that
// it runs again only when one of them changes: the Roc files of root's
// directory and of the local packages it lists, recursively, the files they
// import, and the compiler's binary.
fn addRocAppInputs(
    b: *std.Build,
    run: *std.Build.Step.Run,
    sources: SourceTree,
    compiler: []const u8,
    root: []const u8,
) void {
    var directories = std.ArrayList([]const u8).empty;
    directories.append(b.allocator, std.fs.path.dirname(root).?) catch @panic("out of memory");
    var index: usize = 0;
    while (index < directories.items.len) : (index += 1) {
        const directory = directories.items[index];
        for (sources.roc_files) |path| {
            if (inDirectory(path, directory)) run.addFileInput(b.path(path));
        }
        for (sources.roc_references) |reference| {
            if (!inDirectory(reference.from, directory)) continue;
            switch (reference.kind) {
                .file => run.addFileInput(b.path(reference.path)),
                .package => for (directories.items) |listed| {
                    if (std.mem.eql(u8, listed, reference.path)) break;
                } else directories.append(b.allocator, reference.path) catch @panic("out of memory"),
            }
        }
    }
    // Without the compiler on PATH, the build fails when it runs instead.
    const compiler_path = b.findProgram(&.{compiler}, &.{}) catch return;
    run.addFileInput(.{ .cwd_relative = compiler_path });
}

// Builds the app at root with compiler and flags into a file called name,
// again only when what it reads changes.
fn addRocBuild(
    b: *std.Build,
    sources: SourceTree,
    compiler: []const u8,
    flags: []const []const u8,
    root: []const u8,
    name: []const u8,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ compiler, "build" });
    run.addArgs(flags);
    run.setName(b.fmt("{s} build {s}", .{ compiler, root }));
    run.addFileArg(b.path(root));
    addRocAppInputs(b, run, sources, compiler, root);
    return run.addPrefixedOutputFileArg("--output=", name);
}

// Runs the development tool with args, every time: what it does reads and
// writes files the build doesn't track.
fn addDevtoolCommand(
    b: *std.Build,
    devtool: std.Build.LazyPath,
    name: []const u8,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run = std.Build.Step.Run.create(b, b.fmt("run devtool {s}", .{name}));
    run.addFileArg(devtool);
    run.addArgs(args);
    run.has_side_effects = true;
    return run;
}

// The browser UI, its page and the runtime files of roc_signals's release
// bundle, into a directory. Built for size: the wasm's download is most of a
// cold load (bench/). Releases are specialized, whose input answers in about
// half the time (a keystroke under a long timeline in 29 ms against 62 ms),
// but whose module is 8 times the size, loads in 4 times as long, holds 10
// times the memory, and takes about an hour and 20 GB of memory to build.
fn addUiBuild(
    b: *std.Build,
    sources: SourceTree,
    devtool: std.Build.LazyPath,
    roc_ui: []const u8,
    roc_signals: *std.Build.Dependency,
    specialize: bool,
) std.Build.LazyPath {
    const build_ui = std.Build.Step.Run.create(b, if (specialize) "build the specialized browser UI" else "build the browser UI");
    build_ui.addFileArg(devtool);
    build_ui.addArgs(&.{ "ui", roc_ui });
    const www = build_ui.addOutputDirectoryArg("www");
    for ([_][]const u8{ "runtime.mjs", "environment.mjs", "startup.mjs", "worker.mjs" }) |file| build_ui.addFileArg(roc_signals.path(file));
    if (!specialize) build_ui.addArg("--specialize=no");
    addRocAppInputs(b, build_ui, sources, roc_ui, "ui/main.roc");
    for (sources.ui_page_files) |path| build_ui.addFileInput(b.path(path));
    return www;
}

pub fn build(b: *std.Build) void {
    const sources = discoverSources(b);

    // The Roc compiler Kaifile.roc provides, and the UI's, the same unless
    // -Droc-ui tries the UI on another.
    const roc = b.option([]const u8, "roc", "The daemon's Roc compiler") orelse "roc";
    const roc_ui = b.option([]const u8, "roc-ui", "The UI's Roc compiler") orelse roc;
    // The UI as zig build release builds it, with lambda-set specialization,
    // to measure what ships (bench/): about an hour and 20 GB of memory.
    const specialize = b.option(bool, "specialize", "Build the browser UI with specialization, as releases do") orelse false;

    var roc_files = std.ArrayList([]const u8).empty;
    var ui_roc_files = std.ArrayList([]const u8).empty;
    for (sources.roc_files) |path| {
        const files = if (isUi(path)) &ui_roc_files else &roc_files;
        files.append(b.allocator, path) catch @panic("out of memory");
    }

    // The UI's platform's release bundle, the one ui/main.roc names, for the
    // runtime.mjs and the environment.mjs, startup.mjs and worker.mjs it loads.
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

    // The capabilities and setup packages are imported by the UI and the
    // daemon, so a UI compiler of its own checks and tests them too.
    const test_step = b.step("test", "Run checks and Roc tests");
    test_step.dependOn(check_step);
    for (sources.roc_roots) |root| {
        const shared = std.mem.startsWith(u8, root, "capabilities/") or std.mem.startsWith(u8, root, "setup/");
        if (!isUi(root)) addRocRoot(b, check_step, test_step, roc, root);
        if (isUi(root) or (shared and !std.mem.eql(u8, roc_ui, roc))) addRocRoot(b, check_step, test_step, roc_ui, root);
    }

    // liton's development tool (devtool/), on the daemon's compiler, which
    // runs the tasks that would otherwise be shell scripts, as kai's does.
    const build_devtool = b.addSystemCommand(&.{ roc, "build", "--opt=dev" });
    build_devtool.addFileArg(b.path("devtool/main.roc"));
    for (sources.roc_files) |path| {
        if (std.mem.startsWith(u8, path, "devtool/")) build_devtool.addFileInput(b.path(path));
    }
    const devtool = build_devtool.addPrefixedOutputFileArg("--output=", "liton-devtool");
    const devtool_step = b.step("devtool", "Run liton's development tool: zig build devtool -- help");
    const run_devtool = addDevtoolCommand(b, devtool, "devtool", b.args orelse &.{});
    devtool_step.dependOn(&run_devtool.step);
    // `previews` renders the UI against the daemon, both built first, in
    // headless Chrome through roc-signals's DevTools client.
    const previews = if (b.args) |args| args.len == 1 and std.mem.eql(u8, args[0], "previews") else false;
    if (previews) run_devtool.addFileArg(b.dependency("roc_signals_source", .{}).path("tests/browser/cdp.mjs"));

    // The UI's .scm specs, in the native runner roc-signals's release builds
    // the UI into for the machine running the build. Without lambda-set
    // specialization it builds in about a minute rather than ten after a UI
    // change, and the specs check behaviour, not speed; the e2e step drives
    // the specialized module the browser gets.
    const spec_step = b.step("spec", "Run the UI's specs natively");
    const spec_runner = addRocBuild(b, sources, roc_ui, &.{ "--specialize=no", b.fmt("--target={s}", .{nativeRocTarget(b)}) }, "ui/main.roc", "liton-specs");
    const run_specs = addDevtoolCommand(b, devtool, "spec", &.{"spec"});
    run_specs.addFileArg(spec_runner);
    spec_step.dependOn(&run_specs.step);
    test_step.dependOn(&run_specs.step);

    // The browser UI, its page and the roc-signals runtime, into zig-out/www.
    // Without specialization unless -Dspecialize: about 9 MB, built in about
    // three minutes, against 81 MB in about an hour.
    const ui_step = b.step("ui", "Build the browser UI into zig-out/www");
    const www = addUiBuild(b, sources, devtool, roc_ui, roc_signals, specialize);
    const install_ui = b.addInstallDirectory(.{ .source_dir = www, .install_dir = .prefix, .install_subdir = "www" });
    ui_step.dependOn(&install_ui.step);

    // The packages' and apps' API docs, from their `##` comments, into
    // zig-out/docs, again only when a Roc file or a compiler changes. The
    // test step checks that they build.
    const docs_step = b.step("docs", "Build the API docs into zig-out/docs");
    const build_docs = std.Build.Step.Run.create(b, "build the API docs");
    build_docs.addFileArg(devtool);
    build_docs.addArgs(&.{ "docs", roc, roc_ui });
    const docs = build_docs.addOutputDirectoryArg("docs");
    for (sources.roc_files) |path| build_docs.addFileInput(b.path(path));
    for ([_][]const u8{ roc, roc_ui }) |compiler| {
        const compiler_path = b.findProgram(&.{compiler}, &.{}) catch continue;
        build_docs.addFileInput(.{ .cwd_relative = compiler_path });
    }
    const install_docs = b.addInstallDirectory(.{ .source_dir = docs, .install_dir = .prefix, .install_subdir = "docs" });
    docs_step.dependOn(&install_docs.step);
    test_step.dependOn(&build_docs.step);

    const daemon_step = b.step("daemon", "Build the daemon into zig-out/bin/liton-daemon");
    const install_daemon = b.addInstallBinFile(addRocBuild(b, sources, roc, &.{}, "daemon/main.roc", "liton-daemon"), "liton-daemon");
    daemon_step.dependOn(&install_daemon.step);
    if (previews) {
        run_devtool.step.dependOn(&install_ui.step);
        run_devtool.step.dependOn(&install_daemon.step);
    }

    // The command line client, whose platform, basic-cli, runs on the
    // daemon's compiler.
    const cli_step = b.step("cli", "Build the command line client into zig-out/bin/liton");
    const install_cli = b.addInstallBinFile(addRocBuild(b, sources, roc, &.{}, "cli/main.roc", "liton"), "liton");
    cli_step.dependOn(&install_cli.step);

    // The example provider outside the daemon, a server of /liton/v1 on the
    // daemon's platform and compiler.
    const example_step = b.step("example-provider", "Build the example provider into zig-out/bin/provider-echo");
    const install_example = b.addInstallBinFile(addRocBuild(b, sources, roc, &.{}, "examples/provider-echo/main.roc", "provider-echo"), "provider-echo");
    example_step.dependOn(&install_example.step);

    // The release archives flake.nix fetches, liton-VERSION-SYSTEM.tar.gz
    // and their SHA256SUMS, into zig-out/release: for each Linux system the
    // daemon's and the command line's platforms build for, their static
    // binaries in bin/ and the specialized UI in share/liton/www, the same
    // bytes from the same sources.
    const release_step = b.step("release", "Build the release archives into zig-out/release");
    const release_www = if (specialize) www else addUiBuild(b, sources, devtool, roc_ui, roc_signals, true);
    const version = @import("build.zig.zon").version;
    const sums = b.addSystemCommand(&.{ "sha256sum", "--" });
    for ([_][2][]const u8{ .{ "x86_64-linux", "x64musl" }, .{ "aarch64-linux", "arm64musl" } }) |release| {
        const target = b.fmt("--target={s}", .{release[1]});
        const tree = b.addWriteFiles();
        _ = tree.addCopyFile(addRocBuild(b, sources, roc, &.{target}, "daemon/main.roc", "liton-daemon"), "bin/liton-daemon");
        _ = tree.addCopyFile(addRocBuild(b, sources, roc, &.{target}, "cli/main.roc", "liton"), "bin/liton");
        _ = tree.addCopyDirectory(release_www, "share/liton/www", .{});
        const name = b.fmt("liton-{s}-{s}.tar.gz", .{ version, release[0] });
        const archive = b.addSystemCommand(&.{ "tar", "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "--use-compress-program=gzip -n" });
        archive.addPrefixedDirectoryArg("--directory=", tree.getDirectory());
        const packed_archive = archive.addPrefixedOutputFileArg("--file=", name);
        archive.addArgs(&.{ "--create", "bin", "share" });
        const install = b.addInstallFileWithDir(packed_archive, .{ .custom = "release" }, name);
        release_step.dependOn(&install.step);
        sums.addArg(name);
        sums.step.dependOn(&install.step);
    }
    // In zig-out/release, so the sums name the archives alone.
    sums.setCwd(.{ .cwd_relative = b.getInstallPath(.{ .custom = "release" }, "") });
    release_step.dependOn(&b.addInstallFileWithDir(sums.captureStdOut(.{}), .{ .custom = "release" }, "SHA256SUMS").step);

    // Serves the UI, its API docs and the API at http://127.0.0.1:8095
    // (LITON_HOST and LITON_PORT to change it).
    const run_step = b.step("run", "Build the UI and the daemon, and run the daemon");
    const run_daemon = b.addSystemCommand(&.{"zig-out/bin/liton-daemon"});
    run_daemon.has_side_effects = true;
    run_daemon.step.dependOn(&install_ui.step);
    run_daemon.step.dependOn(&install_daemon.step);
    run_daemon.step.dependOn(&install_docs.step);
    run_step.dependOn(&run_daemon.step);

    // Drives the UI in headless Chrome (CHROME, or chromium on PATH) against
    // a daemon of its own serving the mock provider, through the DevTools
    // client in roc-signals's source, which its release bundle leaves out.
    const e2e_step = b.step("e2e", "Drive the UI in headless Chrome against the daemon");
    const run_e2e = b.addSystemCommand(&.{ "node", "e2e/journey.mjs" });
    run_e2e.addFileArg(b.dependency("roc_signals_source", .{}).path("tests/browser/cdp.mjs"));
    run_e2e.has_side_effects = true;
    run_e2e.step.dependOn(&install_ui.step);
    run_e2e.step.dependOn(&install_daemon.step);
    run_e2e.step.dependOn(&install_cli.step);
    e2e_step.dependOn(&run_e2e.step);
    const run_protocol = b.addSystemCommand(&.{ "node", "e2e/protocol.mjs" });
    run_protocol.has_side_effects = true;
    run_protocol.step.dependOn(&install_daemon.step);
    run_protocol.step.dependOn(&install_cli.step);
    e2e_step.dependOn(&run_protocol.step);
    const run_auth = b.addSystemCommand(&.{ "node", "e2e/auth.mjs" });
    run_auth.has_side_effects = true;
    run_auth.step.dependOn(&install_daemon.step);
    run_auth.step.dependOn(&install_cli.step);
    e2e_step.dependOn(&run_auth.step);
    const run_federation = b.addSystemCommand(&.{ "node", "e2e/federation.mjs" });
    run_federation.has_side_effects = true;
    run_federation.step.dependOn(&install_daemon.step);
    run_federation.step.dependOn(&install_example.step);
    e2e_step.dependOn(&run_federation.step);
    // Transcribes a fixture only with LITON_STT naming a running speech
    // engine (rig/speech/), and skips that check without one.
    const run_voice = b.addSystemCommand(&.{ "node", "e2e/voice.mjs" });
    run_voice.has_side_effects = true;
    run_voice.step.dependOn(&install_daemon.step);
    e2e_step.dependOn(&run_voice.step);
    // Dictates in headless Chrome from a fake microphone playing the same
    // fixture, and skips the dictation without an engine.
    const run_voice_ui = b.addSystemCommand(&.{ "node", "e2e/voice-ui.mjs" });
    run_voice_ui.addFileArg(b.dependency("roc_signals_source", .{}).path("tests/browser/cdp.mjs"));
    run_voice_ui.has_side_effects = true;
    run_voice_ui.step.dependOn(&install_ui.step);
    run_voice_ui.step.dependOn(&install_daemon.step);
    e2e_step.dependOn(&run_voice_ui.step);

    // Benchmarks liton against Paseo's web client in a private network
    // namespace, against a throwaway Paseo (bench/README.md).
    const bench_step = b.step("bench", "Benchmark liton against Paseo's web client");
    const run_bench = b.addSystemCommand(&.{ "node", "bench/bench.mjs" });
    run_bench.addFileArg(b.dependency("roc_signals_source", .{}).path("tests/browser/cdp.mjs"));
    run_bench.has_side_effects = true;
    run_bench.step.dependOn(&install_ui.step);
    run_bench.step.dependOn(&install_daemon.step);
    bench_step.dependOn(&run_bench.step);
}
