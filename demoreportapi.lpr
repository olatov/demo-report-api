program DemoReportApi;

{$Codepage UTF8}

{$IfDef MSWINDOWS}
  {$AppType console}
{$EndIf}

{$Mode delphi}

uses
  {$IfDef UNIX}
    cthreads,
  {$endif}
  SysUtils, Classes, Types, Math,
  fphttpapp, HTTPRoute, HTTPDefs, fpJson, JsonParser,
  fpPDF, FpImage, FPCanvas;

const
  FontFile = './LibreFranklin-Medium.ttf';
  FontName = 'Libre Franklin';
  ChartWidth = 176;
  ChartHeight = 80;
  DefaultBarColor = clBlue;
  DefaultPort = 5050;

type
  TReportModel = record
    Title, Subtitle, Logo: String;
    Bars: record
      Color: TARGBColor;
      Labels: array of String;
      Values: array of Single;
      MaxValue: Single;
    end;
  end;

function TryParseHtmlColor(const Value: String; out Color: TARGBColor): Boolean;
var
  S: String;
begin
  S := Trim(Value).TrimLeft(['#']);
  if S.IsEmpty then Exit(False);

  Result := TryStrToUInt('$' + S, Color);
end;

procedure LogRequest(ARequest: TRequest);
begin
  Writeln(ARequest.RemoteAddress,': ', ARequest.Method, ' ', ARequest.URL);
end;

procedure HandleHome(ARequest: TRequest; AResponse: TResponse);
begin
  LogRequest(ARequest);

  AResponse.Contents.LoadFromFile('index.html', TEncoding.UTF8);
  AResponse.ContentType := 'text/html; charset=utf-8';
end;

procedure HandleReport(ARequest: TRequest; AResponse: TResponse);

  function TryParseRequest(ARequest: TRequest; out AModel: TReportModel): Boolean;
  var
    Payload: TJSONData = Nil;
    Bars: TJSONArray;
    BarCount, I: Integer;
    BarColor: TARGBColor;
  begin
    Result := False;
    if ARequest.ContentLength > 1024 * 8 then Exit;

    Payload := GetJSON(ARequest.Content);
    try
      if not Assigned(Payload) then Exit;
      try
        AModel.Title := Payload.FindPath('title').AsString;
        AModel.Subtitle := Payload.FindPath('subtitle').AsString;

        AModel.Logo := ExtractFileName(Payload.FindPath('logo').AsString);

        if TryParseHtmlColor(Payload.FindPath('barColor').AsString, BarColor) then
          AModel.Bars.Color := BarColor
        else
          AModel.Bars.Color := DefaultBarColor;

        Bars := TJSONArray(Payload.GetPath('bars'));
        BarCount := Min(Bars.Count, 12);

        SetLength(AModel.Bars.Labels, BarCount);
        SetLength(AModel.Bars.Values, BarCount);
        AModel.Bars.MaxValue := Single.MinValue;
        for I := 0 to BarCount - 1 do
        begin
          AModel.Bars.Labels[I] := Bars.Items[I].GetPath('label').AsString;
          AModel.Bars.Values[I] := Bars.Items[I].GetPath('value').AsFloat;
          AModel.Bars.MaxValue := Max(AModel.Bars.MaxValue, AModel.Bars.Values[I]);
        end;
      except
        Exit;
      end;
    finally
      FreeAndNil(Payload);
    end;

    Result := True;
  end;

  function RenderReport(AReport: TReportModel): TPDFDocument;
  var
    Page: TPDFPage;
    Section: TPDFSection;
    Font, I, Logo: Integer;
    ColWidth, BarHeight: Single;
  begin
    Result := TPDFDocument.Create(Nil);
    try
      Result.Options := [poPageOriginAtTop];
      Result.DefaultUnitOfMeasure := uomMillimeters;
      Result.StartDocument;

      Page := Result.Pages.AddPage;
      Page.Orientation := ppoPortrait;
      Page.PaperType := ptA4;

      Section := Result.Sections.AddSection;
      Section.AddPage(Page);

      Font := Result.AddFont(FontFile, FontName);

      { Logo }
      if not AReport.Logo.IsEmpty then
      begin
        Logo := Result.Images.AddFromFile(AReport.Logo);
        Page.DrawImage(172, 32, 24, 24, Logo);
      end;

      { Title }
      Page.SetFont(Font, 36);
      Page.SetColor(clMaroon, False);
      Page.WriteText(20, 24, AReport.Title);

      { Subtitle }
      Page.SetFont(Font, 18);
      Page.SetColor(clBlack, False);
      Page.WriteText(20, 36, AReport.Subtitle);

      { Bars }
      if Length(AReport.Bars.Values) > 0 then
      begin
        Page.SetColor(clLtGray, True);
        Page.DrawRect(20, 172, 180, 116, 0.25, False, True);

        ColWidth := ChartWidth / Length(AReport.Bars.Values);

        for I := 0 to High(AReport.Bars.Values) do
        begin
          Page.SetColor(AReport.Bars.Color);
          Page.SetColor(AReport.Bars.Color, False);

          BarHeight := AReport.Bars.Values[I] / AReport.Bars.MaxValue * ChartHeight;
          Page.DrawRect(
            30 + (ColWidth * I), 148,
            ColWidth * 0.5,
            BarHeight,
            0.5, True, True);

          Page.SetColor(clBlack, False);

          Page.SetFont(Font, 16);
          Page.WriteText(
            30 + (ColWidth * I), 158,
            AReport.Bars.Labels[I]);

          Page.SetFont(Font, 12);
          Page.SetColor(clGreen, False);
          Page.WriteText(
            30 + (ColWidth * I), 166,
            Format('%.2n', [AReport.Bars.Values[I]]));
        end;
      end;
    except
      begin
        FreeAndNil(Result);
        raise;
      end;
    end;
  end;

var
  Document: TPDFDocument = Nil;
  Report: TReportModel;
begin
  LogRequest(ARequest);

  if not TryParseRequest(ARequest, Report) then
  begin
    AResponse.Code := 400;
    Exit;
  end;

  try
    Document := RenderReport(Report);

    AResponse.ContentStream := TMemoryStream.Create;
    Document.SaveToStream(AResponse.ContentStream);
    AResponse.FreeContentStream := True;

    AResponse.ContentLength := AResponse.ContentStream.Size;
    AResponse.ContentType := 'application/pdf';
    AResponse.CustomHeaders.AddPair(
      'Content-Disposition',
      'attachment; filename="report.pdf"');
  finally
    FreeAndNil(Document);
  end;
end;

var
  StdOutBuffer: AnsiChar = #0;
  StdErrBuffer: AnsiChar = #0;

begin
  {
    Usage: demoreportapi [port]
    Default port: 5050
  }

  SetTextBuf(Output, StdOutBuffer, SizeOf(StdOutBuffer));
  SetTextBuf(stderr, StdErrBuffer, SizeOf(StdErrBuffer));

  HTTPRouter.RegisterRoute('/', rmGet, HandleHome, True);
  HTTPRouter.RegisterRoute('/report', rmPost, HandleReport);

  Application.Port := StrToIntDef(ParamStr(1), DefaultPort);
  Application.Threaded := True;

  Application.Initialize;
  Writeln('Listening port ', Application.Port);

  Application.Run;
end.


