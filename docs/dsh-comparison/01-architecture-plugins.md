# DSH 桌面版实现调研 01：架构与插件机制

> 调研对象：DeepSeek Harness 桌面版随包运行时，根目录 `D:\DeepSeek\ds\resources\app.asar\dsh`（下文所有相对路径均以该目录为基准）。
> 调研方式：直接读取 app.asar 内文件（read/glob/grep 工具无法穿透 asar，本调研用 Node 的 asar 感知文件读取逐个核验原文）。
> 版本：`dsh/package.json:4` `"version": "0.2.0-rc.2"`；Cordis 为 `4.0.4`（`dsh/package.json:8`）。
> 约定：每条事实后附 `相对路径:行号` 与原文摘要；无法核实的显式标注 **未核实**。

---

## 0. 调研对象的真实形态（先纠正入口假设）

任务书给出的高价值入口 README.md、docs/architecture.md、packages/preset/、packages/skill*/、docs/subsystems/ **在该绝对路径下均不存在**。实际目录内容为：

- `dsh/package.json:1-6`：`"name": "@deepseek-ai/dsh-desktop-runtime"`，`"private": true`，`"type": "module"`。
- 同级仅有 `desktop-runtime.json`、`node_modules/`、`package.json`（对该目录做 readdir 的实际结果）。
- `dsh/package.json` 的 `dependencies` 列出 280+ 个 `@deepseek-ai/dsh-*` 包（例：`dsh-agent-preset`、`dsh-skill`、`dsh-hook-protocol`）。
- `node_modules/@deepseek-ai/` 下共 289 个条目（含 cordis 系列 6 个与 dsh 系列）。

因此本调研的"源码"是**已构建、已打包的发行产物**，形态为：

| 形态 | 例子 | 含义 |
|---|---|---|
| README.md（含 YAML frontmatter） | `node_modules/@deepseek-ai/dsh-skill/README.md:1-4` `kind: "package-reference"` | 面向用户的契约文档，是当前唯一可靠的行为规格 |
| `lib/*.js`（rollup 产物） | `node_modules/@deepseek-ai/dsh-agent-preset/lib/index.js:1` `import { Service } from "@deepseek-ai/cordis"` | 真实运行代码，带 JSDoc 保留 |
| `src/*.ts`（仅 cordis 系列） | `node_modules/@deepseek-ai/cordis/src/registry.ts` | 仅 cordis / cordis-plugin-loader / -group / -include 随包发布 TS 源码 |

**关键限制（影响"哪些有类型"的判断）**：任务书提到的 `docs/config-catalog.md`、`docs/tool-catalog.md`、`docs/persistence-catalog.md`、`docs/cordis-primer.md`、`apps/cli/composition.md` 在整棵已安装依赖树中都不存在（对 `node_modules/@deepseek-ai` 全树按文件名检索，0 命中；全树也不存在任何名为 `docs` 的目录）。各包 `package.json` 中声明的 `"types": "./lib/types/index.d.ts"` 指向的文件在该安装中**全部缺失**：全树 3664 个文件中 `.d.ts` 计数为 0。即运行时只带 JS 与 README，类型契约只存在于 README 文本和（源码包的）`src/*.ts` 中。

---

## 1. Cordis 插件组织机制

### 1.1 插件的三种声明形态

`node_modules/@deepseek-ai/cordis/src/registry.ts:91-95`：

```ts
export type Plugin<T = any> =
  | Plugin.Function<T>
  | Plugin.Constructor<T>
  | Plugin.Object<T>
```

- 函数插件：`registry.ts:120-123` `(ctx: Context, config: T): any`。
- 类插件：`registry.ts:125-128` `new (ctx: Context, config: T): any`。
- 对象插件：`registry.ts:130-133` `apply(ctx: Context, config: T): any`。
- 公共元数据基类：`registry.ts:100-111`，字段 `name`（诊断/日志名）、`Config`（standard-schema 校验器）、`inject`（依赖服务）、`provide`（提供的服务名）、`intercept`（消费的拦截配置）。

校验入口：`registry.ts:222-228` `resolve(plugin)` 只接受函数或带 `apply` 的对象；不合法时 `registry.ts:319` 抛 `invalid plugin, expect function or object with an "apply" method`。

### 1.2 生命周期状态机与钩子

状态定义在 `cordis/src/fiber.ts:139-154`（注释即契约）：

```
PENDING  — 等待所需服务
LOADING  — 插件回调正在运行
ACTIVE   — 已加载并已提供服务
FAILED   — 回调或其配置抛错
UNLOADING— 正在执行 disposer
DISPOSED — 已移除，不可重启
```

驱动逻辑：

- 依赖可用性决定启停：`fiber.ts:611-623` `_refresh()` 遍历 `this.inject` 的名字，任一 `_store[name]` 缺失就把 epoch 置为 `INACTIVE`；`fiber.ts:625-639` `_setEpoch()` 在 `INACTIVE → 有效` 时调 `_reload()`，反向时调 `_unload()`。
- 加载：`fiber.ts:646-673` `_reload()` 先 `this.config = this._resolveConfig(this._config)` 再 `await this._execute(this._runner)`；异常记入 `this._error` 并把 epoch 置回 INACTIVE。
- 卸载：`fiber.ts:675-696` `_unload()` 逐个 `runDisposable(dispose)`，失败只记日志（`this.ctx.logger.error(reason)`），不中断。
- 等待与重启：`fiber.ts:704-710` `await()` 排空 `inertia` 后重抛启动错误；`fiber.ts:718-723` `restart()`；`fiber.ts:736-753` `update(config, noSave)` 先跑 `internal/update` waterfall（HMR 可在此否决或替换重启），再重启。
- 框架事件：`fiber.ts:193-194` 注释声明状态迁移发出 `internal/status`；`fiber.ts:586` `this.context.emit('internal/status', this, oldState)`；`fiber.ts:302` 与 `fiber.ts:120-137` 插件发布与销毁通知 `internal/plugin`。
- 类插件额外初始化钩子：`fiber.ts:251-257` 若是构造函数则 `new runtime.callback(ctx, config)`，随后依次执行 `instance[symbols.initHooks]` 与 `instance[symbols.init]()`。
- 服务基类的启动钩子：`cordis/src/service.ts:24` `static readonly init: unique symbol = symbols.init`，注释（`service.ts:12`）为 "Symbol key of an instance method run after construction (class plugins)"。

### 1.3 服务注入与发现

- 依赖声明类型：`registry.ts:19` `export type Inject<M = Dict> = (keyof M)[] | { [K in keyof M]?: M[K] }`；即数组形式 = 只声明服务名，对象形式 = 服务名 → 该服务的 intercept 配置。
- 归一化：`registry.ts:71-88` `Inject.resolve()` 把数组/对象/类继承链归一成 map，缺失配置统一补 `null`。
- 装饰器：`registry.ts:37-60` `@Inject(name, config?)`，类上写入静态 `inject`，方法上延迟到服务可用后再调用。
- 声明式等待：`registry.ts:176-177` 与 `registry.ts:300-302`，`ctx.inject(deps, callback)` 就是 `ctx.plugin({ inject, apply: callback, name: callback.name })`；JSDoc 明确"任一必需服务变化时回调会被卸载并重跑"。
- 服务注册：`cordis/src/reflect.ts:277-305` `provide(name, value?, check?)`；实现体在 `ctx.reflect.store` 中以隔离标签为键，重复注册抛 `service "..." has been registered at <...>`（`reflect.ts:289-291`）。
- 服务读取：`reflect.ts:233-243` `get(name, strict = true)`，`strict` 时只返回提供方 fiber 处于 `ACTIVE` 的实现（`reflect.ts:241`）。
- 代理级强制：`reflect.ts:135-171` 上下文 Proxy 的 `get` trap；未声明依赖直接读服务会抛 `cannot get property "<prop>" without inject`（`reflect.ts:144`），即便已 `inject` 但上下文未激活则抛 `cannot get required service "<prop>" in inactive context`（`reflect.ts:160`）。
- 服务基类：`service.ts:42-59` 构造函数里 `self.ctx.reflect.provide(name, self, this[symbols.check])`，即"注册即随所属 fiber 自动注销"（`service.ts:8-9` 注释）。
- 方法混入 `ctx`：`reflect.ts:219-222` 安装 `reflect.get/set/provide/accessor/mixin`、`fiber.runtime/effect`、`registry.inject/plugin`、`events.on/once/parallel/emit/serial/bail/waterfall`；`reflect.ts:364-390` `mixin()` 用 accessor 转发。
- 依赖变化通知：`reflect.ts:314-336` `notify(names, filter)`，逐个 fiber 重算 `_checkImpl`/`_refresh`，并发出 `internal/service`（`reflect.ts:333`）。

### 1.4 作用域与隔离

- `cordis/src/context.ts:99-107` `extend(meta)`：原型继承父上下文，不修改父。
- `context.ts:121-125` `isolate(name, label?)`：为某个服务名开独立作用域；相同 `label` 两次调用即共享作用域。
- `context.ts:139-145` `intercept(name, config)`：为子树上启动的插件注入该服务的 intercept 配置，合并规则见 `service.ts:86-102` `resolveConfig`。
- 隔离标签比较：`service.ts:61-63` `ctx[symbols.isolate][this.name] === this.ctx[symbols.isolate][this.name]`。

### 1.5 依赖解析（加载器 Loader）

`@deepseek-ai/cordis-plugin-loader` 是 dsh 的插件树实现，契约见其 README 与 TS 源码。

- 条目选项（这是插件清单的实际字段）：`cordis-plugin-loader/src/config/entry.ts:9-23`
  ```ts
  export interface EntryOptions {
    id: string      // Stable id inside the containing entry tree.
    name: string    // Module specifier imported by the entry tree.
    config?: any
    group?: boolean | null      // Marks this entry as a nested group.
    disabled?: boolean | null   // Prevents this entry and descendants from running.
    inject?: Inject | null      // Required services or service intercept config
  }
  ```
- `disabled` 支持 `!!js` 表达式：`entry.ts:86-92` `isJsExpr(options.disabled) ? Boolean(this.evaluate(options.disabled.__jsExpr)) : Boolean(options.disabled)`。
- 导入与启动：`entry.ts:221-235` `_init()` → `this.parent.tree.import(this.options.name, ...)` → `this.loader.unwrapExports(exports)` → `this.ctx.registry.plugin(plugin, this.options.config, ...)`。
- 模块说明符解析：`cordis-plugin-loader/src/config/tree.ts:112-129`，`cordis:` 前缀走 `ctx.loader.builtins`（`tree.ts:113-115`），其余经 `loader.internal.import(name, ctx.baseUrl, {})`。
- id 与嵌套：`tree.ts:8` `static readonly sep = ':'`；`tree.ts:60-72` `resolve(id)` 支持 `a:b` 形式的多级 id；`tree.ts:51-58` 未给 `id` 时自动生成 `Math.random().toString(16).slice(2, 10)`。
- 增删改：`tree.ts:82-87` `create()`、`tree.ts:90-94` `remove()`、`tree.ts:97-109` `update()`（可换组、可定位）、`tree.ts:43-49` `await()` 等待全部 import 与 lifecycle 任务。
- 依赖解析的可见性扩展：`cordis-plugin-loader/src/index.ts:129-135` `internal/plugin` 观察者把 `fiber.entry` 绑定到 fiber，并 `Inject.resolve(fiber.entry.options.inject, fiber.inject)`，即条目级 `inject` 会并入插件自身 `inject`。
- 树载体不被插值：`index.ts:104-113` `internal/config` 钩子里对声明了 `EntryGroup.key` 的插件直接返回原 config，保证 Group/Include 的嵌套行 `!!js` 留给子行自己的 fiber。
- 服务等待闸门：`index.ts:175-179` `[Service.check]()` 在 intercept 的 `await` 为真且仍有 pending 任务时返回 false，令依赖者保持 PENDING。
- Loader 声明的事件（`index.ts:23-42`）：`exit`、`loader/config-update`、`loader/entry-init`、`loader/partial-dispose`、`loader/volatile-update`（@mode emit）、`loader/patch-context`（@mode waterfall）。
- 配置校验：`cordis/src/fiber.ts:50-62` `resolveConfig(runtime, config)` 调 `runtime.Config['~standard'].validate(config)`；失败抛 `ValidationError`（`fiber.ts:19-36`，消息形如 `invalid config:` 后跟 `  - <message> (at <path>)`）。异步校验不支持（`fiber.ts:54-56`）。
- volatile 配置：`cordis-plugin-loader/README.md`（末节）描述 `equalExceptVolatile` 只对 volatile 字段做免重启提交，并发出 `loader/volatile-update`；代码位置 `cordis-plugin-loader/src/config/diff.ts`（该文件存在，本调研未逐行核对内部算法，其比较精度细节 **未核实**）。

### 1.6 组合与补丁（profile / bundle）

**profile 结构**（`app-boot` 源码注释，`node_modules/@deepseek-ai/dsh-app-boot/lib/index.js:465-475`）：

```
A profile is a directory under `$DSH_HOME/profiles/<name>` holding a
`package.json` (out-of-tree plugin dependencies plus the profile manifest
`dsh.profile` with its ordered `bundles` list) and a `cordis.patch.yml`
(the user's own patch layer, applied after every bundle layer).
```

- bundle 清单字段：`dsh.bundle.patch` 单文件或有序列表；`dsh-app-boot/lib/index.js:495-499` `bundlePatchFiles()` 校验，`index.js:507-509` `bundlePatchPaths()` 解析为绝对路径。
- 组合顺序（`dsh-app-boot/lib/index.js:472-475`）：每个 bundle 的 patch 按 `dsh.profile.bundles` 顺序叠加在**空条目列表**上，然后 profile 自身 patch，然后启动器层（`--patch` 与 flag 派生 patch）。
- 补丁语义（`dsh-app-boot/lib/index.js:61-105`，与 `cordis-plugin-include/src/index.ts:43-57` 共享同一套语义）：
  - `insert` 无 `id`：追加到顶层（`index.js:74,87`）。
  - `insert` 带 `id`：目标必须是 `group: true`，追加进其 `config` 列表（`index.js:75-86`）；不匹配告警 `patch insert: entry %C not found`（`index.js:78`），非 group 告警 `is not a group`（`index.js:82`）。
  - 无 `insert` 且无 `id`：告警 `patch: id is required for non-insert patches`（`index.js:92`）。
  - 带 `id` 的覆盖：目标不存在告警（`index.js:97`）；给了 `name` 且与目标不一致则跳过，告警 `name mismatch ... skipping`（`index.js:100-102`）；其余字段直接替换（`index.js:104-105`）。
  - `config` **整体替换而非深合并**（`dsh-app-boot/lib/index.js:2760` 的 JSON Schema description 原文："Other patches replace supplied fields; config is replaced wholesale, not deep-merged."）。
- 补丁的 JSON Schema 定义在 `dsh-app-boot/lib/index.js:2725-2762`：entry 的 `id`/`name`/`config`/`group`/`disabled`（boolean|null|loaderExpression）/`inject`/`intercept`/`isolate`；patch 为 `{insert: entryList}` 或 entryMetadata（`allOf`）。
- 内建树载体：`dsh-app-boot/lib/index.js:3703` `ctx.loader.builtins.group = Group;`；`index.js:3692` `ctx.loader.builtins.include = ...`，因此 `cordis:group` / `cordis:include` 的解析由 app-boot 安装而非 Cordis 核心。
- Group 插件：`cordis-plugin-group/src/index.ts:1-3` 仅 `export default Group`；`Group` 实现于 `cordis-plugin-loader/src/config/group.ts`，`static readonly [EntryGroup.key] = true`（文件内 "Plugin that mounts a nested loader entry group."），`config` 即子条目列表，`update(config)` 负责差异增删。
- Include 插件：`cordis-plugin-include/src/index.ts:143-156` `Include.Config = { path, initial?, patches?, enableLogs? }`；`index.ts:159-167` 类定义与 `EntryGroup.key` 标记；`index.ts:178-200` 构造函数解析 `path`（相对 `ctx.baseUrl`）、限定扩展名 `.json/.yaml/.yml`（`index.ts:27-33`）。
- 启动装配：`dsh-app-boot/lib/index.js:3691-3718` `mountRootInclude()` 创建 `{ id: 'include', name: 'cordis:include', config: { path: <fileURL>, patches: prepared } }`。
- 启动审计：`dsh-app-boot/lib/index.js:4010-4019` 收集未激活条目，命中 required 集合则抛 `StartupError`，否则仅告警；全局 required id 列表见 `dsh-app-boot/README.md:43`：`agent-loop`、`webserver`、`modules`、`connection`、`headless-runner`、`acp`、`sdk-jsonrpc-server`。
- 内置 profile 模板：`dsh-app-boot/lib/index.js:529-535`（`web` = base+web-app，`headless` = base+headless，`sdk` = base+sdk-app，`acp` = base+acp-app，`sdk-minimal` = 仅 sdk-minimal）；默认自定义 profile 只含 base（`index.js:543` `DEFAULT_PROFILE_BUNDLES = ["@deepseek-ai/dsh-base"]`）。
- profile 名合法性：`index.js:524-527` 拒绝空名、含 `/` 或 `\\`、`.`、`..`、`node_modules`。
- profile 初始化产物：`index.js:576-592` `initProfile()` 写 `package.json`（`name: dsh-profile-<dir>`、`private: true`、`dependencies: {}`、`dsh.profile.bundles`）、`cordis.patch.yml`（模板 `index.js:558-562`，注释 + `[]`）、`pnpm-workspace.yaml`（`index.js:563-568`，`nodeLinker: hoisted`、`autoInstallPeers: false`）。
- bundle 解析两锚点：`index.js:477-481`（先 dsh 安装，再 profile 目录；pnpm 管理的 profile `node_modules` 优先）；解析失败抛 `cannot resolve profile bundle ... run 'dsh plugin --profile <name> install'`（`index.js:906`）。
- 跳过语义：`index.js:912-956` 不可读或 peer 不兼容的 bundle 被跳过并记入 `skippedBundles`，不改变清单；`index.js:515-517` `reportSkippedBundles()` 每次启动打印一次。
- 兼容性检查：`dsh-app-boot/README.md:52`："Before a profile imports a plugin, DSH checks its `peerDependencies` on `@deepseek-ai/dsh` and `@deepseek-ai/dsh-*` against the single runtime version returned by `getDshRuntimeVersion()`"；豁免来自 profile 的 `compatibility.json`（同文件 \`:56\`）。

### 1.7 实例：真实安装中的 profile

本机 `C:\Users\HJIE\.dsh\profiles\` 存在 `default`、`desktop`、`headless`、`smoother-deepseek-harness`、`web` 五个 profile 目录（实际 readdir 结果）。`web\package.json` 实测：

```json
{ "name": "dsh-profile-web", "private": true, "dependencies": {},
  "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"] } } }
```

与 `dsh-app-boot/lib/index.js:531` 的模板一致；`web\cordis.patch.yml` 实测为局部覆盖行（`- id: ui-settings-general`），未声明 HMR。**注意**：以上为宿主机运行时目录，不属于 `dsh/` 包内文件。

---

## 2. Agent preset 结构

### 2.1 当前形态：Cordis 声明行（不是目录）

`node_modules/@deepseek-ai/dsh-agent-preset/README.md:12` 原文："Define an Agent's child plugins in ordinary Cordis YAML. Declare several presets and let sessions select one."

最小声明（`dsh-agent-preset/README.md:28-38`）：

```yaml
- id: agent-preset-registry
  name: '@deepseek-ai/dsh-agent-preset-registry'
  config:
    default: standard
- id: preset-standard
  name: '@deepseek-ai/dsh-agent-preset'
  config:
    id: standard
    plugins: []
```

字段表（`dsh-agent-preset/README.md:40-46`）：

| Field | Default | Meaning |
|---|---|---|
| `id` | required | Stable preset identifier |
| `plugins` | required | Child plugin entry list |
| `name` | unset | Display name |
| `description` | unset | Display description |
| `order` | unset | Roster order |

代码级 schema（`dsh-agent-preset/lib/index.js:13-19`）：

```js
static Config = z.object({
  id: z.string().required(),
  name: z.string(),
  description: z.string(),
  order: z.number(),
  plugins: z.array(z.any()).required()
});
```

- 依赖：`dsh-agent-preset/lib/index.js:10` `static inject = ["agentPresets"];`
- 组标记（保持子表达式延迟求值）：`lib/index.js:12` `static [EntryGroup.key] = true;`
- 注册动作：`lib/index.js:24-26` `async *[Service.init]() { yield await this.ctx.agentPresets.register(this.config); }`（yield 出去的 disposer 随 fiber 卸下而撤销注册）。
- README 补充的语义边界（`dsh-agent-preset/README.md:48`）："The declaration row's `id` addresses Loader edits; `config.id` is the preset identity saved by sessions. Child entry IDs may be omitted and assigned by Loader."

### 2.2 注册表服务

`node_modules/@deepseek-ai/dsh-agent-preset-registry/lib/index.js`：

- 服务名与依赖：`index.js:470-474` `static inject = ["loader", "sessionProjections"]`；`Config = z.object({ default: z.string().required(), selectedDefault: z.string().volatile() })`；`index.js:481` `super(ctx, "agentPresets")`。
- 默认值解析：`index.js:493-495` `get defaultId() { return this.config.selectedDefault.get() ?? this.config.default; }`（用户默认优先于部署默认）。
- 注册与校验：`index.js:500-524`
  - `dsh-agent-preset-registry/lib/index.js:502`：`if (!definition.id.trim()) throw new Error("Preset id must not be empty")`。
  - `dsh-agent-preset-registry/lib/index.js:503`：`if (this.definitions.has(definition.id)) throw new Error(`Duplicate agent preset: ${definition.id}`)`。
  - `dsh-agent-preset-registry/lib/index.js:521-522`：`record.ready = this.activate(record); await record.ready;`（急切激活）。
- 激活与失败可见：`index.js:525-545`：先 `entryListProblem(record.config.plugins)` 校验（529-530），失败时 `record.broken = error.message` 并 `logger.warn("agent preset <id>: <broken>")`（541-543），**失败声明仍留在名册上**。
- 条目列表校验：`lib/types/definition.js` `entryListProblem(rows, at)` —— 顶层必须是数组，否则返回 `the composition must be a top-level list of plugin rows`；每行必须是带非空 `name` 字符串的 map；`group === true` 时递归校验 `config`。
- 会话记录：`lib/types/session.js` 定义 `agentPresetProjectionDefinition`，`key: 'agentPreset'`，`init: header => header.agentPreset ?? null`，`apply` 仅在 `event.type === 'agent-preset/selected'` 时更新；文件头注释明确 "Reconstruction reads the `agentPreset` Session projection, never the header alone."
- 修订保留：`dsh-agent-preset/README.md:60`："[index.ts](src/index.ts) registers a definition and returns its disposer to Cordis... The registry owns revision retention and release."；\`:84\` 限制："Requires the `agentPresets` service. Duplicate preset IDs fail declaration loading."
- 隔离/泄漏审计：`dsh-agent-preset-registry/lib/types/mount.js` `leakedServices(ctx, mount)` 读取 `ctx.reflect.store` 与 `ctx.root[Context.isolate]`，用于判定挂载子树是否把服务泄漏到根 realm。

### 2.3 id 规则与安装位置

- **id 规则**（`dsh-agent-preset/skills/editing-cordis-compositions/SKILL.md:14` 原文）："`id` (required, lowercase letters, digits and hyphens), `plugins` (required Cordis entry list), and optional `name`, `description` and `order` (roster position). The Loader row `id` is `preset-<id>` by convention."
- **声明位置**：随包的 Web preset 位于 `@deepseek-ai/dsh-web-app` bundle 的 `presets/<id>.patch.yml`（`editing-cordis-compositions/SKILL.md:12` 给出 ids `standard`、`ptc`、`minimal`、`cordis`）。实测文件：`dsh-web-app/presets/{standard,ptc,minimal,cordis}.patch.yml`；由 `dsh-web-app/package.json` 的 `dsh.bundle.patch` 数组按序应用（`"./cordis.patch.yml"` 后接四个 preset 文件）。
- 实测片段 `dsh-web-app/presets/standard.patch.yml:4-10`：
  ```yaml
  - insert:
      - id: preset-standard
        name: '@deepseek-ai/dsh-agent-preset'
        config:
          id: standard
          order: 1
          plugins:
  ```
- 注册表安装行在 web patch 尾部：`dsh-web-app/cordis.patch.yml:561-565`（`- insert:` / `id: agent-preset-registry` / `name: '@deepseek-ai/dsh-agent-preset-registry'` / `config: default: standard`）。
- **新增/覆盖 preset 的唯一途径是 bundle patch**：`dsh-agent-preset-registry/README.md`："A new preset or an override of a shipped one is a bundle patch: an `insert` of a `@deepseek-ai/dsh-agent-preset` row, or a patch keyed by that row's id, installed into the profile with `plugin_manager`"。安装流程与两个文件（`package.json` + `cordis.patch.yml`）示例见 `editing-cordis-compositions/SKILL.md` 的 "Create a preset" 一节。
- **Web 面把 agent 面整体交给 preset**：`dsh-web-app/cordis.patch.yml:430-435` 原文注释 "Every row below composes what ONE agent contributes to the host registries... The Web surface disables them here and lets each session mount a preset instead."；具体禁用的宿主行覆盖见同文件 `447-556`（`tool-bash`、`tool-pwsh`、`tool-fs`、`skill-filesystem`、`tool-skill`、`compaction-*`、`tool-subagent*` 等）。宿主面保留的服务与理由逐条写在同段注释中（如 `tool-jobs` 注册表留在宿主，见 `cordis.patch.yml:456-464`）。
- **隔离契约**（`editing-cordis-compositions/SKILL.md:76-83` "Choose plugin placement" 一节）："A preset plugin that supplies a service must isolate the provider and all its consumers in the same realm. A service consumed by Host plugins belongs in the Host configuration. Scope controls contributions and event visibility; `isolate` controls service instances."
- **旧版 preset 目录（已废弃）**：`editing-cordis-compositions/SKILL.md:70` 原文："Before declaration rows, a user preset was a directory `$DSH_HOME/.agent-presets/<id>/` holding `preset.yml` (display `name`, `description`, `order`) and `agent.cordis.yml` (the plugin entry list). Nothing reads that directory any more."
  - 全树检索 `node_modules/@deepseek-ai`：`agent.cordis.yml` 与 `preset.yml` 仅命中该 SKILL.md 这一处，无任何代码读取它们。
  - 本机 `~/.dsh/.agent-presets` 目录存在但为空（实测），与"已无读取方"一致。
  - `preset.yml` 是否还有该段落未列出的字段、`agent.cordis.yml` 的完整语法：**未核实**。
- 退役字段：`dsh-agent-preset-registry/README.md`："A profile patch may still carry the retired `modeSelectionEnabled` field; the registry declares no such field and neither reads nor rewrites it."

### 2.4 其他相关载体

- `dsh-experimental-agent-team-profile/cordis.patch.yml:1-34` 展示"实验能力即可选 bundle"的模式：禁用 `tool-subagent*` 四行后 `insert` 若干 `dsh-experimental-agent-team` 行，且无 preset 声明。它证明 bundle 也可只改宿主面。
- 本机存在 `windows-2a47ad.dshpreset` 文件，但其格式：在 `node_modules/@deepseek-ai` 全树检索 `dshpreset` 零命中，**未核实**（可能由安装目录之外的包提供）。

---

## 3. Skill 发现路径、frontmatter 契约与注入

### 3.1 三个包的分工

- 注册表 `dsh-skill`：提供 `ctx.skills`，合并多来源目录（`dsh-skill/README.md:12`："the registry merges everything any provider reports"）。
- 本地提供方 `dsh-skill-filesystem`：扫描磁盘根并按优先级上报候选。
- 模型消费者 `dsh-tool-skill`：渲染会话目录 + 提供 `skill` 工具 + 处理 `/name` 显式调用。

### 3.2 发现路径与优先级（rank）

`dsh-skill-filesystem/lib/index.js:21-25` 常量与 `index.js:150-188` `roots(cwd)`：

| Rank | 常量 | 路径 | 代码位置 |
|---|---|---|---|
| 100 | `PROJECT_DSH_RANK` | `<projectRoot>/.dsh/skills` | `lib/index.js:155-158` |
| 200 | `PROJECT_AGENTS_RANK` | `<projectRoot>/.agents/skills` | `lib/index.js:159-164` |
| 300 | `CUSTOM_RANK` | `Config.customSkillDirs` 各目录 | `lib/index.js:166-170` |
| 400 | `USER_DSH_RANK` | `<dshHome>/skills`，`skipSystem: true` | `lib/index.js:171-176` |
| 500 | `USER_AGENTS_RANK` | `<agentsHome>/skills` | `lib/index.js:177-180` |
| 600 | `BUNDLED_SKILL_RANK` | `bundledSkillDir`（`trustedHost: true`） | `lib/index.js:181-186`；常量定义 `dsh-skill/lib/index.js:23` |

- 与 README 表格一致：`dsh-skill-filesystem/README.md:49-54`（含 "project root 是最近的 `.git` 祖先，否则用 cwd"、"user DSH root 跳过 `.system`"、"rank 600 为 bundled"）。
- 目录默认值：`lib/index.js:77` `resolveDshHome(config.dshHome)`；`index.js:78` `resolve(config.agentsHome ?? process.env.DSH_AGENTS_HOME ?? join(homedir(), ".agents"))`；`index.js:84` `config.bundledSkillDir ?? (includeDefaultRoots ? process.env.DSH_BUNDLED_SKILL_DIR : void 0)`。
- `includeDefaultRoots: false` 会整体省略项目根、用户根与 `DSH_BUNDLED_SKILL_DIR` 默认值（`dsh-skill-filesystem/README.md:56`）。
- 谁设置 `DSH_BUNDLED_SKILL_DIR`：在 `node_modules/@deepseek-ai` 全树检索仅命中 `dsh-skill-filesystem` 自身，**未核实**其注入点（可能在启动器或 Electron 宿主中）。

### 3.3 文件形态与 SKILL.md frontmatter 契约

发现深度：**只有一层**。`dsh-skill-filesystem/README.md:148`（Known Limitations 首条）："Discovery is one level deep — only `<root>/<name>/SKILL.md` and `<root>/<name>.md` are recognized; nested skill trees and package manifests are ignored."；代码中目录包解析 `path: join(entry.path, "SKILL.md")`、平铺文件 `entry.name.endsWith(".md")`（`lib/index.js:584-599`）。

解析实现 `dsh-skill-filesystem/lib/index.js:664-705`（`parseSkillFile`）：

| 字段 | 必需 | 行为 | 行号 |
|---|---|---|---|
| `name` | 是 | 非空字符串；否则告警 `frontmatter requires name and description` | `679-684` |
| `description` | 是 | 同上 | `680-684` |
| name 语法 | — | 不匹配 `isSkillName` 告警 `invalid skill name "<name>"` 并丢弃 | `685-688` |
| `whenToUse` | 否 | 可选字符串，原样带入候选 | `699`（`optionalString` 定义 `845-848`） |
| `metadata` | 否 | 仅接受非 null、非数组的对象 | `879-883` |
| `disable-model-invocation` | 否 | 严格布尔语法 | `849-859` |
| `user-invocable` | 否 | 严格布尔语法 | `849-859` |

- 名称语法：`dsh-skill/lib/index.js:17` `const SKILL_NAME = /^[a-z0-9]+(?:-[a-z0-9]+)*$/`；`isSkillName` 在 `29-31`。
- 严格布尔语法（`lib/index.js:863-878`）：接受真实布尔、`1`/`"1"`/`0`/`"0"`，以及大小写不敏感的 `true/false`、`yes/no`、`on/off`；其余抛 `frontmatter field "<key>" must be a boolean`，导致**整个 skill 被丢弃并告警**（`index.js:690-695`；`dsh-skill-filesystem/README.md:38` 亦说明 "a rejected spelling or a non-boolean value drops the whole skill with a warning"）。
- 旧键拒绝（`index.js:849-862`）：`disableModelInvocation`、`modelInvocable`、`userInvocable` 三个驼峰旧名一律抛 `frontmatter field "<legacy>" is unsupported; use "<canonical>"`。
- 调用策略解析结果（`index.js:855-858`）：`modelInvocable = disableModelInvocation !== true`，`userInvocable = userInvocable !== false`（两个键都省略时两面均可调用）。
- 目录/正文生命周期分离：`dsh-skill-filesystem/README.md:42` "discovery parses frontmatter into the catalog entry, and every load re-reads the current file"；`parseSkillFile` 每次重新读文件并 `content: parsed.body.trim()`（`index.js:702-703`）。
- 变更检测：`lib/index.js:57-60` 监听 `fs/observed`，仅对首方写工具（`mutationToolName(actor)`）触发的改动同步失效；宿主文件监听负责 IDE/Git/shell 改动（`dsh-skill-filesystem/README.md:79` "Change detection" 一节）。

### 3.4 注册表契约（provider / 合并 / 缓存）

- 配置：`dsh-skill/lib/index.js:120` `static Config = z.object({ collectCacheMaxEntries: z.number().default(DEFAULT_COLLECT_CACHE_ENTRIES) })`，`dsh-skill/README.md:44` 的字段表给出默认值 `128`。
- 提供方注册：`dsh-skill/lib/index.js:147-183` `registerProvider(create)` —— `create(control)` 同步拿到 `{ signal, invalidate }`；返回值是 Cordis effect disposer。`runtime` 为保留名：`dsh-skill/lib/index.js:161` `if (name === RUNTIME_PROVIDER) throw ...`（`RUNTIME_PROVIDER = "runtime"`，`:20`）。
- 内嵌 skill 注册：`index.js:193-215` `register(skill)`，同层同名 first-wins 并告警（197-199），默认调用策略与 provider 标签 `runtime` 自动补齐（201-208）。
- 目录读取：`index.js:224-225` `list(options)` = `(await this.snapshot(options)).skills`；加载单个定义 `get(name, options)` 在 250 行起。
- 候选校验：`dsh-skill/lib/index.js:454` provider 返回非法名抛 `skill provider "<providerName>" returned invalid skill name "<name>"`；`:466`、`:481` 亦有对应校验。
- 调用策略四象限、合并/缓存/失效语义：见 `dsh-skill/README.md:48` "What the registry gives you"、`:88` "Catalog collection"、`:97` "Loading and staleness"、`:105` "Invalidation" 各节（例如 "The registry has no TTL: only a provider calling its registration-scoped `invalidate()`, or a runtime registration or disposal, clears completed catalogs."）。
- 命名导出（`index.js:566`）：`BUNDLED_SKILL_RANK`、`SkillRegistry`、`escapeText`、`isModelInvocable`、`isSkillName`、`isUserInvocable`、`renderSkillContent`。

### 3.5 skill 如何注入 prompt

由 `dsh-tool-skill` 完成，两种入口共用同一份渲染（`renderSkillContent` 定义在 `dsh-skill/lib/index.js:57-60` 起）：

1. **会话目录（durable 目录消息）**：`dsh-tool-skill/lib/index.js:203-236`，注册在 `agent/pre-step` waterfall 上。
   - 可见性闸门：`dsh-tool-skill/lib/index.js:203-214`仅当 `ctx.tools.get(skillTool.name, agent) === skillTool`（本插件注册的那个确切工具定义可见）才取 `ctx.skills.snapshot(...)`，否则给空集。
   - 快照不完整则不发布、保留上次视图：`dsh-tool-skill/lib/index.js:216` `if (!snapshot.complete) return decision;`
   - 只发布可被模型调用的 skill：`dsh-tool-skill/lib/index.js:217` `snapshot.skills.filter(isModelInvocable)`。
   - 以**条目摘要的 digest** 判断是否重发（218-230 行）。
   - 首次用 `renderCatalogMessage`（238-261），之后用 `renderCatalogUpdate`（262-286）追加整份替换目录。
   - 消息形态：`<system-reminder>` + `<available_skills>` + 每行 `- \`<name>\`: <description>`（293-295 行）+ 结尾两条指令（250-251 行），`source.kind = "skill-catalog"`（256 行）。这与本会话实际收到的技能目录模板逐字一致。
   - 空目录会显式作废旧名字：`dsh-tool-skill/lib/index.js:263` "No skills are currently available through the `skill` tool. Do not use names from earlier skill catalogs."
   - 描述长度上限：`Config.catalogDescriptionMaxLength`，默认 `500`（`dsh-tool-skill/lib/index.js:49`；`dsh-tool-skill/README.md` 字段表同值，最小值 3）。
2. **`skill` 工具（模型显式加载）**：`index.js:59-157` 定义 `name: "skill"`，参数 `{ name: string, required }`（62-66 行），输出含 `name`/`provider`/`resourceBase`/`content`（67-131 行），`render` 直接调 `renderSkillContent(value)`（133-136 行）。执行体错误文本精确为（139/146/147/149/150 行）：
   - `invalid skill name "<name>"`
   - `skill "<name>" is unknown or no longer available`
   - `skill "<name>" is not available for model invocation`
3. **用户 `/name` 显式调用**：`index.js:168-202`，扫描本 step 已认领的用户消息中的空白边界 `/name` token（`invokedSkillNames`），命中 user-invocable 的 skill 就注入 `renderSkillContent` 的 `user` 角色消息（`source.kind = "skill-invocation"`，184-195 行），追加在其它注入之后（198-201 行）。这是 `disable-model-invocation` skill 的唯一入口（README "Invocation boundary" 一节）。

### 3.6 随包发布的 skill 实例（可作为 frontmatter 样板）

`dsh-agent-preset/skills/` 下 4 个（实测目录）：

- `agent-experience/SKILL.md`（frontmatter 仅 `name` + `description`，`agent-experience/SKILL.md:1-4`）
- `cordis-plugin-development/SKILL.md`（另有 `references/` 与 `templates/` 子目录）
- `editing-cordis-compositions/SKILL.md`
- `cordis-composition-reference/SKILL.md` + `references/packages.md`

`cordis-plugin-development/SKILL.md:28-32`（"Knowledge sources, in order"：先 Inspection、再 Package documentation、最后 Source）与 `editing-cordis-compositions/SKILL.md:8-9` 明确要求先读 `cordis_inspect_query` 结果、再读 package README（由 `Config.listConfigs` 返回的 `packageDir`），最后才看 `lib/`。`cordis-composition-reference/references/packages.md:1-5` 自述为生成产物（`scripts/gen-plugin-packages.ts`，`doc-sync` 门禁），列出全部可加载 plugin 包名与 "Config: yes/no"。该文件共 513 行，是本会话能拿到的最接近"插件目录"的随包清单。

---

## 4. 扩展点清单：稳定契约 vs 内部实现

### 4.1 可视为稳定契约的扩展点

判定标准：有 README 明文规格 + 有具名类型/配置 schema + 有随包 skill 或官方工具引导。

| # | 扩展点 | 契约证据 | 备注 |
|---|---|---|---|
| 1 | Cordis 插件形态（函数 / 类 / `{apply}`）与 `name/Config/inject/provide/intercept` | `cordis/src/registry.ts:91-111`、`120-133`；`cordis/README.md` Quick Start | 三种形态都有 JSDoc 与类型 |
| 2 | 服务注册与消费（`Service` 子类、`ctx.provide/get`、`ctx.inject`） | `cordis/src/service.ts:11-59`；`reflect.ts:176-186`(JSDoc)、`277-305`、`233-243` | 未 inject 直接读服务会抛错，属强制边界 |
| 3 | Loader 条目选项与补丁方言（`id/name/config/group/disabled/inject`、`insert`、按 id 覆盖、`isolate`、`!!js`） | `cordis-plugin-loader/src/config/entry.ts:9-23`；`cordis-plugin-loader/README.md` "Entry Options"/"API" 两表；`dsh-app-boot/lib/index.js:2725-2762`（JSON Schema）；`dsh-agent-preset/skills/cordis-composition-reference/SKILL.md:11-19` | 补丁整块替换 config 是写在 schema description 里的硬规则 |
| 4 | profile 与 bundle 清单：`dsh.profile.bundles`、`dsh.bundle.patch`、`manifestVersion`、`engines.dsh`、`dsh.client` | `dsh-package-manifest/README.md:30-57`（类型示例与字段表）、`:93`（不强制声明）；`dsh-app-boot/lib/index.js:465-509`；`dsh-app-boot/README.md:48-56` | `dsh-package-manifest/README.md:93` 自述 "Current installers and loaders do not enforce `dsh.manifestVersion` or `engines.dsh`"；真正被强制的是 `peerDependencies` 版本区间（`dsh-app-boot/README.md:52`） |
| 5 | agent preset 声明（`@deepseek-ai/dsh-agent-preset` 行的 `config` 字段） | `dsh-agent-preset/lib/index.js:13-19`；`dsh-agent-preset-registry/README.md` 字段表；`editing-cordis-compositions/SKILL.md:14` | 声明行 id 约定 `preset-<id>` |
| 6 | `agentPresets` 注册表配置（`default`、volatile `selectedDefault`） | `dsh-agent-preset-registry/lib/index.js:471-474`；`dsh-agent-preset-registry/README.md` 字段表 | `selectedDefault` 为 volatile，改它不重启 |
| 7 | SKILL.md frontmatter：`name`、`description`、`whenToUse`、`metadata`、`disable-model-invocation`、`user-invocable` | `dsh-skill-filesystem/README.md:34-38`；`lib/index.js:664-705`、`849-883` | 严格布尔语法与旧键拒绝是明确契约 |
| 8 | 本地 skill 根与 rank（含 `customSkillDirs`/`includeDefaultRoots`/`bundledSkillDir`） | `dsh-skill-filesystem/README.md:49-64`；`lib/index.js:21-25`、`150-188` | |
| 9 | skill provider 接口（`registerProvider` + `list()/get()` + `invalidate()`）与调用策略两键 | `dsh-skill/lib/index.js:147-183`、`193-215`；`dsh-skill/README.md:48` "What the registry gives you" | provider 为同进程借用对象 |
| 10 | 工具注册（`defineTool`）与呈现模式 `native/ptc/both` | `dsh-tools/README.md` "Register a tool"/"Configure the presentation mode" | 配置项 `mode`、`maxParallelSubCalls` |
| 11 | system prompt 分节与变量贡献（`ctx.systemPrompt.section/variable`、`order`、`complete`） | `dsh-system-prompt/README.md` "Contribute a prompt section"/"Contribute a prompt variable" | `complete: true` 只能有一个 |
| 12 | 宿主→客户端能力暴露（`@Remote` / `@RemoteScope` / `TypertRemoteService` / `RemoteError` 码表） | `dsh-typert-protocol/README.md` "Exposing a Host method"/"Reporting and reading a Remote failure" | 生成管线负责 wire 描述符 |
| 13 | 客户端插件清单 `dsh.client`（`platform`、`external`、`inject`、`immediately`，`exports` 暴露 `./client`） | `dsh-client-modules/README.md` "Declaring a client plugin"/"Sharing modules"；实例 `dsh-client-ui-theme/package.json` 的 `dsh.client` | 宿主经 `/plugins` 提供已构建 `lib/client.js` |
| 14 | 持久化安装入口 `plugin_manager`（`install_bundle`、`set_plugin`、`set_bundle`、`list_bundles`、`list_plugins`） | `dsh-plugin-manager/README.md`；`dsh-agent-preset/skills/cordis-plugin-development/SKILL.md:8` | 每次调用需 Full access 或审批 |
| 15 | 运行时 API 探查 `cordis_inspect_list/query`（含 `Config.listConfigs`） | `dsh-tool-cordis/README.md` | 只读；见 4.3 限制 |
| 16 | 外部 hook 协议（Claude Code / Codex `hooks.json` 的 command hook、退出码 2 = 阻断） | `dsh-hook-protocol/README.md` "What a hook can do"；`lib/index.js:62` `BLOCKING_EXIT_CODE = 2` | 只执行 `{type:'command'}`，其余形态解析后跳过并告警 |

### 4.2 明确属于"内部实现"的部分

| 项 | 证据 | 性质 |
|---|---|---|
| Cordis 内部事件与状态机 | `internal/status`(`fiber.ts:586`)、`internal/plugin`(`fiber.ts:302`)、`internal/config`(`fiber.ts:642`)、`internal/update`(`fiber.ts:748`)、`internal/service`(`reflect.ts:333`)、`internal/get`/`internal/set`(`reflect.ts:153,191`) | 命名前缀 `internal/`，非包 README 承诺的对外 API；其中 `internal/config` 被 Loader 明确用于树载体保真（`cordis-plugin-loader/src/index.ts:104-113`） |
| `Service.init/check/config/invoke/extend/tracker` 符号 | `cordis/src/service.ts:11-25` | 半公开：插件作者用它（如 `dsh-agent-preset/lib/index.js:24`），但无独立文档章节 |
| Fiber 的 `store/inertia/_runner/uid` | `fiber.ts:184-210`、`611-696` | 运行时内部状态；对外只承诺 `state`、`name`、`update/restart/await/dispose` |
| `Entry` 的 `_patchContext/_commitVolatile`、`equalExceptVolatile` | `cordis-plugin-loader/src/config/entry.ts:99-176` | README 只描述可观察结果（volatile 免重启），函数本身带 `private`/`_` 前缀 |
| `loader.builtins` 的 `group`/`include` 由 app-boot 安装 | `dsh-app-boot/lib/index.js:3692,3703` | `cordis:group`/`cordis:include` 不是 Cordis 核心契约，而是 dsh 启动装配的别名 |
| preset 挂载内部：`PresetTree`、`createScope`、`leakedServices`、`livePresetMounts` | `dsh-agent-preset-registry/lib/types/mount.js` 全文；`index.js:123`、`271` | README 明确把 `mount.ts` 放在 "Implementation internals" 折叠块内 |
| `agentPresetProjectionDefinition` 的字段与 stateVersion | `dsh-agent-preset-registry/lib/types/session.js` | 会话投影内部定义，README 仅说 "session logs retain the preset ID" |
| Hook `hook/invoked`/`hook/result` 事件与不变量伴随 | `dsh-hook-protocol/README.md` "hook/* session events"；`lib/invariant.js` 存在 | 事件本身是持久化事实（属契约），但"必须在开放 turn 内"等由 invariant 伴随强制 |
| `dsh-skill-filesystem` 的 Chokidar/缺失根探测细节 | `lib/index.js` watch manager；`dsh-skill-filesystem/README.md:155-162` Dev Note 自述为开放设计（TODO 提议抽出 file-watch 服务） | 明确标注为可重构内部 |
| 已退役但可被读入的字段（如 `modeSelectionEnabled`） | `dsh-agent-preset-registry/README.md` | 声明为 registry 既不读也不写 |

### 4.3 已知边界与"未核实"

已由文档明确声明的能力边界（可直接引用）：

- `cordis_inspect_query` 的 `Config.listConfigs` **只遍历 profile Loader 树**；只在 preset 声明里的插件不会被列出（`dsh-tool-cordis/README.md` Known Limitations）。
- skill 目录**不含** `whenToUse`、来源、provider 元数据；正文无长度上限；资源只是提示不下载（`dsh-tool-skill/README.md` Known Limitations）。
- skill 发现**只一层**、project root 只认 `.git`、坏条目静默消失（`dsh-skill-filesystem/README.md` Known Limitations）。
- preset **不是安全沙箱**：YAML 与插件都能执行 Host 代码；用户覆盖整体替换子列表且不合并未来变更（`dsh-agent-preset-registry/README.md` Known Limitations）。
- hook：`updatedInput` 解析但不生效；`continue:false` 折叠为 sticky stop 但无 run 级硬停；只有 command 形态执行（`dsh-hook-protocol/README.md` Known Limitations）。
- bundle 兼容豁免是精确版本对（`name@version` → DSH 版本列表），升级即失效（`dsh-app-boot/README.md:56`）。

本调研中显式 **未核实** 的项目：

1. `preset.yml` 除 `name`/`description`/`order` 外的字段，以及 `agent.cordis.yml` 的完整语法（仅有 SKILL.md 的文字描述，无代码读取方）。
2. `DSH_BUNDLED_SKILL_DIR` 的实际注入点（全树仅见消费方，未见设置方）。
3. `dshpreset` 文件格式是否由核心支持（`@deepseek-ai` 全树零命中，仅宿主机存在 `windows-2a47ad.dshpreset`）。
4. `cordis-plugin-loader/src/config/diff.ts` 中 `equalExceptVolatile` 的逐行算法（文件存在，未逐行核对）。
5. `cordis/src/events.ts` 的事件派发模式（`emit/serial/bail/waterfall/parallel`）内部实现（仅在 `reflect.ts:222` 看到混入名，未读 events.ts）。
6. 任务书提到的 `docs/`、`packages/`、`apps/` 源目录树、`config-catalog.md`、`tool-catalog.md`、`composition.md`：在该桌面版发行树中**不存在**，无法据此核对"生成目录"的内容。
7. 各包 `package.json` 声明的 `lib/types/**/*.d.ts`：本安装中 **0 个 `.d.ts` 文件**，"有类型"目前只能从 README 与源码包的 `src/*.ts` 推断。
