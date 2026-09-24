package com.nexusagent.app;

// Shizuku UserService：在 Shizuku 提供的 shell(uid 2000) 或 root(uid 0) 进程中执行
// 由应用侧固定模板生成的命令。stdin/stdout/stderr 通过管道 ParcelFileDescriptor 流式传输。
interface IPrivilegedShell {
    // Shizuku 约定的销毁事务号。
    void destroy() = 16777114;

    int start(String command, in ParcelFileDescriptor stdin, in ParcelFileDescriptor stdout, in ParcelFileDescriptor stderr) = 1;

    // 返回退出码；超时返回 -1001，未知句柄返回 -1002。
    int waitFor(int handle, long timeoutMs) = 2;

    void kill(int handle) = 3;

    int uid() = 4;
}
