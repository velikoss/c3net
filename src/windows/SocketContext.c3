module c3net::iocp;

import std::thread;
import std::collections::list;

struct SocketContext {
    Socket connSocket;
    InAddr clientAddr;

    List(<IOContext*>) arrIOContext;
    IOContextPool ioContextPool;
    Mutex* csLock;
}

fn void SocketContext.init(SocketContext* self) {
    self.csLock = mem::new(Mutex);
    self.csLock.init()!!;
    self.arrIOContext.new_init();
    self.connSocket = INVALID_SOCKET;
    self.ioContextPool.init();
    win_ZeroMemory(&self.clientAddr, InAddr.sizeof);
}

fn void SocketContext.free(SocketContext* self) {
    if (self.connSocket != INVALID_SOCKET) {
        win_closesocket(self.connSocket);
        self.connSocket = INVALID_SOCKET;
    }

    foreach (IOContext* context: self.arrIOContext) {
        self.ioContextPool.releaseIOContext(context);
    }

    self.csLock.lock()!!;
    self.arrIOContext.free();
    self.csLock.unlock()!!;

    self.csLock.destroy()!!;
}
import std::io;
fn IOContext* SocketContext.getNewIOContext(SocketContext* self) {
    IOContext* context = self.ioContextPool.allocateIOContext();
    io::printn(context);
    if (context != null) {
        self.csLock.lock()!!;
        self.arrIOContext.push(context);
        self.csLock.unlock()!!;
    }
    return context;
}

fn void SocketContext.removeContext(SocketContext* self, IOContext* context) {
    foreach(IOContext* iContext: self.arrIOContext) {
        if (iContext == context) {
            self.ioContextPool.releaseIOContext(context);

            self.csLock.lock()!!;
            self.arrIOContext.remove_item(context);
            self.csLock.unlock()!!;
            
            break;
        }
    }
}