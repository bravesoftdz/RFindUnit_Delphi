﻿unit FindUnit.EnvironmentController;

interface

uses
  Classes, Generics.Collections, FindUnit.PasParser, OtlParallelFU, ToolsAPI, XMLIntf, FindUnit.FileCache, SysUtils,
  Log4Pascal, FindUnit.Worker, FindUnit.AutoImport, Windows, FindUnit.Header;

type
  TEnvironmentController = class(TInterfacedObject, IOTAProjectFileStorageNotifier)
  private
    FProcessingDCU: Boolean;
    FAutoImport: TAutoImport;

    FProjectUnits: TUnitsController;
    FLibraryPath: TUnitsController;

    FProjectPathWorker: TParserWorker;
    FLibraryPathWorker: TParserWorker;

    procedure CreateLibraryPathUnits;
    procedure OnFinishedLibraryPathScan(FindUnits: TObjectList<TPasFile>);

    procedure CreateProjectPathUnits;
    procedure OnFinishedProjectPathScan(FindUnits: TObjectList<TPasFile>);

    procedure CreatingProject(const ProjectOrGroup: IOTAModule);
    //Dummy
    procedure ProjectLoaded(const ProjectOrGroup: IOTAModule; const Node: IXMLNode);
    procedure ProjectSaving(const ProjectOrGroup: IOTAModule; const Node: IXMLNode);
    procedure ProjectClosing(const ProjectOrGroup: IOTAModule);

    procedure CallProcessDcuFiles;
  public
    function GetName: string;

    constructor Create;
    destructor Destroy; override;

    procedure LoadLibraryPath;
    procedure LoadProjectPath;
    procedure ForceLoadProjectPath;

    function GetProjectUnits(const SearchString: string): TStringList;
    function GetLibraryPathUnits(const SearchString: string): TStringList;

    function IsProjectsUnitReady: Boolean;
    function IsLibraryPathsUnitReady: Boolean;

    function GetLibraryPathStatus: string;
    function GetProjectPathStatus: string;

    procedure ProcessDCUFiles;

    property ProcessingDCU: Boolean read FProcessingDCU;
    property AutoImport: TAutoImport read FAutoImport;

    procedure ImportMissingUnits(ShowNoImport: Boolean = true);
  end;

implementation

uses
  FindUnit.OTAUtils, FindUnit.Utils, FindUnit.FileEditor, FindUnit.FormMessage, FindUnit.StringPositionList;

{ TEnvUpdateControl }

constructor TEnvironmentController.Create;
begin
  FAutoImport := TAutoImport.Create(FindUnitDir + AUTO_IMPORT_FILE);
  FAutoImport.Load;
  LoadLibraryPath;
end;

procedure TEnvironmentController.CreateLibraryPathUnits;
var
  Paths, Files: TStringList;
  EnvironmentOptions: IOTAEnvironmentOptions;
begin
  if FLibraryPath <> nil then
    Exit;

  try
    FreeAndNil(FLibraryPathWorker);
  except
    on e: exception do
      Logger.Error('TEnvironmentController.CreateLibraryPathUnits: ' + e.Message);
  end;

  while (BorlandIDEServices as IOTAServices) = nil do
  begin
    Logger.Debug('TEnvironmentController.CreateLibraryPathUnits: waiting for IOTAServices');
    Sleep(1000);
  end;

  try
    Files := nil;
    Paths := TStringList.Create;
    Paths.Delimiter := ';';
    Paths.StrictDelimiter := True;
    Paths.Duplicates := dupIgnore;

    EnvironmentOptions := (BorlandIDEServices as IOTAServices).GetEnvironmentOptions;
    GetLibraryPath(Paths, 'Win32');
    Paths.Add('$(BDS)\source\rtl\win');

    FLibraryPath := TUnitsController.Create;
    FLibraryPathWorker := TParserWorker.Create(Paths, Files);
    FLibraryPathWorker.Start(OnFinishedLibraryPathScan);
  except
    on E: exception do
      Logger.Error('TEnvironmentController.CreateLibraryPathUnits: %s', [e.Message]);
  end;
end;

procedure TEnvironmentController.CreateProjectPathUnits;
var
  I: Integer;
  CurProject: IOTAProject;
  FileDesc: string;
  Files, Paths: TStringList;
begin
  if FProjectUnits <> nil then
    Exit;

  try
    FreeAndNil(FProjectPathWorker);
  except
    on E: exception do
      Logger.Debug('TEnvironmentController.CreateProjectPathUnits: Error removing object');
  end;

  while GetCurrentProject = nil do
  begin
    Logger.Debug('TEnvironmentController.CreateProjectPathUnits: waiting GetCurrentProject <> nil');
    Sleep(1000);
  end;

  Files := GetAllFilesFromProjectGroup;
  Paths := nil;

  FProjectUnits := TUnitsController.Create;
  FProjectPathWorker := TParserWorker.Create(Paths, Files);
  FProjectPathWorker.Start(OnFinishedProjectPathScan);
end;

procedure TEnvironmentController.CreatingProject(const ProjectOrGroup: IOTAModule);
begin
  LoadProjectPath;
end;

destructor TEnvironmentController.Destroy;
begin
  FAutoImport.Free;
  FProjectUnits.Free;
  FLibraryPath.Free;
  inherited;
end;

procedure TEnvironmentController.ForceLoadProjectPath;
begin
  if FProjectUnits = nil then
    LoadProjectPath;
end;

function TEnvironmentController.GetLibraryPathStatus: string;
begin
  Result := 'Ready';
  if FLibraryPathWorker <> nil then
    Result := Format('%d/%d Processing...', [FLibraryPathWorker.ParsedItems, FLibraryPathWorker.ItemsToParse]);
end;

function TEnvironmentController.GetLibraryPathUnits(const SearchString: string): TStringList;
begin
  if IsLibraryPathsUnitReady then
    Result := FLibraryPath.GetFindInfo(SearchString)
  else
    Result := TStringList.Create;
end;

function TEnvironmentController.GetName: string;
begin
  Result := 'RfUtils - Replace FindUnit';
end;

function TEnvironmentController.GetProjectPathStatus: string;
begin
  Result := 'Ready';
  if FProjectPathWorker <> nil then
    Result := Format('%d/%d Files Processed...', [FProjectPathWorker.ParsedItems, FProjectPathWorker.ItemsToParse]);
end;

function TEnvironmentController.GetProjectUnits(const SearchString: string): TStringList;
begin
  if IsProjectsUnitReady then
    Result := FProjectUnits.GetFindInfo(SearchString)
  else
    Result := TStringList.Create;
end;

procedure TEnvironmentController.ImportMissingUnits(ShowNoImport: Boolean);
var
  CurEditor: IOTASourceEditor;
  FileEditor: TSourceFileEditor;
  ListToImport: TStringPositionList;
  Item: TStringPosition;
  OldFocus: Cardinal;
begin
  if FAutoImport = nil then
    Exit;

  CurEditor := OtaGetCurrentSourceEditor;
  if CurEditor = nil then
    Exit;

  OldFocus := GetFocus;

  ListToImport := FAutoImport.LoadUnitListToImport;
  if ListToImport.Count = 0 then
  begin
    if ShowNoImport then
      TfrmMessage.ShowInfoToUser('There is no possible uses to import.');
    ListToImport.Free;
    SetFocus(OldFocus);
    Exit;
  end;

  FileEditor := TSourceFileEditor.Create(CurEditor);
  try
    FileEditor.Prepare;
    for Item in ListToImport do
    begin
      FileEditor.AddUnit(Item);
      SetFocus(OldFocus);
    end;
  finally
    FileEditor.Free;
  end;
  ListToImport.Free;
end;

function TEnvironmentController.IsLibraryPathsUnitReady: Boolean;
begin
  Result := (FLibraryPath <> nil) and (FLibraryPath.Ready);
end;

function TEnvironmentController.IsProjectsUnitReady: Boolean;
begin
  Result := (FProjectUnits <> nil) and (FProjectUnits.Ready);
end;

procedure TEnvironmentController.LoadLibraryPath;
begin
  Logger.Debug('TEnvironmentController.LoadLibraryPath');
  if (FLibraryPath <> nil) and (not FLibraryPath.Ready) then
  begin
    Logger.Debug('TEnvironmentController.LoadLibraryPath: no');
    Exit;
  end;
  Logger.Debug('TEnvironmentController.LoadLibraryPath: yes');

  FreeAndNil(FLibraryPath);
  Parallel.Async(CreateLibraryPathUnits);
end;

procedure TEnvironmentController.LoadProjectPath;
begin
  Logger.Debug('TEnvironmentController.LoadProjectPath');
  if (FProjectUnits <> nil) and (not FProjectUnits.Ready) then
  begin
    Logger.Debug('TEnvironmentController.LoadProjectPath: no');
    Exit;
  end;

  Logger.Debug('TEnvironmentController.LoadProjectPath: yes');
  FreeAndNil(FProjectUnits);
  Parallel.Async(CreateProjectPathUnits);
end;

procedure TEnvironmentController.OnFinishedLibraryPathScan(FindUnits: TObjectList<TPasFile>);
begin
  FLibraryPath.Units := FindUnits;
  FLibraryPath.Ready := True;
end;

procedure TEnvironmentController.OnFinishedProjectPathScan(FindUnits: TObjectList<TPasFile>);
begin
  FProjectUnits.Ready := True;
  FProjectUnits.Units := FindUnits;
end;

procedure TEnvironmentController.ProcessDCUFiles;
begin
  Parallel.Async(CallProcessDcuFiles);
end;

procedure TEnvironmentController.CallProcessDcuFiles;
var
  Paths, Files: TStringList;
  EnvironmentOptions: IOTAEnvironmentOptions;
  DcuProcess: TParserWorker;
  Items: TObject;
begin
  FProcessingDCU := True;
  while (BorlandIDEServices as IOTAServices) = nil do
    Sleep(1000);

  Paths := TStringList.Create;
  Paths.Delimiter := ';';
  Paths.StrictDelimiter := True;
  EnvironmentOptions := (BorlandIDEServices as IOTAServices).GetEnvironmentOptions;
  Paths.DelimitedText := EnvironmentOptions.Values['LibraryPath'] + ';' + EnvironmentOptions.Values['BrowsingPath'];

  Files := nil;
  DcuProcess := TParserWorker.Create(Paths, Files);
  DcuProcess.ParseDcuFile := True;
  Items := DcuProcess.Start;
  DcuProcess.Free;
  Items.Free;
  FProcessingDCU := False;
end;

procedure TEnvironmentController.ProjectClosing(const ProjectOrGroup: IOTAModule);
begin
  Logger.Debug('TEnvironmentController.ProjectClosing');
end;

procedure TEnvironmentController.ProjectLoaded(const ProjectOrGroup: IOTAModule; const Node: IXMLNode);
begin
  Logger.Debug('TEnvironmentController.ProjectLoaded');
end;

procedure TEnvironmentController.ProjectSaving(const ProjectOrGroup: IOTAModule; const Node: IXMLNode);
begin
  Logger.Debug('TEnvironmentController.ProjectSaving');
end;

end.

