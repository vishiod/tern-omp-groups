# tern-omp-groups

Group [omp](https://omp.sh) chats in [Tern](https://stencil.so/tern) by a stable code, and reopen any saved chat in its group with one click.

- omp starts every chat title with a code: the issue key without the hyphen (`ABC123`), else a work type (`PR`, `EXPLAIN`, `TRIAGE`, `PLAN`, `BUILD`, `OMP`, `OPS`, `MISC`).
- When a new chat gets its code, Tern moves the chat to the session with that name, and the window follows it.
- The **omp chats** button (or `⌘⌥O`) lists every saved chat under its group. Click an open chat to jump to it. Click a closed chat to reopen it in its group.

Design notes: [`docs/design.md`](docs/design.md).

## Contents

1. [Requirements](#requirements)
2. [Install Tern](#1-install-tern)
3. [Install omp](#2-install-omp)
4. [Install the plugin](#3-install-the-plugin)
5. [Install the omp title rule](#4-install-the-omp-title-rule)
6. [Turn on Tern's status line](#5-turn-on-terns-status-line)
7. [Check the setup](#6-check-the-setup)
8. [Use](#use)
9. [Troubleshooting](#troubleshooting)
10. [Update, remove, develop](#update)

## Requirements

| Item | Version used for testing | Note |
|---|---|---|
| macOS | 15 (Apple Silicon) | Tern also runs on Linux. This plugin is tested on macOS only. |
| Tern | 0.8.4 | Closed beta |
| omp | 18.11.1 | |
| git | any | `tern plugin install` clones with git |
| luau | 0.742 | Optional, only to run the tests |

## 1. Install Tern

Tern is a terminal from Stencil. Its sessions run in a daemon, so shells and omp chats keep running when the window closes.

1. Join the closed beta waitlist at <https://stencil.so/tern>.
2. When Stencil gives you access, install Tern with their instructions and sign in with your Stencil account.
3. Put the `tern` command on your `PATH`. On macOS with Homebrew on Apple Silicon:

   ```sh
   ln -s /Applications/Tern.app/Contents/MacOS/tern /opt/homebrew/bin/tern
   ```

   (On Intel Macs use `/usr/local/bin/tern`.)

4. Check it:

   ```sh
   tern --version
   ```

## 2. Install omp

omp is a terminal coding agent. Tern draws it natively and keeps its chats alive in the daemon.

1. Install it with one of these commands:

   ```sh
   curl -fsSL https://omp.sh/install | sh
   # or
   brew install can1357/tap/omp
   ```

2. Log in to a model provider:

   ```sh
   omp login
   ```

3. Optional: run the guided setup for optional features.

   ```sh
   omp setup
   ```

4. Check it:

   ```sh
   omp --version
   ```

NOTE: Tern can keep its own copy of omp in `~/Library/Application Support/Tern/omp/` and put it first on `PATH` inside Tern panes. Run `which omp` in a Tern pane to see which copy runs.

## 3. Install the plugin

```sh
tern plugin install github.com/vishiod/tern-omp-groups
tern plugin list
```

Expected line:

```text
omp-groups 0.1.0 omp groups — 0 blocks, 0 lenses, window  ready
```

Installing a plugin runs its code with your account's access. Read `window.luau` and `codes.luau` before you install.

## 4. Install the omp title rule

The rule makes omp start each title with a stable code. Copy it from the installed plugin:

```sh
mkdir -p ~/.omp/agent
cp "$(tern plugin dir)/omp-groups/omp/TITLE_SYSTEM.md" ~/.omp/agent/TITLE_SYSTEM.md
```

CAUTION: If `~/.omp/agent/TITLE_SYSTEM.md` already exists, the command replaces it. Merge the two files by hand if you want to keep your own rule.

- New chats use the rule at once. Chats that already have a title keep it.
- A project file wins over this global file: `<project>/.omp/TITLE_SYSTEM.md` (also `.claude/`, `.codex/` or `.gemini/`).
- With this rule, omp writes titles with its small title model, and titles have no icon.

## 5. Turn on Tern's status line

The **omp chats** button lives in Tern's status line, which is off by default.

1. Open `~/Library/Application Support/Tern/settings.json`.
2. Add `"status_bar": true`, for example:

   ```json
   {
     "status_bar": true
   }
   ```

3. In the command palette (`⌘⇧P`), run **Reload settings**.

You can skip this step and use `⌘⌥O` or the palette command **Reopen omp chat** instead.

## 6. Check the setup

1. In a Tern pane, run:

   ```sh
   omp "Start work on ABC-123: add a rate limit field. Reply OK only."
   ```

2. Wait for the title. Expected: the title is `ABC123: …`, the chat moves to a new session named `ABC123`, and the window shows it.
3. Click **omp chats** at the right end of the status line. Expected: a picker with an `ABC123` group that holds the chat, with a check mark.
4. Close the chat, then click **omp chats** again and pick it. Expected: the chat opens again in session `ABC123` with its history.

## Use

| To | Do |
|---|---|
| Find, switch to or reopen a chat | Click **omp chats**, or press `⌘⌥O` |
| Switch between whole groups | `⌘⇧P`, then the **Sessions** filter (open sessions only) |
| Start a chat in a group | Name the issue key or the kind of work in your first prompt |

### One source of truth

A chat's group is the Tern session that holds it, so the picker and the **Sessions** filter always agree.

| Chat | Group in the picker |
|---|---|
| Open | The session it is in now, also after you move it by hand |
| Closed | The last session the plugin saw it in |
| Never seen since install | Its title code |

### Behavior

| Event | Result |
|---|---|
| A chat title gets a code for the first time | The chat moves to session `<CODE>` (made if missing), and the window follows it |
| The title changes again (re-plan, `/rename`) | Nothing. A chat moves at most once and keeps its group. |
| A code is not a work type or an issue key | The group is `MISC` |
| The plugin loads or reloads | Nothing moves. Chats that are open stay where they are. |
| A move or read fails | An error toast shows the reason, and the chat stays where it is |

### Limits

- `/rename <text>` makes omp add its own icon and a free code in front of your text. The chat keeps its group, because the group is its session.
- A session with no pane has no status line. Use `⌘⌥O` there.
- Tern keeps a session after its last chat closes. Close empty sessions by hand.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Toast "Plugin omp status failed" (or another hook name) | A hook ran over Tern's time budget (status 4 ms, others 50 ms), and Tern turned it off | Run `tern plugin reload`. The log line is in `~/Library/Logs/Tern/tern.log` (`plugin hook exceeded its budget`). |
| No **omp chats** button | Status line is off, or the session has no pane | Do [step 5](#5-turn-on-terns-status-line), or use `⌘⌥O` |
| Chats do not move | Titles have no code | Check that `~/.omp/agent/TITLE_SYSTEM.md` exists and that no project file overrides it |
| `⌘⌥O` does nothing | Another binding uses the chord | Use the palette command **Reopen omp chat** |
| `tern plugin list` shows `failed:` | The plugin did not load | Read the error, then run `tern plugin reload` |

Plugin state is in `~/Library/Application Support/Tern/plugin-data/omp-groups/kv.json`: `moved` (pane id → code) and `groups` (omp chat id → last Tern session).

## Update

```sh
tern plugin install --force github.com/vishiod/tern-omp-groups
cp "$(tern plugin dir)/omp-groups/omp/TITLE_SYSTEM.md" ~/.omp/agent/TITLE_SYSTEM.md
```

## Remove

```sh
tern plugin remove omp-groups
rm ~/.omp/agent/TITLE_SYSTEM.md
```

Sessions that the plugin made stay. Close or rename them in Tern. The plugin data folder stays too. Delete `~/Library/Application Support/Tern/plugin-data/omp-groups` to start fresh.

## Develop

```sh
git clone https://github.com/vishiod/tern-omp-groups.git
cd tern-omp-groups
tern plugin link "$PWD"                         # Tern reloads the plugin when you save a file
ln -sf "$PWD/omp/TITLE_SYSTEM.md" ~/.omp/agent/TITLE_SYSTEM.md
brew install luau && luau tests/codes_test.luau # pure logic in codes.luau
tern plugin types "$PWD"                        # tern.d.luau for luau-lsp (not committed)
```

`tern plugin link` fails while an installed copy exists. Run `tern plugin remove omp-groups` first.

| File | Purpose |
|---|---|
| `plugin.toml` | Tern manifest |
| `window.luau` | Tern glue: auto-move, group memory, picker, status button |
| `codes.luau` | Pure logic: parse, normalize, group, age |
| `tests/codes_test.luau` | Tests for `codes.luau` |
| `omp/TITLE_SYSTEM.md` | omp title rule |
| `docs/design.md` | Design notes |

Tern plugin docs: <https://docs.stencil.so/tern/guides/getting-started.html>.

## License

[MIT](LICENSE)
