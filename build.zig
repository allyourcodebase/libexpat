const std = @import("std");

const version: std.SemanticVersion = .{ .major = 2, .minor = 7, .patch = 1 };

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("libexpat", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .static;
    const strip = b.option(bool, "strip", "Omit debug information");
    const pic = b.option(bool, "pie", "Produce Position Independent Code");

    // Most of these config options have not been tested.

    var context_bytes = b.option(i64, "context-bytes", "Define to specify how much context to retain around the current parse point, 0 to disable") orelse 1024;
    if (context_bytes < 0) context_bytes = 0;

    const CharType = enum {
        char,
        ushort,
        wchar_t,
    };

    const char_type = b.option(CharType, "char-type", "Character type to use. (default=char)") orelse .char;
    const dtd = b.option(bool, "dtd", "Define to make parameter entity parsing functionality available") orelse true;
    const ge = b.option(bool, "ge", "Define to make general entity parsing functionality available") orelse true;
    const ns = b.option(bool, "ns", "Define to make XML Namespaces functionality available") orelse true;
    const attr_info = b.option(bool, "attr-info", "Define to allow retrieving the byte offsets for attribute names and values") orelse false;
    const large_size = b.option(bool, "large-size", "Make XML_GetCurrent* functions return <(unsigned) long long> rather than <(unsigned) long>") orelse false;
    const min_size = b.option(bool, "min-size", "Get a smaller (but slower) parser (in particular avoid multiple copies of the tokenizer)") orelse false;

    if (dtd and !ge) {
        std.log.err("Option `dtd` requires that `ge` is also enabled.", .{});
        std.log.err("Please either enable option `ge` (recommended) or disable `dtd` also.\n", .{});
        b.invalid_user_input = true;
        return;
    }

    const need_short_char_arg = char_type == .wchar_t and target.result.os.tag != .windows;

    const examples_dir: std.Build.Step.InstallArtifact.Options.Dir = .{ .override = .{ .custom = "examples" } };

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(upstream.path("expat/AUTHORS"), .prefix, "AUTHORS").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(upstream.path("expat/Changes"), .prefix, "changelog").step);

    const has_getrandom: bool = switch (target.result.os.tag) {
        .linux => if (target.result.isMuslLibC())
            true
        else if (target.result.isGnuLibC())
            target.result.os.version_range.linux.glibc.order(.{ .major = 2, .minor = 25, .patch = 0 }) != .lt
        else
            unreachable,
        .freebsd => target.result.os.isAtLeast(.freebsd, .{ .major = 12, .minor = 0, .patch = 0 }) orelse false,
        .netbsd => target.result.os.isAtLeast(.netbsd, .{ .major = 10, .minor = 0, .patch = 0 }) orelse false,
        else => false,
    };

    const config_header = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("expat/expat_config.h.cmake") },
        .include_path = "expat_config.h",
    }, .{
        .BYTEORDER = @as(i64, switch (target.result.cpu.arch.endian()) {
            .little => 1234,
            .big => 4321,
        }),
        .HAVE_ARC4RANDOM = null,
        .HAVE_ARC4RANDOM_BUF = switch (target.result.os.tag) {
            .dragonfly,
            .netbsd,
            .freebsd,
            .solaris,
            .openbsd,
            .macos,
            .ios,
            .tvos,
            .watchos,
            .visionos,
            => true,
            else => false,
        },
        .HAVE_DLFCN_H = target.result.os.tag != .windows,
        .HAVE_FCNTL_H = true,
        .HAVE_GETPAGESIZE = target.result.os.tag.isBSD(),
        .HAVE_GETRANDOM = has_getrandom,
        .HAVE_INTTYPES_H = true,
        .HAVE_LIBBSD = null,
        .HAVE_MEMORY_H = true,
        .HAVE_MMAP = target.result.os.tag != .windows and target.result.os.tag != .wasi,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYSCALL_GETRANDOM = has_getrandom,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .PACKAGE = "expat",
        .PACKAGE_BUGREPORT = "https://github.com/libexpat/libexpat/issues",
        .PACKAGE_NAME = "expat",
        .PACKAGE_STRING = b.fmt("expat {}", .{version}),
        .PACKAGE_TARNAME = "expat",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{version}),
        .STDC_HEADERS = true,
        .WORDS_BIGENDIAN = target.result.cpu.arch.endian() == .big,
        .XML_ATTR_INFO = attr_info,
        .XML_CONTEXT_BYTES = context_bytes,
        .XML_DEV_URANDOM = target.result.os.tag != .windows,
        .XML_DTD = dtd,
        .XML_GE = ge,
        .XML_NS = ns,
        .off_t = null,
    });

    const expat = b.addLibrary(.{
        .linkage = linkage,
        .name = "expat",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .strip = strip,
            .pic = pic,
        }),
    });
    b.installArtifact(expat);
    expat.root_module.addConfigHeader(config_header);
    if (large_size) expat.root_module.addCMacro("XML_LARGE_SIZE", "1");
    if (min_size) expat.root_module.addCMacro("XML_MIN_SIZE", "1");
    if (char_type != .char) expat.root_module.addCMacro("XML_UNICODE", "1");
    if (char_type == .wchar_t) expat.root_module.addCMacro("XML_UNICODE_WCHAR_T", "1");
    expat.root_module.addIncludePath(upstream.path("expat/lib"));
    expat.installHeader(upstream.path("expat/lib/expat.h"), "expat.h");
    expat.installHeader(upstream.path("expat/lib/expat_external.h"), "expat_external.h");
    expat.root_module.addCSourceFiles(.{
        .files = sources,
        .root = upstream.path("expat"),
        .flags = if (need_short_char_arg) &.{ "-std=c99", "-fshort-wchar" } else &.{"-std=c99"},
    });

    const xmlwf = b.addExecutable(.{
        .name = "xmlwf",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .strip = strip,
            .pic = pic,
        }),
    });
    xmlwf.root_module.addConfigHeader(config_header);
    xmlwf.root_module.addIncludePath(upstream.path("expat/lib"));
    if (char_type != .char) xmlwf.root_module.addCMacro("XML_UNICODE", "1");
    if (char_type == .wchar_t) xmlwf.root_module.addCMacro("XML_UNICODE_WCHAR_T", "1");
    xmlwf.root_module.addCSourceFiles(.{
        .files = xmlwf_sources,
        .root = upstream.path("expat"),
        .flags = if (need_short_char_arg) &.{"-fshort-wchar"} else &.{},
    });
    xmlwf.root_module.linkLibrary(expat);

    switch (char_type) {
        .char => {},
        .ushort => @panic("The xmlwf tool can not be built with option -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t)"),
        .wchar_t => if (target.result.os.tag != .windows) {
            @panic("The xmlwf tool can not be built with option -Dchar-type=wchar_t outside of Windows. Please pass -Dchar-type=char");
        },
    }

    const run_xmlwf_cmd = b.addRunArtifact(xmlwf);

    if (b.args) |args| {
        run_xmlwf_cmd.addArgs(args);
    }

    const xmlwf_step = b.step("xmlwf", "run xmlwf");
    xmlwf_step.dependOn(&run_xmlwf_cmd.step);

    const examples_step = b.step("examples", "Build examples");

    for (examples) |source| {
        const exe = b.addExecutable(.{
            .name = std.fs.path.stem(source),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .strip = strip,
                .pic = pic,
            }),
        });
        if (char_type != .char) exe.root_module.addCMacro("XML_UNICODE", "1");
        if (char_type == .wchar_t) exe.root_module.addCMacro("XML_UNICODE_WCHAR_T", "1");
        exe.root_module.addCSourceFile(.{
            .file = upstream.path(b.fmt("expat/{s}", .{source})),
            .flags = if (need_short_char_arg) &.{"-fshort-wchar"} else &.{},
        });
        exe.root_module.linkLibrary(expat);

        examples_step.dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = examples_dir }).step);

        if (char_type == .ushort) {
            @panic("Examples can not be built with option -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t)");
        }
    }

    const test_step = b.step("test", "Run unit tests");

    for (
        [_][]const u8{ "runtests", "runtests_cxx" },
        [_][]const []const u8{ runtests_sources, runtests_cxx_sources },
        [_]bool{ false, true },
    ) |name, test_sources, link_cpp| {
        var flags: std.ArrayListUnmanaged([]const u8) = .{};
        if (link_cpp) flags.append(b.allocator, "-std=c++11") catch @panic("OOM");
        if (need_short_char_arg) flags.append(b.allocator, "-fshort-wchar") catch @panic("OOM");

        const test_exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .link_libcpp = link_cpp,
                .strip = strip,
                .pic = pic,
            }),
        });
        test_exe.root_module.addCMacro("XML_TESTING", "1");
        if (char_type != .char) test_exe.root_module.addCMacro("XML_UNICODE", "1");
        if (char_type == .wchar_t) test_exe.root_module.addCMacro("XML_UNICODE_WCHAR_T", "1");
        test_exe.root_module.addCSourceFiles(.{
            .flags = flags.items,
            .root = upstream.path("expat"),
            .files = test_sources,
        });
        test_exe.root_module.addConfigHeader(config_header);
        test_exe.root_module.addIncludePath(upstream.path("expat/lib"));
        if (large_size) test_exe.root_module.addCMacro("XML_LARGE_SIZE", "1");
        if (min_size) test_exe.root_module.addCMacro("XML_MIN_SIZE", "1");
        test_exe.root_module.addCSourceFiles(.{
            .files = sources,
            .root = upstream.path("expat"),
            .flags = if (need_short_char_arg) &.{ "-std=c99", "-fshort-wchar" } else &.{"-std=c99"},
        });

        if (char_type == .ushort) {
            @panic("The testsuite can not be built with option -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t)");
        }

        const run_test_cmd = b.addRunArtifact(test_exe);
        if (b.args) |args| {
            run_test_cmd.addArgs(args);
        }
        test_step.dependOn(&run_test_cmd.step);
    }

    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .target = target,
        .optimize = optimize,
    });
    if (char_type != .char) benchmark.root_module.addCMacro("XML_UNICODE", "1");
    if (char_type == .wchar_t) benchmark.root_module.addCMacro("XML_UNICODE_WCHAR_T", "1");
    benchmark.addCSourceFile(.{
        .file = upstream.path("expat/tests/benchmark/benchmark.c"),
        .flags = if (need_short_char_arg) &.{"-fshort-wchar"} else &.{},
    });
    benchmark.linkLibrary(expat);

    const run_benchmark_cmd = b.addRunArtifact(benchmark);
    if (b.args) |args| {
        run_benchmark_cmd.addArgs(args);
    }

    const benchmark_step = b.step("benchmark", "Run benchmark");
    benchmark_step.dependOn(&run_benchmark_cmd.step);
}

const sources: []const []const u8 = &.{
    "lib/xmlparse.c",
    "lib/xmlrole.c",
    "lib/xmltok.c",
};

const xmlwf_sources: []const []const u8 = &.{
    "xmlwf/codepage.c",
    "xmlwf/readfilemap.c",
    "xmlwf/xmlfile.c",
    "xmlwf/xmlwf.c",
};

const examples: []const []const u8 = &.{
    "examples/element_declarations.c",
    "examples/elements.c",
    "examples/outline.c",
};

const runtests_sources: []const []const u8 = &.{
    "tests/acc_tests.c",
    "tests/alloc_tests.c",
    "tests/basic_tests.c",
    "tests/chardata.c",
    "tests/common.c",
    "tests/dummy.c",
    "tests/handlers.c",
    "tests/memcheck.c",
    "tests/minicheck.c",
    "tests/misc_tests.c",
    "tests/ns_tests.c",
    "tests/nsalloc_tests.c",
    "tests/runtests.c",
    "tests/structdata.c",
};

const runtests_cxx_sources: []const []const u8 = &.{
    "tests/acc_tests_cxx.cpp",
    "tests/alloc_tests_cxx.cpp",
    "tests/basic_tests_cxx.cpp",
    "tests/chardata_cxx.cpp",
    "tests/common_cxx.cpp",
    "tests/dummy_cxx.cpp",
    "tests/handlers_cxx.cpp",
    "tests/memcheck_cxx.cpp",
    "tests/minicheck_cxx.cpp",
    "tests/misc_tests_cxx.cpp",
    "tests/ns_tests_cxx.cpp",
    "tests/nsalloc_tests_cxx.cpp",
    "tests/runtests_cxx.cpp",
    "tests/structdata_cxx.cpp",
};
