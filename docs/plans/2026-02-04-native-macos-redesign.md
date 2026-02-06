# Claude Monitor - Native macOS Redesign

## Overview

Redesign the app to follow Apple HIG closely, resembling a native system utility like Activity Monitor. Remove custom theming in favor of system colors and controls.

## User Context

- **Usage patterns**: Quick glances (menu bar), active monitoring (main window), troubleshooting (logs)
- **Concurrent instances**: 4+ typically
- **Priority information**: Instance status, activity feed

## Layout

Standard macOS `NavigationSplitView`:

```
┌─────────────────────────────────────────────────────────┐
│ Toolbar                                                 │
├────────────┬────────────────────────────────────────────┤
│ Sidebar    │ Detail (Activity Feed)                     │
│            │                                            │
│            ├────────────────────────────────────────────┤
│            │ Console (collapsible)                      │
└────────────┴────────────────────────────────────────────┘
```

## Sidebar

Native `List` with `.sidebar` style.

**Each row:**

- Status indicator: `●` active, `○` idle, `⚠` error
- Project name (last path component of working directory)
- Mini sparkline (8 chars, last 20s of activity)

**Removed:**

- PID numbers
- Session ID suffixes
- Task/agent counts
- Uptime

## Detail View (Activity Feed)

**Header:**

- Project name + full path
- Status line: "Running · 3 agents · 2 tasks in progress"

**Feed:**

- Reverse chronological list of tool operations
- Each row: timestamp, icon, verb, file path (or command)
- Line numbers for Edit operations
- Time separators every minute
- Click row for full details (expandable or sheet)

**Tool icons:**
| Tool | Icon | Verb |
|------|------|------|
| Read | 📖 | Read |
| Edit | ✏️ | Edit |
| Write | 📝 | Write |
| Bash | ▶️ | Bash |
| Grep | 🔍 | Grep |
| Glob | 📁 | Glob |
| Task | 🤖 | Agent |

## Console

Collapsible bottom panel.

**Header bar:**

- Chevron (expand/collapse)
- "Console" label
- Entry count badge
- Filter dropdown: All / Debug / Info / Error
- Clear button

**Behavior:**

- Collapsed by default
- Auto-expands briefly on error
- Remembers state per session

**Rows:**

- Timestamp | Level | Message
- Error rows have subtle red background

## Menu Bar Dropdown

Mirrors sidebar for quick status check.

```
┌────────────────────────────────┐
│ Claude Monitor             ●   │
├────────────────────────────────┤
│ ● cm-swift        ▪▪▪▫▫▪▪     │
│ ○ api-svc         ▫▫▫▫▫▫▫     │
│ ● website         ▪▪▫▫▪▪▪     │
├────────────────────────────────┤
│ Open Monitor            ⌘O    │
│ Quit                    ⌘Q    │
└────────────────────────────────┘
```

**Click instance** → opens main window with that instance selected.

**Menu bar icon:**

- `circle.fill` - any instance active (blue)
- `circle` - all idle (gray)
- `exclamationmark.circle.fill` - recent error (yellow)

## Technical Changes

### Remove

- `Theme.swift` - custom colors
- `CardView.swift` - custom card styling
- `MetricCard.swift` - metric display component
- Custom fonts (cmTitle, cmBody, etc.)
- Custom spacing constants
- Custom radius constants

### Update

- `MainView.swift` - new NavigationSplitView layout
- `ConsoleView.swift` - simplified, collapsible
- `MenuBarContent.swift` - cleaner dropdown
- `InstanceCard.swift` → `InstanceRow.swift` - simpler list row

### Add

- `ActivityFeedView.swift` - new detail view
- `ActivityRow.swift` - single operation row

### Keep

- All models (ClaudeInstance, Agent, AgentTask, etc.)
- All services (ProcessScanner, LogTailer, etc.)
- SparklineView (but simplify)
- StatusDot (but use system colors)

## Color Palette

Use system semantic colors only:

```swift
// Backgrounds
Color(.windowBackgroundColor)
Color(.controlBackgroundColor)

// Text
Color.primary
Color.secondary

// Status
Color.blue   // active
Color.gray   // idle
Color.yellow // warning
Color.red    // error
```

## Success Criteria

1. App looks native - could pass as Apple-made utility
2. Scannable at a glance with 4+ instances
3. Activity feed shows what's happening in real-time
4. Console accessible but not in the way
5. Works well in both light and dark mode
