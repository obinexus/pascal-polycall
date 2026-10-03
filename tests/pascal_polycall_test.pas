program PascalPolycallTest;

{ pascal-polycall tests against the REAL installed libpolycall (no mock).

    pascal_polycall_test <repo-root>

  Covers the checklist of the core's docs/BINDING_ABI.md through the unit
  (TThread for cancel/close/concurrent senders). Checks that need the C CLI
  read POLYCALL_CLI, POLYCALL_CLI_PEER, POLYCALL_RPC_ENDPOINT and
  POLYCALL_DEV_TOKEN (tests/run-real.sh); without them they print SKIP,
  never PASS. Exit code 1 on any FAIL. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, DateUtils, ctypes, PascalPolycall;

var
  Passed, Failed, Skipped: Integer;
  Root: string;

function libc_system(cmd: PAnsiChar): cint; cdecl; external 'c' name 'system';

procedure Check(OK: Boolean; const Name: string; const Detail: string = '');
begin
  if OK then
  begin
    Inc(Passed);
    WriteLn('PASS ', Name);
  end
  else
  begin
    Inc(Failed);
    if Detail <> '' then
      WriteLn('FAIL ', Name, ' -- ', Detail)
    else
      WriteLn('FAIL ', Name);
  end;
  Flush(Output);
end;

procedure Expect(Want, Got: LongInt; const Name: string);
begin
  Check(Want = Got, Name, Format('expected %d got %d (%s)', [Want, Got, PolycallStrError(Got)]));
end;

procedure Skip(const Name, Reason: string);
begin
  Inc(Skipped);
  WriteLn('SKIP ', Name, ' -- ', Reason);
end;

function Run(const Cmd: string): Integer;
begin
  Result := libc_system(PAnsiChar(Cmd));
end;

function Slurp(const Path: string): RawByteString;
var
  F: TFileStream;
begin
  Result := '';
  if not FileExists(Path) then
    Exit;
  F := TFileStream.Create(Path, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure WriteBytes(const Path: string; const Data: RawByteString);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    if Length(Data) > 0 then
      F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
end;

function Base64(const B: RawByteString): string;
const
  T = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  I, V, N: Integer;
begin
  Result := '';
  N := Length(B);
  I := 1;
  while I + 2 <= N do
  begin
    V := Ord(B[I]) shl 16 or Ord(B[I + 1]) shl 8 or Ord(B[I + 2]);
    Result := Result + T[(V shr 18) and 63 + 1] + T[(V shr 12) and 63 + 1] +
      T[(V shr 6) and 63 + 1] + T[V and 63 + 1];
    Inc(I, 3);
  end;
  if N - I + 1 = 1 then
  begin
    V := Ord(B[I]) shl 16;
    Result := Result + T[(V shr 18) and 63 + 1] + T[(V shr 12) and 63 + 1] + '==';
  end
  else if N - I + 1 = 2 then
  begin
    V := Ord(B[I]) shl 16 or Ord(B[I + 1]) shl 8;
    Result := Result + T[(V shr 18) and 63 + 1] + T[(V shr 12) and 63 + 1] +
      T[(V shr 6) and 63 + 1] + '=';
  end;
end;

{ ---------------------------------------------------------------------------- }

procedure TestVersion;
begin
  Check(PolycallABIVersion = 1, 'abi: PolycallABIVersion = 1');
  try
    PolycallCheckABI;
    Check(True, 'abi: PolycallCheckABI accepts the library');
  except
    on E: EPolycallError do
      Check(False, 'abi: PolycallCheckABI accepts the library', E.Message);
  end;
  Check((Copy(PolycallVersion, 1, 2) = '1.') and (PolycallVersion >= '1.1.0'),
    'version: library >= 1.1.0', PolycallVersion);
  Check(Pos('POLYCALL_E_TIMEOUT', PolycallStrError(POLYCALL_E_TIMEOUT)) = 1, 'strerror names E_TIMEOUT');
  Check(Pos('POLYCALL_E_UNKNOWN', PolycallStrError(-999)) = 1, 'strerror of an unknown code');
end;

{ Prefix + Bytes as a UTF8String, byte for byte (no code page conversion). }
function Utf8Path(const Prefix: string; const Bytes: RawByteString): UTF8String;
var
  R: RawByteString;
begin
  SetLength(R, Length(Prefix) + Length(Bytes));
  if Length(Prefix) > 0 then
    Move(Prefix[1], R[1], Length(Prefix));
  if Length(Bytes) > 0 then
    Move(Bytes[1], R[Length(Prefix) + 1], Length(Bytes));
  SetCodePage(R, CP_UTF8, False);
  Result := R;
end;

{ tests/fixtures/<U>: a valid configuration whose file name is not ASCII,
  passed to polycall_ffi_run_config as its UTF-8 bytes. }
procedure TestUnicodePath(const Fx: string);
const
  U: RawByteString = #$C3#$BC'n'#$C3#$AF'c'#$C3#$B8'd'#$C3#$A9'-'#$E9#$85#$8D#$E7#$BD#$AE'-polycallrc';
var
  P, Missing: UTF8String;
  D: RawByteString;
begin
  P := Utf8Path(Fx, U);
  Missing := Utf8Path(Fx + 'missing-', U);
  Expect(POLYCALL_OK, PolycallRunConfig(P), 'run_config: non-ASCII (UTF-8) path, strict');
  Expect(POLYCALL_OK, PolycallRunConfig(P, False), 'run_config: non-ASCII (UTF-8) path, validate');
  try
    Check(Pos('log_level', PolycallDescribe(P)) > 0, 'describe: non-ASCII (UTF-8) path');
  except
    on E: Exception do Check(False, 'describe: non-ASCII (UTF-8) path', E.Message);
  end;
  try
    PolycallRunConfigOrRaise(Missing);
    Check(False, 'run_config: missing non-ASCII path -> E_NOT_FOUND', 'no exception');
  except
    on E: EPolycallError do
    begin
      Expect(POLYCALL_E_NOT_FOUND, E.Status, 'run_config: missing non-ASCII path -> E_NOT_FOUND');
      D := E.Detail;
      Check(Pos(RawByteString('missing-') + U, D) > 0,
        'run_config: last_error detail keeps the UTF-8 path bytes', E.Detail);
    end;
  end;
end;

procedure TestRunConfig;
var
  Fx, Desc: string;
  Status: LongInt;
begin
  Fx := Root + '/tests/fixtures/';
  Expect(POLYCALL_OK, PolycallRunConfig(Root + '/pascal-polycallrc'), 'run_config: shipped pascal-polycallrc (run=1)');
  Expect(POLYCALL_OK, PolycallRunConfig(Root + '/pascal-polycallrc', False), 'run_config: valid, validate-only');
  Expect(POLYCALL_OK, PolycallRunConfig(Root + '/examples/pascal-polycallrc'), 'run_config: examples/pascal-polycallrc');
  try
    PolycallRunConfigOrRaise(Fx + 'does-not-exist');
    Check(False, 'run_config: missing -> E_NOT_FOUND', 'no exception');
  except
    on E: EPolycallError do
    begin
      Expect(POLYCALL_E_NOT_FOUND, E.Status, 'run_config: missing -> E_NOT_FOUND');
      Check((Pos('POLYCALL_E_NOT_FOUND', E.StatusName) = 1) and (Pos('does-not-exist', E.Detail) > 0),
        'EPolycallError carries status, name and last_error detail', E.Message);
    end;
  end;
  Expect(POLYCALL_E_CONFIG, PolycallRunConfig(Fx + 'invalid-polycallrc', False), 'run_config: malformed -> E_CONFIG (validate)');
  Expect(POLYCALL_E_CONFIG, PolycallRunConfig(Fx + 'invalid-polycallrc', True), 'run_config: malformed -> E_CONFIG (strict)');
  Expect(POLYCALL_OK, PolycallRunConfig(Fx + 'unknown-key-polycallrc', False), 'run_config: unknown key warns when validating');
  Expect(POLYCALL_E_CONFIG, PolycallRunConfig(Fx + 'unknown-key-polycallrc', True), 'run_config: unknown key fails when strict');
  Expect(POLYCALL_OK, PolycallRunConfig(Fx + 'tls-polycallrc', False), 'run_config: tls_enabled=true validates');
  Expect(POLYCALL_E_UNSUPPORTED, PolycallRunConfig(Fx + 'tls-polycallrc'), 'run_config: tls strict -> E_UNSUPPORTED');
  Expect(POLYCALL_E_INVALID_ARGUMENT, PolycallRunConfig(''), 'run_config: empty path');
  Status := 0;
  try
    PolycallRunConfigOrRaise(Fx + 'tls-polycallrc');
  except
    on E: EPolycallError do Status := E.Status;
  end;
  Expect(POLYCALL_E_UNSUPPORTED, Status, 'PolycallRunConfigOrRaise raises with the status');
  Desc := PolycallDescribe(Root + '/pascal-polycallrc');
  Check((Copy(Desc, 1, 1) = '{') and (Pos('log_level', Desc) > 0), 'describe: JSON', Desc);
  TestUnicodePath(Fx);
end;

procedure TestCall;
var
  Ep, Out1: string;
begin
  Expect(POLYCALL_E_TRANSPORT, PolycallCallStatus('127.0.0.1:1', 'debug', 'echo', '{}', 1500, Out1),
    'call: no runtime -> E_TRANSPORT');
  Expect(POLYCALL_E_INVALID_ARGUMENT, PolycallCallStatus('127.0.0.1:1', 'debug', 'echo', '{}', 0, Out1),
    'call: timeout 0 -> E_INVALID_ARGUMENT');
  Expect(POLYCALL_E_INVALID_ARGUMENT, PolycallCallStatus('127.0.0.1:1', 'debug', 'echo', '{}', 600001, Out1),
    'call: timeout 600001 -> E_INVALID_ARGUMENT');
  Ep := GetEnvironmentVariable('POLYCALL_RPC_ENDPOINT');
  if Ep = '' then
  begin
    Skip('call: success / unknown op / deadline / invalid input', 'POLYCALL_RPC_ENDPOINT not set (run via tests/run-real.sh)');
    Exit;
  end;
  Out1 := PolycallCall(Ep, 'inventory', 'get', '{"item_id":"widget-a"}', 3000);
  Check(Out1 = '{"item_id":"widget-a","quantity":42,"in_stock":true}', 'call: inventory.get exact output', Out1);
  Out1 := PolycallCall(Ep, 'debug', 'echo', '{"p":true}', 3000);
  Check(Out1 = '{"echo":{"p":true}}', 'call: debug.echo exact output', Out1);
  Check(PolycallCall(Ep, 'debug', 'echo') = '{"echo":null}', 'call: empty input is sent as null');
  Expect(POLYCALL_OK, PolycallCallStatus(Ep, 'debug', 'echo', '{}', 600000, Out1),
    'call: timeout 600000 (the maximum) accepted');
  Check(Out1 = '{"echo":{}}', 'call: timeout 600000 output', Out1);
  Expect(POLYCALL_E_NOT_FOUND, PolycallCallStatus(Ep, 'inventory', 'teleport', '{}', 3000, Out1),
    'call: unknown operation -> E_NOT_FOUND');
  Check(Pos('operation.unknown', Out1) > 0, 'call: unknown operation error object', Out1);
  try
    PolycallCall(Ep, 'inventory', 'get', '{"item_id":"nope"}', 3000);
    Check(False, 'call: unknown item -> E_REMOTE', 'no exception');
  except
    on E: EPolycallError do
      Check((E.Status = POLYCALL_E_REMOTE) and (Pos('item.unknown', E.Output) > 0),
        'call: unknown item -> E_REMOTE + error object on the exception', E.Output);
  end;
  Expect(POLYCALL_E_TIMEOUT, PolycallCallStatus(Ep, 'debug', 'sleep', '{"ms":3000}', 200, Out1),
    'call: deadline -> E_TIMEOUT');
  Expect(POLYCALL_E_INVALID_ARGUMENT, PolycallCallStatus(Ep, 'debug', 'echo', '{not json', 1000, Out1),
    'call: invalid input JSON -> E_INVALID_ARGUMENT');
end;

function StatusOf(E: Exception): LongInt;
begin
  if E is EPolycallError then
    Result := EPolycallError(E).Status
  else
    Result := 12345;
end;

procedure Exchange(From: TPolycallPeer; const FromId: string; ToPeer: TPolycallPeer;
  const Payload: RawByteString; const Mid, LabelText: string);
var
  M: TPolycallMessage;
begin
  try
    From.Send(ToPeer.Endpoint, Payload, Mid);
    M := ToPeer.Receive(5000);
    Check((M.Sender = FromId) and (M.Id = Mid) and (M.Payload = Payload), LabelText,
      Format('sender=%s id=%s len=%d', [M.Sender, M.Id, Length(M.Payload)]));
  except
    on E: Exception do
      Check(False, LabelText, E.Message);
  end;
end;

procedure TestPeers;
var
  A, B, S: TPolycallPeer;
  Mib, Bin, Utf8: RawByteString;
  M: TPolycallMessage;
  I, Status: LongInt;
  T0: TDateTime;
begin
  A := TPolycallPeer.Create('pas-a');
  B := TPolycallPeer.Create('pas-b', '127.0.0.1:0');
  try
    Check((Pos('127.0.0.1:', A.Endpoint) = 1) and (A.Endpoint <> '127.0.0.1:0'), 'peer: ephemeral endpoint', A.Endpoint);
    Check(A.NodeId = 'pas-a', 'peer: node_id');
    Check(Pos('"node_id":"pas-a"', A.Health) > 0, 'peer: health JSON', A.Health);
    Bin := #0#1#0#255#127#0#128;
    Utf8 := 'h'#$C3#$A9'llo '#$E2#$9C#$93;
    SetLength(Mib, PolycallMaxPayload + 1);
    for I := 1 to Length(Mib) do
      Mib[I] := AnsiChar(((I - 1) * 31 + 7) and 255);
    Exchange(A, 'pas-a', B, '', 'm-empty-ab', 'peer a->b: empty payload');
    Exchange(B, 'pas-b', A, '', 'm-empty-ba', 'peer b->a: empty payload');
    Exchange(A, 'pas-a', B, Utf8, 'm-utf8-ab', 'peer a->b: UTF-8');
    Exchange(B, 'pas-b', A, Utf8, 'm-utf8-ba', 'peer b->a: UTF-8');
    Exchange(A, 'pas-a', B, Bin, 'm-bin-ab', 'peer a->b: binary with NUL');
    Exchange(B, 'pas-b', A, Bin, 'm-bin-ba', 'peer b->a: binary with NUL');
    Exchange(A, 'pas-a', B, Copy(Mib, 1, PolycallMaxPayload), 'm-mib-ab', 'peer a->b: exactly 1 MiB');
    Exchange(B, 'pas-b', A, Copy(Mib, 1, PolycallMaxPayload), 'm-mib-ba', 'peer b->a: exactly 1 MiB');
    Status := 0;
    try
      A.Send(B.Endpoint, Mib, 'm-over');
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_TOO_LARGE, Status, 'peer: 1 MiB + 1 -> E_TOO_LARGE');
    Check(not B.TryReceive(M, 200), 'peer: oversize payload never delivered');

    { registry ownership }
    A.RegisterPeer('pas-b', B.Endpoint);
    Check(Pos('"pas-b":"' + B.Endpoint + '"', A.List) > 0, 'registry: register on a', A.List);
    Check(B.List = '{}', 'registry: b''s registry is its own (empty)', B.List);
    A.Send('pas-b', 'by-id', 'm-by-id');
    M := B.Receive(5000);
    Check((M.Payload = 'by-id') and (M.Sender = 'pas-a'), 'registry: send by registered id');
    Check(B.List = '{}', 'registry: receiving does not register the sender', B.List);
    try
      A.Ping('pas-b');
      A.Ping(B.Endpoint);
      Check(True, 'ping: registered id and host:port');
    except
      on E: Exception do Check(False, 'ping: registered id and host:port', E.Message);
    end;
    A.RegisterPeer('impostor', B.Endpoint);
    Status := 0;
    try
      A.Ping('impostor');
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_PROTOCOL, Status, 'ping: id answered by another node -> E_PROTOCOL');
    A.UnregisterPeer('impostor');
    Status := 0;
    try
      A.UnregisterPeer('impostor');
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_NOT_FOUND, Status, 'registry: unregister unknown -> E_NOT_FOUND');
    Status := 0;
    try
      A.RegisterPeer('bad id!', B.Endpoint);
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_INVALID_ARGUMENT, Status, 'registry: invalid id -> E_INVALID_ARGUMENT');

    { duplicate message id }
    A.Send(B.Endpoint, 'dup', 'm-dup');
    A.Send(B.Endpoint, 'dup', 'm-dup');
    M := B.Receive(5000);
    Check(M.Id = 'm-dup', 'duplicate: first copy delivered');
    Check(not B.TryReceive(M, 300), 'duplicate: second copy dropped');

    { generated id, timeout, too-small buffer }
    A.Send(B.Endpoint, 'gen');
    M := B.Receive(5000);
    Check((M.Id <> '') and (M.Payload = 'gen'), 'send: empty message id is generated', M.Id);
    T0 := Now;
    Status := 0;
    try
      B.Receive(150);
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_TIMEOUT, Status, 'recv: timeout -> E_TIMEOUT');
    Check(MilliSecondsBetween(Now, T0) >= 100, 'recv: waited for the timeout');
    A.Send(B.Endpoint, '0123456789', 'm-small');
    M := B.Receive(1000, 4);
    Check((M.Payload = '0123456789') and (M.Id = 'm-small'),
      'recv: 4-byte buffer -> E_TOO_LARGE kept the message queued (regrown)');
    A.Send(B.Endpoint, '0123456789', 'm-exact');
    M := B.Receive(1000, 10);
    Check((M.Payload = '0123456789') and (M.Id = 'm-exact'), 'recv: buffer of exactly the payload size');
    Check(not B.TryReceive(M, 0), 'recv: poll (timeout 0) on an empty inbox -> E_TIMEOUT');
    A.Send(B.Endpoint, 'queued', 'm-queued');
    Check(B.TryReceive(M, 0) and (M.Id = 'm-queued'), 'recv: poll (timeout 0) returns a queued message');
    A.Send(B.Endpoint, 'queued', 'm-queued-2');
    T0 := Now;
    M := B.Receive(PolycallWaitForever);
    Check((M.Id = 'm-queued-2') and (MilliSecondsBetween(Now, T0) < 2000),
      'recv: PolycallWaitForever (UINT32_MAX) returns a queued message at once');

    { identifiers: 1..63 bytes; the unit's buffers are 64 incl. NUL }
    S := TPolycallPeer.CreateSendOnly(StringOfChar('n', 63));
    try
      Check(S.NodeId = StringOfChar('n', 63), 'ids: 63-byte node id round-trips', S.NodeId);
      S.Send(B.Endpoint, 'id63', StringOfChar('m', 63));
      M := B.Receive(5000);
      Check((M.Sender = StringOfChar('n', 63)) and (M.Id = StringOfChar('m', 63)),
        'ids: 63-byte sender and message id arrive intact', M.Sender + ' / ' + M.Id);
    finally
      S.Free;
    end;
    Status := 0;
    try
      TPolycallPeer.CreateSendOnly(StringOfChar('n', 64)).Free;
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_INVALID_ARGUMENT, Status, 'ids: 64-byte node id -> E_INVALID_ARGUMENT');
    Status := 0;
    try
      A.Send(B.Endpoint, 'x', StringOfChar('m', 64));
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_INVALID_ARGUMENT, Status, 'ids: 64-byte message id -> E_INVALID_ARGUMENT');

    { send-only node }
    S := TPolycallPeer.CreateSendOnly('pas-sendonly');
    try
      Check(S.Endpoint = '', 'send-only: empty endpoint');
      S.Send(B.Endpoint, 'so', 'm-so');
      M := B.Receive(5000);
      Check(M.Sender = 'pas-sendonly', 'send-only: can send');
    finally
      S.Free;
    end;
  except
    on E: Exception do
      Check(False, 'peers: unexpected exception', E.Message);
  end;
  A.Free;
  B.Free;
end;

procedure TestAuthTransport;
var
  Sec, Anon, Wrong, Member, Gone: TPolycallPeer;
  Dead: string;
  Status: LongInt;
  M: TPolycallMessage;
begin
  Sec := TPolycallPeer.Create('pas-secured', '127.0.0.1:0', 'qa-secret-1');
  Anon := TPolycallPeer.CreateSendOnly('pas-anon');
  Wrong := TPolycallPeer.CreateSendOnly('pas-wrong', 'nope');
  Member := TPolycallPeer.CreateSendOnly('pas-member', 'qa-secret-1');
  try
    Status := 0;
    try
      Anon.Send(Sec.Endpoint, 'x', 'm-a1');
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_AUTH, Status, 'auth: no token -> E_AUTH');
    Status := 0;
    try
      Wrong.Send(Sec.Endpoint, 'x', 'm-a2');
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_AUTH, Status, 'auth: wrong token -> E_AUTH');
    Member.Send(Sec.Endpoint, 'x', 'm-a3');
    M := Sec.Receive(5000);
    Check(M.Sender = 'pas-member', 'auth: right token delivers');
    Status := 0;
    try
      TPolycallPeer.Create('pas-open', '0.0.0.0:0').Free;
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_CONFIG, Status, 'open: non-loopback without token -> E_CONFIG');
    Status := 0;
    try
      TPolycallPeer.Create('bad id').Free;
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_INVALID_ARGUMENT, Status, 'open: invalid node id');
    Gone := TPolycallPeer.Create('pas-gone');
    Dead := Gone.Endpoint;
    Gone.Free;
    Status := 0;
    try
      Member.Send(Dead, 'x', 'm-dead', 3000);
    except
      on E: Exception do Status := StatusOf(E);
    end;
    Expect(POLYCALL_E_TRANSPORT, Status, 'send to a dead peer -> E_TRANSPORT');
  finally
    Sec.Free;
    Anon.Free;
    Wrong.Free;
    Member.Free;
  end;
end;

type
  TBlockedReceiver = class(TThread)
  public
    Peer: TPolycallPeer;
    Status: LongInt;
    procedure Execute; override;
  end;

  TSenderThread = class(TThread)
  public
    Index: Integer;
    Target: string;
    Failures: Integer;
    procedure Execute; override;
  end;

  { One thread of concurrent calls: 20 debug.echo calls with distinct inputs
    (exact outputs) and an unknown operation (status + name), then 50 rounds
    of the string-returning calls on its own node. }
  TCallerThread = class(TThread)
  public
    Index: Integer;
    Rpc: string;
    CallWrong, NodeWrong: Integer;
    procedure Execute; override;
  end;

procedure TCallerThread.Execute;
var
  I: Integer;
  Input, Output, Name, Ep0: string;
  Node: TPolycallPeer;
begin
  CallWrong := 0;
  NodeWrong := 0;
  if Rpc <> '' then
  begin
    for I := 0 to 19 do
      try
        Input := Format('{"t":%d,"i":%d}', [Index, I]);
        if PolycallCall(Rpc, 'debug', 'echo', Input, 5000) <> '{"echo":' + Input + '}' then
          Inc(CallWrong);
      except
        on E: Exception do Inc(CallWrong);
      end;
    if PolycallCallStatus(Rpc, 'inventory', 'teleport', '{}', 5000, Output) <> POLYCALL_E_NOT_FOUND then
      Inc(CallWrong)
    else if Pos('operation.unknown', Output) = 0 then
      Inc(CallWrong);
    try
      PolycallCall(Rpc, 'inventory', 'teleport', '{}', 5000);
      Inc(CallWrong);
    except
      on E: EPolycallError do
        if (E.Status <> POLYCALL_E_NOT_FOUND) or (Pos('POLYCALL_E_NOT_FOUND', E.StatusName) <> 1) then
          Inc(CallWrong);
    end;
  end;
  Name := Format('pas-c%d', [Index]);
  try
    Node := TPolycallPeer.Create(Name);
    try
      Ep0 := Node.Endpoint;
      for I := 1 to 50 do
        if (Node.NodeId <> Name) or (Node.Endpoint <> Ep0) or
           (Pos('"node_id":"' + Name + '"', Node.Health) = 0) or (Node.List <> '{}') then
          Inc(NodeWrong);
    finally
      Node.Free;
    end;
  except
    on E: Exception do Inc(NodeWrong, 50);
  end;
end;

procedure TBlockedReceiver.Execute;
begin
  Status := 0;
  try
    Peer.Receive(PolycallWaitForever);
  except
    on E: Exception do Status := StatusOf(E);
  end;
end;

procedure TSenderThread.Execute;
var
  Tx: TPolycallPeer;
  I: Integer;
begin
  Failures := 0;
  try
    Tx := TPolycallPeer.CreateSendOnly('pas-tx' + IntToStr(Index));
    try
      for I := 0 to 24 do
        try
          Tx.Send(Target, Format('t%d-%d', [Index, I]), Format('m-%d-%d', [Index, I]), 10000);
        except
          on E: Exception do Inc(Failures);
        end;
    finally
      Tx.Free;
    end;
  except
    on E: Exception do Failures := 25;
  end;
end;

procedure TestThreads;
var
  R, Rx: TPolycallPeer;
  T: TBlockedReceiver;
  Senders: array[0..3] of TSenderThread;
  Callers: array[0..3] of TCallerThread;
  Calls, Nodes: Integer;
  Seen: TStringList;
  M: TPolycallMessage;
  I, Fails, Status: Integer;
begin
  R := TPolycallPeer.Create('pas-blocked');
  T := TBlockedReceiver.Create(True);
  T.Peer := R;
  T.Start;
  Sleep(300);
  R.Cancel;
  T.WaitFor;
  Expect(POLYCALL_E_CANCELLED, T.Status, 'cancel wakes a blocked Receive -> E_CANCELLED');
  T.Free;
  T := TBlockedReceiver.Create(True);
  T.Peer := R;
  T.Start;
  Sleep(300);
  R.Close;
  T.WaitFor;
  Expect(POLYCALL_E_CLOSED, T.Status, 'close wakes a blocked Receive -> E_CLOSED');
  T.Free;
  Status := 0;
  try
    R.Close;
  except
    on E: Exception do Status := StatusOf(E);
  end;
  Expect(POLYCALL_E_INVALID_HANDLE, Status, 'double close -> E_INVALID_HANDLE');
  Status := 0;
  try
    R.Endpoint;
  except
    on E: Exception do Status := StatusOf(E);
  end;
  Expect(POLYCALL_E_INVALID_HANDLE, Status, 'endpoint after close -> E_INVALID_HANDLE');
  Status := 0;
  try
    R.Send('127.0.0.1:1', 'x');
  except
    on E: Exception do Status := StatusOf(E);
  end;
  Expect(POLYCALL_E_INVALID_HANDLE, Status, 'send after close -> E_INVALID_HANDLE');
  Status := 0;
  try
    R.Receive(0);
  except
    on E: Exception do Status := StatusOf(E);
  end;
  Expect(POLYCALL_E_INVALID_HANDLE, Status, 'recv after close -> E_INVALID_HANDLE');
  R.Free;

  Rx := TPolycallPeer.Create('pas-rx');
  Seen := TStringList.Create;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  try
    for I := 0 to 3 do
    begin
      Senders[I] := TSenderThread.Create(True);
      Senders[I].Index := I;
      Senders[I].Target := Rx.Endpoint;
      Senders[I].Start;
    end;
    for I := 1 to 100 do
    begin
      if not Rx.TryReceive(M, 10000) then
        Break;
      Seen.Add(M.Sender + '/' + M.Id);
    end;
    Fails := 0;
    for I := 0 to 3 do
    begin
      Senders[I].WaitFor;
      Inc(Fails, Senders[I].Failures);
      Senders[I].Free;
    end;
    Check((Seen.Count = 100) and (Fails = 0), 'concurrent senders: 4 threads x 25, all delivered once',
      Format('%d unique, %d failures', [Seen.Count, Fails]));
  finally
    Seen.Free;
    Rx.Free;
  end;

  Calls := 0;
  Nodes := 0;
  for I := 0 to 3 do
  begin
    Callers[I] := TCallerThread.Create(True);
    Callers[I].Index := I;
    Callers[I].Rpc := GetEnvironmentVariable('POLYCALL_RPC_ENDPOINT');
    Callers[I].Start;
  end;
  for I := 0 to 3 do
  begin
    Callers[I].WaitFor;
    Inc(Calls, Callers[I].CallWrong);
    Inc(Nodes, Callers[I].NodeWrong);
    Callers[I].Free;
  end;
  if GetEnvironmentVariable('POLYCALL_RPC_ENDPOINT') = '' then
    Skip('concurrent calls: 4 threads x 20 PolycallCall, exact outputs and errors',
      'POLYCALL_RPC_ENDPOINT not set (run via tests/run-real.sh)')
  else
    Check(Calls = 0, 'concurrent calls: 4 threads x 20 PolycallCall, exact outputs and errors',
      Format('%d wrong', [Calls]));
  Check(Nodes = 0, 'concurrent node calls: 4 threads x 50 NodeId/Endpoint/Health/List',
    Format('%d wrong', [Nodes]));
end;

procedure TestInterop;
var
  Cli, CliPeer: string;
  Node: TPolycallPeer;
  Payload, Got: RawByteString;
  M: TPolycallMessage;
  Rc: Integer;
begin
  Cli := GetEnvironmentVariable('POLYCALL_CLI');
  CliPeer := GetEnvironmentVariable('POLYCALL_CLI_PEER');
  if (Cli = '') or (CliPeer = '') then
  begin
    Skip('interop: polycall CLI peer -> Pascal', 'POLYCALL_CLI/POLYCALL_CLI_PEER not set');
    Skip('interop: Pascal -> polycall CLI peer', 'POLYCALL_CLI/POLYCALL_CLI_PEER not set');
    Exit;
  end;
  Payload := 'pas'#0'bin'#1#255' '#$C3#$A9' end';
  Node := TPolycallPeer.Create('pas-node', '127.0.0.1:0', GetEnvironmentVariable('POLYCALL_DEV_TOKEN'));
  try
    WriteBytes('pas_cli_payload.bin', Payload);
    Rc := Run('"' + Cli + '" peer send --to ' + Node.Endpoint +
      ' --payload-file pas_cli_payload.bin --from cli-node --id cli-to-pas-1 -t 5000 > pas_cli_send.log 2>&1');
    try
      M := Node.Receive(5000);
      Check((Rc = 0) and (M.Sender = 'cli-node') and (M.Id = 'cli-to-pas-1') and (M.Payload = Payload),
        'interop: polycall CLI peer send -> Pascal peer (bytes, sender, id)');
    except
      on E: Exception do
        Check(False, 'interop: polycall CLI peer send -> Pascal peer (bytes, sender, id)',
          Format('rc=%d %s %s', [Rc, E.Message, Slurp('pas_cli_send.log')]));
    end;
    Node.RegisterPeer('cli-node', CliPeer);
    try
      Node.Ping('cli-node');
      Check(True, 'interop: ping the CLI node by id');
      Node.Send('cli-node', Payload, 'pas-to-cli-1');
      Rc := Run('"' + Cli + '" --format json peer recv --to ' + CliPeer + ' -t 5000 > pas_cli_recv.json 2>&1');
      Got := Slurp('pas_cli_recv.json');
      Check((Rc = 0) and (Pos('"from":"pas-node"', Got) > 0) and (Pos('"id":"pas-to-cli-1"', Got) > 0) and
        (Pos('"payload_b64":"' + Base64(Payload) + '"', Got) > 0),
        'interop: Pascal peer -> polycall peer serve, read by polycall peer recv', Got);
    except
      on E: Exception do Check(False, 'interop: Pascal peer -> polycall CLI peer', E.Message);
    end;
    DeleteFile('pas_cli_payload.bin');
    DeleteFile('pas_cli_send.log');
    DeleteFile('pas_cli_recv.json');
  finally
    Node.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  Skipped := 0;
  if ParamCount > 0 then
    Root := ParamStr(1)
  else
    Root := '.';
  WriteLn('pascal-polycall real-core tests: libpolycall ', PolycallVersion, ', ABI ', PolycallABIVersion);
  TestVersion;
  TestRunConfig;
  TestCall;
  TestPeers;
  TestAuthTransport;
  TestThreads;
  TestInterop;
  WriteLn(Format('SUMMARY pass=%d fail=%d skip=%d', [Passed, Failed, Skipped]));
  if Failed > 0 then
    Halt(1);
end.
