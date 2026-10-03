unit PascalPolycall;

{ Free Pascal binding for the Polycall binding ABI v1 (<polycall.h>,
  polycall >= 1.1.0; docs/BINDING_ABI.md in
  https://github.com/obinexus/polycall).

  The C functions are declared as cdecl externals of the core library with
  their exact signatures (ctypes): no C shim, no parser, no socket code.
  Failures raise EPolycallError carrying the status, its name
  (polycall_strerror) and the core's detail (polycall_last_error). }

{$mode objfpc}{$H+}

{$IFDEF UNIX}
  { libpolycall is a C library: start the program through libc. }
  {$LINKLIB c}
{$ENDIF}

interface

uses
  SysUtils, ctypes;

const
  PolycallDefaultConfig = 'pascal-polycallrc';
  PolycallExpectedABI = 1;
  PolycallMaxPayload = 1 shl 20;      { POLYCALL_PEER_MAX_PAYLOAD }
  PolycallMaxCallOutput = 1 shl 20;   { POLYCALL_CALL_MAX_OUTPUT }
  PolycallWaitForever = High(cuint32);

  POLYCALL_OK = 0;
  POLYCALL_E_INVALID_ARGUMENT = -1;
  POLYCALL_E_NO_MEMORY = -2;
  POLYCALL_E_INVALID_HANDLE = -3;
  POLYCALL_E_TIMEOUT = -4;
  POLYCALL_E_TRANSPORT = -5;
  POLYCALL_E_PROTOCOL = -6;
  POLYCALL_E_NOT_FOUND = -7;
  POLYCALL_E_AUTH = -8;
  POLYCALL_E_REMOTE = -9;
  POLYCALL_E_TOO_LARGE = -10;
  POLYCALL_E_BUSY = -11;
  POLYCALL_E_CANCELLED = -12;
  POLYCALL_E_CONFIG = -13;
  POLYCALL_E_ADDRESS_IN_USE = -14;
  POLYCALL_E_UNSUPPORTED = -15;
  POLYCALL_E_PERMISSION = -16;
  POLYCALL_E_CLOSED = -17;
  POLYCALL_E_INTERNAL = -18;

type
  TPolycallPeerHandle = cint32;

  EPolycallError = class(Exception)
  private
    FStatus: LongInt;
    FStatusName: string;
    FDetail: string;
    FOutput: string;
  public
    { Reads polycall_strerror / polycall_last_error of the calling thread. }
    constructor Create(AStatus: LongInt);
    constructor CreateFor(AStatus: LongInt; const AContext: string;
      const AOutput: string = '');
    property Status: LongInt read FStatus;
    property StatusName: string read FStatusName;
    property Detail: string read FDetail;
    // PolycallCall: the remote error object {"code":..,"message":..}.
    property Output: string read FOutput;
  end;

  TPolycallMessage = record
    Sender: string;
    Id: string;
    Payload: RawByteString;   { exact bytes, may contain #0 }
  end;

  { One peer node. Free closes it; Close asks the core every time, so a
    second Close raises POLYCALL_E_INVALID_HANDLE, as does any call on a
    closed node. }
  TPolycallPeer = class
  private
    FHandle: TPolycallPeerHandle;
    FOpen: Boolean;
    procedure DoOpen(const ANodeId: string; ABind: PAnsiChar; const AuthToken: string);
  public
    constructor Create(const ANodeId: string;
      const BindEndpoint: string = '127.0.0.1:0'; const AuthToken: string = '');
    constructor CreateSendOnly(const ANodeId: string; const AuthToken: string = '');
    destructor Destroy; override;
    procedure Close;
    function Endpoint: string;
    function NodeId: string;
    procedure RegisterPeer(const PeerId, PeerEndpoint: string);
    procedure UnregisterPeer(const PeerId: string);
    function List: string;
    procedure Ping(const Target: string; TimeoutMs: cuint32 = 3000);
    procedure Send(const Target: string; const Payload: RawByteString;
      const MessageId: string = ''; TimeoutMs: cuint32 = 5000);
    { Raises EPolycallError (POLYCALL_E_TIMEOUT) when nothing arrived. A
      too-small buffer is grown and the call retried: the core keeps the
      message queued on POLYCALL_E_TOO_LARGE. }
    function Receive(TimeoutMs: cuint32 = PolycallWaitForever;
      InitialCapacity: SizeInt = 65536): TPolycallMessage;
    function TryReceive(out Msg: TPolycallMessage; TimeoutMs: cuint32 = 0): Boolean;
    procedure Cancel;
    function Health: string;
    property Handle: TPolycallPeerHandle read FHandle;
    property IsOpen: Boolean read FOpen;
  end;

function PolycallABIVersion: LongInt;
function PolycallVersion: string;
function PolycallStrError(Status: LongInt): string;
function PolycallLastError: string;
procedure PolycallCheckABI;

{ Historical entry point: polycall_ffi_run_config(ConfigPath, 1); the status
  is returned unchanged. }
function PolycallRunConfig(
  const ConfigPath: UTF8String = PolycallDefaultConfig
): LongInt; overload;
{ Strict = False validates only (unknown keys are warnings). }
function PolycallRunConfig(const ConfigPath: UTF8String; Strict: Boolean): LongInt; overload;
procedure PolycallRunConfigOrRaise(
  const ConfigPath: UTF8String = PolycallDefaultConfig;
  Strict: Boolean = True
);
function PolycallDescribe(const ConfigPath: UTF8String): string;

{ One polycall_rpc v1 round trip (never retried). InputJson '' = null. }
function PolycallCall(const Endpoint, Service, Operation: string;
  const InputJson: string = ''; TimeoutMs: cuint32 = 5000): string;
{ Non-raising form: Output is the result JSON or the remote error object;
  a library not speaking binding ABI 1 gives POLYCALL_E_UNSUPPORTED. }
function PolycallCallStatus(const Endpoint, Service, Operation, InputJson: string;
  TimeoutMs: cuint32; out Output: string): LongInt;

implementation

const
{$IFDEF MSWINDOWS}
  {$IFDEF POLYCALL_MINGW}
  PolycallLib = 'libpolycall.dll';
  {$ELSE}
  PolycallLib = 'polycall.dll';
  {$ENDIF}
{$ELSE}
  PolycallLib = 'polycall';
{$ENDIF}

type
  pcint32 = ^cint32;

{ ---- binding ABI v1 (exact <polycall.h> signatures) ---------------------- }

function c_abi_version: cint; cdecl; external PolycallLib name 'polycall_ffi_abi_version';
function c_version(buf: PAnsiChar; len: cint): cint; cdecl;
  external PolycallLib name 'polycall_ffi_version';
function c_strerror(status: cint): PAnsiChar; cdecl; external PolycallLib name 'polycall_strerror';
function c_last_error(buf: PAnsiChar; cap: csize_t): cint; cdecl;
  external PolycallLib name 'polycall_last_error';
function c_run_config(path: PAnsiChar; run: cint): cint; cdecl;
  external PolycallLib name 'polycall_ffi_run_config';
function c_describe(path: PAnsiChar; buf: PAnsiChar; len: cint): cint; cdecl;
  external PolycallLib name 'polycall_ffi_describe';
function c_call(endpoint, service, operation, input: PAnsiChar; timeout_ms: cuint32;
  output: PAnsiChar; output_cap: csize_t; output_len: pcsize_t): cint; cdecl;
  external PolycallLib name 'polycall_call';
function c_peer_open(node_id, bind_endpoint, auth_token: PAnsiChar;
  out_handle: pcint32): cint; cdecl; external PolycallLib name 'polycall_peer_open';
function c_peer_close(h: cint32): cint; cdecl; external PolycallLib name 'polycall_peer_close';
function c_peer_endpoint(h: cint32; buf: PAnsiChar; cap: csize_t): cint; cdecl;
  external PolycallLib name 'polycall_peer_endpoint';
function c_peer_node_id(h: cint32; buf: PAnsiChar; cap: csize_t): cint; cdecl;
  external PolycallLib name 'polycall_peer_node_id';
function c_peer_register(h: cint32; peer_id, endpoint: PAnsiChar): cint; cdecl;
  external PolycallLib name 'polycall_peer_register';
function c_peer_unregister(h: cint32; peer_id: PAnsiChar): cint; cdecl;
  external PolycallLib name 'polycall_peer_unregister';
function c_peer_list(h: cint32; buf: PAnsiChar; cap: csize_t; out_len: pcsize_t): cint; cdecl;
  external PolycallLib name 'polycall_peer_list';
function c_peer_ping(h: cint32; peer: PAnsiChar; timeout_ms: cuint32): cint; cdecl;
  external PolycallLib name 'polycall_peer_ping';
function c_peer_send(h: cint32; peer: PAnsiChar; payload: Pointer; len: csize_t;
  message_id: PAnsiChar; timeout_ms: cuint32): cint; cdecl;
  external PolycallLib name 'polycall_peer_send';
function c_peer_recv(h: cint32; timeout_ms: cuint32; sender: PAnsiChar; sender_cap: csize_t;
  message_id: PAnsiChar; message_id_cap: csize_t; payload: Pointer; payload_cap: csize_t;
  payload_len: pcsize_t): cint; cdecl; external PolycallLib name 'polycall_peer_recv';
function c_peer_cancel(h: cint32): cint; cdecl; external PolycallLib name 'polycall_peer_cancel';
function c_peer_health(h: cint32; buf: PAnsiChar; cap: csize_t; out_len: pcsize_t): cint; cdecl;
  external PolycallLib name 'polycall_peer_health';

{ ---- helpers --------------------------------------------------------------- }

function OptPChar(const S: string): PAnsiChar;
begin
  if S = '' then
    Result := nil
  else
    Result := PAnsiChar(S);
end;

procedure Check(Status: cint; const Context: string);
begin
  if Status <> POLYCALL_OK then
    raise EPolycallError.CreateFor(Status, Context);
end;

procedure RequireABI;
begin
  if c_abi_version <> PolycallExpectedABI then
    PolycallCheckABI;
end;

{ ---- EPolycallError -------------------------------------------------------- }

constructor EPolycallError.Create(AStatus: LongInt);
begin
  CreateFor(AStatus, '');
end;

constructor EPolycallError.CreateFor(AStatus: LongInt; const AContext: string;
  const AOutput: string);
var
  Msg: string;
begin
  { polycall_last_error is per thread: read it first. }
  FDetail := PolycallLastError;
  FStatus := AStatus;
  FStatusName := PolycallStrError(AStatus);
  FOutput := AOutput;
  Msg := Format('libpolycall failed with status %d: %s', [AStatus, FStatusName]);
  if FDetail <> '' then
    Msg := Msg + ' (' + FDetail + ')';
  if AContext <> '' then
    Msg := AContext + ': ' + Msg;
  inherited Create(Msg);
end;

{ ---- library --------------------------------------------------------------- }

function PolycallABIVersion: LongInt;
begin
  Result := c_abi_version;
end;

function PolycallVersion: string;
var
  Buf: array[0..63] of AnsiChar;
begin
  Buf[0] := #0;
  if c_version(@Buf[0], SizeOf(Buf)) < 0 then
    Exit('');
  Result := StrPas(PAnsiChar(@Buf[0]));
end;

function PolycallStrError(Status: LongInt): string;
begin
  Result := StrPas(c_strerror(Status));
end;

function PolycallLastError: string;
var
  Buf: array[0..2047] of AnsiChar;
begin
  Buf[0] := #0;
  if c_last_error(@Buf[0], SizeOf(Buf)) < 0 then
    Exit('');
  Result := StrPas(PAnsiChar(@Buf[0]));
end;

procedure PolycallCheckABI;
var
  Got: LongInt;
  E: EPolycallError;
begin
  Got := c_abi_version;
  if Got <> PolycallExpectedABI then
  begin
    E := EPolycallError.CreateFor(POLYCALL_E_UNSUPPORTED, 'PolycallCheckABI');
    E.FDetail := Format('libpolycall reports binding ABI %d, pascal-polycall requires ABI %d',
      [Got, PolycallExpectedABI]);
    E.Message := Format('PolycallCheckABI: %s (%s)', [E.StatusName, E.FDetail]);
    raise E;
  end;
end;

{ ---- configuration --------------------------------------------------------- }

function PolycallRunConfig(const ConfigPath: UTF8String): LongInt;
begin
  Result := PolycallRunConfig(ConfigPath, True);
end;

function PolycallRunConfig(const ConfigPath: UTF8String; Strict: Boolean): LongInt;
var
  StablePath: UTF8String;
begin
  if c_abi_version <> PolycallExpectedABI then
    Exit(POLYCALL_E_UNSUPPORTED);
  StablePath := ConfigPath;
  Result := c_run_config(PAnsiChar(StablePath), Ord(Strict));
end;

procedure PolycallRunConfigOrRaise(const ConfigPath: UTF8String; Strict: Boolean);
var
  StablePath: UTF8String;
  Status: cint;
begin
  RequireABI;
  StablePath := ConfigPath;
  Status := c_run_config(PAnsiChar(StablePath), Ord(Strict));
  if Status <> 0 then
    raise EPolycallError.CreateFor(Status, 'PolycallRunConfig(''' + ConfigPath + ''')');
end;

function PolycallDescribe(const ConfigPath: UTF8String): string;
var
  Buf: RawByteString;
  N: cint;
  Attempt: Integer;
begin
  RequireABI;
  SetLength(Buf, 16384);
  for Attempt := 1 to 4 do
  begin
    N := c_describe(PAnsiChar(ConfigPath), PAnsiChar(Buf), Length(Buf));
    if N < 0 then
      raise EPolycallError.CreateFor(N, 'PolycallDescribe(''' + ConfigPath + ''')');
    if N < Length(Buf) then
      Exit(Copy(Buf, 1, N));
    SetLength(Buf, N + 1);
  end;
  raise EPolycallError.CreateFor(POLYCALL_E_TOO_LARGE, 'PolycallDescribe');
end;

{ ---- RPC ------------------------------------------------------------------- }

function PolycallCallStatus(const Endpoint, Service, Operation, InputJson: string;
  TimeoutMs: cuint32; out Output: string): LongInt;
var
  Buf: RawByteString;
  Len: csize_t;
begin
  if c_abi_version <> PolycallExpectedABI then
  begin
    Output := '';   { non-raising form: report, do not raise }
    Exit(POLYCALL_E_UNSUPPORTED);
  end;
  SetLength(Buf, PolycallMaxCallOutput + 1);
  Buf[1] := #0;
  Len := 0;
  Result := c_call(PAnsiChar(Endpoint), PAnsiChar(Service), PAnsiChar(Operation),
    OptPChar(InputJson), TimeoutMs, PAnsiChar(Buf), Length(Buf), @Len);
  if Result = POLYCALL_OK then
    Output := Copy(Buf, 1, Len)
  else
    Output := StrPas(PAnsiChar(Buf));
end;

function PolycallCall(const Endpoint, Service, Operation: string;
  const InputJson: string; TimeoutMs: cuint32): string;
var
  Status: LongInt;
  Output: string;
begin
  RequireABI;   { raises EPolycallError naming the ABI it found }
  Status := PolycallCallStatus(Endpoint, Service, Operation, InputJson, TimeoutMs, Output);
  if Status <> POLYCALL_OK then
    raise EPolycallError.CreateFor(Status,
      'PolycallCall(' + Service + '.' + Operation + ' @ ' + Endpoint + ')', Output);
  Result := Output;
end;

{ ---- TPolycallPeer --------------------------------------------------------- }

procedure TPolycallPeer.DoOpen(const ANodeId: string; ABind: PAnsiChar; const AuthToken: string);
var
  H: cint32;
begin
  RequireABI;
  H := 0;
  Check(c_peer_open(PAnsiChar(ANodeId), ABind, OptPChar(AuthToken), @H),
    'TPolycallPeer(''' + ANodeId + ''')');
  FHandle := H;
  FOpen := True;
end;

constructor TPolycallPeer.Create(const ANodeId: string; const BindEndpoint: string;
  const AuthToken: string);
begin
  inherited Create;
  DoOpen(ANodeId, PAnsiChar(BindEndpoint), AuthToken);
end;

constructor TPolycallPeer.CreateSendOnly(const ANodeId: string; const AuthToken: string);
begin
  inherited Create;
  DoOpen(ANodeId, nil, AuthToken);
end;

destructor TPolycallPeer.Destroy;
begin
  if FOpen then
    c_peer_close(FHandle);
  FOpen := False;
  inherited Destroy;
end;

procedure TPolycallPeer.Close;
var
  Status: cint;
begin
  Status := c_peer_close(FHandle);
  FOpen := False;
  Check(Status, 'TPolycallPeer.Close');
end;

function TPolycallPeer.Endpoint: string;
var
  Buf: array[0..255] of AnsiChar;
begin
  Buf[0] := #0;
  Check(c_peer_endpoint(FHandle, @Buf[0], SizeOf(Buf)), 'TPolycallPeer.Endpoint');
  Result := StrPas(PAnsiChar(@Buf[0]));
end;

function TPolycallPeer.NodeId: string;
var
  Buf: array[0..63] of AnsiChar;
begin
  Buf[0] := #0;
  Check(c_peer_node_id(FHandle, @Buf[0], SizeOf(Buf)), 'TPolycallPeer.NodeId');
  Result := StrPas(PAnsiChar(@Buf[0]));
end;

procedure TPolycallPeer.RegisterPeer(const PeerId, PeerEndpoint: string);
begin
  Check(c_peer_register(FHandle, PAnsiChar(PeerId), PAnsiChar(PeerEndpoint)),
    'TPolycallPeer.RegisterPeer(''' + PeerId + ''')');
end;

procedure TPolycallPeer.UnregisterPeer(const PeerId: string);
begin
  Check(c_peer_unregister(FHandle, PAnsiChar(PeerId)),
    'TPolycallPeer.UnregisterPeer(''' + PeerId + ''')');
end;

type
  TJsonGetter = function(h: cint32; buf: PAnsiChar; cap: csize_t; out_len: pcsize_t): cint; cdecl;

function ReadJson(H: cint32; Get: TJsonGetter; const Context: string): string;
var
  Buf: RawByteString;
  Needed: csize_t;
  Status: cint;
  Attempt: Integer;
begin
  SetLength(Buf, 4096);
  for Attempt := 1 to 4 do
  begin
    Needed := 0;
    Status := Get(H, PAnsiChar(Buf), Length(Buf), @Needed);
    if (Status = POLYCALL_E_TOO_LARGE) and (Needed >= csize_t(Length(Buf))) then
    begin
      SetLength(Buf, Needed + 1);
      Continue;
    end;
    Check(Status, Context);
    Exit(Copy(Buf, 1, Needed));
  end;
  raise EPolycallError.CreateFor(POLYCALL_E_TOO_LARGE, Context);
end;

function TPolycallPeer.List: string;
begin
  Result := ReadJson(FHandle, @c_peer_list, 'TPolycallPeer.List');
end;

function TPolycallPeer.Health: string;
begin
  Result := ReadJson(FHandle, @c_peer_health, 'TPolycallPeer.Health');
end;

procedure TPolycallPeer.Ping(const Target: string; TimeoutMs: cuint32);
begin
  Check(c_peer_ping(FHandle, PAnsiChar(Target), TimeoutMs),
    'TPolycallPeer.Ping(''' + Target + ''')');
end;

procedure TPolycallPeer.Send(const Target: string; const Payload: RawByteString;
  const MessageId: string; TimeoutMs: cuint32);
const
  Empty: AnsiChar = #0;
var
  P: Pointer;
begin
  if Length(Payload) = 0 then
    P := @Empty
  else
    P := Pointer(Payload);
  Check(c_peer_send(FHandle, PAnsiChar(Target), P, Length(Payload), OptPChar(MessageId),
    TimeoutMs), 'TPolycallPeer.Send(''' + Target + ''')');
end;

function TPolycallPeer.TryReceive(out Msg: TPolycallMessage; TimeoutMs: cuint32): Boolean;
var
  Sender, Id: array[0..63] of AnsiChar;
  Buf: RawByteString;
  Len: csize_t;
  Status: cint;
begin
  SetLength(Buf, 65536);
  repeat
    Sender[0] := #0;
    Id[0] := #0;
    Len := 0;
    Status := c_peer_recv(FHandle, TimeoutMs, @Sender[0], SizeOf(Sender), @Id[0], SizeOf(Id),
      Pointer(Buf), Length(Buf), @Len);
    if (Status = POLYCALL_E_TOO_LARGE) and (Len > csize_t(Length(Buf))) then
      SetLength(Buf, Len)   { message stays queued: retry with room for it }
    else
      Break;
  until False;
  if Status = POLYCALL_E_TIMEOUT then
    Exit(False);
  Check(Status, 'TPolycallPeer.Receive');
  Msg.Sender := StrPas(PAnsiChar(@Sender[0]));
  Msg.Id := StrPas(PAnsiChar(@Id[0]));
  Msg.Payload := Copy(Buf, 1, Len);
  Result := True;
end;

function TPolycallPeer.Receive(TimeoutMs: cuint32; InitialCapacity: SizeInt): TPolycallMessage;
var
  Sender, Id: array[0..63] of AnsiChar;
  Buf: RawByteString;
  Len: csize_t;
  Status: cint;
begin
  if InitialCapacity < 1 then
    InitialCapacity := 1;
  SetLength(Buf, InitialCapacity);
  repeat
    Sender[0] := #0;
    Id[0] := #0;
    Len := 0;
    Status := c_peer_recv(FHandle, TimeoutMs, @Sender[0], SizeOf(Sender), @Id[0], SizeOf(Id),
      Pointer(Buf), Length(Buf), @Len);
    if (Status = POLYCALL_E_TOO_LARGE) and (Len > csize_t(Length(Buf))) then
      SetLength(Buf, Len)   { message stays queued: retry with room for it }
    else
      Break;
  until False;
  Check(Status, 'TPolycallPeer.Receive');
  Result.Sender := StrPas(PAnsiChar(@Sender[0]));
  Result.Id := StrPas(PAnsiChar(@Id[0]));
  Result.Payload := Copy(Buf, 1, Len);
end;

procedure TPolycallPeer.Cancel;
begin
  Check(c_peer_cancel(FHandle), 'TPolycallPeer.Cancel');
end;

end.
