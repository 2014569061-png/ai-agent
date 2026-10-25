# Windows 本地自托管执行器：运行与协议说明

状态：可运行的本地原型，不是 F13/W12 完整交付。仅支持当前 Windows 电脑回环监听与 Android 模拟器连接，不开放公网。当前默认只有无副作用的 `diagnostic` 命名任务；手机审批提交、配对、同步与完整创作交付仍未接入。

## 启动（项目根目录，Bash）

```bash
python tool/windows_remote_executor.py --state-dir local/remote-executor --token-file local/remote-executor/token --port 8767
```

- Python >=3.9，当前宿主已验证为 3.12.7；只使用标准库，不安装依赖。
- 服务固定监听 `127.0.0.1`，不能通过参数意外绑定公网。Android 模拟器使用 `http://10.0.2.2:8767` 访问宿主；不要为此操作真机、重启 ADB 或开放防火墙。
- 初次启动生成本机令牌到 `local/remote-executor/token`，不打印令牌。只在模拟器「项目 → 远程执行验证」页面的遮蔽输入框中输入；不要贴到聊天、提交 Git 或截图明文。
- 令牌、SQLite、日志及成果快照位于 Git 忽略的 `local/`。Windows 目录继承当前用户权限，尚未增加独立 ACL/加密管理；只适合当前单用户本地原型，不能当作加固后的多租户服务。
- 更换或移除令牌文件会撤销旧令牌的后续 API 请求。它不是完整的多设备配对/撤销体系，不擦除既有下载副本。
- 服务进程与手机连接独立。手机页面离开或断网不会取消已接收作业；宿主关机或执行器重启不保证在运行任务继续，未完成作业会标记 `unknown`，不会默认重放。
- 同一状态目录有独占锁，不允许启动第二个执行器并同时拥有作业。

## 宿主命名任务

可选 `--tasks-file <本机JSON配置>`。配置由宿主用户审核，不能由模型/远程请求写入。值仅允许 `argv`、`cwd`、`timeout`、`artifacts`；参数是固定字符串数组，禁止把远程内容拼到命令。示意结构：

```json
{
  "review-project": {
    "argv": ["C:/path/to/review-tool.exe", "--check"],
    "cwd": "D:/explicitly-authorized/project",
    "timeout": 120,
    "artifacts": ["review-result.txt"]
  }
}
```

此示例不表示路径存在，也未安装或运行任何 review-tool。原型不是 OS 沙箱：宿主批准的程序拥有启动用户的权限；不能接收不可信配置。当前部署未添加这类工作任务，只有内置 diagnostic。

## HTTP 协议

所有请求都需要 `Authorization: Bearer <本机令牌>`。不提供浏览器 CORS 授权；带 Origin 的请求拒绝。客户端禁止跟随重定向，避免向其他接收方转发令牌。当前客户端明文 HTTP 仅允许本机/模拟器宿主地址，其他接收方要求 HTTPS；服务端当前不提供公网 HTTPS 部署。

| 方法与路径 | 行为 |
| --- | --- |
| GET `/handshake` | 返回真实协议、架构、Python 版本、磁盘空间、并发、命名任务列表 |
| POST `/jobs` | 仅接收 `requestId`、`runId`、`task`；不接受远程 command/argv/cwd |
| GET `/jobs` | 最近 100 条持久作业 |
| GET `/jobs/{jobId}` | 查询持久状态，不启动任何新尝试 |
| POST `/jobs/{jobId}/cancel` | 排队时取消；运行时请求停止，不宣称撤销既有副作用 |
| GET `/jobs/{jobId}/logs` | 最多返回末尾 1 MiB 输出；可信命令仍可能输出秘密，调用方须审查/脱敏后才给模型 |
| GET `/jobs/{jobId}/artifacts/{index}` | 读取完成时快照并验证 SHA256，不从当前项目文件冒充旧成果 |

- 相同 requestId/runId/task 重复提交返回同一 jobId。相同 requestId 改变参数返回 409，不静默启动第二次。
- 单并发、最多 32 个待处理作业；请求体最多 16 KiB。执行时限与日志预算超限会请求停止，未知副作用保持 unknown。
- 状态：queued → running → completed/failed。排队取消为 cancelled；执行中取消/超时/重启/完成竞争等无法充分确认时为 unknown，不标记“已撤销”或“整棵进程树已停止”。
- 只显式终止自身启动的直接子进程；后代进程的停止与既有外部效果未可靠验证，必须保守处理，不能自动重试有副作用的任务。
- 每个成果传输上限 16 MiB，缺失/越界/超限成果不报告完整完成。快照完整性不等同于功能验证通过。

## 当前证据与限制

- 最新用户“全部测试在模拟器”要求之前，Windows 宿主上执行器 13 项隔离测试与 Flutter 传输/兼容选测 20 项通过，仅作为历史记录；之后不再运行宿主测试套件。
- 新要求之前已在 Windows 通过真实认证 HTTP 提交 diagnostic，查询到 completed/exitCode 0，重复提交返回同一 jobId。证据：`local/temp/major-remote-host-evidence-20261018.json`，不含令牌。
- 手机页面不再以固定返回值冒充握手；未配置时明确失败，地址/令牌输入后还需用户勾选并点击才发起请求。
- 当前手机页面只做连接诊断，不提交工作任务，不绕过既有运行/审批。任务和审批层接线、重连查询、执行拥有者/租约、跨设备冲突/删除传播、配对密钥管理、运维/升级仍待实现。
- 模拟器验收另记实际结果；不能用宿主测试通过替代模拟器或真机证据。
- 模拟器实际页面已完成认证握手，返回真实 nexus-remote/1 / AMD64 / python-3.12.7 / 磁盘空间，截图 `local/temp/major-remote-handshake-20261018.png`。此处没有执行手机任务提交、上传项目或模型调用。
- 真机专项必须最后说明影响并单独取得用户许可；当前禁止操作真机及干扰其接口。
