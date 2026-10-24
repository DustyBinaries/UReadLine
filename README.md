# UReadLine

A minimal GNU-readline-like line editor for the Windows console, written in Delphi 7 (Object Pascal). It has no dependencies beyond the RTL and the Windows API.

## Features

- Emacs-style editing with a kill buffer and yank
- Command history with up/down browsing and incremental search (Ctrl+R / Ctrl+S)
- Tab completion through a user-supplied event, with common-prefix insertion and a match list on a second Tab
- Handles lines that wrap past the console width and scrolling at the bottom of the buffer
- Console I/O goes through the wide API, so accented characters display correctly
- Falls back to plain `Readln` when stdin/stdout are not a console (pipes, redirection)

## Usage

Add `UReadLine.pas` to your project and use the shared default instance:

```pascal
uses UReadLine;

var
  Line: string;
begin
  while ReadLine('> ', Line) do
    Writeln('You typed: ', Line);
end.
```

`ReadLine` returns `False` on EOF or Ctrl+C. Check `LastResult` to tell them apart (`rlrOk`, `rlrEof`, `rlrInterrupt`).

You can also create your own instance with `TReadLine.Create`, for example to keep separate histories.

### Completion

Assign `OnComplete` and fill `Matches` with candidates for `Word`, the text between the previous word break character and the cursor:

```pascal
procedure TCompleter.Complete(Sender: TObject; const Word: string; Matches: TStrings);
begin
  if Copy('help', 1, Length(Word)) = Word then
    Matches.Add('help');
end;

DefaultReadLine.OnComplete := Completer.Complete;
```

A single match is inserted followed by a space. With several matches, the longest common prefix is inserted. Pressing Tab again lists them.

### API

| Member | Description |
| --- | --- |
| `ReadLine(Prompt, Line)` | Show the prompt and edit a line. Returns `False` on EOF or Ctrl+C. |
| `AddHistory(S)` | Add an entry. Blank lines and consecutive duplicates are ignored. |
| `History` | The history as a `TStringList`. |
| `HistoryMax` | Maximum number of history entries (default 500). |
| `AutoAddHistory` | Add accepted lines to the history automatically (default `True`). |
| `LastResult` | `rlrOk`, `rlrEof` or `rlrInterrupt` for the last call. |
| `OnComplete` | Completion callback. |
| `WordBreakChars` | Characters that delimit the word passed to `OnComplete` (default: space). |
| `DefaultReadLine` | The shared instance used by the global `ReadLine` and `AddHistory`. |

A multi-line prompt is supported. Only its last line is redrawn.

## Key bindings

The bindings are fixed. There is no `.inputrc` support.

| Keys | Action |
| --- | --- |
| Ctrl+A / Home | Beginning of line |
| Ctrl+E / End | End of line |
| Ctrl+B / Left | Back one character |
| Ctrl+F / Right | Forward one character |
| Alt+B / Ctrl+Left | Back one word |
| Alt+F / Ctrl+Right | Forward one word |
| Ctrl+D / Del | Delete character under cursor (Ctrl+D on an empty line = EOF) |
| Ctrl+H / Backspace | Delete character before cursor |
| Ctrl+K | Kill to end of line |
| Ctrl+U | Kill to beginning of line |
| Ctrl+W | Kill previous whitespace-delimited word |
| Alt+D / Ctrl+Del | Kill next word |
| Alt+Backspace / Ctrl+Backspace | Kill previous word |
| Ctrl+Y | Yank (paste) last killed text |
| Ctrl+T | Transpose characters |
| Alt+U / Alt+L / Alt+C | Upcase / downcase / capitalize word |
| Ctrl+P / Up | Previous history entry |
| Ctrl+N / Down | Next history entry |
| Ctrl+R / Ctrl+S | Incremental search backward / forward in history |
| Ctrl+L | Clear screen |
| Tab / Ctrl+I | Completion; Tab twice lists matches |
| Esc | Clear the whole line |
| Ctrl+C | Abort line (`ReadLine` returns `False`, `LastResult = rlrInterrupt`) |
| Ctrl+Z | EOF on empty line |
| Enter / Ctrl+J / Ctrl+M | Accept line |

Consecutive kill commands accumulate in the kill buffer, as in readline.

### Incremental search

Type to refine the query. Ctrl+R / Ctrl+S again jumps to the next match, and on an empty query repeats the last search. Backspace shortens the query. Enter accepts, and Esc or Ctrl+G cancels. Any other key leaves search mode and edits the found line.

## Notes

- Strings are ANSI (the Delphi 7 `string`).
- Windows only. It uses the Win32 console API directly.

## Demo

`Demo.dpr` is a small console program that shows history, completion and the key bindings. It completes a few command names, and `history` prints the history. Type `quit` or press Ctrl+D on an empty line to exit.

Build it with the Delphi 7 command-line compiler:

```
dcc32 Demo.dpr
```
