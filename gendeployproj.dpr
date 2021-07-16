program gendeployproj;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, System.IOUtils,
  GDP.DeployProjCreator;

var
  LAppName: string;
  LOverwrite: Boolean;
  LFileName: string;

procedure ShowUsage;
begin
  Writeln(Format('%s generates a .deployproj from a .dproj file', [LAppName]));
  Writeln;
  Writeln(Format('Usage: %s <DprojFileName> [0|1]', [LAppName]));
  Writeln;
  Writeln('e.g.: gendeployproj C:\Projects\MyProject\MyProject.dproj 1');
  Writeln;
  Writeln('<DprojFileName> is the .dproj file for the project');
  Writeln('[0|1] is an optional flag to indicate whether or not to overwrite the .deployproj if it exists. 0 (do not overwrite) is the default');
  Writeln(Format('  If the .deployproj exists and 0 is specified, %s does nothing', [LAppName]));
  Writeln;
  Writeln('If successful, the .deployproj file is created in the same folder as the .dproj');
  ExitCode := -1;
end;

begin
  LAppName := TPath.GetFileNameWithoutExtension(ParamStr(0));
  if ParamCount > 0 then
  begin
    LOverwrite := False;
    LFileName := ParamStr(1);
    if ParamCount > 1 then
     LOverwrite := ParamStr(2) = '1';
    try
      ExitCode := TDeployProjCreator.CreateDeployProj(LFileName, LOverwrite);
    except
      on E: Exception do
      begin
        Writeln(Format('%s caused an unhandled exception - %s: %s', [LAppName, E.ClassName, E.Message]));
        ExitCode := MaxInt;
      end;
    end;
  end
  else
    ShowUsage;
end.
