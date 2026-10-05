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
  }>,
  categories: Array<{
    id: string; name: string; type: 'expense' | 'income';
    icon: string;               // 一个 emoji
    keywords: string[];         // 自然语言解析用的关键词
    archived: boolean;
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
  }>,
  settings: { autoLockMinutes: number }   // 0 表示关闭自动锁定
}
```

约定：

- `id` 为 UUID v4 字符串。
- 实现必须保留无法识别的字段（读入后原样写回），以便新旧版本客户端共存。
- 周期账单的日期规则：按月的规则以 `startDate` 的日为锚点，短月份取当月最后一天；按年的 2 月 29 日在平年取 2 月 28 日。

## 4. 测试向量

`fixtures/vault-v1.json` 包含：

- `password`：主密码；
- `envelope`：用该密码加密的信封（为了让测试跑得快，`iterations` 取允许的最小值 100000）；
- `data`：期望解密得到的账本数据。

任何实现都必须能用 `password` 打开 `envelope` 并得到与 `data` 深度相等的结果。
