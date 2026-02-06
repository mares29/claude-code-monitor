# ClaudeMonitor

macOS menu bar app monitoring Claude Code CLI instances. Swift 6 + SwiftUI.

Entry point: `ClaudeMonitor/ClaudeMonitorApp.swift` (MenuBarExtra + Window scenes).

## Build & Run

```bash
xcodebuild -scheme ClaudeMonitor -configuration Debug build   # build
open ClaudeMonitor.xcodeproj                                   # open in Xcode
```

No external dependencies. Requires macOS 14+ and Xcode 16+.

## Project Structure

```
ClaudeMonitor/
├── Models/      # ClaudeInstance, MonitorState, SessionModels, ActivityModels, Agent
├── Services/    # Actors: ProcessScanner, LogTailer, AgentScanner, FileTracker,
│                #   ActivityTracker, ConflictDetector, SessionParser, SessionFileWatcher
├── Views/
│   ├── Menu/    # MenuBarContent (NSMenu dropdown)
│   ├── Detail/  # SessionFeedView, TurnCard, TimelineRow, AgentBlock
│   └── Console/ # ConsoleView (log viewer)
├── Components/  # InstanceRow, SparklineView, StatusDot, GroupHeaderLabel,
│                #   TreeLine, SessionActionBar, InstanceContextMenu
├── Utilities/   # ProcessParser, LogParser, InstanceActions
```

## Key Patterns

- **State**: `MonitorState` is @Observable @MainActor singleton
- **Concurrency**: Services are actors; use `await` and `MainActor.run` for UI updates
- **Parsing**: Incremental JSONL parsing with file position tracking
- **Terminal detection**: Walks PPID chain to find parent terminal app

## Claude File Paths

- Sessions: `~/.claude/projects/<encoded-path>/<sessionId>.jsonl`
- Index: `~/.claude/projects/<encoded-path>/sessions-index.json`
- Debug logs: `~/.claude/debug/<sessionId>.txt`
- Path encoding: `/` and `.` become `-`

## Conventions

- One type per file
- Actors for thread-safe services, structs for stateless parsers
- Computed properties for derived state (e.g., `displayName`, `filteredLogs`)
- Silent failure with defaults on parse errors

## Git Commits

```
feat(scope): description   # new feature
fix(scope): description    # bug fix
```

Scopes: menubar, parser, sort, feed, terminals, flags, tools, etc.

## Gotchas

- **NSMenu styling**: `.menuBarExtraStyle(.menu)` renders native NSMenu items. SwiftUI modifiers like `.foregroundStyle()` and `.opacity()` are ignored — use `AttributedString` with `.foregroundColor` instead.
- **ToolOperationParser**: Lives in Services/ despite being in Utilities/ conceptually — it's registered as a service in the app.
- **Silent parse failures**: All JSON decoding uses `try?` with fallback defaults. Never crashes on malformed JSONL.
