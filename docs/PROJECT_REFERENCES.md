# Project References

## Introduction

I want to track a lot of things, all in one place, using just one coherent and consistent tool, across all platforms.
And I want "dot" to be an open-source and local-first tool that can help me do that.

### What to Track?

There are just too many things I want to track, some examples are:

- digital activity, i.e how much time I spend on my devices, in which apps, on which web domains,
- books I own, have read, am reading, and have not read yet,
- my quantitative and qualitative health parameters, e.g weight, sleep time, my mood, my energy level, etc.,
- real-time questionnaire/quiz that helps facilitate presentation or workshop, similar to Kahoot but without all the subscription and cloud 💩.

This means there are a lot of opportunities and ideas to realise here. However, the primary focus for the MVP is the first one mentioned above.

#### Tracking Digital Activity

Imagine this use case: I am a freelancer working primarily on my desktop/laptop, where I spend my time in:

- code editors, e.g. VSCode or NeoVim,
- web browsers,
- a wide range of other apps, e.g. terminal, design tools (e.g. Figma), communication tools (Discord), etc.

dot runs in the background and tracks how much time I spend on each app, globally and scoped within a project if specified:

- I can optionally "select" a project, after which tracked time & activity will be associated with that project until I "deselect" it. Time tracked without selecting a project will be associated with a default/global project.
- When I go into my code editor, an optional dot integration (editor plugin), if present, will track in more detail what repo/branch/file/commit I am working on. Looking to [Wakatime](https://wakatime.com/), for example, time working on `.md` files is associated with a separate category "Writing docs".
- When I go into my web browser, an optional dot integration (browser extension), if present, will track in more detail which web domains I am spending time on. Note that dot only tracks the domain, not the specific page, for privacy reasons.

Regardless of the app, dot can track how much time I am on an app and show an aggregation of input events, e.g. number of keystrokes, mouse clicks, etc.

dot can show statistics:

- in table or graph format,
- optionally filtered by project, app, time range, etc.

dot can let me export my data from the above statistics in one or more standard formats, e.g csv, json, pdf, etc.

If a server is connected, dot can also host a shared project with teams/members, where data query and aggregation can be performed and shared across members.

### Local first

Data is stored on device first and foremost. Cloud storage is the last thing to support. In fact, top-priority should be cross-device sync, data migration, and data export over cloud storage. The central idea is to bring back user control over their tools and data.

Imagine this use case:

- I have a desktop (D), primarily where I perform my daily digital activities,developers
- I also own a laptop (L), which I sometimes take on the go to achieve the same digital activities,
- I also have a mobile (M) phone, where I perform a vastly different set of digital activities,

I want to be able to have dot installed on all these devices to track all relevant activities:

- The data will live on the device where the activity happens.
- Sometimes I get a configurable reminder to sync data between devices.
- I can perform two-way-sync between devices, for example between (D) & (M), after which both devices have the same data.

Optionally, I may connect dot to a dedicated home/remote server (S). Data from devices will automatically be uploaded to the server, and when querying data, dot will also grab data from the server.

From time to time, I want to backup and restore my data:

- dot allows me to export my data to one or more standard formats, e.g csv, json, xml, etc.
- dot also allows me to import a backup and restore all the data to the device.

### Open Source

Built in public, free to use, modify, and share. Note that "open source" doesn't necessarily mean "open contribution". Although I eventually want everyone to be able to contribute, let's start by locking the project to internal contributors only, and start accepting external contributions only when there is enough resource to maintain that aspect.

## Prior Arts & Inspiration Pool

- [mrusme/zeit](https://github.com/mrusme/zeit): a CLI tool; has the right idea, but quite rudimentary and require manual trigger.
- [wakatime](https://github.com/wakatime) is quite nice but [it has become a subscription service](https://wakatime.com/pricing). There is also [wakatime-focused](https://github.com/joshuadavidthomas/wakatime-focusd), or [wakatime-desktop](https://github.com/wakatime/desktop-wakatime) that may be relevant given the discussed use case.
