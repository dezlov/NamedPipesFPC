This is an object oriented implementation of Named Pipes for Free Pascal.

The implementation consists of two main classes TNamedPipeServerStream and TNamedPipeClientStream, corresponding to the server end and the client end of the pipe, respectively. Both classes inherit from TNamedPipeStream class, which provides common functions and allows both server and client instances to be used interchangeably as abstract streams.

A named pipe is uniquely identified by the pipe name. A named pipe can be served by any number of server instances, or can be restricted to a specific maximum number of instances if necessary. The maximum number of simultaneously connected clients is dictated by the number of available server instances. A communication channel between a server instance and a connected client instance is not shared with other server/client instances operating on the same pipe name. A server can wait for a client connection, disconnect a client, read from and write to pipe. A client can connect to a server, wait for a server to become idle (not busy with another client), read from and write to pipe.

Pipes are setup in a blocking mode, so read and write operations will block until the data can be read/written or if connection is broken by a disconnected pipe. There doesn't appear to be a straight forward way to detect if a client disconnects, except but try to read from the pipe and check for ERROR_BROKEN_PIPE error code, however, this would block on a connected pipe if there is no data to be read. Perhaps using an asynchronous read with an overlapped feature might help, but it becomes messy very quickly.

An example program creates multiple servers and clients for a named pipe, using multiple threads and processes. Clients connect to an available server and sent few messages at random intervals. Server instances close down if no client connects within a certain period of time.

Command line options for an example program:
$ program.exe server  <- start a single server instance
$ program.exe servers <- start multiple server instances
$ program.exe client  <- start a single client instance
$ program.exe clients <- start multiple client instances

Documentation for Named Pipes at MSDN:
https://msdn.microsoft.com/en-us/library/windows/desktop/aa365590.aspx

Author: Denis Kozlov
License: Creative Commons Zero (CC0)
License URL: https://creativecommons.org/publicdomain/zero/1.0/
