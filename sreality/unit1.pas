unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Buttons,
  IniPropStorage, URIParser, HTTPDefs, ClipBrd, ExtCtrls, StdCtrls, Process,
  DefaultTranslator, ubarcodes;
  // HTTPDefs нужен для функции HTTPDecode (раскодирование процентов вроде %2F в /)

type

  { TMainForm }

  TMainForm = class(TForm)
    BarcodeQR1: TBarcodeQR;
    Image1: TImage;
    IniPropStorage1: TIniPropStorage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LogMemo: TMemo;
    PasteBtn: TBitBtn;
    Shape1: TShape;
    StartBtn: TBitBtn;
    StaticText1: TStaticText;
    StopBtn: TBitBtn;
    QRBtn: TBitBtn;

    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ParseV2RayURI(const AURI: string);
    procedure PasteBtnClick(Sender: TObject);
    procedure QRBtnClick(Sender: TObject);
    procedure StartBtnClick(Sender: TObject);
    procedure StopBtnClick(Sender: TObject);
    procedure StartProcess(command: string);

  private

  public

  end;

var
  MainForm: TMainForm;

resourcestring

  SImportSuccess = 'Configuration imported successfully...';
  SNoMatchVLESS = 'The clipboard does not contain VLESS Reality configuration!';
  SFileExists = 'Configuration file exists! Overwrite?';
  SNoSupport = 'Transport not support! Use RAW (tcp) or gRPC!';
  SFlowRequires =
    'This configuration does not use Vision protection!' + LineEnding +
    LineEnding + 'Specify "flow=xtls-rprx-vision" on the server!';
  SGRPCRequires =
    'GRPC transport requires a "serviceName" (for example, "grpc-service") to be specified on the server!';
  SInvalidGRPCFlow =
    '"Flow" was detected in the gRPC transport!' + LineEnding +
    LineEnding +
    'The server configuration may not have been cleared after switching transports!';


implementation

uses start_trd, service_state_trd;

var
  fproto, ftype, fserver, fserver_port, fuuid, fserver_name, ffingerprint,
  fpublic_key, fshort_id, fflow, fpath, fserviceName, fbookmark: string;

  {$R *.lfm}

  { TMainForm }

//Общая процедура запуска команд (асинхронная)
procedure TMainForm.StartProcess(command: string);
var
  ExProcess: TProcess;
begin
  ExProcess := TProcess.Create(nil);
  try
    ExProcess.Executable := '/bin/bash';
    ExProcess.Parameters.Add('-c');
    ExProcess.Parameters.Add(command);
    ExProcess.Options := ExProcess.Options + [poWaitOnExit];
    ExProcess.Execute;
  finally
    ExProcess.Free;
  end;
end;

procedure TMainForm.ParseV2RayURI(const AURI: string);
var
  ParsedURI: TURI;
  ParamsList: TStringList;
  I: integer;
  ParamName, ParamValue: string;
begin
  // Используем встроенный TURI для базового разбора структуры
  ParsedURI := ParseURI(AURI);

  //Очистка публичных переменных
  fproto := '';
  ftype := '';
  fserver := '';
  fserver_port := '';
  fuuid := '';
  fserver_name := '';
  ffingerprint := '';
  fpublic_key := '';
  fshort_id := '';
  fflow := '';
  fpath := '';
  fserviceName := '';
  fbookmark := '';

  // Выводим базовые значения ДО знака ?
  // protocol = vless
  fproto := ParsedURI.Protocol;
  // uuid
  fuuid := ParsedURI.Username;
  // server = IP address or domain
  fserver := ParsedURI.Host;
  // server Port (integer)
  fserver_port := IntToStr(ParsedURI.Port);
  // Название соединения (Хэш после знака #)
  fbookmark := HTTPDecode(ParsedURI.Bookmark);
  // Если fbookmark пуст, пробуем из другого места
  if fbookmark = '' then fbookmark := HTTPDecode(ParsedURI.Document);

  // Не используются в vless
  // WriteLn('Password: ', ParsedURI.Password); // То, что до @
  // WriteLn('Path: ', ParsedURI.Path);
  // WriteLn('Document: ', ParsedURI.Document);
  // Одинаковые - название соединения
  // WriteLn('Bookmark: ', ParsedURI.Bookmark);

  // 2. Разбираем параметры (всё, что после знака "?")
  if ParsedURI.Params <> '' then
  begin
    ParamsList := TStringList.Create;
    try
      // Заменяем разделители параметров '&' на перенос строки для TStringList
      ParamsList.Text := StringReplace(ParsedURI.Params, '&', sLineBreak,
        [rfReplaceAll]);

      // Дополнительные параметры
      for I := 0 to ParamsList.Count - 1 do
      begin
        ParamName := ParamsList.Names[I];
        // Например: security
        ParamValue := HTTPDecode(ParamsList.ValueFromIndex[I]); // Например: tls

        // Читаем остальные поля
        // "server_name"
        if ParamName = 'sni' then fserver_name := ParamValue;
        // "fingerprint"
        if ParamName = 'fp' then ffingerprint := ParamValue;
        // "public_key"
        if ParamName = 'pbk' then fpublic_key := ParamValue;
        // "short_id"
        if ParamName = 'sid' then fshort_id := ParamValue;
        // "flow"
        if ParamName = 'flow' then fflow := ParamValue;
        // "type" (RAW=tcp, XHTTP=xhttp, gRPC=grpc)
        if ParamName = 'type' then ftype := ParamValue;
        // "path"
        if ParamName = 'path' then fpath := ParamValue;
        // serviceName
        if ParamName = 'serviceName' then fserviceName := ParamValue;

      end;
    finally
      ParamsList.Free;
    end;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  bmp: TBitmap;
begin
  MainForm.Caption := Application.Title;

  // Устраняем баг иконки приложения
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.Assign(Image1.Picture.Graphic);
    Application.Icon.Assign(bmp);
  finally
    bmp.Free;
  end;

  if not DirectoryExists(GetUserDir + '.config/sreality') then
    ForceDirectories(GetUserDir + '.config/sreality');

  IniPropStorage1.IniFileName := GetUserDir + '.config/sreality/sreality.conf';
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  IniPropStorage1.Restore;

  QRBtn.Width := QRBtn.Height;

  //Запуск потока проверки состояния сервиса (active/inactive)
  ServiceState.Create(False);

  //Запуск поток непрерывного чтения лога
  ShowLogTRD.Create(False);
end;

//Вставка URI (vless://)
procedure TMainForm.PasteBtnClick(Sender: TObject);
var
  S: TStringList;
  VlessURI: string;
begin
  VlessURI := Trim(ClipBoard.AsText);

  //Проверка буфера на соответствие шаблону + reality
  if not VlessURI.StartsWith('vless://') or
    (Pos('security=reality', VlessURI) = 0) then
  begin
    MessageDlg(SNoMatchVLESS, mtWarning, [mbOK], 0);
    Exit;
  end;

  //Получаем переменные
  ParseV2RayURI(VlessURI);

  if (ftype <> 'tcp') and (ftype <> 'grpc') then
  begin
    MessageDlg(SNoSupport, mtWarning, [mbOK], 0);
    Exit;
  end;

  //Рекомендуем Flow для RAW
  if (ftype = 'tcp') and (Pos('flow=', VlessURI) = 0) then
    if MessageDlg(SFlowRequires, mtInformation, [mbOK], 0) <> mrOk then Exit;

  //Требуем serviceName для gRPC
  if (ftype = 'grpc') and (fserviceName = '') then
  begin
    MessageDlg(SGRPCRequires, mtWarning, [mbOK], 0);
    Exit;
  end;

  //Проверяем на присутствие flow конфиг gRPC (баг панели 3X-UI) - может и не придти, а на сервере будет
  //https://github.com/MHSanaei/3x-ui/issues/5322
  if (ftype = 'grpc') and (fflow <> '') then
  begin
    MessageDlg(SInvalidGRPCFlow, mtWarning, [mbOK], 0);
    Exit;
  end;

  //Перезаписать существующий конфиг?
  if FileExists(GetUserDir + '.config/sreality/client.json') then
    if MessageDlg(SFileExists, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  //Останов
  StopBtn.Click;
  Application.ProcessMessages;
  LogMemo.Visible := True;
  LogMemo.Clear;

  //Показываем и сохраняем название соединения
  Label3.Caption := fbookmark;
  IniPropStorage1.Save;

  LogMemo.Append(SImportSuccess);

  //Создаём файлы конфигураций
  try
    S := TStringList.Create;

    //Сохраняем VlessURI для QR-кода
    S.Text := VlessURI;
    S.SaveToFile(GetUserDir + '.config/sreality/uri.txt');
    S.Clear;

    //Создаём новую конфигурацию
    S.Add('{');
    S.Add('"log": {');
    S.Add('  "level": "info"');
    S.Add('},');
    S.Add('');

    S.Add('"dns": {');
    S.Add('  "servers": [');
    S.Add('    {');
    S.Add('      "tag": "remote",');
    S.Add('      "type": "udp",');
    S.Add('      "server": "1.0.0.1"');
    S.Add('    },');
    S.Add('    {');
    S.Add('      "tag": "remote-fallback",');
    S.Add('      "type": "udp",');
    S.Add('      "server": "9.9.9.9"');
    S.Add('    },');
    S.Add('    {');
    S.Add('      "tag": "local",');
    S.Add('      "type": "udp",');
    S.Add('      "server": "8.8.4.4"');
    S.Add('    }');
    S.Add('  ],');
    S.Add('');
    S.Add('  "rules": [');
    S.Add('    {');
    S.Add('      "domain_suffix": [".ru", ".xn--p1ai"],');
    S.Add('      "server": "local"');
    S.Add('    }');
    S.Add('  ]');
    S.Add('},');
    S.Add('');

    S.Add('"inbounds": [');
    S.Add('  {');
    S.Add('    "type": "mixed",');
    S.Add('    "tag": "mixed-in",');
    S.Add('    "listen_port": 11080,');
    S.Add('    "set_system_proxy": true');

    S.Add('  }');

    S.Add('],');
    S.Add('');

    S.Add('"outbounds": [');
    S.Add('    {');
    S.Add('      "type": "' + fproto + '",');
    S.Add('      "tag": "proxy",');
    S.Add('      "server": "' + fserver + '",');
    S.Add('      "server_port": ' + fserver_port + ',');
    S.Add('      "uuid": "' + fuuid + '",');

    if fflow <> '' then
      S.Add('      "flow": "' + fflow + '",');

    S.Add('      "tls": {');
    S.Add('        "enabled": true,');
    S.Add('        "server_name": "' + fserver_name + '",');
    S.Add('        "utls": {');
    S.Add('          "enabled": true,');
    S.Add('          "fingerprint": "' + ffingerprint + '"');
    S.Add('        },');
    S.Add('        "reality": {');
    S.Add('          "enabled": true,');
    S.Add('          "public_key": "' + fpublic_key + '",');
    S.Add('          "short_id": "' + fshort_id + '"');
    S.Add('        }');
    S.Add('      },');

    // if ftype = '"httpupgrade"' then
    // begin
    //   S.Add('      "transport": {');
    //   S.Add('          "type": "httpupgrade",');
    //   S.Add('          "host": "www.nvidia.com",');
    //   S.Add('          "path": ' + fpath);
    //   S.Add('        },');
    // end;

    if ftype = 'grpc' then
    begin
      S.Add('      "transport": {');
      S.Add('          "type": "grpc",');
      S.Add('          "service_name": "' + fserviceName + '"');
      S.Add('        },');
    end;

    S.Add('      "packet_encoding": "xudp"');
    S.Add('    },');
    S.Add('    {');
    S.Add('    "type": "direct",');
    S.Add('    "tag": "direct"');
    S.Add('    }');
    S.Add('],');
    S.Add('');

    S.Add('"route": {');
    S.Add('  "default_domain_resolver": "remote",');
    S.Add('');
    S.Add('  "rules": [');
    S.Add('    {');
    S.Add('      "domain_suffix": [".ru", ".xn--p1ai"],');
    S.Add('      "outbound": "direct"');
    S.Add('    }');
    S.Add('  ],');
    S.Add('');

    S.Add('  "final": "proxy"');
    S.Add('}');
    S.Add('}');

    S.SaveToFile(GetUserDir + '.config/sreality/client.json')

  finally
    S.Free;
  end;
end;

//Показать QR-код
procedure TMainForm.QRBtnClick(Sender: TObject);
var
  S: TStringList;
begin
  //Если файл с URI для QR отсутствует - выйти
  if not FileExists(GetUserDir + '.config/sreality/uri.txt') then Exit;

  try
    S := TStringList.Create;

    if LogMemo.Visible then
    begin
      LogMemo.Visible := False;
      S.LoadFromFile(GetUserDir + '.config/sreality/uri.txt');
      S.Text := Trim(S.Text);
      BarcodeQR1.Text := S.Text;
    end
    else
      LogMemo.Visible := True;
  finally
    S.Free;
  end;
end;

//Рестарт / Enable
procedure TMainForm.StartBtnClick(Sender: TObject);
begin
  // StartProcess('~/.config/hybridge/swproxy.sh set');
  LogMemo.Visible := True;
  if not FileExists(GetUserDir + '.config/sreality/client.json') then Exit;
  StartProcess('systemctl --user restart sreality.service; systemctl --user enable sreality.service');
end;

//Стоп / Disable
procedure TMainForm.StopBtnClick(Sender: TObject);
begin
  // StartProcess('~/.config/hybridge/swproxy.sh reset');
  LogMemo.Visible := True;
  StartProcess('systemctl --user stop sreality.service; systemctl --user disable sreality.service');
end;

end.
