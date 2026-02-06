# ClaudeMonitor

macOS menu bar app monitoring Claude Code CLI instances. Swift 6 + SwiftUI.

## Build & Run

```bash
xcodebuild -scheme ClaudeMonitor -configuration Debug build   # build
open ClaudeMonitor.xcodeproj                                   # open in Xcode
```

No external dependencies. Requires Xcode 16+.

## Project Structure

```
ClaudeMonitor/
├── Models/      # Data types: ClaudeInstance, ConversationTurn, MonitorState
├── Services/    # Actors: ProcessScanner, FileTracker, ActivityTracker, SessionParser
├── Views/       # SwiftUI: MainView (NavigationSplitView), SessionFeedView, TurnCard
├── Components/  # Reusable: InstanceRow, SparklineView, StatusDot
├── Utilities/   # Parsers: ProcessParser, LogParser, ToolOperationParser
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
