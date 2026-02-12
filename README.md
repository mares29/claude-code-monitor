# Claude Code Monitor

A native macOS menu bar app for monitoring running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI instances in real time.

Built with Swift 6 and SwiftUI. Zero external dependencies.

<!--
<p align="center">
  <img src="docs/assets/demo.gif" alt="Claude Code Monitor demo" width="800">
</p>
-->

## Features

**Menu bar at a glance** — always-visible instance count (total/active) with one-click access to the main window.

**Live session feed** — stream every conversation turn as it happens: user messages, assistant responses, tool calls with expandable input/output, agent spawns, and token usage.

**Git diff view** — see staged and unstaged changes per session with inline diffs, insertion/deletion stats, and file-level expand.

**Instance grouping** — sessions organized by working directory with collapsible groups, activity sparklines, and model badges.

**Terminal detection** — walks the PPID chain to identify the parent terminal: iTerm2, Warp, Ghostty, Cursor, VS Code, Kitty, Alacritty, Hyper, Zed, WezTerm, Rio, tmux, and Terminal.app.

**Conflict detection** — warns when multiple instances read from or write to the same files (warning for mixed access, critical for concurrent writes).

**Safety flags** — surfaces `--dangerously-skip-permissions` and other CLI flags so you can spot YOLO-mode sessions instantly.

**Quick actions** — interrupt (SIGINT), terminate (SIGTERM), focus terminal window, open in Finder, copy paths and session IDs.

**Console panel** — filterable debug log viewer (DEBUG/INFO/ERROR) with search and auto-scroll.

## Keyboard Shortcuts

| Shortcut      | Action                           |
| ------------- | -------------------------------- |
| `Cmd+O`       | Open main window                 |
| `Cmd+1`–`9`   | Jump to instance by index        |
| `Cmd+.`       | Interrupt selected instance      |
| `Cmd+Shift+T` | Focus terminal                   |
| `Cmd+Shift+F` | Open working directory in Finder |
| `Cmd+Shift+C` | Copy working directory path      |

## Requirements

- macOS 14+
- Xcode 16+

## Build & Run

```bash
xcodebuild -scheme ClaudeMonitor -configuration Debug build
```

Or open in Xcode:

```bash
open ClaudeMonitor.xcodeproj
```

## How It Works

Claude Code Monitor uses a three-stage pipeline that runs on background actors:

1. **Process discovery** — polls `ps` every 2 seconds, walks the PPID chain (up to 10 levels) to find the parent terminal, and extracts the working directory via `lsof`.

2. **Session resolution** — locates the active session by checking `--resume` arguments, scanning debug log files, or falling back to the most recently modified JSONL in the project directory.

3. **Incremental parsing** — reads only new lines from session JSONL files using tracked file offsets, extracts conversation turns, tool calls, token usage, and agent spawns.

All data comes from Claude Code's local files:

```
~/.claude/projects/<encoded-path>/<sessionId>.jsonl   # conversation data
~/.claude/projects/<encoded-path>/sessions-index.json  # session index
~/.claude/debug/<sessionId>.txt                        # debug logs
```

Path encoding replaces `/` and `.` with `-`.

## Architecture

```
ClaudeMonitor/
├── Models/        # ClaudeInstance, MonitorState, SessionModels, GitDiffModels, Agent
├── Services/      # Actors: ProcessScanner, SessionParser, SessionFileWatcher,
│                  #   LogTailer, FileTracker, ActivityTracker, ConflictDetector,
│                  #   AgentScanner, GitDiffScanner, ToolOperationParser
├── Views/
│   ├── Menu/      # MenuBarContent (native NSMenu dropdown)
│   ├── Detail/    # SessionFeedView, DiffSummaryView, TimelineRow, ToolCallRow, AgentBlock
│   └── Console/   # ConsoleView (debug log viewer)
├── Components/    # InstanceRow, SparklineView, StatusDot, GroupHeaderLabel, TreeLine,
│                  #   SessionActionBar, InstanceContextMenu, DiffFileRow
└── Utilities/     # ProcessParser, LogParser, InstanceActions
```

| Layer        | Pattern                                                                         |
| ------------ | ------------------------------------------------------------------------------- |
| **State**    | `MonitorState` — `@Observable @MainActor` singleton with computed derived state |
| **Services** | Swift actors for thread-safe concurrent work                                    |
| **Parsing**  | Incremental JSONL with file position tracking; silent failure with defaults     |
| **UI**       | `NavigationSplitView` sidebar + tabbed detail (Session / Changes)               |

## License

[MIT](LICENSE)
