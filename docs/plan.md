# CipherPenny 实施计划（Plan）

> 每个任务都应能单独验证和提交。完成后勾选，并在括号里注明验证方式。
> 需求编号见 [spec.md](./spec.md)。

## M0 基础设施

- [x] 规格文档：spec、design、plan、AGENTS.md、vault-format（跨端格式规范）
- [x] 项目骨架：Vite + React + TS（strict）+ Vitest + ESLint（`pnpm check`）
- [x] PWA（manifest、图标、Service Worker）与生产 CSP（N-SEC-2、N-OFF-1）（检查构建产物：CSP meta 已注入、无内联脚本；应用在 CSP 下实测可用）
- [x] GitHub Actions：CI 与 Pages 部署（N-DEP-1）（`.github/workflows/ci.yml`；需在仓库设置中把 Pages 来源设为 GitHub Actions，首次推送后确认）

## M1 MVP

### 核心逻辑（`src/core`，全部配单元测试）

- [x] 金额与日期工具（F-TX-4）（`money.test.ts`、`dates.test.ts`）
- [x] 数据模型、默认账户和分类（F-CFG-1）
- [x] 账本增删改操作（F-TX-1、F-TX-3）（`stats.test.ts`）
- [x] 周期账单生成（F-REC-1 ~ F-REC-5）（`recurring.test.ts`）
- [x] 统计：月度汇总、分类汇总、账户余额（F-STAT-1 ~ F-STAT-3）（`stats.test.ts`）
- [x] 自然语言解析器，用例放在 `fixtures/parser-cases.json`（F-QA-2 ~ F-QA-6）（29 个用例）
- [x] CSV 导出（F-IO-3）（含公式注入防护）

### 加密与存储

- [x] 信封加密：创建、打开、保存、改密码、格式校验（F-VAULT-3、F-VAULT-5、F-IO-1、F-IO-2）（`vault-crypto.test.ts`）
- [x] 生成并提交加密测试向量 `fixtures/vault-v1.json`（N-PORT-1）（由独立脚本生成，TS 实现可解密）
- [x] IndexedDB 存储（`idb.test.ts`；浏览器中确认只存密文）

### 会话与界面

- [x] 会话状态机、防抖保存、自动锁定（F-VAULT-4）（`session.test.ts`）
- [x] 创建保险库、解锁页面（F-VAULT-1、F-VAULT-2）（浏览器实测：创建、错误密码提示、刷新后解锁）
- [x] 首页：月份切换、账单列表、快速记账、草稿确认（F-QA-1、F-QA-7、F-TX-2）（浏览器实测）
- [x] 语音输入与 `#/add?text=` 链接（F-QA-8、F-QA-9）（深链接已实测；语音需要真实麦克风，待手工验证）
- [x] 账单新增和编辑页（F-TX-1、F-TX-3）
- [x] 统计页（F-STAT）（浏览器实测，余额与手算一致）
- [x] 只记支出（spec v0.5）：界面去掉收入；快速记账跳过收入条目并提示；统计改为支出、笔数、日均或月均，账户余额改为按账户统计支出（`stats.test.ts`；浏览器实测）
- [x] 按年统计（F-STAT-4）（`stats.test.ts`；浏览器实测：年度汇总和月均与手算一致，点击柱子切换到该月，375px 宽度正常）
- [x] 周期账单页（F-REC）（浏览器实测：过去开始日期补记 3 笔）
- [x] 设置页：账户、分类、自动锁定、改密码、备份导入导出、CSV、清空数据（F-CFG-2、F-CFG-3、F-VAULT-5、F-VAULT-6、F-IO）
- [x] 视觉规范与字体（N-UX-3、N-UX-4）（浏览器实测：CSP 下三种字体加载无违规；本机有思源黑体时不下载中文字体；字体进入运行时缓存；浅色和深色模式）
- [x] Service Worker 更新（浏览器实测：新构建会自动激活，不再停在 waiting）

### 验收

- [x] `pnpm check` 全部通过（类型检查、lint、测试、构建）
- [ ] 浏览器手工验收 spec 中标注 `[手工]` 的项目：真实麦克风语音输入、闲置超时自动锁定、导出备份后在另一浏览器导入、在输入框中按 Enter 提交
- [ ] 部署到 GitHub Pages，在桌面 Chrome 和 Android Chrome 上验证（含 PWA 安装）

## M2 之后（待 spec 第 8 节的问题确认后细化）

- [ ] 同步：GitHub 私有仓库或 WebDAV，同步的只是加密信封；需要设计冲突处理
- [ ] 恢复码
- [ ] 可选的大模型解析（用户自备 API key，key 同样加密保存）
- [ ] 账户间转账、信用卡还款
- [ ] 预算与超支提醒
- [ ] 导入支付宝、微信账单 CSV 进行对账
- [ ] Flutter Android 应用（独立仓库）：按 vault-format.md 实现格式读写，跑通 `fixtures/` 下的全部测试向量；需要先确定同步方案
