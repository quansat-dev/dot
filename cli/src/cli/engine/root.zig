const std = @import("std");
const zli = @import("zli");

const start = @import("start.zig");
const stop = @import("stop.zig");
const status = @import("status.zig");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "engine",
        .description = "Manage the dot engine",
    }, showHelp);

    try command.addCommands(&.{
        try start.register(init_options),
        try stop.register(init_options),
        try status.register(init_options),
    });

    return command;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
