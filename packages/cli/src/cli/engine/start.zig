const std = @import("std");
const zli = @import("zli");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "start",
        .description = "Start the dot engine",
    }, run);

    try command.addFlag(.{
        .name = "replace",
        .shortcut = "r",
        .description = "If a dot engine is already running, replace with this new one",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    return command;
}

fn run(_: zli.CommandContext) !void {
    // TBD
}
