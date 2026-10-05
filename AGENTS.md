# AGENTS.md

本文件给 AI 编码代理（以及新加入的开发者）提供项目约定。动手前先读 `docs/spec.md` 和 `docs/design.md`。

## 项目简介

CipherPenny：端到端加密、本地优先的个人记账 PWA，部署在 GitHub Pages（`/cipher-penny/`）。纯前端，无后端。`mobile/` 下是同一应用的 Flutter Android 版（见 design.md 第 8 节）。

## 常用命令

```bash
pnpm install          # 安装依赖（使用 pnpm-lock.yaml）
pnpm dev              # 开发服务器 http://localhost:5173/cipher-penny/
pnpm test             # 单元测试（Vitest，单次运行）
pnpm typecheck        # tsc --noEmit
pnpm lint             # ESLint
pnpm build            # 生产构建到 dist/
pnpm check            # typecheck + lint + test + build，提交前必须通过

# Android（在 mobile/ 下；Flutter 不在 PATH 上时先 export PATH=$HOME/Works/tools/flutter/bin:$PATH）
flutter test          # Dart 单元测试，读取 ../fixtures/
flutter analyze
flutter build apk --release --split-per-abi
```

## 目录结构与分层

- `src/core/`：纯函数领域逻辑。**禁止**引用 React、DOM、IndexedDB。
- `src/crypto/`：只依赖 WebCrypto（`globalThis.crypto`）。
- `src/storage/`：只读写密文（加密信封、用数据密钥加密的同步配置）。
- `src/remote/`：GitHub API 客户端，只收发密文信封。不依赖 `core/`。
- `src/state/`：会话状态和同步流程，UI 访问数据的唯一入口。
- `src/ui/`：React 界面。不直接调用 `crypto/`、`storage/` 或 `remote/`。
- 测试与源码放在一起：`foo.ts` 对应 `foo.test.ts`。
- `mobile/lib/` 的目录与 `src/` 一一对应，分层规则相同；Dart 测试在 `mobile/test/`。修改 `src/core`、`src/crypto`、`src/remote` 或同步流程的行为时，要同步修改 Dart 版本，并让两边都跑过 `fixtures/`。

## 跨端格式

- 加密信封和账本数据结构由 `docs/vault-format.md` 规范性定义，Web 端和 Android 端都依赖它。
- 修改格式必须同时更新规范、提升 `version`、保留旧版本读取能力，并更新 `fixtures/` 测试向量。
- 解析器的行为由 `fixtures/parser-cases.json` 描述。修改解析逻辑时先改用例，再改代码。

## 编码约定

- TypeScript strict；不要用 `any`，确实需要时用 `unknown` 并收窄类型。
- 金额一律用整数“分”（`Cents`）；日期一律用本地 `YYYY-MM-DD` 字符串，用 `core/dates.ts` 处理，不要直接用 `new Date('YYYY-MM-DD')`（会按 UTC 解析）。
- 状态不可变：`core/ledger.ts` 的函数返回新对象。
- 界面文案使用简体中文；代码标识符和注释使用英文。
- 样式只使用 `src/styles.css` 中的 CSS 变量（取值参考 TDesign 令牌），不要写死颜色、字号和圆角；不要引入 UI 组件库。字体只用 `--font-sans`（Inter + 思源黑体）和 `--font-mono`（JetBrains Mono）。
- Android 端样式只用 `mobile/lib/ui/theme.dart` 的 `Td` 令牌（`Td.of(context)`，取值与 `styles.css` 相同）和 `TdText` 字号，共用组件在 `ui/common.dart`（对应 Web 的 `.card`、`.field`、`.banner`、`.segmented` 等）。不要写死颜色，不要用 Material `Icons`：图标用应用图标和与 Web 相同的文字符号（‹ › ✕ ▾ 🔒）及分类 emoji。改 Web 界面的视觉时同步改 Android 端。
- 新增需求或改变行为时，先更新 `docs/spec.md`，再写代码；在提交说明中引用需求编号（如 `F-QA-3`）。

## 安全红线（违反即视为缺陷）

- 禁止 `dangerouslySetInnerHTML`、`innerHTML`、`eval`、`new Function`。
- 不得新增运行时依赖（Web 的 `dependencies`、`mobile/pubspec.yaml` 的 `dependencies`），除非在 `docs/design.md` 的决策记录中写明理由。
- 加密只用 WebCrypto（Android 端用 `cryptography` 包）；不要自己实现加密原语，不要使用固定 IV。
- 明文数据、密钥和同步令牌不得以明文写入 `localStorage`、IndexedDB、文件、日志或 URL。
- 除同步用的 `https://api.github.com` 外，不得向第三方域名发起网络请求；发往 GitHub 的只能是加密信封。

## 完成的定义

1. `pnpm check` 通过；改了 `mobile/` 时 `flutter analyze` 和 `flutter test` 也通过。
2. 新逻辑有单元测试（尤其是 `core/`、`crypto/`）。
3. `docs/plan.md` 中对应任务已勾选。
4. 涉及界面的改动在浏览器中实际操作验证过。
