# CipherPenny

端到端加密、本地优先的个人记账 Web 应用（PWA）。一句话记账，数据只以密文保存在你自己的浏览器里。

在线使用：<https://w3b5h3ll.github.io/cipher-penny/>

## 功能

- **一句话记账**：输入或语音说出“昨天打车28，晚上和朋友吃饭260”，自动拆成多笔，识别金额、日期、分类和账户，确认后保存。
- **端到端加密**：主密码经 PBKDF2-SHA256（60 万次迭代）派生密钥，数据用 AES-256-GCM 加密后存入 IndexedDB；闲置自动锁定。
- **周期账单**：订阅、房租、工资等按周、月、年自动入账，暂停后恢复不会补记暂停期间的账单。
- **统计**：按月汇总收支，分类占比，账户余额。
- **备份与导出**：加密备份文件（换设备时导入）、明文 CSV。
- **离线可用**：可安装为 PWA。
- **快捷链接**：`#/add?text=午饭%2035` 直接打开并预填草稿，可用于书签或自动化工具。

## 安全模型

- GitHub Pages 只托管静态代码，永远拿不到你的数据；没有后端，也不向任何第三方发送账本数据。
- 运行时依赖只有 `react` 和 `react-dom`；加密只使用浏览器内置的 WebCrypto；生产环境启用严格 CSP。
- **忘记主密码无法恢复数据**，请定期导出加密备份。
- 语音输入使用浏览器自带的语音识别，Chrome 会把音频发送到 Google 服务器识别；介意的话请用键盘或输入法输入。
- 网页端加密的固有局限：如果页面本身被注入恶意脚本，脚本可以读取解锁后的数据。详见 [docs/design.md](docs/design.md#43-威胁模型)。

## 文档

本项目按“规格先行”的方式开发：

| 文档 | 内容 |
| --- | --- |
| [docs/spec.md](docs/spec.md) | 需求规格：目标、非目标、带编号的需求与验收标准 |
| [docs/design.md](docs/design.md) | 技术设计：架构、决策记录、加密设计、威胁模型 |
| [docs/vault-format.md](docs/vault-format.md) | 加密文件格式规范（以后的 Flutter Android 版依赖它） |
| [docs/plan.md](docs/plan.md) | 里程碑与任务进度 |
| [AGENTS.md](AGENTS.md) | 给 AI 编码代理和贡献者的约定与安全红线 |

`fixtures/` 下是语言无关的测试向量：`parser-cases.json`（自然语言解析用例）和 `vault-v1.json`（加密格式互通向量，由 `scripts/gen-vault-fixture.mjs` 独立生成）。

## 开发

需要 Node 24+ 和 pnpm。

```bash
pnpm install
pnpm dev        # http://localhost:5173/cipher-penny/
pnpm check      # 类型检查 + lint + 测试 + 构建
```

## 部署

推送到 `master` 后，GitHub Actions 会自动测试并部署到 GitHub Pages。首次使用前需要在仓库的 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。
