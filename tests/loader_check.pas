program LoaderCheck;

{ Loader check for tests/loader-errors.sh: what a Free Pascal program sees
  from the library it was started with. Prints one line per step:

    loader-check: abi=<n>
    loader-check: check_abi=<status> <message>
    loader-check: run_config=<status>
    loader-check: call=<status>   (127.0.0.1:1: E_TRANSPORT with the real core)
    loader-check: peer_open=<status> <message>

  Run from the repository root (it validates ./pascal-polycallrc). }

{$mode objfpc}{$H+}

uses
  SysUtils, PascalPolycall;

var
  Output: string;
  Peer: TPolycallPeer;
begin
  WriteLn('loader-check: abi=', PolycallABIVersion);
  try
    PolycallCheckABI;
    WriteLn('loader-check: check_abi=0 OK');
  except
    on E: EPolycallError do
      WriteLn('loader-check: check_abi=', E.Status, ' ', E.Message);
  end;
  WriteLn('loader-check: run_config=', PolycallRunConfig('pascal-polycallrc'));
  WriteLn('loader-check: call=',
    PolycallCallStatus('127.0.0.1:1', 'debug', 'echo', '{}', 1000, Output));
  try
    Peer := TPolycallPeer.Create('loader-check');
    Peer.Free;
    WriteLn('loader-check: peer_open=0 OK');
  except
    on E: EPolycallError do
      WriteLn('loader-check: peer_open=', E.Status, ' ', E.Message);
  end;
end.
