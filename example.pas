program example;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}cthreads,{$ENDIF}{$ENDIF}
  Classes, SysUtils, Math, FGL, NamedPipes;

const
  ServerInstances = 5;
  ClientInstances = 20;
  ClientDelayMin = 100;
  ClientDelayMax = 500;
  ClientNumMessages = 3;
  ServerIdleTimeout = 5000;
  UniquePipeName = 'EDA5A83C-C5CA-42C6-B07E-F1DBF12CBDD2';

function GetInstanceInfo: String;
begin
  Result := Format('$%x:$%x', [GetProcessID, GetThreadID]);
end;

procedure PerformTest;
var
  Server: TNamedPipeServerStream;
  Client: TNamedPipeClientStream;
begin
  Server := TNamedPipeServerStream.Create(UniquePipeName);
  try
    Server.Open;
    Client := TNamedPipeClientStream.Create(UniquePipeName);
    try
      Client.Open;
      Client.WriteAnsiString('Test message at ' + DateTimeToStr(Now));
      WriteLn(Server.ReadAnsiString);
    finally
      Client.Free;
    end;
  finally
    Server.Free;
  end;
  WriteLn('Finished. Press enter key...');
  ReadLn;
end;

procedure PerformServer;
var
  Server: TNamedPipeServerStream;
  InstanceInfo, Message: String;
begin
  InstanceInfo := GetInstanceInfo;
  WriteLn(Format('Creating server pipe %s.', [InstanceInfo]));
  Server := TNamedPipeServerStream.Create(UniquePipeName, pdIn);
  try
    Server.MaxInstances := ServerInstances;
    Server.Open;
    while True do
    begin
      // Wait for connection from clients
      if not Server.WaitForConnection(ServerIdleTimeout) then
      begin
        WriteLn(Format('No connections for %s. Exiting.', [InstanceInfo]));
        Break;
      end;
      // Read all data
      try
        while True do
        begin
          Message := Server.ReadAnsiString;
          WriteLn(Format('Message recieved by %s: %s', [InstanceInfo, Message]));
        end;
      except
        // Assume client pipe has closed
      end;
      // Disconnect client
      Server.Disconnect;
    end;
    Server.Close;
  finally
    Server.Free;
  end;
end;

procedure PerformClient;
var
  Client: TNamedPipeClientStream;
  InstanceInfo, Message: String;
  MessageCount: Integer;
begin
  InstanceInfo := GetInstanceInfo;
  WriteLn(Format('Creating client pipe %s.', [InstanceInfo]));
  Client := TNamedPipeClientStream.Create(UniquePipeName, pdOut);
  try
    while not Client.Open(-1) do ; // wait until connects
    for MessageCount := 1 to ClientNumMessages do
    begin
      Sleep(RandomRange(ClientDelayMin, ClientDelayMax));
      Message := Format('Hello #%d from client %s at %s.',
        [MessageCount, InstanceInfo, DateTimeToStr(Now)]);
      Client.WriteAnsiString(Message);
      WriteLn(Format('Message sent by %s: %s', [InstanceInfo, Message]));
    end;
    Client.Flush;
    Client.Close;
  finally
    Client.Free;
  end;
end;

type
  TThreadList = specialize TFPGObjectList<TThread>;

procedure PerformThreads(ThreadProc: TProcedure; CountInstances: Integer);
var
  Index: Integer;
  Thread: TThread;
  Threads: TThreadList;
begin
  Threads := TThreadList.Create(True);
  try
    for Index := 1 to CountInstances do
      Threads.Add(TThread.CreateAnonymousThread(ThreadProc));
    for Thread in Threads do
    begin
      Thread.FreeOnTerminate := False;
      Thread.Start;
    end;
    for Thread in Threads do
      Thread.WaitFor;
  finally
    Threads.Free;
  end;
end;

var
  Action: String;

begin
  Randomize;
  Action := ParamStr(1);
  case Action of
    'server'  : PerformServer;
    'client'  : PerformClient;
    'servers' : PerformThreads(@PerformServer, ServerInstances);
    'clients' : PerformThreads(@PerformClient, ClientInstances);
    'test'    : PerformTest;
    else
      WriteLn(Format('Usage: %s [servers|clients|server|client|test]',
        [ExtractFileName(ParamStr(0))]));
  end;
end.

