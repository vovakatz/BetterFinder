---
name: run-betterfinder
description: Build, run, and drive the BetterFinder macOS app. Use when asked to run or start BetterFinder, build it, screenshot its UI, click through it, reproduce a UI bug, confirm a fix works in the real app, or measure click performance.
---

BetterFinder is a SwiftUI file manager. Drive it with `.claude/skills/run-betterfinder/drive.sh`, which injects `driver.m` into a test build and runs a script of clicks, keys, and snapshots. All paths are relative to the repo root.

Everything runs inside the app process, so it needs no Accessibility or Screen Recording permission. External tools don't work here: `osascript` clicks, `screencapture`, and `CGEvent` posting are all denied to the agent's shell.

## Prerequisites

Xcode (verified with 26.2) on macOS. Nothing else to install; SwiftTerm resolves during the build.

## Build

```bash
.claude/skills/run-betterfinder/drive.sh build
.claude/skills/run-betterfinder/drive.sh fixtures
```

`build` compiles your working tree under the throwaway bundle ID `com.KatzStudio.BetterFinder.agent`, so runs can't touch the developer's settings. `fixtures` generates 12 colored JPEGs and a `nested/Album` folder. Output goes to `$TMPDIR/betterfinder-agent` (`BF_WORK` overrides it; `drive.sh path` prints it).

## Run (agent path)

Pipe a script of steps to `run`. Each `--out` name gets its own directory, and the log prints when the script ends.

```bash
.claude/skills/run-betterfinder/drive.sh run --out first <<'EOF'
wait 3
snap 0_before
click 407 273
wait 0.5
pixel 350 273 cell_background
snap 1_selected
EOF
```

Snapshots land in `<work>/out/<name>/`, next to `driver.log` and `app.log`. **Read the PNG with the Read tool**; a clean log does not prove the app did what you wanted.

A window appears on the real screen and takes focus for the length of the run.

| Step | What it does |
|---|---|
| `wait <sec>` | Pause. Put one after every input, before you observe the result. |
| `click <x> <y> [cmd] [shift] [opt] [ctrl]` | Left click. |
| `rclick <x> <y>` | Opens the context menu. |
| `move <x> <y>` | Hover over a point. Required before `dclick`, and before clicking a name to rename it. |
| `dclick <x> <y>` | Double click. |
| `key <name> [cmd] [shift] [opt] [ctrl]` | A character, or `return`, `escape`, `tab`, `delete`, `up`, `down`, `left`, `right`. |
| `type <text>` | Insert text into the focused field, or warn if no text field has focus. |
| `menu` | Log the open context menu's items. |
| `pick <title>` | Choose an item from the open context menu. |
| `snap <name>` | Save `<name>.png`, flattened onto white. |
| `pixel <x> <y> [label]` | Log RGBA at a point. Alpha 0 means nothing is drawn there. |
| `stall <sec>` | Log the longest main-thread stall. Start it **before** the action. |
| `touch <name>` | Create a file in the start folder (fixtures only). |
| `windows` | Log the app's windows and run loop mode. |
| `quit` | Exit now. The script also exits at its end. |

`run` options: `--fixture NAME` or `--folder PATH` picks the start folder (default: `photos`), `--mode thumbnails|list` (default: `thumbnails`), `--tag NAME` picks the build, `--timeout SEC` sets the watchdog (default: 60).

### Layout

Coordinates are points from the window's top-left, and snapshots are 2x, so halve what you read off a PNG. A run always starts at 1000x650.

- **Grid cells:** columns at x = 262, 407, 553, 698 and rows at y = 134, 273, 412. A cell's name is 51 points below its center, such as (407, 324).
- **Selection in the grid:** sample 57 points left of the cell's center, such as `pixel 350 273` for the cell at (407, 273). Selected reads `rgba=(50,120,245,51)`, unselected reads `(0,0,0,0)`.
- **List rows:** the first row is at y = 113, and each row is 20 points tall.

### Recipes

**Is the state wrong, or did the view just not redraw?** The Info panel and status bar show the app's real selection, so compare them with the grid. Then force a redraw: if the highlight appears only after an unrelated write, the view isn't observing the state.

```bash
.claude/skills/run-betterfinder/drive.sh run --out redraw <<'EOF'
wait 3
click 407 273
wait 0.5
pixel 350 273 after_click
touch redraw.txt
wait 1
pixel 350 273 after_unrelated_write
EOF
```

**Use a context menu, then check the result on disk.** `menu` also shows what a menu targets: Rename only appears for a single file.

```bash
.claude/skills/run-betterfinder/drive.sh fixtures
.claude/skills/run-betterfinder/drive.sh run --out rename <<'EOF'
wait 3
rclick 407 273
wait 0.5
menu
pick Rename
wait 0.6
type renamed-file
wait 0.3
click 553 273
wait 1.2
EOF
ls "$(.claude/skills/run-betterfinder/drive.sh path)/fixtures/photos" | grep renamed
```

**Click a selected name to rename it.** The second click starts the rename after a 0.5 second delay, so `wait` past that before typing. Use the same steps in list view with `--mode list` and a point on a row's name, such as (275, 133).

```bash
.claude/skills/run-betterfinder/drive.sh fixtures
.claude/skills/run-betterfinder/drive.sh run --out click-rename <<'EOF'
wait 3
move 407 324
wait 0.3
click 407 324
wait 1.1
move 407 324
wait 0.2
click 407 324
wait 1
type renamed-file
wait 0.3
key return
wait 1
EOF
ls "$(.claude/skills/run-betterfinder/drive.sh path)/fixtures/photos" | grep renamed
```

**Open a folder.**

```bash
.claude/skills/run-betterfinder/drive.sh run --out open --fixture nested <<'EOF'
wait 3
move 262 134
wait 0.4
dclick 262 134
wait 1.5
snap opened
EOF
```

**List view.**

```bash
.claude/skills/run-betterfinder/drive.sh run --out list --mode list <<'EOF'
wait 3
click 300 133
wait 0.4
key down
wait 0.4
snap selected
EOF
```

**Compare a change against a baseline.** `--ref` builds an exported copy, so your working tree stays put. It contains committed code only, which makes `--ref HEAD` the "before" for uncommitted work. Use `--release`, and run performance comparisons more than once.

```bash
D=.claude/skills/run-betterfinder/drive.sh
$D build --release --tag before --ref HEAD
$D build --release --tag after
$D fixtures --name big --count 5000
for tag in before after; do
  $D run --out perf-$tag --tag $tag --fixture big <<'EOF'
wait 8
stall 0.6
click 262 134
wait 1
stall 0.6
click 407 134
wait 1
stall 0.6
click 553 134
wait 1
EOF
done
```

**Clean up** when you're done:

```bash
.claude/skills/run-betterfinder/drive.sh clean
```

## Run (human path)

`./build_and_install.sh` builds Release and overwrites `/Applications/BetterFinder.app`. Don't run it unless asked: it replaces the developer's installed copy, and it isn't drivable.

## Test

There is no test suite. Verify changes with the driver.

## Gotchas

- **`pick` and `type` act for real.** Move to Trash really trashes. Keep them on fixtures. `--folder` is for read-only looking at real folders, such as a network volume, and `touch` refuses to run there. Give network folders a longer first `wait` (12 seconds worked for 23 photos on a NAS).
- **`dclick` without `move` only selects.** The app ignores double-clicks unless `.onHover` reports the mouse over the view, and synthetic clicks don't produce hover. The log looks clean either way, so check the path bar or the Back arrow.
- **`key return` doesn't open items in the grid.** Its `.onKeyPress` needs keyboard focus that the scroll view doesn't have. Use `move` then `dclick`.
- **Double-clicking a JPEG launches Preview,** which takes focus and leaves a window open. Test opening with `--fixture nested`.
- **`stall` after a click under-reports badly.** The work has already finished by the next step, and it read 4.5ms for a click that really took over 40ms. Start it first, then `wait` longer than its duration.
- **Debug builds overstate SwiftUI cost.** One click measured about 118ms in Debug and 83ms in Release. Identical builds also vary between runs (33 to 53ms in one case), so don't read much into a single run.
- **Drag and drop can't be driven,** and clicks on the sidebar are untested. Verify those by hand.
- **Snapshots skip the sidebar and window chrome.** They render blank, which isn't a bug in the app. The left 180 points of a snapshot are empty.
- **Cmd+A acts oddly under the driver.** With nothing selected it does nothing, and after a selection it reports one item fewer than it highlights. Don't treat it as a reliable way to select everything.
- **SourceKit errors like `Cannot find type 'FileListViewModel' in scope` are noise** from single-file indexing. Trust `xcodebuild`.
- **Editing `driver.m`: post events with `postEvent`, never `sendEvent`.** `sendEvent` bypasses the queue, so `NSTableView`'s tracking loop never sees the mouse-up and the app hangs.
- **Editing `driver.m`: keep hover on hosting views.** List rows have their own `CellHostingView`, so `move` walks the views under the point. Sending `mouseEntered:` to the window frame raises an exception.
- **A crash shows the developer a macOS dialog.** Its Reopen button starts the test copy with no driver or arguments, and that copy then trips the double-launch guard.
- **Agent shell limits:** foreground `sleep` is blocked and macOS has no `timeout`, so use `wait` steps and `--timeout`. zsh aborts on unmatched globs, so quote them.

## Troubleshooting

- **`error: another driven instance is running (pid N)`:** two copies fight over focus and the loser's results are invalid. Let it finish, or kill that pid. If `ps -o ppid,command -p N` shows parent 1 and no arguments, it's a test copy reopened after a crash, and it's safe to kill.
- **`INVALID RUN`, exit 4:** a `WARNING` was logged. Either the window lost focus mid-run or `type` found no text field. Clicks on an unfocused window don't behave normally, so discard the results and run again. `focus: <app> became active` lines in the log name what took it. If the developer is using the Mac, that can hit every run, so wait until they're done rather than retrying.
- **`WATCHDOG: exceeded Ns, stuck at step: ...`, exit 124:** the step wedged the main thread, or the script simply outlasted `--timeout`. Raise the timeout, or look at `app.log`.
- **`menu: no context menu is open`:** nothing was under the point, or the `wait` after `rclick` was too short. The `windows` step shows an `NSPopupMenuWindow` when a menu is really open.
- **`error: no build for tag 'NAME'`:** run `drive.sh build --tag NAME` first.
- **`ERROR: touch refused`:** the start folder isn't a fixture.
- **`ERROR: unknown step`, exit 2:** a typo in the script.
