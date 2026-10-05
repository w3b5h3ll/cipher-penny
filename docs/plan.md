# CipherPenny 实施计划（Plan）

> 每个任务都应能单独验证和提交。完成后勾选，并在括号里注明验证方式。
> 需求编号见 [spec.md](./spec.md)。

## M0 基础设施

- [ ] 规格文档：spec、design、plan、AGENTS.md
- [ ] 项目骨架：Vite + React + TS（strict）+ Vitest + ESLint
- [ ] PWA（manifest、图标、Service Worker）与生产 CSP（N-SEC-2、N-OFF-1）
- [ ] GitHub Actions：CI 与 Pages 部署（N-DEP-1）

## M1 MVP

### 核心逻辑（`src/core`，全部配单元测试）

- [ ] 金额与日期工具（F-TX-4）
- [ ] 数据模型、默认账户和分类（F-CFG-1）
- [ ] 账本增删改操作（F-TX-1、F-TX-3）
- [ ] 周期账单生成（F-REC-1 ~ F-REC-5）
- [ ] 统计：月度汇总、分类汇总、账户余额（F-STAT-1 ~ F-STAT-3）
- [ ] 自然语言解析器（F-QA-2 ~ F-QA-6）
- [ ] CSV 导出（F-IO-3）

### 加密与存储

- [ ] 信封加密：创建、打开、保存、改密码、格式校验（F-VAULT-3、F-VAULT-5、F-IO-1、F-IO-2）
- [ ] IndexedDB 存储

### 会话与界面

- [ ] 会话状态机、防抖保存、自动锁定（F-VAULT-4）
- [ ] 创建保险库、解锁页面（F-VAULT-1、F-VAULT-2）
- [ ] 首页：月份切换、账单列表、快速记账、草稿确认（F-QA-1、F-QA-7、F-TX-2）
- [ ] 语音输入与 `#/add?text=` 链接（F-QA-8、F-QA-9）
- [ ] 账单新增和编辑页（F-TX-1、F-TX-3）
- [ ] 统计页（F-STAT）
- [ ] 周期账单页（F-REC）
- [ ] 设置页：账户、分类、自动锁定、改密码、备份导入导出、CSV、清空数据（F-CFG-2、F-CFG-3、F-VAULT-5、F-VAULT-6、F-IO）

### 验收

- [ ] `pnpm check` 全部通过（类型检查、lint、测试、构建）
- [ ] 浏览器手工验收 spec 中标注 `[手工]` 的项目
- [ ] 部署到 GitHub Pages 并在手机上安装 PWA 验证

## M2 之后（待 spec 第 7 节的问题确认后细化）

- [ ] 同步：GitHub 私有仓库或 WebDAV，同步的只是加密信封；需要设计冲突处理
- [ ] 恢复码
- [ ] 可选的大模型解析（用户自备 API key，key 同样加密保存）
- [ ] 账户间转账、信用卡还款
- [ ] 预算与超支提醒
- [ ] 导入支付宝、微信账单 CSV 进行对账
- [ ] Capacitor 打包，接入原生语音识别、Face ID、Siri
