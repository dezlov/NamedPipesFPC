unit NamedPipes;

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils;

type
  TPipeDirection = (pdInOut, pdIn, pdOut);

  TNamedPipeStream = class(TStream)
  public const
    DefaultBufferSize: Integer = 64 * 1024; // 64K
  private
    FPipeName: String;
    FPipeHandle: THandle;
    FDirection: TPipeDirection;
    FBufferSize: Integer;
    function GetIsOpen: Boolean;
    procedure SetPipeName(const Value: String);
    procedure SetDirection(const Value: TPipeDirection);
    procedure SetBufferSize(const Value: Integer);
  protected
    procedure CheckOpen;
    procedure CheckClosed;
    procedure Initialize; virtual;
    class function GetSystemPipePath(const APipeName: String): String;
  public
    constructor Create(const APipeName: String; ADirection: TPipeDirection = pdInOut);
    destructor Destroy; override;
    function TryOpen: Boolean;
    procedure Open; virtual;
    procedure Close; virtual;
    procedure Flush;
    function AvailableBytes: Cardinal;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    property PipeHandle: THandle read FPipeHandle;
    property PipeName: String read FPipeName write SetPipeName;
    property Direction: TPipeDirection read FDirection write SetDirection;
    property BufferSize: Integer read FBufferSize write SetBufferSize;
    property IsOpen: Boolean read GetIsOpen;
  end;

  TNamedPipeServerStream = class(TNamedPipeStream)
  public const
    DefaultMaxInstances = 1;
    DefaultOverlapped = True;
  private
    FMaxInstances: Integer;
    FOverlapped: Boolean;
    procedure SetMaxInstances(Value: Integer);
    function GetMaxInstancesUnlimited: Boolean;
    procedure SetMaxInstancesUnlimited(Value: Boolean);
    procedure SetOverlapped(Value: Boolean);
    procedure InternalCreatePipe;
  protected
    procedure Initialize; override;
    procedure CheckOverlapped;
  public
    procedure Open; override;
    procedure WaitForConnection;
    function WaitForConnection(AWaitTimeout: Integer): Boolean;
    procedure Disconnect;
    property MaxInstances: Integer read FMaxInstances write SetMaxInstances;
    property MaxInstancesUnlimited: Boolean read GetMaxInstancesUnlimited write SetMaxInstancesUnlimited;
    property Overlapped: Boolean read FOverlapped write SetOverlapped;
  end;

  TNamedPipeClientStream = class(TNamedPipeStream)
  private
    procedure InternalCreatePipe;
  public
    procedure Open; override;
    function Open(ABusyWaitTimeout: Integer): Boolean;
    function WaitForIdle(ABusyWaitTimeout: Integer): Boolean;
  end;

  ENamedPipeError = class(Exception);

resourcestring
  SErrorPipeOpen = 'This operation is illegal when the pipe is open.';
  SErrorPipeClosed = 'This operation is illegal when the pipe is closed.';
  SErrorPipeOverlappedRequired = 'This operation requires a pipe with an overlapped feature enabled.';
  SErrorPipeTimeoutInvalid = 'Invalid timeout value (%d).';


implementation

const
  FILE_FLAG_FIRST_PIPE_INSTANCE = DWORD($00080000);
  PIPE_UNLIMITED_INSTANCES = 255;
  NMPWAIT_USE_DEFAULT_WAIT = DWORD($00000000);
  NMPWAIT_WAIT_FOREVER = DWORD($ffffffff);

{$REGION 'TNamedPipeStream'}

class function TNamedPipeStream.GetSystemPipePath(const APipeName: String): String;
begin
  Result := '\\.\pipe\' + APipeName;
end;

constructor TNamedPipeStream.Create(const APipeName: String; ADirection: TPipeDirection);
begin
  FPipeName := APipeName;
  FDirection := ADirection;
  FPipeHandle := INVALID_HANDLE_VALUE;
  FBufferSize := DefaultBufferSize;
  Initialize;
end;

destructor TNamedPipeStream.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TNamedPipeStream.Initialize;
begin
  // Virtual method to be overridden by descendants.
end;

procedure TNamedPipeStream.Open;
begin
  // Virtual method to be overridden by descendants.
end;

function TNamedPipeStream.TryOpen: Boolean;
begin
  try
    Open;
    Result := True;
  except
    Result := False;
  end;
end;

procedure TNamedPipeStream.Close;
begin
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure TNamedPipeStream.CheckOpen;
begin
  if not IsOpen then
    raise ENamedPipeError.Create(SErrorPipeClosed);
end;

procedure TNamedPipeStream.CheckClosed;
begin
  if IsOpen then
    raise ENamedPipeError.Create(SErrorPipeOpen);
end;

function TNamedPipeStream.GetIsOpen: Boolean;
begin
  Result := FPipeHandle <> INVALID_HANDLE_VALUE;
end;

procedure TNamedPipeStream.SetPipeName(const Value: String);
begin
  CheckClosed;
  FPipeName := Value;
end;

procedure TNamedPipeStream.SetDirection(const Value: TPipeDirection);
begin
  CheckClosed;
  FDirection := Value;
end;

procedure TNamedPipeStream.SetBufferSize(const Value: Integer);
begin
  CheckClosed;
  FBufferSize := Value;
end;

// TODO: Async pipe read with a timeout, using ReadFileEx in overlapped mode.
function TNamedPipeStream.Read(var Buffer; Count: Longint): Longint;
begin
  CheckOpen;
  Result := FileRead(FPipeHandle, Buffer, Count);
  if Result = -1 then
    RaiseLastOSError;
end;

// TODO: Async pipe write with a timeout, using WriteFileEx in overlapped mode.
function TNamedPipeStream.Write(const Buffer; Count: Longint): Longint;
begin
  CheckOpen;
  Result := FileWrite(FPipeHandle, Buffer, Count);
  if Result = -1 then
    RaiseLastOSError;
end;

procedure TNamedPipeStream.Flush;
begin
  CheckOpen;
  FlushFileBuffers(FPipeHandle);
end;

function TNamedPipeStream.AvailableBytes: Cardinal;
var
  TotalBytesAvail: DWORD;
  PeekResult: WINBOOL;
begin
  CheckOpen;
  PeekResult := PeekNamedPipe(FPipeHandle, nil, 0, nil, @TotalBytesAvail, nil);
  if LongWord(PeekResult) = 0 then
    RaiseLastOSError;
  Result := TotalBytesAvail;
end;

{$ENDREGION}

{$REGION 'TNamedPipeServerStream'}

function TNamedPipeServerStream.GetMaxInstancesUnlimited: Boolean;
begin
  Result := FMaxInstances = PIPE_UNLIMITED_INSTANCES;
end;

procedure TNamedPipeServerStream.SetMaxInstancesUnlimited(Value: Boolean);
begin
  CheckClosed;
  if Value then
    FMaxInstances := PIPE_UNLIMITED_INSTANCES
  else
    FMaxInstances := DefaultMaxInstances;
end;

procedure TNamedPipeServerStream.SetOverlapped(Value: Boolean);
begin
  CheckClosed;
  FOverlapped := Value;
end;

procedure TNamedPipeServerStream.SetMaxInstances(Value: Integer);
begin
  CheckClosed;
  // MSDN: Acceptable values are in the range 1 through PIPE_UNLIMITED_INSTANCES (255).
  if (Value <= 0) or (Value >= PIPE_UNLIMITED_INSTANCES) then
    Value := PIPE_UNLIMITED_INSTANCES;
  FMaxInstances := Value;
end;

procedure TNamedPipeServerStream.Initialize;
begin
  inherited Initialize;
  FOverlapped := DefaultOverlapped;
  FMaxInstances := DefaultMaxInstances;
end;

procedure TNamedPipeServerStream.CheckOverlapped;
begin
  if not FOverlapped then
    raise ENamedPipeError.Create(SErrorPipeOverlappedRequired);
end;

procedure TNamedPipeServerStream.InternalCreatePipe;
var
  PipePath: String;
  dwOpenMode, dwPipeMode, nMaxInstances: DWORD;
begin
  // Pipe path
  PipePath := GetSystemPipePath(FPipeName);

  // Direction
  case FDirection of
    pdInOut:
      dwOpenMode := PIPE_ACCESS_DUPLEX;
    pdIn:
      dwOpenMode := PIPE_ACCESS_INBOUND;
    pdOut:
      dwOpenMode := PIPE_ACCESS_OUTBOUND;
    else
      dwOpenMode := 0;
  end;

  // Overlapped
  if FOverlapped then
    dwOpenMode := dwOpenMode or FILE_FLAG_OVERLAPPED;

  // Pipe mode
  dwPipeMode := PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT; // blocking byte mode

  // Max instances
  nMaxInstances := FMaxInstances;
  if FMaxInstances = 1 then
    dwOpenMode := dwOpenMode or FILE_FLAG_FIRST_PIPE_INSTANCE;

  // Create server pipe
  FPipeHandle := CreateNamedPipe(
    PChar(PipePath), dwOpenMode, dwPipeMode, nMaxInstances,
    FBufferSize, FBufferSize, 0, nil);
end;

procedure TNamedPipeServerStream.Open;
begin
  CheckClosed;
  InternalCreatePipe;
  if FPipeHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
end;

// Disconnect a currently connect client from the pipe.
procedure TNamedPipeServerStream.Disconnect;
begin
  DisconnectNamedPipe(FPipeHandle);
end;

// Wait for a client process to connect to an instance of a named pipe.
procedure TNamedPipeServerStream.WaitForConnection;
var
  ConnectResult: WINBOOL;
begin
  // If a client connects before the function is called, the function returns
  // zero and GetLastError returns ERROR_PIPE_CONNECTED. This can happen if
  // a client connects in the interval between the call to CreateNamedPipe
  // and the call to ConnectNamedPipe. In this situation, there is a good
  // connection between client and server, even though the function returns zero.
  ConnectResult := ConnectNamedPipe(FPipeHandle, nil);
  if (LongWord(ConnectResult) = 0) and (GetLastError <> ERROR_PIPE_CONNECTED) then
    RaiseLastOSError;
end;

// Wait for the specified amount of time for a client process to connect
// to an instance of a named pipe. Returns TRUE if connected, or FALSE otherwise.
function TNamedPipeServerStream.WaitForConnection(AWaitTimeout: Integer): Boolean;
var
  ConnectResult, OverlapResult: WINBOOL;
  OverlapEvent: THandle;
  OverlapStruct: Windows.OVERLAPPED;
  dwDummy, dwTimeout: DWORD;
begin
  Result := False;
  CheckOverlapped;

  // < 0 - infinite wait
  // = 0 - return immediately
  // > 0 - wait for N milliseconds
  if AWaitTimeout < 0 then
    dwTimeout := Windows.INFINITE
  else
    dwTimeout := AWaitTimeout;

  // Create an event
  OverlapEvent := CreateEvent(
    nil,   // default security attribute
    True,  // manual-reset event
    False, // initial state
    nil);  // unnamed event object
  if OverlapEvent = 0 then
    RaiseLastOSError;

  // Start waiting for a connection
  try
    OverlapStruct := Default(Windows.OVERLAPPED);
    OverlapStruct.hEvent := OverlapEvent;
    ConnectResult := ConnectNamedPipe(FPipeHandle, @OverlapStruct);

    if LongWord(ConnectResult) = 0 then
    begin
      case GetLastError of
        // Pipe has just connected
        ERROR_PIPE_CONNECTED:
          Result := True;
        // Pipe is awaiting a connection
        ERROR_IO_PENDING:
          begin
            // Wait for the signal or timeout
            if WaitForSingleObject(OverlapEvent, dwTimeout) = WAIT_OBJECT_0 then
            begin
              // Check that IO operation has been completed
              dwDummy := 0;
              OverlapResult := GetOverlappedResult(FPipeHandle, OverlapStruct, dwDummy, False);
              Result := LongWord(OverlapResult) <> 0;
            end;
            // Cancel pending IO operation if it still hasn't been completed
            if not Result then
              CancelIo(FPipeHandle);
          end;
      end;
    end;

  finally
    CloseHandle(OverlapEvent);
  end;
end;

{$ENDREGION}

{$REGION 'TNamedPipeClientStream'}

procedure TNamedPipeClientStream.InternalCreatePipe;
var
  PipePath: String;
  dwDesiredAccess, dwShareMode, dwCreationDisposition: DWORD;
begin
  // Pipe path
  PipePath := GetSystemPipePath(FPipeName);

  // Desired access
  case FDirection of
    pdInOut:
      dwDesiredAccess := GENERIC_READ or GENERIC_WRITE;
    pdIn:
      // Will also need FILE_WRITE_ATTRIBUTES if need to call SetNamedPipeHandleState
      dwDesiredAccess := GENERIC_READ;
    pdOut:
      // Will also need FILE_READ_ATTRIBUTES if need to call GetNamedPipeInfo or GetNamedPipeHandleState
      dwDesiredAccess := GENERIC_WRITE;
    else
      dwDesiredAccess := 0;
  end;

  // Share mode
  dwShareMode := 0; // no sharing

  // Creation disposition
  dwCreationDisposition := OPEN_EXISTING;

  // Create client pipe
  FPipeHandle := CreateFile(
    PChar(PipePath), dwDesiredAccess, dwShareMode,
    nil, dwCreationDisposition, 0, 0);
end;

// Open the client end of the pipe. Exception is raised if not successful,
// e.g. server pipe does not exist.
procedure TNamedPipeClientStream.Open;
begin
  CheckClosed;
  InternalCreatePipe;
  if FPipeHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
end;

// Open the client end of the pipe and allow waiting for a specified timeout
// if the pipe is busy (occupied by a another client). This function may return
// FALSE before the timeout has expired, in case of the race condition where
// another client beats us to taking the only remaining client slot.
// Exception is raised if any problems have occurred,
// e.g. server pipe does not exist.
function TNamedPipeClientStream.Open(ABusyWaitTimeout: Integer): Boolean;
begin
  CheckClosed;

  // Wait for pipe client slot to become available
  // < 0 - infinite wait
  // = 0 - return immediately
  // > 0 - wait for N milliseconds
  if ABusyWaitTimeout <> 0 then
    if not WaitForIdle(ABusyWaitTimeout) then
      Exit(False);
  // Beware that even if WaitNamedPipe tells us that the pipe is ready
  // to accept a connection, another client may setup a connection
  // before we get a chance to connect ourselves (a race condition).

  // Attempt to create client pipe
  InternalCreatePipe;

  // Pipe created successfully
  if FPipeHandle <> INVALID_HANDLE_VALUE then
    Result := True
  // Server pipe is busy
  else if GetLastError = ERROR_PIPE_BUSY then
    Result := False
  // Some problem has occurred
  else
    RaiseLastOSError;
end;

// Wait for an existing server pipe to become idle, i.e. awaiting a connection
// from a client. Exception is raised if any problems have occurred,
// e.g. server pipe does not exist.
function TNamedPipeClientStream.WaitForIdle(ABusyWaitTimeout: Integer): Boolean;
var
  PipePath: String;
  WaitResult: WINBOOL;
  dwTimeout: DWORD;
begin
  // < 0 - infinite wait
  // = 0 - not supported, clashes with NMPWAIT_USE_DEFAULT_WAIT=0
  // > 0 - wait for N milliseconds
  if ABusyWaitTimeout < 0 then
    dwTimeout := NMPWAIT_WAIT_FOREVER
  else if (ABusyWaitTimeout = NMPWAIT_USE_DEFAULT_WAIT) then
    raise ENamedPipeError.CreateFmt(SErrorPipeTimeoutInvalid, [ABusyWaitTimeout])
  else
    dwTimeout := ABusyWaitTimeout;

  // Pipe path
  PipePath := GetSystemPipePath(FPipeName);

  // Wait for pipe client slot to become available
  WaitResult := WaitNamedPipe(PChar(PipePath), dwTimeout);
  // Beware that even if WaitNamedPipe tells us that the pipe is ready
  // to accept a connection, another client may setup a connection
  // before we get a chance to connect ourselves (a race condition).

  // Server is ready for a connection?
  Result := LongWord(WaitResult) <> 0;

  // Check for non-timeout problems
  if not Result then
    if GetLastError <> ERROR_SEM_TIMEOUT then
      RaiseLastOSError;
end;

{$ENDREGION}

end.

