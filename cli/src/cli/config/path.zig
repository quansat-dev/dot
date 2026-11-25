const std = @import("std");
const zli = @import("zli");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    const command = try zli.Command.init(init_options, .{
        .name = "path",
        .description = "Print path to current dot configuration",
    }, run);

    return command;
}

fn run(ctx: zli.CommandContext) !void {
    const path = ctx.flag("config", []const u8);
    try ctx.writer.print("{s}", .{path});
}
