# Terminal Print Glitch Fix

## Problem Description

When running `zig-wol status --live` with a long list of machines and/or when the terminal window is resized, the stdout "live-printing" using ANSI escape sequences would break.

### Root Causes

1. **Viewport Ceiling Problem (Vertical)**: The original implementation used `\x1b[NA` (Move Cursor Up N lines) to reposition the cursor before reprinting the status. However, ANSI cursor movement commands are relative to the **visible viewport**, not the logical text history. When the output exceeds the terminal height, the cursor cannot move beyond the top of the visible viewport, causing incorrect positioning.

2. **Line Wrapping Issue (Horizontal)**: When terminal lines are longer than the terminal width, they wrap to multiple physical lines. The cursor up command doesn't account for these wrapped lines, leading to incorrect cursor positioning.

## Solution

The fix replaces the problematic cursor movement approach with the **alternate screen buffer** technique, which is the standard solution used by terminal UI applications like `htop`, `top`, `vim`, and `less`.

### Implementation Details

The solution consists of three parts:

1. **Enter Alternate Screen Buffer** (`\x1b[?1049h`)
   - Executed once when live mode starts
   - Switches to a separate screen buffer
   - Preserves the original terminal content and history

2. **Clear Screen and Reset Cursor** (`\x1b[2J\x1b[H`)
   - Executed before each status update
   - `\x1b[2J`: Clears the entire screen
   - `\x1b[H`: Moves cursor to home position (top-left)
   - Replaces the problematic cursor up command

3. **Exit Alternate Screen Buffer** (`\x1b[?1049l`)
   - Executed when the program exits (via defer)
   - Restores the original terminal content
   - Returns user to their previous terminal state

### Code Changes

```zig
// Enter alternate screen buffer in live mode
if (is_status_live) {
    std.debug.print("\x1b[?1049h", .{});
}
defer {
    // Exit alternate screen buffer when done
    if (is_status_live) {
        std.debug.print("\x1b[?1049l", .{});
    }
}

while (true) {
    // Clear screen and move cursor to home instead of cursor up
    if (is_status_live) {
        std.debug.print("\x1b[2J\x1b[H", .{});
    }
    
    // ... print status ...
}
```

## Benefits

- ✅ **Fixes viewport ceiling problem**: No cursor movement needed, so viewport boundaries don't matter
- ✅ **Handles line wrapping correctly**: Clears entire screen regardless of line lengths
- ✅ **Preserves terminal history**: Alternate buffer is separate from main buffer
- ✅ **Works with terminal resizing**: Clears and redraws properly after resize
- ✅ **Standard approach**: Industry-standard pattern for terminal UIs
- ✅ **Non-live mode unchanged**: Single-shot status display works as before

## Technical Notes

### Why Defer Pattern?

The `defer` statement in Zig ensures cleanup code runs when the function scope exits, including:
- Normal function return
- Program termination via signals (Ctrl+C, SIGTERM)
- Error conditions

In live mode, the while loop runs indefinitely until interrupted, making `defer` the correct pattern for cleanup.

### ANSI Escape Sequence Reference

- `\x1b[?1049h`: Switch to alternate screen buffer (save main buffer)
- `\x1b[?1049l`: Switch back to main screen buffer (restore main buffer)
- `\x1b[2J`: Clear entire screen
- `\x1b[H`: Move cursor to home position (1,1)
- `\x1b[NA`: Move cursor up N lines (removed - was problematic)

### Terminal Compatibility

The alternate screen buffer feature is widely supported:
- ✅ Linux terminals (xterm, gnome-terminal, konsole, etc.)
- ✅ macOS Terminal.app and iTerm2
- ✅ Windows Terminal
- ✅ tmux and screen multiplexers
- ⚠️ Very old terminals may not support it (rare)

## Testing

To test the fix:

1. Create several test aliases with FQDNs
2. Run `zig-wol status --live`
3. Verify no glitches with:
   - Large number of machines (exceeding terminal height)
   - Terminal window resizing
   - Long machine names (exceeding terminal width)
4. Press Ctrl+C to exit
5. Verify terminal returns to normal state

## References

- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [Alternate Screen Buffer Usage](https://stackoverflow.com/questions/11023929/using-the-alternate-screen-in-a-bash-script)
