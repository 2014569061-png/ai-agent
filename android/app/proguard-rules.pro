# Shizuku UserService 由 Shizuku 进程按类名反射加载，R8 不能重命名或移除。
-keep class com.nexusagent.app.PrivilegedShellService { *; }
-keep class com.nexusagent.app.IPrivilegedShell { *; }
-keep class com.nexusagent.app.IPrivilegedShell$Stub { *; }
-keep class com.nexusagent.app.IPrivilegedShell$Stub$Proxy { *; }
