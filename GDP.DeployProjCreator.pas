unit GDP.DeployProjCreator;

interface

type
  TDeployProjCreator = record
  private
    class procedure WriteError(const AMsg: string); static;
  public
    class function CreateDeployProj(const ADprojFileName: string; const AOverwrite: Boolean): Integer; static;
  end;

implementation

uses
  System.IOUtils, System.SysUtils, System.Variants,
  Xml.XMLDoc, Xml.XmlIntf;

const
  cProjectExtensionsNodeName = 'ProjectExtensions';
  cDprojDeploymentNodeName = 'Deployment';
  cDprojDeployFileNodeName = 'DeployFile';
  cDprojDeployClassNodeName = 'DeployClass';
  cDprojProjectRootNodeName = 'ProjectRoot';
  cDprojDeployFilePlatformNodeRemoteDirNodeName = 'RemoteDir';
  cDprojDeployFilePlatformNodeRemoteNameNodeName = 'RemoteName';
  cDprojDeployFilePlatformNodeOverwriteNodeName = 'Overwrite';

  cDprojDeployFileNodeConfigurationAttributeName = 'Configuration';
  cDprojDeployFileNodeClassAttributeName = 'Class';
  cDprojDeployFileNodeLocalNameAttributeName = 'LocalName';
  cDprojDeployFilePlatformNodeNameAttributeName = 'Name';

  cDeployProjRootNodeName = 'Project';
  cDeployProjImportNodeName = 'Import';
  cDeployProjItemGroupNodeName = 'ItemGroup';
  cDeployProjItemGroupDeployFileNodeName = 'DeployFile';
  cDeployProjProjectExtensionsProjectFileVersionNodeName = 'ProjectFileVersion';
  cDeployProjProjectExtensionsProjectFileVersionNodeValue = '12'; // Might change?

  cDeployProjImportNodeConditionAttributeName = 'Condition';
  cDeployProjImportNodeConditionAttributeValue = 'Exists(''$(BDS)\bin\CodeGear.Deployment.targets'')';
  cDeployProjImportNodeProjectAttributeName = 'Project';
  cDeployProjImportNodeProjectAttributeValue = '$(BDS)\bin\CodeGear.Deployment.targets';
  cDeployProjItemGroupNodeConditionAttributeName = 'Condition';
  cDeployProjItemGroupNodeConditionAttributeValueTemplate = '''$(Platform)''==''%s''';
  cDeployProjItemGroupDeployFileNodeIncludeAttributeName = 'Include';
  cDeployProjItemGroupDeployFileNodeConditionAttributeName = 'Condition';
  cDeployProjItemGroupDeployFileNodeConditionAttributeValueTemplate = '''$(Config)''==''%s''';

  cXmlNSAttributeName = 'xmlns';
  cMSBuildXmlNSSchemaURL = 'http://schemas.microsoft.com/developer/msbuild/2003';

resourcestring
  sDprojNoExist = '%s does not exist';
  sDprojNodeMissing = 'Cannot find %s node in %s';
  sDeployProjExist = '%s already exists';

  sFileReadException = 'Loading %s caused an exception - %s: %s';
  sFileSaveException = 'Saving %s caused an exception - %s: %s';

type
  TPlatformDeployFile = record
    PlatformName: string;
    RemoteDir: string;
    RemoteName: string;
    Overwrite: string;
    procedure Clear;
  end;

  TPlatformDeployFiles = TArray<TPlatformDeployFile>;

  TDeployFile = record
    Configuration: string;
    DeployClass: string;
    LocalName: string;
    PlatformDeployFiles: TPlatformDeployFiles;
    procedure Clear;
  end;

  TDeployFiles = TArray<TDeployFile>;

  TDeployClassPlatform = record
    Extensions: string;
    Operation: string;
    RemoteDir: string;
    PlatformName: string;
  end;

  TDeployClassPlatforms = TArray<TDeployClassPlatform>;

  TDeployClass = record
    Name: string;
    Required: string;
    DeployClassPlatforms: TDeployClassPlatforms;
    procedure Clear;
    function FindPlatform(const APlatformName: string; out ADeployClassPlatform: TDeployClassPlatform): Boolean;
  end;

  TDeployClasses = TArray<TDeployClass>;

  TDeployClassesHelper = record helper for TDeployClasses
    function Find(const AName: string; out ADeployClass: TDeployClass): Boolean;
    function FindPlatform(const AName: string; const APlatform: string;  out ADeployClassPlatform: TDeployClassPlatform): Boolean;
  end;

  TPlatform = record
    PlatformName: string;
    ProjectRoot: string;
  end;

  TPlatforms = TArray<TPlatform>;

  TPlatformsHelper = record helper for TPlatforms
    procedure Add(const APlatformName: string);
    function Count: Integer;
    function GetProjectRoot(const APlatformName: string): string;
    procedure SetProjectRoot(const APlatformName, AProjectRoot: string);
  end;

function FindNode(const AParentNode: IXMLNode; const ANodeName: string): IXMLNode;
var
  I: Integer;
begin
  Result := nil;
  if not AParentNode.NodeName.Equals(ANodeName) then
  begin
    for I := 0 to AParentNode.ChildNodes.Count - 1 do
    begin
      Result := FindNode(AParentNode.ChildNodes[I], ANodeName);
      if Result <> nil then
        Break;
    end;
  end
  else
    Result := AParentNode;
end;

function GetChildNodeText(const AParentNode: IXmlNode; const AChildNodeName: string): string;
var
  LChildNode: IXmlNode;
begin
  Result := '';
  LChildNode := FindNode(AParentNode, AChildNodeName);
  if LChildNode <> nil then
    Result := LChildNode.Text;
end;

procedure AddChildNode(const AParentNode: IXmlNode; const AName, AText: string);
var
  LChildNode: IXmlNode;
begin
  LChildNode := AParentNode.AddChild(AName);
  LChildNode.Text := AText;
end;

{ TPlatformDeployFile }

procedure TPlatformDeployFile.Clear;
begin
  PlatformName := '';
  RemoteDir := '';
  RemoteName := '';
  Overwrite := '';
end;

{ TDeployFile }

procedure TDeployFile.Clear;
begin
  Configuration := '';
  DeployClass := '';
  LocalName := '';
  SetLength(PlatformDeployFiles, 0);
end;

{ TDeployClass }

procedure TDeployClass.Clear;
begin
  Name := '';
  Required := '';
  SetLength(DeployClassPlatforms, 0);
end;

function TDeployClass.FindPlatform(const APlatformName: string; out ADeployClassPlatform: TDeployClassPlatform): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Length(DeployClassPlatforms) - 1 do
  begin
    if DeployClassPlatforms[I].PlatformName.Equals(APlatformName) then
    begin
      ADeployClassPlatform := DeployClassPlatforms[I];
      Exit(True);
    end;
  end;
end;

{ TDeployClassesHelper }

function TDeployClassesHelper.Find(const AName: string; out ADeployClass: TDeployClass): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Length(Self) - 1 do
  begin
    if Self[I].Name.Equals(AName) then
    begin
      ADeployClass := Self[I];
      Exit(True);
    end;
  end;
end;

function TDeployClassesHelper.FindPlatform(const AName: string; const APlatform: string;  out ADeployClassPlatform: TDeployClassPlatform): Boolean;
var
  LDeployClass: TDeployClass;
begin
  Result := False;
  if Find(AName, LDeployClass) then
    Result := LDeployClass.FindPlatform(APlatform, ADeployClassPlatform);
end;

{ TPlatformsHelper }

procedure TPlatformsHelper.Add(const APlatformName: string);
var
  I: Integer;
  LPlatform: TPlatform;
begin
  for I := 0 to Count - 1 do
  begin
    if Self[I].PlatformName.Equals(APlatformName) then
      Exit;
  end;
  LPlatform.PlatformName := APlatformName;
  Self := Self + [LPlatform];
end;

function TPlatformsHelper.Count: Integer;
begin
  Result := Length(Self);
end;

function TPlatformsHelper.GetProjectRoot(const APlatformName: string): string;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    if Self[I].PlatformName.Equals(APlatformName) then
      Exit(Self[I].ProjectRoot);
  end;
  Result := '';
end;

procedure TPlatformsHelper.SetProjectRoot(const APlatformName, AProjectRoot: string);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    if Self[I].PlatformName.Equals(APlatformName) then
      Self[I].ProjectRoot := AProjectRoot;
  end;
end;

{ TDeployProjCreator }

class procedure TDeployProjCreator.WriteError(const AMsg: string);
begin
  if IsConsole then
    Writeln(AMsg);
end;

class function TDeployProjCreator.CreateDeployProj(const ADprojFileName: string; const AOverwrite: Boolean): Integer;
var
  LXML: IXMLDocument;
  LDprojNode, LDrojDeployNode, LDrojDeployPlatformNode,
  LDeployProjRootNode, LDeployProjProjectExtensionsNode, LDeployProjItemGroupNode, LDeployProjDeployFileNode, LNode: IXmlNode;
  LPlatforms: TPlatforms;
  I, J, K: Integer;
  LDeployFile: TDeployFile;
  LDeployFiles: TDeployFiles;
  LPlatformDeployFile: TPlatformDeployFile;
  LDeployClass: TDeployClass;
  LDeployClasses: TDeployClasses;
  LDeployClassPlatform: TDeployClassPlatform;
  LDeployProjFileName, LAttributeValue, LOperation, LPlatform, LRemoteDir, LProjectName, LXMLString: string;
begin
  Result := 0; // Success
  if not TFile.Exists(ADprojFileName) then
  begin
    WriteError(Format(sDprojNoExist, [ADprojFileName]));
    Exit(1); // No Dproj
  end;
  LDeployProjFileName := TPath.ChangeExtension(ADprojFileName, '.deployproj');
  if TFile.Exists(LDeployProjFileName) and not AOverwrite then
  begin
    WriteError(Format(sDeployProjExist, [LDeployProjFileName]));
    Exit(0); // DeployProj already exists - not an error; just don't touch it
  end;
  LProjectName := TPath.GetFileNameWithoutExtension(TPath.GetFileName(ADprojFileName));
  try
    LXML := LoadXMLDocument(ADprojFileName);
  except
    on E: Exception do
    begin
      WriteError(Format(sFileReadException, [ADprojFileName, E.ClassName, E.Message]));
      Exit(2);
    end;
  end;
  LDprojNode := FindNode(LXML.DocumentElement, cProjectExtensionsNodeName);
  if LDprojNode = nil then
  begin
    WriteError(Format(sDprojNodeMissing, [cProjectExtensionsNodeName, ADprojFileName]));
    Exit(3);
  end;
  LDprojNode := FindNode(LDprojNode, cDprojDeploymentNodeName);
  if LDprojNode = nil then
  begin
    WriteError(Format(sDprojNodeMissing, [cDprojDeploymentNodeName, ADprojFileName]));
    Exit(3);
  end;
  for I := 0 to LDprojNode.ChildNodes.Count - 1 do
  begin
    LDrojDeployNode := LDprojNode.ChildNodes[I];
    if LDrojDeployNode.NodeName = cDprojDeployFileNodeName then
    begin
      LDeployFile.Clear;
      LDeployFile.Configuration := VarToStr(LDrojDeployNode.Attributes[cDprojDeployFileNodeConfigurationAttributeName]);
      LDeployFile.DeployClass := VarToStr(LDrojDeployNode.Attributes[cDprojDeployFileNodeClassAttributeName]);
      // e.g. Lib\iOS\opus.framework\opus  - has containing folder with .framework, and has extensionless file (or one ending with .dylib)
      LDeployFile.LocalName := VarToStr(LDrojDeployNode.Attributes[cDprojDeployFileNodeLocalNameAttributeName]);
      for J := 0 to LDrojDeployNode.ChildNodes.Count - 1 do
      begin
        LDrojDeployPlatformNode := LDrojDeployNode.ChildNodes[J];
        LPlatformDeployFile.Clear;
        LPlatformDeployFile.PlatformName := VarToStr(LDrojDeployPlatformNode.Attributes[cDprojDeployFilePlatformNodeNameAttributeName]);
        LPlatforms.Add(LPlatformDeployFile.PlatformName);
        LPlatformDeployFile.RemoteDir := GetChildNodeText(LDrojDeployPlatformNode, cDprojDeployFilePlatformNodeRemoteDirNodeName);
        LPlatformDeployFile.RemoteName := GetChildNodeText(LDrojDeployPlatformNode, cDprojDeployFilePlatformNodeRemoteNameNodeName);
        if LPlatformDeployFile.RemoteName.IsEmpty then
          LPlatformDeployFile.RemoteName := LDeployFile.LocalName.Substring(LDeployFile.LocalName.LastIndexOf('\') + 1);
        LPlatformDeployFile.Overwrite := GetChildNodeText(LDrojDeployPlatformNode, cDprojDeployFilePlatformNodeOverwriteNodeName);
        LDeployFile.PlatformDeployFiles := LDeployFile.PlatformDeployFiles + [LPlatformDeployFile];
      end;
      LDeployFiles := LDeployFiles + [LDeployFile];
    end
    else if LDrojDeployNode.NodeName = cDprojDeployClassNodeName then
    begin
      LDeployClass.Clear;
      LDeployClass.Name := VarToStr(LDrojDeployNode.Attributes['Name']);
      LDeployClass.Required := VarToStr(LDrojDeployNode.Attributes['Required']);
      for J := 0 to LDrojDeployNode.ChildNodes.Count - 1 do
      begin
        LDrojDeployPlatformNode := LDrojDeployNode.ChildNodes[J];
        LDeployClassPlatform.PlatformName := VarToStr(LDrojDeployPlatformNode.Attributes[cDprojDeployFilePlatformNodeNameAttributeName]);
        LDeployClassPlatform.Extensions := GetChildNodeText(LDrojDeployPlatformNode, 'Extensions');
        LDeployClassPlatform.Operation := GetChildNodeText(LDrojDeployPlatformNode, 'Operation');
        LDeployClassPlatform.RemoteDir := GetChildNodeText(LDrojDeployPlatformNode, 'RemoteDir');
        LDeployClass.DeployClassPlatforms := LDeployClass.DeployClassPlatforms + [LDeployClassPlatform];
      end;
      LDeployClasses := LDeployClasses + [LDeployClass];
    end
    else if LDrojDeployNode.NodeName = cDprojProjectRootNodeName then
       LPlatforms.SetProjectRoot(VarToStr(LDrojDeployNode.Attributes['Platform']), VarToStr(LDrojDeployNode.Attributes['Name']));
  end;
  LXML := NewXMLDocument;
  // Root
  LDeployProjRootNode := LXML.AddChild(cDeployProjRootNodeName);
  LDeployProjRootNode.Attributes[cXmlNSAttributeName] := cMSBuildXmlNSSchemaURL;
  // Import
  LNode := LDeployProjRootNode.AddChild(cDeployProjImportNodeName);
  LNode.Attributes[cDeployProjImportNodeConditionAttributeName] := cDeployProjImportNodeConditionAttributeValue;
  LNode.Attributes[cDeployProjImportNodeProjectAttributeName] := cDeployProjImportNodeProjectAttributeValue;
  // Project Extensions
  LDeployProjProjectExtensionsNode := LDeployProjRootNode.AddChild(cProjectExtensionsNodeName);
  // ProjectFileVersion
  LNode := LDeployProjProjectExtensionsNode.AddChild(cDeployProjProjectExtensionsProjectFileVersionNodeName);
  LNode.Text := cDeployProjProjectExtensionsProjectFileVersionNodeValue;
  // Item group for each platform (LPlatforms)
  for I := 0 to LPlatforms.Count - 1 do
  begin
    LDeployProjItemGroupNode := LDeployProjRootNode.AddChild(cDeployProjItemGroupNodeName);
    LDeployProjItemGroupNode.DeclareNamespace('', '');
    LAttributeValue := Format(cDeployProjItemGroupNodeConditionAttributeValueTemplate, [LPlatforms[I].PlatformName]);
    LDeployProjItemGroupNode.Attributes[cDeployProjItemGroupNodeConditionAttributeName] := LAttributeValue;
    // e.g. <ItemGroup Condition="'$(Platform)'=='iOSDevice64'">
    for J := 0 to Length(LDeployFiles) - 1 do
    begin
      LDeployFile := LDeployFiles[J];
      for K := 0 to Length(LDeployFile.PlatformDeployFiles) - 1 do
      begin
        LPlatformDeployFile := LDeployFile.PlatformDeployFiles[K];
        if LPlatformDeployFile.PlatformName = LPlatforms[I].PlatformName then
        begin
          LDeployClasses.Find(LDeployFile.DeployClass, LDeployClass);
          LDeployClasses.FindPlatform(LDeployFile.DeployClass, LPlatformDeployFile.PlatformName, LDeployClassPlatform);
          LDeployProjDeployFileNode := LDeployProjItemGroupNode.AddChild(cDeployProjItemGroupDeployFileNodeName);
          LDeployProjDeployFileNode.Attributes[cDeployProjItemGroupDeployFileNodeIncludeAttributeName] := LDeployFile.LocalName;
          if not LDeployFile.Configuration.IsEmpty then
          begin
            LAttributeValue := Format(cDeployProjItemGroupDeployFileNodeConditionAttributeValueTemplate, [LDeployFile.Configuration]);
            LDeployProjDeployFileNode.Attributes[cDeployProjItemGroupDeployFileNodeConditionAttributeName] := LAttributeValue;
          end;
          // e.g. <DeployFile Include="$(BDS)\bin\Artwork\iOS\iPhone\FM_LaunchImage_640x1136.png" Condition="'$(Config)'=='Debug'">
          LRemoteDir := LPlatformDeployFile.RemoteDir;
          if LRemoteDir.IsEmpty then
            LRemoteDir := LDeployClassPlatform.RemoteDir;
          if LRemoteDir.StartsWith('.\') then
            LRemoteDir := LRemoteDir.Substring(2);
          LRemoteDir := IncludeTrailingPathDelimiter(StringReplace(LPlatforms[I].ProjectRoot, '$(PROJECTNAME)', LProjectName, []) + '\' + LRemoteDir);
          AddChildNode(LDeployProjDeployFileNode, 'RemoteDir', LRemoteDir);
          AddChildNode(LDeployProjDeployFileNode, 'RemoteName', LPlatformDeployFile.RemoteName);
          AddChildNode(LDeployProjDeployFileNode, 'DeployClass', LDeployFile.DeployClass);
          LOperation := LDeployClassPlatform.Operation;
          if LOperation.IsEmpty then
            LOperation := '0';
          AddChildNode(LDeployProjDeployFileNode, 'Operation', LOperation);
          AddChildNode(LDeployProjDeployFileNode, 'LocalCommand', ''); //!!!!!!
          AddChildNode(LDeployProjDeployFileNode, 'RemoteCommand', ''); //!!!!!!
          AddChildNode(LDeployProjDeployFileNode, 'Overwrite', LPlatformDeployFile.Overwrite);
          if not LDeployClass.Required.IsEmpty then
            AddChildNode(LDeployProjDeployFileNode, 'Required', LDeployClass.Required);
        end;
      end;
    end;
  end;
  try
    LXMLString := LXML.XML.Text;
    TFile.WriteAllText(LDeployProjFileName, FormatXMLData(LXMLString.Substring(LXMLString.IndexOf('>') + 1)));
  except
    on E: Exception do
    begin
      WriteError(Format(sFileSaveException, [LDeployProjFileName, E.ClassName, E.Message]));
      Exit(4);
    end;
  end;
end;

end.
