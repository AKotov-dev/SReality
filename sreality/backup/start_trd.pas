unit start_trd;

{$mode objfpc}{$H+}

interface

uses
  Classes, Process, SysUtils;

type
  ShowLogTRD = class(TThread)

  protected
    Result: TStringList;

    procedure Execute; override;
    procedure ShowLog;
    procedure StartTrd;
  end;

implementation

uses Unit1;

function StripANSI(const S: string): string;
var
  i: integer;
  InEscape: boolean;
begin
  Result := '';
  InEscape := False;

  for i := 1 to Length(S) do
  begin
    if S[i] = #27 then
      InEscape := True
    else if InEscape and (S[i] in ['m', 'K']) then
      InEscape := False
    else if not InEscape then
      Result := Result + S[i];
  end;
end;

procedure ShowLogTRD.Execute;
var
  ExProcess: TProcess;
  Buffer: array[0..255] of byte;
  ReadCnt: longint;
  S, Line: string;
  P: SizeInt;
begin
  FreeOnTerminate := True;

  Result := TStringList.Create;
  ExProcess := TProcess.Create(nil);

  try
    Synchronize(@StartTRD);

    ExProcess.Executable := 'journalctl';
    ExProcess.Parameters.Add('--user');
    ExProcess.Parameters.Add('-u');
    ExProcess.Parameters.Add('naive-xray');
    ExProcess.Parameters.Add('-f');
    ExProcess.Parameters.Add('-o');
    ExProcess.Parameters.Add('cat');

    ExProcess.Options := [poUsePipes, poStderrToOutPut];
    ExProcess.Execute;

    S := '';

    while not Terminated and ExProcess.Running do
    begin
      if ExProcess.Output.NumBytesAvailable > 0 then
      begin
        ReadCnt := ExProcess.Output.Read(Buffer, SizeOf(Buffer));
        if ReadCnt > 0 then
        begin
          SetString(Line, PChar(@Buffer[0]), ReadCnt);
          S := S + Line;

          while True do
          begin
            P := Pos(#10, S);
            if P = 0 then Break;

            Result.Add(Trim(StripANSI(Copy(S, 1, P - 1))));

            Delete(S, 1, P);
          end;

          Synchronize(@ShowLog);
        end;
      end
      else
        Sleep(10);
    end;

  finally
    if ExProcess.Running then
      ExProcess.Terminate(0);
    ExProcess.Free;
    Result.Free;
  end;
end;

{ UI }

procedure ShowLogTRD.StartTRD;
begin
  MainForm.LogMemo.Clear;
  MainForm.LogMemo.SelStart := Length(MainForm.LogMemo.Text);
  MainForm.LogMemo.SelLength := 0;
end;

procedure ShowLogTRD.ShowLog;
var
  i: integer;
begin
  for i := 0 to Result.Count - 1 do
    MainForm.LogMemo.Lines.Add(' ' + Result[i]);

  Result.Clear;

  // ограничиваем размер лога
  while MainForm.LogMemo.Lines.Count > 500 do
    MainForm.LogMemo.Lines.Delete(0);

  MainForm.LogMemo.SelStart := Length(MainForm.LogMemo.Text);
  MainForm.LogMemo.SelLength := 0;
end;

end.
