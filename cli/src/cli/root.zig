const std = @import("std");
const zli = @import("zli");

const engine = @import("engine/root.zig");
const config = @import("config/root.zig");
const version = @import("version.zig");

pub fn build(init_options: zli.InitOptions) !*zli.Command {
    const root = try zli.Command.init(init_options, .{
        .name = "dot",
        .description = "(d)igital (o)bservability (t)oolkit",
        .version = .{ .major = 0, .minor = 0, .patch = 1, .pre = null, .build = null },
        .help_footer = "More info at https://quansat.dev/dot",
    }, showHelp);

    try root.addFlag(.{
        .name = "config",
        .shortcut = "c",
        .description = "Path to a custom config file",
        .type = .String,
        .default_value = .{ .String = "~/.config/dot/init.lua" },
        .persistent = true,
    });

    try root.addCommands(&.{
        try engine.register(init_options),
        try config.register(init_options),
        try version.register(init_options),
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
