# Activity Indicator Redesign

## Problem

Active vs inactive instances use filled vs hollow circle — too subtle to distinguish at a glance, especially at menu bar size (12pt). Color usage is also inconsistent across views (blue in sidebar, green in detail header, no color in menu bar).

## Solution: Waveform vs Dot (shape change + animation)

Active instances show an animated `waveform` SF Symbol (EQ bars cycling color). Idle instances show a static gray `circle`. Completely different shapes — unmistakable at any size.

## Visual States

| State   | Icon                          | Color  | Animation                            |
| ------- | ----------------------------- | ------ | ------------------------------------ |
| Active  | `waveform`                    | Blue   | `.variableColor.iterative.reversing` |
| Idle    | `circle`                      | Gray   | None                                 |
| Warning | `exclamationmark.circle.fill` | Yellow | None                                 |
| Error   | `xmark.circle.fill`           | Red    | None                                 |

## Component: StatusDot (single source of truth)

Refactored from Circle()-based drawing to SF Symbol-based rendering.

```swift
struct StatusDot: View {
    let state: StatusDotState  // .idle, .active, .warning, .error
    let size: CGFloat           // 10pt sidebar, 12pt menu bar

    var body: some View {
        Image(systemName: state.iconName)
            .font(.system(size: size))
            .foregroundStyle(state.color)
            .symbolEffect(.variableColor.iterative.reversing, isActive: state == .active)
    }
}
```

## Files Changed

| File                                 | Change                                         |
| ------------------------------------ | ---------------------------------------------- |
| `Components/StatusDot.swift`         | Rewrite: SF Symbol with variableColor effect   |
| `Components/InstanceRow.swift`       | Use `StatusDot`, remove inline icon logic      |
| `Views/Detail/SessionFeedView.swift` | Use `StatusDot` in header                      |
| `ClaudeMonitorApp.swift`             | Menu bar uses `waveform` + variableColor       |
| `Views/Menu/MenuBarContent.swift`    | Instance labels use `waveform` + variableColor |

## Not Changing

- `ClaudeInstance.isActive` logic (CPU > 5% threshold) — unchanged
- `MenuBarStatus` enum — unchanged (still unused, separate concern)
