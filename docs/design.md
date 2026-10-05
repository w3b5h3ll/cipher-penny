# CipherPenny 技术设计（Design）

> 状态：v0.2 · 对应需求：[spec.md](./spec.md) v0.2

## 1. 总体架构

纯前端单页应用 + PWA，所有逻辑在浏览器内执行。

```
┌──────────────────────────── 浏览器 ────────────────────────────┐
│  ui/        React 界面（hash 路由）                             │
│    │                                                           │
│  state/     会话：锁定/解锁、内存中的明文数据、防抖保存、自动锁定 │
│    │                     │                                     │
│  core/      纯函数领域逻辑 │ crypto/  WebCrypto 封装             │
│  （金额、日期、账本、      │ （KDF、密钥封装、加解密、文件格式）   │
│   周期、统计、解析器）     │                                     │
│                          storage/  IndexedDB（只存密文信封）     │
└────────────────────────────────────────────────────────────────┘
         ▲ 静态文件（HTML/JS/CSS/SW）
   GitHub Pages：只托管代码，永远接触不到数据
```

分层规则（由代码评审保证）：

- `core/` 不依赖 DOM、React 和浏览器存储，可以在 Node 中直接测试。
- 跨端（以后的 Flutter Android 应用）共享的是**格式规范和测试向量**，不是代码：[vault-format.md](./vault-format.md) 定义加密信封和数据结构，`fixtures/` 下的 JSON 向量由 TS 测试和以后的 Dart 测试共同使用。
- `crypto/` 只依赖 `globalThis.crypto`（浏览器和 Node 都有）。
- `storage/` 只读写密文信封，不知道明文结构。
- `ui/` 不直接调用 `crypto/` 或 `storage/`，统一经过 `state/`。

## 2. 技术选型与决策记录

| 决策 | 选择 | 理由 / 放弃的方案 |
| --- | --- | --- |
| D1 形态 | Web（PWA），部署 GitHub Pages；Android 以后用 Flutter 单独实现 | 零成本，桌面优先。不做 iOS。两端通过加密数据格式互通，而不是共享代码，所以格式必须有独立规范和测试向量（D10）。 |
| D2 框架 | React 19 + TypeScript + Vite | 生态和 AI 工具支持最好；放弃 Svelte（更轻，但团队/AI 熟悉度略低）。 |
| D3 运行时依赖 | 仅 `react`、`react-dom` | 降低供应链和 XSS 风险。路由（hash）、状态管理、IndexedDB 封装、图表都自己写，代码量很小。 |
| D4 KDF | PBKDF2-SHA256，60 万次迭代 | WebCrypto 内置、零依赖。Argon2id 更抗 GPU 破解，但需要 WASM 依赖，且 GitHub Pages 无法开启 COOP/COEP 多线程。文件格式中记录 KDF 参数，以后可升级。 |
| D5 加密 | AES-256-GCM，信封加密（DEK + KEK） | GCM 自带完整性校验；改密码只需重新封装 DEK。 |
| D6 存储粒度 | 整个账本作为一个加密 JSON 文档 | 个人账本规模小（1 万笔约 2 MB 明文），整体加密耗时可接受；格式简单，导出、备份、以后同步都是同一个文件。代价是每次保存都重新加密全量数据，通过 300 ms 防抖缓解。 |
| D7 路由 | hash 路由（`#/stats`） | GitHub Pages 不支持 SPA 回退，避免刷新 404。 |
| D8 自然语言解析 | 本地规则解析器 | 离线、零成本、可预测、可测试；大模型解析作为以后的可选增强。 |
| D9 视觉规范 | 原生 CSS，变量取值参考 **TDesign 设计令牌**；不引入任何组件库 | 比较过的方案：**Ant Design** 的 CSS-in-JS 会在运行时注入 `<style>`，必须放开 CSP 的 `style-src 'unsafe-inline'`，而且是大体积运行时依赖；**IBM Carbon** 偏英文企业风格，中文排版考虑少；Arco、Semi 和 TDesign 类似，但没有 Flutter 版。**TDesign** 以中文场景为先，同时有桌面和移动端规范，而且有官方的 **TDesign Flutter**，以后 Android 版可以直接用它的组件，两端视觉一致。只借用令牌而不装 `tdesign-react`，既保持了零第三方运行时依赖和严格 CSP，也不受组件库升级影响。品牌色沿用图标的琥珀色（取 TDesign 橙色色板），功能色（成功、错误）、中性灰、圆角、字号、阴影都用 TDesign 的取值。 |
| D11 字体 | 用 Fontsource 自托管 Inter、思源黑体（Noto Sans SC）、JetBrains Mono 的可变字体 | CSP 只允许同源资源，国内也访问不了 Google Fonts，所以必须自托管。字体包只包含 woff2 和 CSS，不含 JS，放在 `devDependencies`，构建时打包进 `dist/`。思源黑体按 unicode-range 切成约 100 片（共 4.5 MB），浏览器只下载页面用到的切片。可变字体比静态 400 + 600 两个字重（7.4 MB）更小。`font-family` 中把本机的 `Source Han Sans SC` 和 `Noto Sans CJK SC` 排在网络字体前面，本机装了就不会下载。字体不放进 Service Worker 的预缓存，改为运行时 CacheFirst 缓存，避免首次安装就下载全部中文切片。 |
| D10 跨端互通 | 格式规范 + JSON 测试向量 | 加密格式只用 PBKDF2、AES-GCM、标准 Base64 这类各语言都有标准实现的原语（Dart 可用 `cryptography` 包）。解析器的期望行为也以 JSON 用例描述，Dart 版本跑同一份用例即可对齐。 |

## 3. 数据模型（明文，仅存在于内存）

```ts
type Cents = number;           // 整数，单位：分
type ISODate = string;         // 'YYYY-MM-DD'，本地日期

interface VaultData {
  schemaVersion: 1;
  accounts: Account[];
  categories: Category[];
  transactions: Transaction[];
  recurring: RecurringRule[];
  settings: { autoLockMinutes: number };   // 0 = 关闭自动锁定
}

interface Account     { id; name; kind: 'cash'|'ewallet'|'debit'|'credit'|'other'; initialBalance: Cents; archived: boolean }
interface Category    { id; name; type: 'expense'|'income'; icon: string; keywords: string[]; archived: boolean }
interface Transaction { id; type; amount: Cents; categoryId; accountId; date: ISODate; note: string;
                        createdAt: string; updatedAt: string; recurringId?: string }
interface RecurringRule {
  id; name; type; amount: Cents; categoryId; accountId; note: string;
  frequency: 'weekly'|'monthly'|'yearly'; interval: number;   // 每 interval 个周期
  startDate: ISODate; endDate?: ISODate; active: boolean;
  lastGenerated?: ISODate;                                    // 已生成到的最后一个日期
}
```

- 金额恒为正数，收支方向由 `type` 决定。
- ID 使用 `crypto.randomUUID()`。
- `schemaVersion` 用于以后的数据迁移（`core/migrate.ts`）。

## 4. 加密设计

### 4.1 密钥层次

```
主密码 ──PBKDF2(salt, 600k)──▶ KEK（不可导出，仅用于 wrap/unwrap）
                                 │ AES-GCM wrap（AAD = "cipher-penny:v1:dek"）
随机生成 DEK（AES-256-GCM）◀──────┘
   │ AES-GCM encrypt（AAD = "cipher-penny:v1:payload"）
   ▼
JSON.stringify(VaultData) ──▶ 密文 payload
```

- 每次保存使用新的 96 位随机 IV；同一 DEK 下随机 IV 的碰撞概率在个人使用量级下可忽略。
- 修改密码：用新密码派生新的 KEK、生成新 salt，重新封装同一个 DEK，payload 不变。
- 密码错误表现为 unwrap 失败（GCM 认证失败），统一抛出 `WrongPasswordError`。
- 解锁后 DEK 保存在内存中（需要可导出才能在改密码时重新封装）。锁定时丢弃 DEK 引用和明文数据。

### 4.2 信封格式（存储和备份文件共用）

规范性定义见 [vault-format.md](./vault-format.md)，这里只说明设计取舍：

- 读取时严格校验 `format`、`version` 和字段类型，不支持的版本抛出 `UnsupportedFormatError`。
- KDF 参数没有单独做认证：如果被篡改，派生出的 KEK 是错的，unwrap 会失败，不会导致数据被静默替换。

### 4.3 威胁模型

| 威胁 | 是否防护 | 说明 |
| --- | --- | --- |
| 他人拿到设备的浏览器数据或备份文件 | ✅ | 只有密文；强度取决于主密码。 |
| GitHub Pages 或同步端读取数据 | ✅ | 它们只有代码或密文。 |
| 密文被篡改 | ✅ | GCM 认证失败，拒绝加载。 |
| 解锁状态下有人拿到手机 | ⚠️ 部分 | 自动锁定缩短暴露窗口。 |
| 页面被注入恶意脚本（XSS、恶意依赖、托管被篡改） | ⚠️ 部分 | 注入的代码可以直接读取内存明文，这是所有网页端加密应用的固有局限。缓解：严格 CSP、只有两个运行时依赖、禁止 innerHTML、锁文件 + CI 构建。 |
| 主密码被暴力破解 | ⚠️ 部分 | PBKDF2 60 万次；要求至少 8 位，建议使用长口令。 |
| 忘记主密码 | ❌ | 设计上无法恢复；创建时强提示，建议定期导出备份。 |

## 5. 模块说明

| 模块 | 职责 |
| --- | --- |
| `core/money.ts` | 金额字符串与分的互转、格式化。 |
| `core/dates.ts` | 本地日期运算（不受时区影响，统一用 `YYYY-MM-DD`）。 |
| `core/model.ts` | 类型定义。 |
| `core/defaults.ts` | 默认账户、分类与关键词，创建空账本。 |
| `core/ledger.ts` | 不可变的增删改操作。 |
| `core/recurring.ts` | 计算规则的发生日期并补齐账单（F-REC）。 |
| `core/stats.ts` | 支出统计（F-STAT）：按月、按年、按分类、按账户汇总，日均和月均的天数、月数。所有函数只计入 `type === 'expense'` 的记录；收入记录保留在数据中，但不参与统计也不显示。 |
| `core/csv.ts` | CSV 导出（F-IO-3）。 |
| `core/parser/` | 自然语言解析（F-QA），细分为中文数字、金额、日期、分类匹配。 |
| `crypto/vault-crypto.ts` | 创建、打开、重新保存、修改密码、信封校验（F-VAULT）。 |
| `storage/idb.ts` | 极简 IndexedDB 键值封装。 |
| `state/session.ts` | 会话状态机（加载中 → 空 / 已锁定 → 已解锁），对外提供 `useSession()`。 |
| `ui/` | 页面和组件。 |

### 会话状态机

```
loading ──有信封──▶ locked ──正确密码──▶ unlocked ──锁定/超时──▶ locked
   └──无信封──▶ empty ──创建密码──▶ unlocked
```

- 修改数据：`session.update(fn)` 先更新内存中的状态并通知界面，再用 300 ms 防抖加密保存；页面隐藏（`visibilitychange`）时立即保存。
- 自动锁定：监听 `pointerdown`、`keydown`、`visibilitychange`，超时后先保存再锁定。
- 解锁成功后执行周期账单补齐（F-REC-2）。

## 6. 自然语言解析器

处理流程：

1. **规范化**：全角数字和标点转半角，去掉 `¥`/`￥`。
2. **分段**：按 `，,；;。！!？?\n` 和“然后、还有、另外”切分。
3. **逐段处理**：
   1. 提取日期并从文本中移除；有日期时更新上下文日期（向后延续）。
   2. 把带货币单位的中文数字（如“三十五块”）转成阿拉伯数字。
   3. 提取金额候选，优先取带单位的，否则取最后一个；没有金额的分段不产生草稿。
   4. 判断收入提示词，按最长关键词匹配分类，从而确定类型。
   5. 去掉填充词，剩余部分作为备注。
4. 输出 `Draft[]`，交给界面编辑确认。

解析器只接受当前日期和分类列表作为输入，是纯函数，便于测试。

## 7. 构建与部署

- 使用 Vite 的 `base: '/cipher-penny/'`（可通过 `BASE_PATH` 覆盖）。
- 用 `vite-plugin-pwa` 生成 Service Worker 和 manifest（`registerType: autoUpdate`）。vite-plugin-pwa 2 不再自动开启 `skipWaiting` / `clientsClaim`，配置里必须显式打开，否则新版本会一直停在 waiting 状态，用户永远拿不到更新。新版本在下次打开应用时生效。
- 自定义 Vite 插件只在生产构建时向 `index.html` 注入 CSP `<meta>`（开发模式下 Vite 的热更新需要内联脚本）。
- GitHub Actions 依次执行：安装依赖（锁文件）→ 类型检查 → lint → 测试 → 构建 → 推送到 `master` 时部署 Pages。
