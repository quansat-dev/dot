const std = @import("std");
const zli = @import("zli");

const path = @import("path.zig");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "config",
        .description = "Manage dot configuration",
    }, showHelp);

    try command.addCommands(&.{
        try path.register(init_options),
    });

    return command;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
