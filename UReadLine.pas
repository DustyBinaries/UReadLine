unit UReadLine;

{
  Minimal GNU-readline-like line editor for the Windows console (Delphi 7).

  Emacs-style key bindings (no .inputrc, bindings are fixed):

    Ctrl+A / Home          beginning of line
    Ctrl+E / End           end of line
    Ctrl+B / Left          back one character
    Ctrl+F / Right         forward one character
    Alt+B  / Ctrl+Left     back one word
    Alt+F  / Ctrl+Right    forward one word
    Ctrl+D / Del           delete character under cursor (Ctrl+D on empty line = EOF)
    Ctrl+H / Backspace     delete character before cursor
    Ctrl+K                 kill to end of line
    Ctrl+U                 kill to beginning of line
    Ctrl+W                 kill previous whitespace-delimited word
    Alt+D  / Ctrl+Del      kill next word
    Alt+Backspace / Ctrl+Backspace   kill previous word
    Ctrl+Y                 yank (paste) last killed text
    Ctrl+T                 transpose characters
    Alt+U / Alt+L / Alt+C  upcase / downcase / capitalize word
    Ctrl+P / Up            previous history entry
    Ctrl+N / Down          next history entry
    Ctrl+R / Ctrl+S        incremental search backward / forward in history:
                             type to refine, Ctrl+R/Ctrl+S again for the next
                             match (on an empty query: repeat the last search),
                             Backspace shortens the query, Enter accepts,
                             Esc / Ctrl+G cancels, any other key leaves search
                             and edits the found line
    Ctrl+L                 clear screen
    Tab / Ctrl+I           completion (see OnComplete); Tab twice lists matches
    Esc                    clear the whole line
    Ctrl+C                 abort line (ReadLine returns False, LastResult = rlrInterrupt)
    Ctrl+Z                 EOF on empty line (Windows habit)
    Enter / Ctrl+J / Ctrl+M  accept line

  Strings are handled as ANSI (the Delphi 7 "string"); console I/O goes
  through the wide API so accented characters display correctly.
  When stdin/stdout are not a console it falls back to plain Readln.
}

interface

uses
  Windows, SysUtils, Classes;

type
  TReadLineResult = (rlrOk, rlrEof, rlrInterrupt);

  TReadLineCommand = (rcNone, rcInsert, rcAccept, rcBeginLine, rcEndLine,
    rcBackChar, rcForwardChar, rcBackWord, rcForwardWord, rcDeleteChar,
    rcDeleteOrEof, rcEof, rcBackDeleteChar, rcKillLine, rcUnixLineDiscard,
    rcUnixWordRubout, rcKillWord, rcBackKillWord, rcKillWholeLine, rcYank,
    rcTranspose, rcUpcaseWord, rcDowncaseWord, rcCapitalizeWord,
    rcPrevHistory, rcNextHistory, rcClearScreen, rcComplete, rcInterrupt,
    rcReverseSearch, rcForwardSearch, rcAbort);

  { Fill Matches with candidates that complete Word (the text between the
    previous word break character and the cursor). }
  TReadLineCompleteEvent = procedure(Sender: TObject; const Word: string;
    Matches: TStrings) of object;

  TReadLine = class
  private
    FHistory: TStringList;
    FHistoryMax: Integer;
    FAutoAddHistory: Boolean;
    FOnComplete: TReadLineCompleteEvent;
    FWordBreakChars: string;
    FLastResult: TReadLineResult;
    { per-call editing state }
    FIn, FOut: THandle;
    FPrompt: string;
    FLine: string;
    FPos: Integer;          { cursor, 0-based: between FLine[FPos] and FLine[FPos+1] }
    FOrgX, FOrgY: Integer;  { screen cell where the prompt starts }
    FDrawn: string;         { prompt + line as currently painted on screen }
    FDirty: Boolean;        { FLine/FPos changed since the last Redraw }
    FKillBuf: string;
    FHistIdx: Integer;
    FSavedLine: string;     { line being typed before history browsing started }
    FLastCmd: TReadLineCommand;
    FDone: Boolean;
    { incremental history search (Ctrl+R / Ctrl+S) }
    FSearching: Boolean;
    FSearchDir: Integer;    { -1 = reverse (older), 1 = forward (newer) }
    FSearchQuery: string;
    FSearchIdx: Integer;    { history index of the current match }
    FSearchFailed: Boolean;
    FSearchSaved: string;   { line and cursor to restore on cancel }
    FSearchSavedPos: Integer;
    FLastSearch: string;
    function ReadPlain(const Prompt: string; var Line: string): Boolean;
    procedure HandleEvent(const Rec: TInputRecord);
    function InputPending: Boolean;
    function MapKey(const K: TKeyEventRecord; var Text: string): TReadLineCommand;
    procedure RunCommand(Cmd: TReadLineCommand; const Text: string);
    procedure Execute(Cmd: TReadLineCommand; const Text: string);
    procedure Finish(R: TReadLineResult; const Echo: string);
    procedure WriteText(const S: string);
    procedure SaveOrigin;
    procedure SetCursor(X, Y: Integer);
    procedure MoveTo(Off: Integer);
    procedure Redraw;
    function IsWordChar(C: Char): Boolean;
    function PrevWordStart(P: Integer): Integer;
    function NextWordEnd(P: Integer): Integer;
    procedure KillText(A, B: Integer; Prepend: Boolean);
    procedure ChangeCase(Cmd: TReadLineCommand);
    procedure SetLine(const S: string);
    procedure HistoryMove(Delta: Integer);
    procedure ClearScreen;
    procedure Complete;
    procedure ShowMatches(Matches: TStrings);
    procedure SetHistoryMax(Value: Integer);
    function CurrentPrompt: string;
    procedure StartSearch(Dir: Integer);
    procedure SearchCommand(Cmd: TReadLineCommand; const Text: string);
    procedure SearchHistory(Next: Boolean);
    procedure EndSearch;
  public
    constructor Create;
    destructor Destroy; override;
    { Shows Prompt and edits a line. Returns False on EOF or Ctrl+C
      (check LastResult to tell them apart). }
    function ReadLine(const Prompt: string; var Line: string): Boolean;
    procedure AddHistory(const S: string);
    property History: TStringList read FHistory;
    property HistoryMax: Integer read FHistoryMax write SetHistoryMax;
    property AutoAddHistory: Boolean read FAutoAddHistory write FAutoAddHistory;
    property LastResult: TReadLineResult read FLastResult;
    property OnComplete: TReadLineCompleteEvent read FOnComplete write FOnComplete;
    { characters that delimit the word handed to OnComplete (default: space) }
    property WordBreakChars: string read FWordBreakChars write FWordBreakChars;
  end;

{ Convenience wrappers around a shared default instance. }
function ReadLine(const Prompt: string; var Line: string): Boolean;
procedure AddHistory(const S: string);
function DefaultReadLine: TReadLine;

implementation

const
  ENABLE_VIRTUAL_TERMINAL_INPUT = $0200;
  KillCommands = [rcKillLine, rcUnixLineDiscard, rcUnixWordRubout, rcKillWord,
    rcBackKillWord, rcKillWholeLine];

var
  GReadLine: TReadLine = nil;

function DefaultReadLine: TReadLine;
begin
  if GReadLine = nil then
    GReadLine := TReadLine.Create;
  Result := GReadLine;
end;

function ReadLine(const Prompt: string; var Line: string): Boolean;
begin
  Result := DefaultReadLine.ReadLine(Prompt, Line);
end;

procedure AddHistory(const S: string);
begin
  DefaultReadLine.AddHistory(S);
end;

{ TReadLine }

constructor TReadLine.Create;
begin
  inherited Create;
  FHistory := TStringList.Create;
  FHistoryMax := 500;
  FAutoAddHistory := True;
  FWordBreakChars := ' ';
end;

destructor TReadLine.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

procedure TReadLine.SetHistoryMax(Value: Integer);
begin
  FHistoryMax := Value;
  while (FHistoryMax >= 0) and (FHistory.Count > FHistoryMax) do
    FHistory.Delete(0);
end;

procedure TReadLine.AddHistory(const S: string);
begin
  if Trim(S) = '' then
    Exit;
  if (FHistory.Count > 0) and (FHistory[FHistory.Count - 1] = S) then
    Exit;
  FHistory.Add(S);
  SetHistoryMax(FHistoryMax);
end;

function TReadLine.ReadPlain(const Prompt: string; var Line: string): Boolean;
begin
  Write(Prompt);
  Result := not Eof(Input);
  if Result then
  begin
    Readln(Line);
    FLastResult := rlrOk;
    if FAutoAddHistory then
      AddHistory(Line);
  end
  else
  begin
    Line := '';
    FLastResult := rlrEof;
  end;
end;

function TReadLine.ReadLine(const Prompt: string; var Line: string): Boolean;
var
  OldMode, N: DWORD;
  Info: TConsoleScreenBufferInfo;
  Rec: TInputRecord;
  I: Integer;
begin
  FIn := GetStdHandle(STD_INPUT_HANDLE);
  FOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if not GetConsoleMode(FIn, OldMode) or
     not GetConsoleScreenBufferInfo(FOut, Info) then
  begin
    Result := ReadPlain(Prompt, Line);
    Exit;
  end;

  { make sure anything written with Write() is on screen before we start }
  if TTextRec(Output).Mode = fmOutput then
    Flush(Output);

  { raw keys: no line buffering, no echo, Ctrl+C delivered as a key }
  SetConsoleMode(FIn, OldMode and not (ENABLE_PROCESSED_INPUT or
    ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT or ENABLE_WINDOW_INPUT or
    ENABLE_MOUSE_INPUT or ENABLE_VIRTUAL_TERMINAL_INPUT));
  try
    { only the prompt's last line is redrawn; print anything before it once }
    I := LastDelimiter(#10, Prompt);
    WriteText(Copy(Prompt, 1, I));
    FPrompt := Copy(Prompt, I + 1, MaxInt);
    FLine := '';
    FPos := 0;
    FDrawn := '';
    FDirty := False;
    FHistIdx := FHistory.Count;
    FSavedLine := '';
    FLastCmd := rcNone;
    FLastResult := rlrOk;
    FDone := False;
    FSearching := False;

    SaveOrigin;
    Redraw;

    repeat
      if not ReadConsoleInputW(FIn, Rec, 1, N) then
      begin
        Finish(rlrEof, '');
        Break;
      end;
      if N > 0 then
        HandleEvent(Rec);
      { while keys are still queued (fast typing, paste) defer the repaint }
      if FDirty and not FDone and not InputPending then
        Redraw;
    until FDone;
  finally
    SetConsoleMode(FIn, OldMode);
  end;

  Result := FLastResult = rlrOk;
  if Result then
  begin
    Line := FLine;
    if FAutoAddHistory then
      AddHistory(Line);
  end
  else
    Line := '';
end;

procedure TReadLine.HandleEvent(const Rec: TInputRecord);
var
  Cmd: TReadLineCommand;
  Text: string;
  I: Integer;
begin
  if Rec.EventType <> KEY_EVENT then
    Exit;

  with Rec.Event.KeyEvent do
    if not bKeyDown then
    begin
      { Alt+numpad codes deliver their character on Alt release }
      if (wVirtualKeyCode = VK_MENU) and (Ord(UnicodeChar) >= 32) then
        RunCommand(rcInsert, WideCharLenToString(@UnicodeChar, 1));
      Exit;
    end;

  Cmd := MapKey(Rec.Event.KeyEvent, Text);
  if Cmd = rcNone then
    Exit;
  for I := 1 to Rec.Event.KeyEvent.wRepeatCount do
  begin
    RunCommand(Cmd, Text);
    if FDone then
      Break;
  end;
end;

function TReadLine.InputPending: Boolean;
var
  N: DWORD;
begin
  Result := GetNumberOfConsoleInputEvents(FIn, N) and (N > 0);
end;

procedure TReadLine.RunCommand(Cmd: TReadLineCommand; const Text: string);
begin
  if FSearching then
    SearchCommand(Cmd, Text)
  else
    Execute(Cmd, Text);
  FLastCmd := Cmd;
  FDirty := True;
end;

function TReadLine.MapKey(const K: TKeyEventRecord; var Text: string): TReadLineCommand;
var
  Ctrl, Alt: Boolean;
  Ch: WideChar;
begin
  Result := rcNone;
  Text := '';
  Ch := K.UnicodeChar;
  Ctrl := K.dwControlKeyState and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED) <> 0;
  Alt := K.dwControlKeyState and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED) <> 0;
  { AltGr arrives as Ctrl+Alt; when it produced a character it is plain text }
  if Ctrl and Alt and (Ord(Ch) >= 32) then
  begin
    Ctrl := False;
    Alt := False;
  end;

  case K.wVirtualKeyCode of
    VK_RETURN: Result := rcAccept;
    VK_TAB:    Result := rcComplete;
    VK_ESCAPE: Result := rcKillWholeLine;
    VK_HOME:   Result := rcBeginLine;
    VK_END:    Result := rcEndLine;
    VK_UP:     Result := rcPrevHistory;
    VK_DOWN:   Result := rcNextHistory;
    VK_LEFT:
      if Ctrl then Result := rcBackWord else Result := rcBackChar;
    VK_RIGHT:
      if Ctrl then Result := rcForwardWord else Result := rcForwardChar;
    VK_BACK:
      if Ctrl or Alt then Result := rcBackKillWord else Result := rcBackDeleteChar;
    VK_DELETE:
      if Ctrl or Alt then Result := rcKillWord else Result := rcDeleteChar;
  end;
  if Result <> rcNone then
    Exit;

  if Ctrl and not Alt then
    case K.wVirtualKeyCode of
      Ord('A'): Result := rcBeginLine;
      Ord('B'): Result := rcBackChar;
      Ord('C'): Result := rcInterrupt;
      Ord('D'): Result := rcDeleteOrEof;
      Ord('E'): Result := rcEndLine;
      Ord('F'): Result := rcForwardChar;
      Ord('G'): Result := rcAbort;
      Ord('H'): Result := rcBackDeleteChar;
      Ord('I'): Result := rcComplete;
      Ord('J'), Ord('M'): Result := rcAccept;
      Ord('K'): Result := rcKillLine;
      Ord('L'): Result := rcClearScreen;
      Ord('N'): Result := rcNextHistory;
      Ord('P'): Result := rcPrevHistory;
      Ord('R'): Result := rcReverseSearch;
      Ord('S'): Result := rcForwardSearch;
      Ord('T'): Result := rcTranspose;
      Ord('U'): Result := rcUnixLineDiscard;
      Ord('W'): Result := rcUnixWordRubout;
      Ord('Y'): Result := rcYank;
      Ord('Z'): Result := rcEof;
    end
  else if Alt and not Ctrl then
    case K.wVirtualKeyCode of
      Ord('B'): Result := rcBackWord;
      Ord('C'): Result := rcCapitalizeWord;
      Ord('D'): Result := rcKillWord;
      Ord('F'): Result := rcForwardWord;
      Ord('L'): Result := rcDowncaseWord;
      Ord('U'): Result := rcUpcaseWord;
    end
  else if Ord(Ch) >= 32 then
  begin
    Text := WideCharLenToString(@Ch, 1);
    Result := rcInsert;
  end;
end;

procedure TReadLine.Execute(Cmd: TReadLineCommand; const Text: string);
var
  Len, P: Integer;
  C: Char;
begin
  Len := Length(FLine);
  case Cmd of
    rcInsert:
      begin
        Insert(Text, FLine, FPos + 1);
        Inc(FPos, Length(Text));
      end;
    rcAccept:      Finish(rlrOk, '');
    rcInterrupt:   Finish(rlrInterrupt, '^C');
    rcBeginLine:   FPos := 0;
    rcEndLine:     FPos := Len;
    rcBackChar:    if FPos > 0 then Dec(FPos);
    rcForwardChar: if FPos < Len then Inc(FPos);
    rcBackWord:    FPos := PrevWordStart(FPos);
    rcForwardWord: FPos := NextWordEnd(FPos);
    rcDeleteChar:  if FPos < Len then Delete(FLine, FPos + 1, 1);
    rcDeleteOrEof:
      if Len = 0 then
        Finish(rlrEof, '')
      else if FPos < Len then
        Delete(FLine, FPos + 1, 1);
    rcEof:
      if Len = 0 then
        Finish(rlrEof, '');
    rcBackDeleteChar:
      if FPos > 0 then
      begin
        Delete(FLine, FPos, 1);
        Dec(FPos);
      end;
    rcKillLine:        KillText(FPos, Len, False);
    rcUnixLineDiscard: KillText(0, FPos, True);
    rcUnixWordRubout:
      begin
        P := FPos;
        while (P > 0) and (FLine[P] = ' ') do
          Dec(P);
        while (P > 0) and (FLine[P] <> ' ') do
          Dec(P);
        KillText(P, FPos, True);
      end;
    rcKillWord:      KillText(FPos, NextWordEnd(FPos), False);
    rcBackKillWord:  KillText(PrevWordStart(FPos), FPos, True);
    rcKillWholeLine: KillText(0, Len, False);
    rcYank:
      if FKillBuf <> '' then
      begin
        Insert(FKillBuf, FLine, FPos + 1);
        Inc(FPos, Length(FKillBuf));
      end;
    rcTranspose:
      if (Len >= 2) and (FPos > 0) then
      begin
        if FPos = Len then
          Dec(FPos);
        C := FLine[FPos];
        FLine[FPos] := FLine[FPos + 1];
        FLine[FPos + 1] := C;
        Inc(FPos);
      end;
    rcUpcaseWord, rcDowncaseWord, rcCapitalizeWord: ChangeCase(Cmd);
    rcPrevHistory: HistoryMove(-1);
    rcNextHistory: HistoryMove(1);
    rcClearScreen: ClearScreen;
    rcComplete:    Complete;
    rcReverseSearch: StartSearch(-1);
    rcForwardSearch: StartSearch(1);
  end;
end;

procedure TReadLine.Finish(R: TReadLineResult; const Echo: string);
begin
  FPos := Length(FLine);
  Redraw;
  WriteText(Echo + #13#10);
  FLastResult := R;
  FDone := True;
end;

{ --- screen handling --- }

procedure TReadLine.WriteText(const S: string);
var
  W: WideString;
  N: DWORD;
begin
  if S = '' then
    Exit;
  W := S;
  WriteConsoleW(FOut, PWideChar(W), Length(W), N, nil);
end;

procedure TReadLine.SaveOrigin;
var
  Info: TConsoleScreenBufferInfo;
begin
  GetConsoleScreenBufferInfo(FOut, Info);
  FOrgX := Info.dwCursorPosition.X;
  FOrgY := Info.dwCursorPosition.Y;
end;

procedure TReadLine.SetCursor(X, Y: Integer);
var
  C: TCoord;
begin
  C.X := X;
  C.Y := Y;
  SetConsoleCursorPosition(FOut, C);
end;

{ Puts the cursor Off cells after the start of the origin row, touching the
  console only when it is not already there. }
procedure TReadLine.MoveTo(Off: Integer);
var
  Info: TConsoleScreenBufferInfo;
  X, Y: Integer;
begin
  GetConsoleScreenBufferInfo(FOut, Info);
  X := Off mod Info.dwSize.X;
  Y := FOrgY + Off div Info.dwSize.X;
  if (Info.dwCursorPosition.X <> X) or (Info.dwCursorPosition.Y <> Y) then
    SetCursor(X, Y);
end;

procedure TReadLine.Redraw;
var
  Info: TConsoleScreenBufferInfo;
  Prompt, Display, S: string;
  Same, Pad: Integer;
begin
  Prompt := CurrentPrompt;
  Display := Prompt + FLine;

  { repaint only from the first changed character, so typing at the end of
    the line never sends the cursor back to the line start }
  Same := 0;
  while (Same < Length(Display)) and (Same < Length(FDrawn)) and
        (Display[Same + 1] = FDrawn[Same + 1]) do
    Inc(Same);
  Pad := Length(FDrawn) - Length(Display);
  if Pad < 0 then
    Pad := 0;
  S := Copy(Display, Same + 1, MaxInt) + StringOfChar(' ', Pad);

  if S <> '' then
  begin
    MoveTo(FOrgX + Same);
    WriteText(S);
    { writing past the bottom scrolls the buffer, so recompute the origin
      row from where the cursor ended up (the console wraps eagerly) }
    GetConsoleScreenBufferInfo(FOut, Info);
    FOrgY := Info.dwCursorPosition.Y - (FOrgX + Same + Length(S)) div Info.dwSize.X;
  end;
  FDrawn := Display;
  FDirty := False;

  MoveTo(FOrgX + Length(Prompt) + FPos);
end;

procedure TReadLine.ClearScreen;
var
  Info: TConsoleScreenBufferInfo;
  Top: TCoord;
  Count, N: DWORD;
begin
  GetConsoleScreenBufferInfo(FOut, Info);
  Top.X := 0;
  Top.Y := Info.srWindow.Top;
  Count := (Info.dwSize.Y - Top.Y) * Info.dwSize.X;
  FillConsoleOutputCharacter(FOut, ' ', Count, Top, N);
  FillConsoleOutputAttribute(FOut, Info.wAttributes, Count, Top, N);
  SetConsoleCursorPosition(FOut, Top);
  SaveOrigin;
  FDrawn := '';
end;

{ --- editing helpers --- }

function TReadLine.IsWordChar(C: Char): Boolean;
begin
  Result := IsCharAlphaNumeric(C);
end;

function TReadLine.PrevWordStart(P: Integer): Integer;
begin
  while (P > 0) and not IsWordChar(FLine[P]) do
    Dec(P);
  while (P > 0) and IsWordChar(FLine[P]) do
    Dec(P);
  Result := P;
end;

function TReadLine.NextWordEnd(P: Integer): Integer;
var
  Len: Integer;
begin
  Len := Length(FLine);
  while (P < Len) and not IsWordChar(FLine[P + 1]) do
    Inc(P);
  while (P < Len) and IsWordChar(FLine[P + 1]) do
    Inc(P);
  Result := P;
end;

{ Removes FLine[A+1..B] (the 0-based range [A, B)) into the kill buffer.
  Consecutive kills accumulate, like readline. }
procedure TReadLine.KillText(A, B: Integer; Prepend: Boolean);
var
  S: string;
begin
  if B <= A then
    Exit;
  S := Copy(FLine, A + 1, B - A);
  if FLastCmd in KillCommands then
  begin
    if Prepend then
      FKillBuf := S + FKillBuf
    else
      FKillBuf := FKillBuf + S;
  end
  else
    FKillBuf := S;
  Delete(FLine, A + 1, B - A);
  FPos := A;
end;

procedure TReadLine.ChangeCase(Cmd: TReadLineCommand);
var
  E, I: Integer;
  S: string;
begin
  E := NextWordEnd(FPos);
  S := Copy(FLine, FPos + 1, E - FPos);
  case Cmd of
    rcUpcaseWord:   S := AnsiUpperCase(S);
    rcDowncaseWord: S := AnsiLowerCase(S);
    rcCapitalizeWord:
      begin
        S := AnsiLowerCase(S);
        for I := 1 to Length(S) do
          if IsWordChar(S[I]) then
          begin
            S[I] := AnsiUpperCase(S[I])[1];
            Break;
          end;
      end;
  end;
  FLine := Copy(FLine, 1, FPos) + S + Copy(FLine, E + 1, MaxInt);
  FPos := E;
end;

procedure TReadLine.SetLine(const S: string);
begin
  FLine := S;
  FPos := Length(S);
end;

procedure TReadLine.HistoryMove(Delta: Integer);
var
  NewIdx: Integer;
begin
  NewIdx := FHistIdx + Delta;
  if (NewIdx < 0) or (NewIdx > FHistory.Count) then
    Exit;
  if FHistIdx = FHistory.Count then
    FSavedLine := FLine;
  FHistIdx := NewIdx;
  if FHistIdx = FHistory.Count then
    SetLine(FSavedLine)
  else
    SetLine(FHistory[FHistIdx]);
end;

{ --- completion --- }

procedure TReadLine.Complete;
var
  Start, I, J: Integer;
  Word, Prefix: string;
  Matches: TStringList;

  procedure ReplaceWord(const S: string);
  begin
    Delete(FLine, Start + 1, FPos - Start);
    Insert(S, FLine, Start + 1);
    FPos := Start + Length(S);
  end;

begin
  if not Assigned(FOnComplete) then
    Exit;
  Start := FPos;
  while (Start > 0) and (Pos(FLine[Start], FWordBreakChars) = 0) do
    Dec(Start);
  Word := Copy(FLine, Start + 1, FPos - Start);

  Matches := TStringList.Create;
  try
    FOnComplete(Self, Word, Matches);
    if Matches.Count = 0 then
      Exit;
    if Matches.Count = 1 then
    begin
      ReplaceWord(Matches[0] + ' ');
      Exit;
    end;

    { longest common prefix of all matches }
    Prefix := Matches[0];
    for I := 1 to Matches.Count - 1 do
    begin
      J := 0;
      while (J < Length(Prefix)) and (J < Length(Matches[I])) and
            (Prefix[J + 1] = Matches[I][J + 1]) do
        Inc(J);
      SetLength(Prefix, J);
    end;

    if Length(Prefix) > Length(Word) then
      ReplaceWord(Prefix)
    else if FLastCmd = rcComplete then
      ShowMatches(Matches);
  finally
    Matches.Free;
  end;
end;

procedure TReadLine.ShowMatches(Matches: TStrings);
var
  Info: TConsoleScreenBufferInfo;
  I, ColW, Cols: Integer;
  S: string;
begin
  GetConsoleScreenBufferInfo(FOut, Info);
  ColW := 0;
  for I := 0 to Matches.Count - 1 do
    if Length(Matches[I]) > ColW then
      ColW := Length(Matches[I]);
  Inc(ColW, 2);
  Cols := (Info.dwSize.X - 1) div ColW;
  if Cols < 1 then
    Cols := 1;

  { leave the cursor after the line, list matches, then repaint below }
  I := FPos;
  FPos := Length(FLine);
  Redraw;
  FPos := I;
  WriteText(#13#10);
  S := '';
  for I := 0 to Matches.Count - 1 do
  begin
    S := S + Matches[I] + StringOfChar(' ', ColW - Length(Matches[I]));
    if ((I + 1) mod Cols = 0) or (I = Matches.Count - 1) then
    begin
      WriteText(TrimRight(S) + #13#10);
      S := '';
    end;
  end;
  SaveOrigin;
  FDrawn := '';
end;

{ --- incremental history search --- }

function TReadLine.CurrentPrompt: string;
begin
  if not FSearching then
  begin
    Result := FPrompt;
    Exit;
  end;
  Result := '(';
  if FSearchFailed then
    Result := Result + 'failed ';
  if FSearchDir < 0 then
    Result := Result + 'reverse-';
  Result := Result + 'i-search)`' + FSearchQuery + ''': ';
end;

procedure TReadLine.StartSearch(Dir: Integer);
begin
  FSearching := True;
  FSearchDir := Dir;
  FSearchQuery := '';
  FSearchIdx := FHistIdx;
  FSearchFailed := False;
  FSearchSaved := FLine;
  FSearchSavedPos := FPos;
end;

procedure TReadLine.SearchCommand(Cmd: TReadLineCommand; const Text: string);
begin
  case Cmd of
    rcInsert:
      begin
        FSearchQuery := FSearchQuery + Text;
        SearchHistory(False);
      end;
    rcBackDeleteChar:
      if FSearchQuery <> '' then
      begin
        Delete(FSearchQuery, Length(FSearchQuery), 1);
        SearchHistory(False);
      end;
    rcReverseSearch, rcForwardSearch:
      begin
        if Cmd = rcReverseSearch then
          FSearchDir := -1
        else
          FSearchDir := 1;
        if FSearchQuery = '' then
          FSearchQuery := FLastSearch;
        SearchHistory(True);
      end;
    rcAbort, rcKillWholeLine:
      begin
        FSearching := False;
        FLine := FSearchSaved;
        FPos := FSearchSavedPos;
      end;
  else
    { any other key keeps the found line and is then handled normally }
    EndSearch;
    Execute(Cmd, Text);
  end;
end;

{ Finds the query in the history, starting at the current match (Next =
  False, used while the query is being typed) or past it (Next = True).
  On failure the last match stays on screen, like readline. }
procedure TReadLine.SearchHistory(Next: Boolean);
var
  I, P: Integer;
begin
  FSearchFailed := False;
  if FSearchQuery = '' then
    Exit;
  FLastSearch := FSearchQuery;

  I := FSearchIdx;
  if Next or (I >= FHistory.Count) then
    Inc(I, FSearchDir);
  FSearchFailed := True;
  while (I >= 0) and (I < FHistory.Count) do
  begin
    P := Pos(FSearchQuery, FHistory[I]);
    { when stepping to the next match skip duplicates of the shown line }
    if (P > 0) and not (Next and (FHistory[I] = FLine)) then
    begin
      FSearchIdx := I;
      FLine := FHistory[I];
      FPos := P - 1;
      FSearchFailed := False;
      Break;
    end;
    Inc(I, FSearchDir);
  end;
end;

procedure TReadLine.EndSearch;
begin
  FSearching := False;
  { Up/Down continue from the entry that was found }
  if FSearchIdx < FHistory.Count then
  begin
    if FHistIdx = FHistory.Count then
      FSavedLine := FSearchSaved;
    FHistIdx := FSearchIdx;
  end;
end;

initialization

finalization
  FreeAndNil(GReadLine);

end.
