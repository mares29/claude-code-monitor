# Claude Code Monitor

A native macOS menu bar app for monitoring running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI instances in real time.

Built with Swift 6 and SwiftUI. No external dependencies.

<p align="center">
  <img src="docs/assets/demo.gif" alt="Claude Code Monitor demo" width="800">
</p>

## Features

- **Menu bar presence** — see total/active instance count at a glance
- **Live session feed** — stream conversation turns, tool calls, and model responses as they happen
- **Instance grouping** — instances organized by working directory
- **Activity sparklines** — per-session activity visualization
- **Terminal detection** — identifies parent terminal (iTerm, Warp, Ghostty, Cursor, VS Code, etc.)
- **YOLO mode warnings** — flags instances running with `--dangerously-skip-permissions`
- **Token tracking** — input/output/cache token usage per session
- **Conflict detection** — warns when multiple instances touch the same files
- **Quick actions** — interrupt, kill, focus terminal, open in Finder/editor

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

Claude Code Monitor discovers running `claude` processes via `ps`, walks the PPID chain to identify the parent terminal app, and reads session data from Claude's local files:

- `~/.claude/projects/<encoded-path>/<sessionId>.jsonl` — session conversation data
- `~/.claude/projects/<encoded-path>/sessions-index.json` — session index
- `~/.claude/debug/<sessionId>.txt` — debug logs

All parsing is incremental (only new lines are read) and runs on background actors to keep the UI responsive.

## Architecture

```
ClaudeMonitor/
├── Models/      # ClaudeInstance, MonitorState, SessionModels
├── Services/    # ProcessScanner, FileTracker, ActivityTracker, SessionParser
├── Views/       # MainView, SessionFeedView, MenuBarContent
├── Components/  # InstanceRow, SparklineView, StatusDot
└── Utilities/   # ProcessParser, LogParser, ToolOperationParser
```

- **State**: `MonitorState` — `@Observable @MainActor` singleton
- **Services**: Swift actors for thread-safe background work
- **Parsing**: Incremental JSONL with file position tracking
- **UI**: `NavigationSplitView` with sidebar + detail

## License

MIT
