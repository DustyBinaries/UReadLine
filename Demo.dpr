program Demo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, UReadLine;

type
  TCompleter = class
    procedure Complete(Sender: TObject; const Word: string; Matches: TStrings);
  end;

const
  Commands: array[0..6] of string =
    ('help', 'history', 'hello', 'quit', 'exit', 'echo', 'clear');

procedure TCompleter.Complete(Sender: TObject; const Word: string; Matches: TStrings);
var
  I: Integer;
begin
  for I := Low(Commands) to High(Commands) do
    if Copy(Commands[I], 1, Length(Word)) = Word then
      Matches.Add(Commands[I]);
end;

var
  Completer: TCompleter;
  Line: string;
  I: Integer;
begin
  Completer := TCompleter.Create;
  try
    DefaultReadLine.OnComplete := Completer.Complete;
    Writeln('ReadLine demo. Try Ctrl+A, Ctrl+E, Alt+F, Alt+B, Ctrl+K, Ctrl+Y, Up/Down, Tab.');
    Writeln('Type "quit" or press Ctrl+D on an empty line to exit.');
    while True do
    begin
      if not ReadLine('demo> ', Line) then
      begin
        if DefaultReadLine.LastResult = rlrInterrupt then
          Continue;
        Break;
      end;
      Line := Trim(Line);
      if (Line = 'quit') or (Line = 'exit') then
        Break
      else if Line = 'history' then
        for I := 0 to DefaultReadLine.History.Count - 1 do
          Writeln(Format('%4d  %s', [I + 1, DefaultReadLine.History[I]]))
      else if Line <> '' then
        Writeln('You typed: [', Line, ']');
    end;
  finally
    Completer.Free;
  end;
end.
