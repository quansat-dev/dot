const std = @import("std");
const zli = @import("zli");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "status",
        .description = "Show the status of a running dot engine, if any",
    }, run);

    return command;
}

fn run(_: zli.CommandContext) !void {
    // TBD
}
