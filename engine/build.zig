const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.dependency("translate_c", .{});

    const x11: Translator = .init(translate_c, .{
        .name = "x11",
        .c_source_file = b.path("src/x11.h"),
        .target = target,
        .optimize = optimize,
        // Header discovery during translation plus linking on x11.mod.
        .link_system_libs = &.{
            .{ .name = "X11" },
            .{ .name = "Xtst" },
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
                .{ .name = "c", .module = x11.mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run the engine").dependOn(&run.step);
}
