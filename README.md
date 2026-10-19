# tern-omp-groups

Group [omp](https://omp.sh) chats in [Tern](https://stencil.so/tern) by a stable code, switch between chats and their subagents, and read any chat's history.

- omp starts every chat title with a code: the issue key without the hyphen (`ABC123`), else a work type (`PR`, `EXPLAIN`, `TRIAGE`, `PLAN`, `BUILD`, `OMP`, `OPS`, `MISC`).
- When a new chat gets its code, Tern moves the chat to the session with that name, and the window follows it.
- The **history** icon button in Tern's status line (or `⌘⌥O`) lists every saved chat under its group, with its subagents below it. Pick a chat to jump to it or reopen it. Pick a subagent to read its history.
- The palette command **Read omp chat history** opens the history of any chat or subagent, open or closed, as a scrollable note.

Design notes: [`docs/design.md`](docs/design.md).

## Setup

You need [Tern](https://stencil.so/tern) (closed beta) with `tern` on your `PATH`, and [omp](https://omp.sh) with a logged-in model provider. Then run:

```sh
curl -fsSL https://raw.githubusercontent.com/vishiod/tern-omp-groups/main/install.sh | sh
```

The script installs the plugin, the omp title rule, Tern's status line and the omp reload hook, then checks that the plugin loaded. Run it again to update. Your own `~/.omp/agent/TITLE_SYSTEM.md` is kept as `TITLE_SYSTEM.md.bak`.

| Command | Result |
|---|---|
| `sh install.sh --uninstall` | Removes everything the script installed and restores your title rule |
| `./install.sh --dev` (in a clone) | Links the clone, so Tern reloads the plugin when you save a file |

Installing a plugin runs its code with your account's access. Read `window.luau`, `codes.luau` and `transcript.luau` before you install.

Tested with macOS 15, Tern 0.8.4 and omp 18.11.1.

## Use

| To | Do |
|---|---|
| Find, switch to or reopen a chat | Click the **history** icon, or press `⌘⌥O`, then pick the chat |
| Read a subagent's history | Same picker, pick the `↳` row under its chat |
| Read a chat's history without opening it | Palette (`⌘⇧P`): **Read omp chat history** |
| Switch between whole groups | `⌘⇧P`, then the **Sessions** filter |
| Start a chat in a group | Name the issue key or the kind of work in your first prompt |

A chat's group is the Tern session that holds it, so the picker and the **Sessions** filter always agree. A chat moves at most once: later title changes (`/rename`, re-plan) do not move it again.

The history note shows the user and assistant messages, oldest first, with one line per tool call. It leaves out thinking and tool output. A very long chat shows its newest 512 KiB.

## Troubleshooting

| Symptom | Fix |
|---|---|
| The **history** icon is gone, or a toast says "Plugin omp status failed" | Tern turned off a hook that ran over its time budget. Start a new omp chat (the reload hook turns it on again) or run `tern plugin reload`. |
| Chats do not move | Check that `~/.omp/agent/TITLE_SYSTEM.md` exists and that no `<project>/.omp/TITLE_SYSTEM.md` overrides it |
| `⌘⌥O` does nothing | Use the palette command **Reopen omp chat** |
| `tern plugin list` shows `failed:` | Read the error, then run `tern plugin reload` |

Plugin state is in `~/Library/Application Support/Tern/plugin-data/omp-groups/kv.json`.

## Develop

```sh
git clone https://github.com/vishiod/tern-omp-groups.git && cd tern-omp-groups
./install.sh --dev
luau tests/codes_test.luau && luau tests/transcript_test.luau
```

| File | Purpose |
|---|---|
| `install.sh` | Setup, update, dev link and removal |
| `plugin.toml` | Tern manifest |
| `window.luau` | Tern glue: auto-move, group memory, picker, history notes, status button |
| `codes.luau` | Pure logic: parse, normalize, group, age |
| `transcript.luau` | Pure logic: find subagents, turn a session file into a history note |
| `tests/` | Tests for the pure logic |
| `omp/TITLE_SYSTEM.md` | omp title rule |
| `omp/reload-hook.ts` | omp hook: reloads the plugin on a new chat when Tern turned it off |

Tern plugin docs: <https://docs.stencil.so/tern/guides/getting-started.html>.

## License

[MIT](LICENSE)
