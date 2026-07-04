program PascalPolycallSmoke;

{$mode objfpc}{$H+}

uses
  PascalPolycall;

var
  Status: LongInt;
  RaisedExpectedError: Boolean;

begin
  Status := PolycallRunConfig('explicit-polycallrc');
  if Status <> 0 then
    Halt(1);

  Status := PolycallRunConfig;
  if Status <> 0 then
    Halt(2);

  Status := PolycallRunConfig('__status_37__');
  if Status <> 37 then
    Halt(3);

  RaisedExpectedError := False;
  try
    PolycallRunConfigOrRaise('__status_37__');
  except
    on Error: EPolycallError do
    begin
      if Error.Status <> 37 then
        Halt(4);
      RaisedExpectedError := True;
    end;
  end;

  if not RaisedExpectedError then
    Halt(5);

  WriteLn('pascal-polycall Free Pascal smoke test: PASS');
end.
