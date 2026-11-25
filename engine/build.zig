const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.dependency("translate_c", .{});
    const backend_name = b.option([]const u8, "backend", "Input backend") orelse "x11";

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

    const x11_c: Translator = .init(translate_c, .{
        .name = "x11_c",
        .c_source_file = b.path("src/platform/x11.h"),
        .target = target,
        .optimize = optimize,
        // Header discovery during translation plus linking on x11_c.mod.
        .link_system_libs = &.{
            .{ .name = "X11" },
            .{ .name = "Xtst" },
        },
    });

    const backend_root = if (std.mem.eql(u8, backend_name, "x11"))
        b.path("src/platform/x11.zig")
    else
        std.debug.panic("unsupported backend: {s}", .{backend_name});

    const backend_mod = b.createModule(.{
        .root_source_file = backend_root,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model", .module = model_mod },
            .{ .name = "platform_api", .module = api_mod },
            .{ .name = "x11_c", .module = x11_c.mod },
        },
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
