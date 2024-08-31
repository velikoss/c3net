module c3net::iocp;

struct IOContext {
    WSAOverlapped overlapped;
    Socket ioSocket;
    WSABuf wsaBuf;
    IoOperationType ioType;
    uint connectID;
}

const usz HEAP_ZERO_MEMORY = 0x00000008;
const usz BUFF_SIZE = 1024 * 4;

fn void IOContext.init(IOContext* self) {
    win_ZeroMemory(&self.overlapped, WSAOverlapped.sizeof);
    self.ioSocket = INVALID_SOCKET;
    //self.wsaBuf.buf = (char*) win_HeapAlloc(win_GetProcessHeap(), HEAP_ZERO_MEMORY, &BUFF_SIZE);
    self.wsaBuf.buf = mem::new_array(char, BUFF_SIZE);
    self.wsaBuf.len = BUFF_SIZE;
    self.ioType = NULL_POSTED;
    self.connectID = 0;
}

fn void IOContext.free(IOContext* self) {
    if (self.ioSocket != INVALID_SOCKET) {
        win_closesocket(self.ioSocket);
        self.ioSocket = INVALID_SOCKET;
    }    
    if (self.wsaBuf.buf != null) {
        win_HeapFree(win_GetProcessHeap(), 0, self.wsaBuf.buf);
    }
}

fn void IOContext.reset(IOContext* self) {
    if (self.wsaBuf.buf != null) {
        win_ZeroMemory(self.wsaBuf.buf, BUFF_SIZE);
    } else {
        self.wsaBuf.buf = (char*) win_HeapAlloc(win_GetProcessHeap(), HEAP_ZERO_MEMORY, &BUFF_SIZE);
    }
    win_ZeroMemory(&self.overlapped, WSAOverlapped.sizeof);
}
