unit PascalPolycall;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  PolycallDefaultConfig = 'pascal-polycallrc';

type
  EPolycallError = class(Exception)
  private
    FStatus: LongInt;
  public
    constructor Create(AStatus: LongInt);
    property Status: LongInt read FStatus;
  end;

function PolycallRunConfig(
  const ConfigPath: UTF8String = PolycallDefaultConfig
): LongInt;

procedure PolycallRunConfigOrRaise(
  const ConfigPath: UTF8String = PolycallDefaultConfig
);

implementation

function pascal_polycall_run_config(ConfigPath: PAnsiChar): LongInt;
  cdecl; external name 'pascal_polycall_run_config';

constructor EPolycallError.Create(AStatus: LongInt);
begin
  FStatus := AStatus;
  inherited CreateFmt('libpolycall failed with status %d', [AStatus]);
end;

function PolycallRunConfig(const ConfigPath: UTF8String): LongInt;
var
  StablePath: UTF8String;
begin
  StablePath := ConfigPath;
  Result := pascal_polycall_run_config(PAnsiChar(StablePath));
end;

procedure PolycallRunConfigOrRaise(const ConfigPath: UTF8String);
var
  Status: LongInt;
begin
  Status := PolycallRunConfig(ConfigPath);
  if Status <> 0 then
    raise EPolycallError.Create(Status);
end;

end.
