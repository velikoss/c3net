module c3net::iocp;

import std::os::win32;

enum IoOperationType {
	NULL_POSTED,
	ACCEPT_POSTED,
    SEND_POSTED,
    RECV_POSTED,
}

def Handle = void*; // lol
def WSAEvent = Handle; // lol
def Socket = Handle; // lol
const Socket INVALID_SOCKET = (Socket)(~0UL); // something crazy

struct WSAOverlapped {
    ulong w_Internal;
    ulong w_InternalHigh;
    ulong w_Offset;
    ulong w_OffsetHigh;
    WSAEvent w_hEvent;
}

struct WSABuf {
    ulong len;
    char* buf;
}

struct InAddr {
  union {
    bitstruct s_un_b : char[16] @bigendian {
      char s_b1 : 0 .. 7;
      char s_b2 : 8 .. 15;
      char s_b3 : 16 .. 23;
      char s_b4 : 24 .. 31;
    }
    bitstruct s_un_w : char[16] @bigendian {
      ushort s_w1 : 32 .. 47;
      ushort s_w2 : 48 .. 63;
    }
    ulong s_addr;
  }
}

struct SocketAddrIn {
    short sin_family;
    ushort sin_port;
    InAddr sin_addr;
    char[8] sin_zero;
}

macro void win_ZeroMemory(Handle destination, usz length) {
    libc::memset(destination, 0, length);
}

def FnVoidContext = fn void(SocketContext*);
def FnVoidContextError = fn void(SocketContext*, int);
def FnVoidContextIO = fn void(SocketContext*, IOContext*);
def LPFn_ACCEPTEX = fn bool(Socket, Socket, void*, Win32_DWORD, Win32_DWORD, Win32_DWORD, Win32_DWORD*, void*);
def LPFn_GETACCEPTEXSOCKADDRS = fn void(void*, ulong, ulong, ulong, void*, long*, void*, long*);

const Handle INVALID_HANDLE_VALUE = ((Handle)~0UL);

struct WsaData {
    char[408] data;
}

import libc;

extern fn CInt win_WSAStartup(Win32_WORD version, WsaData* data) @extern("WSAStartup");
extern fn CInt win_WSACleanup() @extern("WSACleanup");
extern fn CInt win_WSAGetLastError() @extern("WSAGetLastError");
extern fn CInt win_GetLastError() @extern("GetLastError");
extern fn Handle win_CreateEvent(void* lpEventAttributes, bool bManualReset, bool bInitialState, char* lpName) @extern("CreateEventA");
extern fn Handle win_CreateThread(void* lpEventAttributes, ulong dwStackSize, void* lpStartAddress, void* lpParameter, Win32_DWORD dwCreationFlags, Win32_DWORD* lpThreadId) @extern("CreateThread");
extern fn bool win_SetEvent(Handle hEvent) @extern("SetEvent");
extern fn bool win_CloseHandle(Handle handle) @extern("CloseHandle");
extern fn bool win_PostQueuedCompletionStatus(Handle completitionPort, ulong dwNumberOfBytesTransferred, ulong* dwCompletionKey, void* lpOverlapped) @extern("PostQueuedCompletionStatus");
extern fn ulong win_WaitForMultipleObjects(ulong nCount, Handle* lpHandles, bool bWaitAll, ulong dwMilliseconds) @extern("WaitForMultipleObjects");
extern fn ulong win_WaitForSingleObject(Handle hHandle, ulong dwMilliseconds) @extern("WaitForSingleObject");
extern fn bool win_GetQueuedCompletionStatus(Handle hHandle, Win32_DWORD* lpNumberOfBytesTransferred, ulong* lpCompletionKey, WSAOverlapped* lpOverlapped, Win32_DWORD dwMilliseconds) @extern("GetQueuedCompletionStatus");
extern fn Handle win_CreateIoCompletionPort(void* fileHandle, void* existingCompletionPort, ulong* completionKey, ulong numberOfConcurrentThreads) @extern("CreateIoCompletionPort");
extern fn Handle win_GetSystemInfo(SystemInfo* info) @extern("GetSystemInfo");
extern fn Handle win_WSASocket(CInt af, CInt type, CInt protocol, void* lpProtocolInfo, CInt g, Win32_DWORD dwFlags) @extern("WSASocketA");
extern fn ulong win_htonl(ulong hostlong) @extern("htonl");
extern fn ushort win_htons(ushort hostshort) @extern("htons");
extern fn int win_bind(Socket s, void* addr, int namelen) @extern("bind");
extern fn int win_send(Socket s, char* buf, int len, int flags) @extern("send");
extern fn int win_listen(Socket s, int backlog) @extern("listen");
// extern fn int win_InterlockedIncrement(long* addend) @extern("InterlockedIncrement");
// extern fn int win_InterlockedDecrement(long* addend) @extern("InterlockedDecrement");
extern fn int win_WSAIoctl(Socket s, Win32_DWORD dwIoControlCode, void* lpvInBuffer, Win32_DWORD cbInBuffer, void* lpvOutBuffer, Win32_DWORD cbOutBuffer, Win32_DWORD* lpcbBytesReturneds, WSAOverlapped* lpOverlapped, void* lpCompletionRoutine) @extern("WSAIoctl");
extern fn int win_WSARecv(Socket s, WSABuf* lpBuffers, ulong dwBufferCount, ulong* lpNumberOfBytesRecvd, ulong* lpFlags, WSAOverlapped* lpOverlapped, void* lpCompletionRoutine) @extern("WSARecv");
extern fn int win_WSASend(Socket s, WSABuf* lpBuffers, ulong dwBufferCount, ulong* lpNumberOfBytesRecvd, ulong* dwFlags, WSAOverlapped* lpOverlapped, void* lpCompletionRoutine) @extern("WSASend");
extern fn Handle win_GetProcessHeap() @extern("GetProcessHeap");
extern fn Handle win_HeapAlloc(Handle hHeap, ulong dwFlags, ulong* dwBytes) @extern("HeapAlloc");
extern fn bool win_HeapFree(Handle hHeap, ulong dwFlags, void* lpMem) @extern("HeapFree");
extern fn CInt win_closesocket(Handle socket) @extern("closesocket");

struct Tcp_keepalive {
    ulong  onoff;
    ulong  keepalivetime;
    ulong  keepaliveinterval;
}