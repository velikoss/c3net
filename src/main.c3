module c3net;
import std::io;
import std::time;

IOCPBase* server;

fn void onConnectionEstablished(SocketContext *sockContext) {
	DateTime sys = std::time::datetime::now();
	io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: Accept a connection, Current connects: %d\n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec, server.connectCnt);
}

fn void onConnectionClosed(SocketContext *sockContext) {
	DateTime sys = std::time::datetime::now();
	io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: A connection had closed, Current connects: %d\n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec, server.connectCnt);
}

fn void onConnectionError(SocketContext *sockContext, int error) {
	DateTime sys = std::time::datetime::now();
	io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: A connection error: %d, Current connects: %d\n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec, error, server.connectCnt);
}

fn void onRecvCompleted(SocketContext *sockContext, IOContext *ioContext) {
	DateTime sys = std::time::datetime::now();
	io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: Recv data: %s \n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec, ioContext.wsaBuf.buf);
}

fn void onSendCompleted(SocketContext *sockContext, IOContext *ioContext) {
	DateTime sys = std::time::datetime::now();
	io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: Send data successed: \n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec);
}

fn int main(String[] args) {
	io::printn("Allocating server...");
	server = mem::alloc(IOCPBase);
	io::printn("Init...");
	server.init(.onConnectionEstablished = &onConnectionEstablished, .onConnectionClosed = &onConnectionClosed, .onConnectionError = &onConnectionError, .onRecvCompleted = &onRecvCompleted, .onSendCompleted = &onSendCompleted);
	io::printn("Starting server...");
	if (server.start()) {
		DateTime sys = std::time::datetime::now();
		io::printf("%4d-%02d-%02d %02d:%02d:%02d.%03d: Server start succussed on port:%d... \n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec, server.port);
	} else {
		DateTime sys = std::time::datetime::now();
		io::eprintf("%4d-%02d-%02d %02d:%02d:%02d.%03d: Server start failed! \n", sys.year, sys.month, sys.day, sys.hour, sys.min, sys.sec, sys.usec);
	}
	io::printn("Running...");
	Handle hEvent = iocp::win_CreateEvent(null, false, false, "ShutdownEvent");
	iocp::win_WaitForSingleObject(hEvent, long.max);
	iocp::win_CloseHandle(hEvent);
	server.stop();
	return 0;
}
