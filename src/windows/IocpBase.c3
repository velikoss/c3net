module c3net::iocp;

import std::thread;
import std::os::win32;
import libc;
import std::io;

struct IOCPBase {
    Handle stopEvent;
    Handle completionPort;
    Handle* workerThreads;
    int workerThreadNum;
    String ip;
    ushort port;
    SocketContext* listenSockContext;
    long connectCnt;
    long acceptPostCnt;
    LPFn_ACCEPTEX fnAcceptEx; // LPFN_ACCEPTEX
    LPFn_GETACCEPTEXSOCKADDRS fnGetAcceptExSockAddrs; // LPFN_GETACCEPTEXSOCKADDRS

    FnVoidContext onConnectionEstablished;
    FnVoidContext onConnectionClosed;
    FnVoidContextError onConnectionError;
    FnVoidContextIO onRecvCompleted;
    FnVoidContextIO onSendCompleted;
}

fn void IOCPBase.init(IOCPBase* self, 
    Handle completionPort = INVALID_HANDLE_VALUE,
	Handle* workerThreads = null,
	int workerThreadNum = 0,
	String ip = "127.0.0.1",
	ushort port = 8080,
	SocketContext* listenSockContext = null,
	LPFn_ACCEPTEX fnAcceptEx = null,
	LPFn_GETACCEPTEXSOCKADDRS fnGetAcceptExSockAddrs = null,
	long connectCnt = 0,
	long acceptPostCnt = 0,
    FnVoidContext onConnectionEstablished = null,
    FnVoidContext onConnectionClosed = null,
    FnVoidContextError onConnectionError = null,
    FnVoidContextIO onRecvCompleted = null,
    FnVoidContextIO onSendCompleted = null
) {
    self.completionPort = completionPort;
    self.workerThreads = workerThreads;
    self.workerThreadNum = workerThreadNum;
    self.ip = ip;
    self.port = port;
    self.fnAcceptEx = fnAcceptEx;
    self.fnGetAcceptExSockAddrs = fnGetAcceptExSockAddrs;
    self.connectCnt = connectCnt;
    self.acceptPostCnt = acceptPostCnt;
    self.onConnectionEstablished = onConnectionEstablished;
    self.onConnectionClosed = onConnectionClosed;
    self.onConnectionError = onConnectionError;
    self.onRecvCompleted = onRecvCompleted;
    self.onSendCompleted = onSendCompleted;

    WsaData wsaData;
    win_WSAStartup(0x0202, &wsaData);
	self.stopEvent = win_CreateEvent(null, true, false, null);
}

fn void IOCPBase.free(IOCPBase* self) {
    if(self.stopEvent != null && self.stopEvent != INVALID_HANDLE_VALUE) { 
        win_CloseHandle(self.stopEvent); 
        self.stopEvent = INVALID_HANDLE_VALUE; 
    }
    self.stop();
    win_WSACleanup();
}

fn bool IOCPBase.start(IOCPBase* self) {
    if (self.initializeIOCP() == false) { return false; }
	if (self.initializeListenSocket() == false) {
		io::eprintfn("%s : %s : %s | Error", $$FILE, $$FUNC, $$LINE);
        self.deInitialize();
		return false;
	}
	return true;
}

macro int IOCPBase.getNumOfProcessors(IOCPBase* self) {
	SystemInfo si;
	win_GetSystemInfo(&si);
	return si.dwNumberOfProcessors;
}

fn bool IOCPBase.initializeIOCP(IOCPBase* self) {
    self.completionPort = win_CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, (ulong*) 0, 0);

    if (self.completionPort == null) {
        return false;
    }

    self.workerThreadNum = self.getNumOfProcessors() * 2; // todo config
    self.workerThreads = mem::new_array(Handle, self.workerThreadNum);

    for (int i = 0; i < self.workerThreadNum; i++) {
		self.workerThreads[i] = win_CreateThread(null, 0, &workerThreadProc, (void *) self, 0, null);
	}

	return true;
}

import std::net::os;

fn bool IOCPBase.initializeListenSocket(IOCPBase* self) {
    self.listenSockContext = mem::new(SocketContext);
    self.listenSockContext.init();
    self.listenSockContext.connSocket = win_WSASocket(2, 1, 0, null, 0, 0x01);
    if (self.listenSockContext.connSocket == INVALID_SOCKET) { return false; }
    if (win_CreateIoCompletionPort(self.listenSockContext.connSocket, self.completionPort, (ulong*) self.listenSockContext, 0) == null) {
        releaseSocket(self.listenSockContext.connSocket);
        return false;
    }

    SocketAddrIn serverAddr;
    win_ZeroMemory((char *)&serverAddr, SocketAddrIn.sizeof);
	serverAddr.sin_family = (short) os::AF_INET;
	serverAddr.sin_addr.s_addr = win_htonl(0x00000000UL);
	serverAddr.sin_port = win_htons(self.port);

    if (win_bind(self.listenSockContext.connSocket, &serverAddr, SocketAddrIn.sizeof) == -1) {
		return false;
	}

	if (win_listen(self.listenSockContext.connSocket, 0x7fffffff) == -1) {
		return false;
	}

    Win32_GUID guidAcceptEx =           {0xb5367df1,0xcbac,0x11cf,{0x95,0xca,0x00,0x80,0x5f,0x48,0xa1,0x92}};
    Win32_GUID guidGetAcceptSockAddrs = {0xb5367df2,0xcbac,0x11cf,{0x95,0xca,0x00,0x80,0x5f,0x48,0xa1,0x92}};

    Win32_DWORD dwBytes = 0;
	if (win_WSAIoctl(
		self.listenSockContext.connSocket,
		(Win32_DWORD)(0x40000000L|0x80000000L)|(0x08000000L)|(6),
		&guidAcceptEx,
		Win32_GUID.sizeof,
		&self.fnAcceptEx,
		LPFn_ACCEPTEX.sizeof,
		&dwBytes,
		null,
		null) == -1) {
		self.deInitialize();
		return false;
	}

	if (win_WSAIoctl(
		self.listenSockContext.connSocket,
		(Win32_DWORD)(0x40000000L|0x80000000L)|(0x08000000L)|(6),
		&guidGetAcceptSockAddrs,
		Win32_GUID.sizeof,
		&self.fnGetAcceptExSockAddrs,
		LPFn_GETACCEPTEXSOCKADDRS.sizeof,
		&dwBytes,
		null,
		null) == -1) {
		self.deInitialize();
		return false;
	}

    for (int i = 0; i < 10; i++) {

        IOContext* ioContext = self.listenSockContext.getNewIOContext();

		if (self.postAccept(self.listenSockContext, ioContext) == false) {
			self.listenSockContext.removeContext(ioContext);
			return false;
		}
	}

    return true;
}

fn bool IOCPBase.isSocketAlive(IOCPBase* self, Socket sock) {
	int nByteSent = win_send(sock, "", 0, 0);
    if (-1 == nByteSent) { return false; }
	return true;
}

fn bool IOCPBase.associateWithIOCP(IOCPBase* self, SocketContext* sockContext) {
	Handle hTemp = win_CreateIoCompletionPort(sockContext.connSocket, self.completionPort, (ulong*) sockContext, 0);

	if (hTemp == null) { return false; }
	return true;
}

import std::atomic;

fn bool IOCPBase.postAccept(IOCPBase* self, SocketContext* sockContext, IOContext* ioContext) {
    ulong dwBytes = 0;
	ioContext.ioType = ACCEPT_POSTED;
	ioContext.ioSocket = win_WSASocket(2, 1, 0, null, 0, 0x01);
   
	if (ioContext.ioSocket == INVALID_SOCKET) {
        io::eprintn("Invalid Socket");
        return false; 
    }
	
	if (self.fnAcceptEx(self.listenSockContext.connSocket, ioContext.ioSocket, ioContext.wsaBuf.buf, 0, SocketAddrIn.sizeof + 16, SocketAddrIn.sizeof + 16, (Win32_DWORD*) &dwBytes, &ioContext.overlapped) == false) {
		int err = win_WSAGetLastError();
        if (err != 997) { 
            io::eprintfn("%d != WSA_IO_PENDING", err);
            return false; 
        } // WSA_IO_PENDING
	}

	//win_InterlockedIncrement(&self.acceptPostCnt);
	atomic::fetch_add(&self.acceptPostCnt, 1);
	return true;
}

fn bool IOCPBase.postRecv(IOCPBase* self, SocketContext* sockContext, IOContext* ioContext) {
	ulong dwFlags = 0;
    ulong dwBytes = 0;
	ioContext.reset();
	ioContext.ioType = RECV_POSTED;

	int nBytesRecv = win_WSARecv(ioContext.ioSocket, &ioContext.wsaBuf, 1, &dwBytes, &dwFlags, &ioContext.overlapped, null);
	
	if ((nBytesRecv == -1) && (win_WSAGetLastError() != 997)) {
		self.doClose(sockContext);
		return false;
	}
	return true;
}

fn bool IOCPBase.postSend(IOCPBase* self, SocketContext* sockContext, IOContext* ioContext) {
	ioContext.ioType = SEND_POSTED;
	ulong dwBytes = 0;
    ulong dwFlags = 0;

	if (win_WSASend(ioContext.ioSocket, &ioContext.wsaBuf, 1, &dwBytes, &dwFlags, &ioContext.overlapped, null) != 0) {
		if (win_WSAGetLastError() != 997) {
			self.doClose(sockContext);
			return false;
		}
	}
	return true;
}

fn bool IOCPBase.doAccept(IOCPBase* self, SocketContext * sockContext, IOContext * ioContext) {
	
	atomic::fetch_add(&self.acceptPostCnt, 1);
	atomic::fetch_add(&self.acceptPostCnt, -1);
	SocketAddrIn* clientAddr = null;
	SocketAddrIn* localAddr = null;
	int clientAddrLen, localAddrLen;
	clientAddrLen = localAddrLen = SocketAddrIn.sizeof;

	self.fnGetAcceptExSockAddrs(ioContext.wsaBuf.buf, 0, localAddrLen, clientAddrLen, (void*) &localAddr, (long*)&localAddrLen, (void*) &clientAddr, (long*)&clientAddrLen);

	SocketContext* newSockContext = mem::alloc(SocketContext);
	newSockContext.connSocket = ioContext.ioSocket;
	libc::memcpy(&(newSockContext.clientAddr), clientAddr, SocketAddrIn.sizeof);

	ioContext.reset();
	if (self.postAccept(self.listenSockContext, ioContext) == false) {
		self.listenSockContext.removeContext(ioContext);
	}

	if (win_CreateIoCompletionPort(newSockContext.connSocket, self.completionPort, (ulong*)newSockContext, 0) == null) {
		ulong dwErr = win_WSAGetLastError();
		if (dwErr != 87) {
			self.doClose(newSockContext);
			return false;
		}
	}

	Tcp_keepalive alive_in;
	Tcp_keepalive alive_out;
	alive_in.onoff = 1;
	alive_in.keepalivetime = 1000 * 60;
	alive_in.keepaliveinterval = 1000 * 10;
	Win32_DWORD ulBytesReturn = 0;
	if (win_WSAIoctl(newSockContext.connSocket, (Win32_DWORD)(0x80000000L|0x18000000L|4), &alive_in, Tcp_keepalive.sizeof, &alive_out, Tcp_keepalive.sizeof, &ulBytesReturn, null, null) == -1) {
		io::eprintfn("WSAIoctl failed: %d", win_WSAGetLastError());
	}


	io::printn("hi");
    self.onConnectionEstablished(newSockContext);

	
	IOContext *newIoContext = newSockContext.getNewIOContext();
	io::printn("bye");
	newIoContext.ioType = RECV_POSTED;
	newIoContext.ioSocket = newSockContext.connSocket;

	if (self.postRecv(newSockContext, newIoContext) == false) {
		self.doClose(sockContext);
		return false;
	}

	return true;
}

fn bool IOCPBase.doRecv(IOCPBase* self, SocketContext* sockContext, IOContext* ioContext) {
    self.onRecvCompleted(sockContext, ioContext);
    ioContext.reset();
    if (self.postRecv(sockContext, ioContext) == false) {
        self.doClose(sockContext);
        return false;
    }
    return true;
}

fn bool IOCPBase.doSend(IOCPBase* self, SocketContext* sockContext, IOContext* ioContext) {
    self.onSendCompleted(sockContext, ioContext);
    return true;
}

fn bool IOCPBase.doClose(IOCPBase* self, SocketContext* sockContext) {
    atomic::fetch_add(&self.connectCnt, -1);
    release(sockContext);
    return true;
}

fn void IOCPBase.stop(IOCPBase* self) {
    if (self.listenSockContext != null && self.listenSockContext.connSocket != INVALID_SOCKET) {
		win_SetEvent(self.stopEvent);

		for (int i = 0; i < self.workerThreadNum; i++)
            win_PostQueuedCompletionStatus(self.completionPort, 0, (ulong*) -1UL, null);

		win_WaitForMultipleObjects(self.workerThreadNum, self.workerThreads, true, ulong.max);

		self.deInitialize();
	}
}

macro void release (Handle x) {
    if(x != null) {
        free(x); 
        x = null;
    }
}

macro void releaseHandle (Handle x) {
    if(x != null && x != INVALID_HANDLE_VALUE) { 
        win_CloseHandle(x); 
        x = INVALID_HANDLE_VALUE; 
    }
}

macro void releaseSocket (Socket x) {
    if(x != null && x != INVALID_SOCKET) { 
        win_closesocket(x); 
        x = INVALID_SOCKET; 
    }
}

fn void IOCPBase.deInitialize(IOCPBase* self) {
    releaseHandle(self.stopEvent);
	for (int i = 0; i < self.workerThreadNum; i++) {
		releaseHandle(self.workerThreads[i]);
	}
	release(self.workerThreads);
	releaseHandle(self.completionPort);
	release(self.listenSockContext);
}

fn ulong workerThreadProc(void* self) {    
    IOCPBase* iocp = (IOCPBase*) self;
	Overlapped* ol = null;
	SocketContext* sockContext;
	Win32_DWORD dwBytes = 0;
	IOContext* ioContext = null;
    
	while (win_WaitForSingleObject(iocp.stopEvent, 0) != 0x00000000) {
        bool bRet = win_GetQueuedCompletionStatus(iocp.completionPort, &dwBytes, (ulong*) &sockContext, &ol, 0xFFFFFFFF);
        
		ioContext = ((IOContext *)((char*)(ol) - (ulong)(&((IOContext *)0).overlapped))); // crazy

		// ioContext = ((IOContext *)((char*)(ol) - (ulong*)(&((IOContext *)0).overlapped))); // crazy
        
		// if ((ulong) sockContext == -1UL) { break; }

		if (!bRet) {
			ulong dwErr = win_GetLastError();
			
			if (dwErr == 0x00000102L) {
				if (!iocp.isSocketAlive(sockContext.connSocket)) {
					iocp.onConnectionClosed(sockContext);
					iocp.doClose(sockContext);
					continue;
				}
				else {
					continue;
				}
			}
			// else if (0x40 == dwErr) { // ERROR_NETNAME_DELETED
			// 	iocp.onConnectionError(sockContext, dwErr);
			// 	iocp.doClose(sockContext);
			// 	continue;
			// }
			else {
				iocp.onConnectionError(sockContext, (int) dwErr);
				iocp.doClose(sockContext);
				continue;
			}
		}
		else {
			io::printn(ioContext);
			if ((dwBytes == 0) && (ioContext.ioType == RECV_POSTED || ioContext.ioType == SEND_POSTED)) {
				io::printn("closing");
				iocp.onConnectionClosed(sockContext);
				iocp.doClose(sockContext);
				continue;
			}
			else {
				io::printn("+");
				switch (ioContext.ioType) {
                    case ACCEPT_POSTED:
                        iocp.doAccept(sockContext, ioContext);
                        break;
                    case RECV_POSTED:
                        iocp.doRecv(sockContext, ioContext);
                        break;
                    case SEND_POSTED:
                        iocp.doSend(sockContext, ioContext);
                        break;
                    default:
                        break;
				}
			}
		}
	}

	release(self);
	return 0;
}