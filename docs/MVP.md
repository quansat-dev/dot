## Minimal Viable Product (MVP)

## Target Audience

I am building this to first and foremost solve my own problem. The ideal persona for the MVP is therefore:

```
I am a freelancing developer 
    in need of a tool to semi-automatically track my digital activities across devices and projects, 
    without paying for subscriptions while retaining total control over my data,
    so that I can better understand how I spend my time and possess the data needed to generate accurate invoices or client reports.
``` 

## Overview

### I. Engine 

This is the core component that handles the tracking via native OS APIs. 

- since it needs to be cross-platform and performant, [rust] is likely a good candidate. 
- dot should come with a simple CLI out of the box to interact with the engine. [clap] is a good library for this purpose.

1. Install the engine via a single command on all UNIX-like systems or [winget] for Windows

    ```bash
    # UNIX
    curl -fsSL https://dot.quansat.dev/install.sh | sh
    # Windows
    winget install dot
    ```

2. Check the status of the engine:

    ```bash
    dot engine status
    ```

3. Start or stop the engine (tracking takes effect immediately and globally)

   ```bash
   dot engine start
   dot engine stop
   ```

3. Start or stop a project (tracking will be associated with the project until it is stopped)

   ```bash
   dot project start <project-name> --memo "some optional memo about the project"
   dot project stop <project-name>
   ```

4. Configure the engine via a config file in Lua, e.g. `~/.config/dot/init.lua`:

   ```lua
   return {
      -- config in lua
   }
   ```

### II. Query Capabilities

The CLI should support some basic query capabilities to show statistics about the tracked data. This should come out-of-the-box with the engine.

For example, 

```bash
dot query \
   [--project <project-name>] \
   [--app <app-name>] \
   [--from <start-date>] [--to <end-date>] \
   [--period <all | N day[s]|week[s]|month[s]|year[s]>] \
   [--metric <total|active>]
```

#### Sensible Defaults

- if no project is specified, show statistics for all projects,
- if no app is specified, show statistics for all apps,
- if no time range is specified, show statistics for the current day,
- if no metric is specified, show the total time.

Datetime (`--from` and `--to`) should accept some common format, but typically expected to support ISO format, e.g. `2026-06-01T00:00:00Z`. `--from` is inclusive while `--to` is exclusive, i.e time range is `[from, to)`.

`--period` should take precedence over `--from` and `--to` if specified, and should be relative to the current time.

### III. TUI Dashboard

For the MVP, let's hold off on building any desktop/web GUI for now and implement some form of text-based user interface (TUI) dashboard to interact with the engine and show some basic statistics. This is good since the target audience for this phase is developers, and we will have some opportunities to experiment with the overall dashboard design.

The TUI should be in rust as well (likely with [ratatui]), and can be installed together with the engine (if not too complex or heavy in size) or as a separate addon package.

```bash
dot dashboard
```

#### Core Features:

- Daily summary: total tracked time and app distributions for the current day.
- Visual analytics: terminal-rendered visual blocks, such as bar charts, proportional breakdown bars, and a GitHub-style activity contributions heatmap.
- Interactive filtering: keyboard-driven query inputs matching the CLI flags specified in II, updating the dashboard view in real time.

### IV. Plugin Ecosystem

We can start with the following plugins:

1. VSCode extension that adds metadata about the repo/branch/file/commit, and show relevant stats in the editor toolbar.
2. Lua-based neovim plugin that does the same as (1).
3. Browser extension (likely implemented using [wxt]) that adds metadata about the web domain, and show relevant stats in the extension popup.
4. [polybar] (linux-only) plugin that utilises the query capabilities in II.
 
#### Plugin-to-Engine Interprocess Communication

We'd likely need to implement some form of communication between the plugins and engine to add the metadata. Some ideas:

- some background daemon, e.g. via "Unix Domain Socket" on UNIX or "Named Pipes" on Windows -> this can support VSCode & Neovim plugins
- a local REST server -> this can support the browser extension and polybar plugin.

#### Unified Interface for Creating Plugins

> [!NOTE]
> This is not strictly necessary for the MVP, but something worth keeping in mind when designing the plugin system.

For extensibility, we can add some first-party libraries in different languages to provide some minimal abstraction for building plugins, e.g. a rust library, a lua library, and a javascript library. The example API could be as follows:

```js
import { definePlugin } from '@quansat/dot/plugin';

const plugin = definePlugin({
   name: 'my-plugin',
   engine: {
      // ... socket / REST configuration ...
   },
});

plugin.registerMetadata({ /* ... */ }); 
plugin.query({ /* ... */ });
```

```rust
use quansat_dot::plugin::define_plugin;

let plugin = define_plugin!(
   name: "my-plugin",
   engine: {
      // ... socket / REST configuration ...
   },
);

plugin.register_metadata({ /* ... */ });
plugin.query({ /* ... */ });
```

```lua
local plugin = require('@quansat/dot/plugin').define_plugin({
   name = 'my-plugin',
   engine = {
      -- ... socket / REST configuration ...
   },
})

plugin.register_metadata({ /* ... */ })
plugin.query({ /* ... */ })
```

#### Engine/Dashboard Plugin 

The plugins discussed above adds metadata to the tracking data. It would also be helpful to have some way to display this metadata in the dashboard or output in a human-readable format in the CLI query results. For that, we probably need a separate layer of plugin support in the engine/dashboard that consumes the metadata and transform it to the right format for display.

```lua
-- ~/.config/dot/init.lua
return {
   plugins = {
      my_plugin = {
         -- ... plugin definition ...
      },
   },
}
```

[rust]: https://rust-lang.org
[winget]: https://github.com/microsoft/winget-cli
[ratatui]: https://ratatui.rs/
[clap]: https://github.com/clap-rs/clap
[polybar]: https://github.com/polybar/polybar
[wxt]: https://wxt.dev/
