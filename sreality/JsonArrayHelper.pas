unit JsonArrayHelper;

interface

uses
  SysUtils, Classes, fpjson, jsonparser;

function JsonReadString(const FileName, Path: string;
  const Default: string = ''): string;
function JsonReadInteger(const FileName, Path: string;
  const Default: integer = 0): integer;
function JsonReadBool(const FileName, Path: string;
  const Default: boolean = False): boolean;

procedure JsonWriteString(const FileName, Path, Value: string);
procedure JsonWriteInteger(const FileName, Path: string; Value: integer);
procedure JsonWriteBool(const FileName, Path: string; Value: boolean);

implementation

// Вспомогательная функция: загружает JSON из файла
function LoadJSON(const FileName: string): TJSONObject;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    if FileExists(FileName) then
      S.LoadFromFile(FileName);
    Result := TJSONObject(GetJSON(S.Text));
  finally
    S.Free;
  end;
end;

// Сохраняет JSON в файл
procedure SaveJSON(const FileName: string; Obj: TJSONObject);
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Text := Obj.FormatJSON;
    S.SaveToFile(FileName);
  finally
    S.Free;
  end;
end;

// --- Вспомогательная функция поиска пути с массивами ---
function FindPathWithArray(Obj: TJSONObject; const Path: string): TJSONData;
var
  Parts: TStringList;
  Current: TJSONData;
  i, idx: integer;
  Part, ArrayIndex: string;
begin
  Result := nil;
  Current := Obj;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := '.';
    Parts.DelimitedText := Path;

    for i := 0 to Parts.Count - 1 do
    begin
      Part := Parts[i];

      // Проверяем индекс массива, например rules[0]
      if Pos('[', Part) > 0 then
      begin
        ArrayIndex := Copy(Part, Pos('[', Part) + 1, Pos(']', Part) -
          Pos('[', Part) - 1);
        idx := StrToIntDef(ArrayIndex, 0);
        Part := Copy(Part, 1, Pos('[', Part) - 1);

        if Current.JSONType = jtObject then
          Current := TJSONObject(Current).FindPath(Part);

        if Assigned(Current) and (Current.JSONType = jtArray) then
          Current := TJSONArray(Current).Items[idx]
        else
        begin
          Result := nil;
          Exit;
        end;
      end
      else
      begin
        if Current.JSONType = jtObject then
          Current := TJSONObject(Current).FindPath(Part)
        else
        begin
          Result := nil;
          Exit;
        end;
      end;
    end;

    Result := Current;
  finally
    Parts.Free;
  end;
end;

// --- Чтение ---
function JsonReadString(const FileName, Path: string;
  const Default: string = ''): string;
var
  Obj: TJSONObject;
  Data: TJSONData;
begin
  Obj := LoadJSON(FileName);
  try
    Data := FindPathWithArray(Obj, Path);
    if Assigned(Data) then
      Result := Data.AsString
    else
      Result := Default;
  finally
    Obj.Free;
  end;
end;

function JsonReadInteger(const FileName, Path: string;
  const Default: integer = 0): integer;
var
  S: string;
begin
  S := JsonReadString(FileName, Path, IntToStr(Default));
  Result := StrToIntDef(S, Default);
end;

function JsonReadBool(const FileName, Path: string;
  const Default: boolean = False): boolean;
var
  S: string;
begin
  S := JsonReadString(FileName, Path, BoolToStr(Default, True));
  Result := SameText(S, 'true') or (S = '1');
end;

// --- Запись ---
procedure JsonWriteString(const FileName, Path, Value: string);
var
  Obj, ParentObj: TJSONObject;
  Parts: TStringList;
  i, idx: integer;
  Part, ArrayIndex: string;
  Data: TJSONData;
  Current: TJSONData;
begin
  Obj := LoadJSON(FileName);
  try
    Parts := TStringList.Create;
    try
      Parts.Delimiter := '.';
      Parts.DelimitedText := Path;

      Current := Obj;
      for i := 0 to Parts.Count - 2 do
      begin
        Part := Parts[i];

        if Pos('[', Part) > 0 then
        begin
          ArrayIndex := Copy(Part, Pos('[', Part) + 1, Pos(']', Part) -
            Pos('[', Part) - 1);
          idx := StrToIntDef(ArrayIndex, 0);
          Part := Copy(Part, 1, Pos('[', Part) - 1);

          if Current.JSONType = jtObject then
            Data := TJSONObject(Current).FindPath(Part)
          else
            Data := nil;

          if not Assigned(Data) or (Data.JSONType <> jtArray) then
          begin
            // создаём массив
            Data := TJSONArray.Create;
            TJSONObject(Current).Add(Part, Data);
          end;

          // расширяем массив, если надо
          while TJSONArray(Data).Count <= idx do
            TJSONArray(Data).Add(TJSONObject.Create);

          Current := TJSONArray(Data).Items[idx];
        end
        else
        begin
          Data := TJSONObject(Current).FindPath(Part);
          if not Assigned(Data) or (Data.JSONType <> jtObject) then
          begin
            Data := TJSONObject.Create;
            TJSONObject(Current).Add(Part, Data);
          end;
          Current := Data;
        end;
      end;

      // записываем последнее поле
      Part := Parts[Parts.Count - 1];
      if Current.JSONType = jtObject then
      begin
        Data := TJSONObject(Current).FindPath(Part);
        if Assigned(Data) then
          Data.AsString := Value
        else
          TJSONObject(Current).Add(Part, Value);
      end;

    finally
      Parts.Free;
    end;

    SaveJSON(FileName, Obj);
  finally
    Obj.Free;
  end;
end;

procedure JsonWriteInteger(const FileName, Path: string; Value: integer);
begin
  JsonWriteString(FileName, Path, IntToStr(Value));
end;

procedure JsonWriteBool(const FileName, Path: string; Value: boolean);
begin
  JsonWriteString(FileName, Path, BoolToStr(Value, True));
end;

end.
