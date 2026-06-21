unit service_state_trd;

{$mode objfpc}{$H+}

interface

uses
  Classes, Forms, Controls, SysUtils, Process, Graphics;

type
  ServiceState = class(TThread)
  private

    { Private declarations }
  protected
  var
    ResultStr: TStringList;

    procedure Execute; override;
    procedure ShowStatus;

  end;

implementation

uses unit1, start_trd, service_state_trd, JsonArrayHelper;

  { TRD }

procedure ServiceState.Execute;
var
  ScanProcess: TProcess;
begin
  FreeOnTerminate := True; //Уничтожать по завершении

  while not Terminated do
  try
    ResultStr := TStringList.Create;

    ScanProcess := TProcess.Create(nil);

    ScanProcess.Executable := 'systemctl';
    ScanProcess.Parameters.Add('--user');
    ScanProcess.Parameters.Add('is-active');
    ScanProcess.Parameters.Add('sreality.service');


    ScanProcess.Options := [poUsePipes, poWaitOnExit]; // poStderrToOutPut,

    //Получение статуса сервиса
    ScanProcess.Execute;

    ResultStr.LoadFromStream(ScanProcess.Output);

    if ResultStr.Count <> 0 then
      Synchronize(@ShowStatus);

    Sleep(1000);
  finally
    ResultStr.Free;
    ScanProcess.Free;
  end;
end;

//Отображение статуса
procedure ServiceState.ShowStatus;
begin
  with MainForm do
  begin
    if Trim(ResultStr.Text) = 'active' then
      Shape1.Brush.Color := clLime
    else
      Shape1.Brush.Color := clYellow;

    Shape1.Repaint;
  end;
end;

end.
