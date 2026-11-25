const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend_name = b.option([]const u8, "backend", "Input backend") orelse "x11";
    const is_x11 = std.mem.eql(u8, backend_name, "x11");

    const model_mod = b.createModule(.{
        .root_source_file = b.path("src/model.zig"),
        .target = target,
        .optimize = optimize,
    });

    const api_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model", .module = model_mod },
        },
    });

    const backend_root = if (is_x11)
        b.path("src/platform/x11/backend.zig")
    else
        std.debug.panic("unsupported backend: {s}", .{backend_name});

    const import_count: usize = if (is_x11) 3 else 2;
    const backend_imports = b.allocator.alloc(std.Build.Module.Import, import_count) catch unreachable;
    backend_imports[0] = .{ .name = "model", .module = model_mod };
    backend_imports[1] = .{ .name = "platform_api", .module = api_mod };

    // Only give the selected backend the imports its implementation needs.
    if (is_x11) {
        const translate_c = b.dependency("translate_c", .{});

        const x11_c: Translator = .init(translate_c, .{
            .name = "x11_c",
            .c_source_file = b.path("src/platform/x11/x11.h"),
            .target = target,
            .optimize = optimize,
            // Header discovery during translation plus linking on x11_c.mod.
            .link_system_libs = &.{
                .{ .name = "X11" },
                .{ .name = "Xtst" },
            },
        });

        backend_imports[2] = .{ .name = "x11_c", .module = x11_c.mod };
    }

    const backend_mod = b.createModule(.{
        .root_source_file = backend_root,
        .target = target,
        .optimize = optimize,
        .imports = backend_imports,
    });

    const exe = b.addExecutable(.{
        .name = "dot-engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "model", .module = model_mod },
                .{ .name = "platform_api", .module = api_mod },
                .{ .name = "backend", .module = backend_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run the engine").dependOn(&run.step);
}
