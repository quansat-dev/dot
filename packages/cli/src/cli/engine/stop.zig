const std = @import("std");
const zli = @import("zli");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "stop",
        .description = "Stop the dot engine",
    }, run);

    return command;
}

fn run(_: zli.CommandContext) !void {
    // TBD
}
