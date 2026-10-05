# AGENTS.md

本文件给 AI 编码代理（以及新加入的开发者）提供项目约定。动手前先读 `docs/spec.md` 和 `docs/design.md`。

## 项目简介

CipherPenny：端到端加密、本地优先的个人记账 PWA，部署在 GitHub Pages（`/cipher-penny/`）。纯前端，无后端。

## 常用命令

```bash
pnpm install          # 安装依赖（使用 pnpm-lock.yaml）
pnpm dev              # 开发服务器 http://localhost:5173/cipher-penny/
pnpm test             # 单元测试（Vitest，单次运行）
pnpm typecheck        # tsc --noEmit
pnpm lint             # ESLint
pnpm build            # 生产构建到 dist/
pnpm check            # typecheck + lint + test + build，提交前必须通过
```

## 目录结构与分层

- `src/core/`：纯函数领域逻辑。**禁止**引用 React、DOM、IndexedDB。
- `src/crypto/`：只依赖 WebCrypto（`globalThis.crypto`）。
- `src/storage/`：只读写密文信封。
- `src/state/`：会话状态，UI 访问数据的唯一入口。
- `src/ui/`：React 界面。不直接调用 `crypto/` 或 `storage/`。
- 测试与源码放在一起：`foo.ts` 对应 `foo.test.ts`。

## 跨端格式

- 加密信封和账本数据结构由 `docs/vault-format.md` 规范性定义，以后的 Flutter Android 应用依赖它。
- 修改格式必须同时更新规范、提升 `version`、保留旧版本读取能力，并更新 `fixtures/` 测试向量。
- 解析器的行为由 `fixtures/parser-cases.json` 描述。修改解析逻辑时先改用例，再改代码。

## 编码约定

- TypeScript strict；不要用 `any`，确实需要时用 `unknown` 并收窄类型。
- 金额一律用整数“分”（`Cents`）；日期一律用本地 `YYYY-MM-DD` 字符串，用 `core/dates.ts` 处理，不要直接用 `new Date('YYYY-MM-DD')`（会按 UTC 解析）。
- 状态不可变：`core/ledger.ts` 的函数返回新对象。
- 界面文案使用简体中文；代码标识符和注释使用英文。
- 新增需求或改变行为时，先更新 `docs/spec.md`，再写代码；在提交说明中引用需求编号（如 `F-QA-3`）。

## 安全红线（违反即视为缺陷）

- 禁止 `dangerouslySetInnerHTML`、`innerHTML`、`eval`、`new Function`。
- 不得新增运行时依赖（`dependencies`），除非在 `docs/design.md` 的决策记录中写明理由。
- 加密只用 WebCrypto；不要自己实现加密原语，不要使用固定 IV。
- 明文数据和密钥不得写入 `localStorage`、IndexedDB、日志或 URL。
- 不得向第三方域名发起网络请求。

## 完成的定义

1. `pnpm check` 通过。
2. 新逻辑有单元测试（尤其是 `core/`、`crypto/`）。
3. `docs/plan.md` 中对应任务已勾选。
4. 涉及界面的改动在浏览器中实际操作验证过。
