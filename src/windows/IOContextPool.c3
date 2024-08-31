module c3net::iocp;

import std::collections::list;
import std::os::win32;
import std::thread;

const usz INIT_IOCONTEXT_NUM = 100;

struct IOContextPool {
    List(<IOContext*>) contextList;
    Mutex* csLock;
}

fn void IOContextPool.init(IOContextPool* self) {
    self.csLock = mem::new(Mutex);
    self.csLock.init()!!;
    self.contextList.new_init();

    self.csLock.lock()!!;
    for (usz i = 0; i < INIT_IOCONTEXT_NUM; i++)
    {
        IOContext context;
        context.init();
        self.contextList.push(@clone(context));
    }
    self.csLock.unlock()!!;
}

fn void IOContextPool.free(IOContextPool* self) {
    self.csLock.lock()!!;
    foreach (IOContext* context: self.contextList) {
        context.free();
    }
    self.contextList.free();
    self.csLock.unlock()!!;

    self.csLock.destroy()!!;
}

import std::io;
fn IOContext* IOContextPool.allocateIOContext(IOContextPool* self) {
    IOContext* context = null;
    self.csLock.lock()!!;
    if (self.contextList.len() > 0) { context = self.contextList.pop()!!; }
    else {
        context = mem::new(IOContext);
        context.init();
    }
    self.csLock.unlock()!!;
    return context;
}

fn void IOContextPool.releaseIOContext(IOContextPool* self, IOContext* context) {
    context.reset();

    self.csLock.lock()!!;
    self.contextList.push_front(context);
    self.csLock.unlock()!!;
}