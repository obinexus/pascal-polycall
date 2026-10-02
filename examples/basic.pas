program PascalPolycallExample;

{$mode objfpc}{$H+}

uses
  SysUtils, PascalPolycall;

var
  ConfigPath: UTF8String;

begin
  if ParamCount > 0 then
    ConfigPath := ParamStr(1)
  else
    ConfigPath := 'pascal-polycallrc';

  try
    PolycallCheckABI;
    WriteLn('pascal-polycall: libpolycall ', PolycallVersion);
    PolycallRunConfigOrRaise(ConfigPath);
    WriteLn('pascal-polycall: ''', ConfigPath, ''' is valid for this build');
  except
    on E: EPolycallError do
    begin
      WriteLn(StdErr, 'pascal-polycall: ', E.Message);
      Halt(1);
    end;
  end;
end.
