const std = @import("std");
const zli = @import("zli");

pub fn register(init_options: zli.InitOptions) !*zli.Command {
    return zli.Command.init(init_options, .{
        .name = "version",
        .shortcut = "v",
        .description = "Print dot CLI version",
    }, show);
}

fn show(ctx: zli.CommandContext) !void {
    try ctx.root.printVersion();
}
