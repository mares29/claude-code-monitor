# Session Feed Design

Replace global activity log with parsed session JSONL in instance detail view.

## Decisions

- **Detail level**: Full activity feed (messages, tool calls, progress, tokens)
- **Grouping**: By turn (assistant message + its tool calls + results), newest at top
- **Text display**: Truncated ~3 lines, expandable
- **Token display**: Per-turn badge (↓in ↑out ⚡cached)
- **Tool calls**: Compact rows, expandable for full input/output
- **Agents**: Collapsed by default ("Agent: explore (12 turns)"), expandable
- **Updates**: File watcher via DispatchSource for real-time

## Data Models

```swift
struct ConversationTurn: Identifiable {
    let id: String
    let timestamp: Date
    let text: String?
    let toolCalls: [ToolCall]
    let tokenUsage: TokenUsage?
    let agentSpawns: [AgentSummary]
}

struct ToolCall: Identifiable {
    let id: String
    let name: String
    let input: ToolCallInput
    let result: ToolCallResult?
    let timestamp: Date
}

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
}

struct AgentSummary: Identifiable {
    let id: String
    let type: AgentType
    let turnCount: Int
    let status: AgentStatus
}
```

## Parsing Strategy

1. Read JSONL lines
2. Group by `parentUuid` chain
3. `type: "assistant"` entries = turn anchors
4. Attach `type: "user"` (tool_result) to parent turn
5. Detect agent spawns from Task tool calls
6. Parse agent JSONL lazily on expand

## View Hierarchy

```
SessionFeedView
├── SessionHeader (project name, status, uptime)
└── ScrollView > LazyVStack
    └── TurnCard (foreach turn)
        ├── TurnHeader (timestamp, token badge)
        ├── TurnTextView (truncated/expandable)
        ├── ToolCallRow (foreach tool, expandable)
        └── AgentBlock (foreach agent, expandable)
```

## Visual Layout

```
┌─────────────────────────────────────────────────────────┐
│ 14:32:05                        ↓1.2k ↑483 ⚡18k cached │
├─────────────────────────────────────────────────────────┤
│ I'll read the configuration file and update the        │
│ database connection settings...                        │
│ ▼ Show more                                            │
├─────────────────────────────────────────────────────────┤
│ 📄 Read    config/database.yml                         │
│ ✏️ Edit    config/database.yml                    ✓    │
│ ▶️ Bash    npm run migrate                        ✓    │
├─────────────────────────────────────────────────────────┤
│ 🤖 Agent: explore (8 turns)                       ▶    │
└─────────────────────────────────────────────────────────┘
```

## File Structure

**Create:**

- `Models/SessionModels.swift`
- `Services/SessionParser.swift`
- `Services/SessionFileWatcher.swift`
- `Views/Detail/SessionFeedView.swift`
- `Views/Detail/TurnCard.swift`
- `Views/Detail/ToolCallRow.swift`
- `Views/Detail/AgentBlock.swift`

**Remove:**

- `Services/ToolOperationParser.swift`
- `Views/Detail/ActivityFeedView.swift`
- `ToolOperation` from `ActivityModels.swift`

**Modify:**

- `MainView.swift` - use SessionFeedView
- `MonitorState.swift` - remove ToolOperation tracking

## Implementation Order

1. SessionModels.swift - data types
2. SessionParser.swift - JSONL parsing
3. SessionFileWatcher.swift - file monitoring
4. TurnCard.swift, ToolCallRow.swift, AgentBlock.swift - components
5. SessionFeedView.swift - main view
6. MainView integration + cleanup old files
