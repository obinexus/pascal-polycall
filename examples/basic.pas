program PascalPolycallExample;

{$mode objfpc}{$H+}

uses
  PascalPolycall;

var
  ConfigPath: UTF8String;

begin
  if ParamCount > 0 then
    ConfigPath := ParamStr(1)
  else
    ConfigPath := 'pascal-polycallrc';

  PolycallRunConfigOrRaise(ConfigPath);
  WriteLn('libpolycall completed successfully');
end.
