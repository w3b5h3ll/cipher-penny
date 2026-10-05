# CipherPenny 保险库格式规范 v1

> 状态：v1 · 规范性文档。Web 端（TypeScript）和以后的 Android 端（Flutter/Dart）都必须遵守。
> 任何不兼容的修改都必须提升 `version`，并保留读取旧版本的能力。
> 互通性测试向量：[`fixtures/vault-v1.json`](../fixtures/vault-v1.json)。

## 1. 信封（Envelope）

本地存储和备份文件使用同一个 JSON 结构，文件编码为 UTF-8，备份文件扩展名为 `.cpenny.json`。

```json
{
  "format": "cipher-penny-vault",
  "version": 1,
  "kdf": { "name": "PBKDF2", "hash": "SHA-256", "iterations": 600000, "salt": "<base64, 16 字节>" },
  "wrappedKey": { "iv": "<base64, 12 字节>", "data": "<base64, 48 字节>" },
  "payload": { "iv": "<base64, 12 字节>", "data": "<base64>" },
  "updatedAt": "2026-10-05T04:00:00.000Z"
}
```

| 字段 | 要求 |
| --- | --- |
| `format` | 固定为 `"cipher-penny-vault"`。 |
| `version` | 整数，本规范为 `1`。 |
| `kdf.name` / `kdf.hash` | 固定为 `"PBKDF2"` / `"SHA-256"`。 |
| `kdf.iterations` | 整数，新建保险库使用 600000；读取时接受 ≥ 100000 的值。 |
| `kdf.salt` | 随机 16 字节。 |
| `wrappedKey` | 被封装的数据密钥，见第 2 节。 |
| `payload` | 加密后的账本数据，见第 2 节。 |
| `updatedAt` | ISO 8601 UTC 时间戳，仅供展示和以后的同步冲突判断，不参与加密。 |

所有二进制字段使用**标准 Base64（RFC 4648 第 4 节，带 `=` 填充，不是 URL-safe 变体）**。

## 2. 加密流程

1. **KEK**（密钥加密密钥）= PBKDF2-HMAC-SHA256(password = 主密码的 UTF-8 字节，salt，iterations)，输出 32 字节。主密码不做任何 Unicode 规范化或去空格处理。
2. **DEK**（数据密钥）= 创建保险库时随机生成的 32 字节，整个保险库生命周期内不变（改密码不改变 DEK）。
3. **wrappedKey.data** = AES-256-GCM(key = KEK, iv = `wrappedKey.iv`, plaintext = DEK 原始 32 字节, AAD = UTF-8 `"cipher-penny:v1:dek"`)，输出为“密文 ‖ 16 字节认证标签”，共 48 字节。
4. **payload.data** = AES-256-GCM(key = DEK, iv = `payload.iv`, plaintext = 账本 JSON 的 UTF-8 字节, AAD = UTF-8 `"cipher-penny:v1:payload"`)，输出同样为“密文 ‖ 16 字节标签”。
5. 每次写入 `payload` 都必须生成新的随机 12 字节 IV；每次封装 DEK 也必须生成新的 IV。

解密时任一 GCM 认证失败都必须当作错误处理：`wrappedKey` 认证失败表示密码错误，`payload` 认证失败表示数据损坏或被篡改。

## 3. 账本数据（payload 明文）

payload 明文是一个 JSON 对象，结构如下（`?` 表示可选字段）：

```ts
{
  schemaVersion: 1,
  accounts: Array<{
    id: string; name: string;
    kind: 'cash' | 'ewallet' | 'debit' | 'credit' | 'other';
    initialBalance: number;     // 整数，单位：分，可为负（如信用卡欠款）
    archived: boolean;
    updatedAt?: string;         // ISO 8601 UTC，最后修改时间（同步合并用）
  }>,
  categories: Array<{
    id: string; name: string; type: 'expense' | 'income';
    icon: string;               // 一个 emoji
    keywords: string[];         // 自然语言解析用的关键词
    archived: boolean;
    updatedAt?: string;
  }>,
  transactions: Array<{
    id: string; type: 'expense' | 'income';
    amount: number;             // 正整数，单位：分
    categoryId: string; accountId: string;
    date: string;               // 本地日期 YYYY-MM-DD
    note: string;
    createdAt: string; updatedAt: string;   // ISO 8601 UTC
    recurringId?: string;
  }>,
  recurring: Array<{
    id: string; name: string; type: 'expense' | 'income';
    amount: number; categoryId: string; accountId: string; note: string;
    frequency: 'weekly' | 'monthly' | 'yearly';
    interval: number;           // 正整数，每 interval 个周期发生一次
    startDate: string; endDate?: string; active: boolean;
    lastGenerated?: string;     // 已生成账单的最后一个发生日期
    updatedAt?: string;
  }>,
  settings: {
    autoLockMinutes: number;    // 0 表示关闭自动锁定
    updatedAt?: string;
  },
  deletions?: Array<{ id: string; deletedAt: string }>   // 删除记录（墓碑），见第 5 节
}
```

约定：

- `id` 是在整个账本内唯一的字符串。用户新建的记录使用 UUID v4；周期规则生成的账单使用确定性 ID `<规则 id>:<发生日期>`（例如 `3f2c…:2026-10-01`），这样两台设备各自补齐同一笔账单时得到相同的 ID。
- 修改任何记录或设置时，必须把它的 `updatedAt` 更新为当前时间。例外：补齐周期账单只更新规则的 `lastGenerated`，不更新规则的 `updatedAt`。
- 周期规则生成的账单：`createdAt` 为生成时间，`updatedAt` 为发生日期当天本地 00:00 对应的 UTC 时间。这样即使另一台设备在同步前重新生成了一笔已被删除或修改过的账单，删除和修改（时间一定晚于发生日期）仍然胜出。
- 删除账单或周期规则时，从数组中移除该记录，并在 `deletions` 中追加（或更新）`{ id, deletedAt: 当前时间 }`。
- 实现必须保留无法识别的字段（读入后原样写回），以便新旧版本客户端共存。
- 周期账单的日期规则：按月的规则以 `startDate` 的日为锚点，短月份取当月最后一天；按年的 2 月 29 日在平年取 2 月 28 日。
- `updatedAt`、`deletions` 和确定性 ID 都是向后兼容的新增约定，不提升 `version`。缺少 `updatedAt` 的记录视为空字符串（比任何时间都旧）。

## 4. 测试向量

`fixtures/vault-v1.json` 包含：

- `password`：主密码；
- `envelope`：用该密码加密的信封（为了让测试跑得快，`iterations` 取允许的最小值 100000）；
- `data`：期望解密得到的账本数据。

任何实现都必须能用 `password` 打开 `envelope` 并得到与 `data` 深度相等的结果。

`fixtures/merge-cases.json` 是第 5 节合并规则的用例，每个用例包含 `base`、`other` 和期望结果 `expected`。为了简短，用例中省略的数组视为空数组，省略的 `settings` 视为 `{ "autoLockMinutes": 5 }`，省略的 `deletions` 视为空数组。任何实现执行 `merge(base, other)` 后都必须得到与 `expected` 深度相等的结果（按同样的规则补全省略字段后比较）。

## 5. 同步与合并

同步文件就是第 1 节的信封，以 UTF-8 JSON 存放在用户自己的 GitHub 私有仓库中（默认路径 `vault.cpenny.json`）。所有设备共用同一个 DEK，因此任何一台已解锁的设备都能直接用内存中的 DEK 解密远端的 `payload`，不需要再输入密码。

### 5.1 合并账本数据：`merge(base, other)`

`base` 是远端的账本，`other` 是本机的账本，两者 `schemaVersion` 相同。结果按以下规则计算：

1. **删除记录**：取两边 `deletions` 的并集，同一 `id` 保留较大的 `deletedAt`。结果中没有删除记录时省略 `deletions` 字段。
2. **记录**：对 `accounts`、`categories`、`transactions`、`recurring` 分别按 `id` 合并：
   - 只在一边出现的记录直接保留。
   - 两边都有时，取 `updatedAt` 较大的整条记录（字符串比较，缺失视为空字符串）。相等时取 `JSON.stringify` 结果按 UTF-16 码元比较较大的一条，保证两端合并结果相同。
   - 对于周期规则，选出的记录的 `lastGenerated` 改为两边 `lastGenerated` 中较大的一个（都没有则省略），避免重复补齐已经生成过的账单。
3. **应用删除**：如果某条记录的 `id` 有删除记录，并且 `deletedAt` ≥ 该记录的 `updatedAt`，则移除该记录。删除之后在另一台设备上修改过的记录会保留下来。
4. **周期账单去重**：带 `recurringId` 的账单中，`recurringId` 和 `date` 都相同的只保留一笔：取 `updatedAt` 较大的；相等时取 `id` 较小的。（兼容使用确定性 ID 之前生成的账单。）
5. **顺序**：先按 `base` 中的顺序排列，再按 `other` 中的顺序追加只在 `other` 中出现的记录。
6. **设置**：两边 `settings` 按第 2 条的规则整体取一个（比较 `settings.updatedAt`）。
7. **其他字段**：无法识别的顶层字段保留；两边都有时以 `base` 为准。

### 5.2 合并信封

- 合并后的数据用 DEK 重新加密，生成新的 `payload` 和 `updatedAt`。
- `kdf` 和 `wrappedKey` 默认取远端的值，这样在一台设备上修改的主密码会传播到其他设备。只有当本机在上次成功同步之后修改过主密码时，才使用本机的值。
- 远端 `payload` 无法用本机 DEK 解密，说明它属于另一个账本（或已损坏），此时必须停止同步，不得自动覆盖任何一边。

### 5.3 写入远端

- 读取远端文件时记下它的版本（GitHub 的 blob `sha`），写入时带上该版本；如果期间被其他设备更新而写入失败，重新读取、合并后再写。
- 远端版本等于上次同步时的版本、且本机在上次同步之后没有修改，则不需要写入。
