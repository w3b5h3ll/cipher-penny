import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/vault_crypto.dart';
import '../state/session.dart';
import 'common.dart';

const _tokenUrl = 'https://github.com/settings/personal-access-tokens/new';

class _SyncHelp extends StatelessWidget {
  const _SyncHelp();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MutedText('1. 在 GitHub 新建一个私有仓库专门放数据，例如 cipher-penny-data。不要用存放代码的公开仓库。'),
      const SizedBox(height: 4),
      const MutedText('2. 创建 fine-grained 令牌：Repository access 选 Only select repositories 并只勾选这个仓库；'
          'Permissions 里把 Contents 设为 Read and write。'),
      Row(children: [
        const Expanded(child: SelectableText(_tokenUrl, style: TextStyle(fontSize: 12))),
        IconButton(
          tooltip: '复制链接',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: _tokenUrl));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
          },
        ),
      ]),
      const MutedText('3. 把令牌粘贴到下面。令牌用你的数据密钥加密后只保存在这台设备上，不会进入同步文件。'),
    ]);
  }
}

class _SyncFields extends StatelessWidget {
  const _SyncFields({required this.repo, required this.path, required this.token, required this.onChanged});
  final TextEditingController repo;
  final TextEditingController path;
  final TextEditingController token;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: repo,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: '仓库', hintText: 'owner/cipher-penny-data'),
        onChanged: (_) => onChanged(),
      ),
      TextField(
        controller: path,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: '文件路径', hintText: defaultSyncPath),
      ),
      TextField(
        controller: token,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        decoration: const InputDecoration(labelText: 'GitHub 令牌', hintText: 'github_pat_…'),
        onChanged: (_) => onChanged(),
      ),
    ]);
  }
}

mixin _SyncForm<T extends StatefulWidget> on State<T> {
  final repo = TextEditingController();
  final path = TextEditingController();
  final token = TextEditingController();

  SyncSetup get setup => SyncSetup(repo: repo.text, path: path.text, token: token.text);

  @override
  void dispose() {
    repo.dispose();
    path.dispose();
    token.dispose();
    super.dispose();
  }
}

/// F-SYNC-1, F-SYNC-3, F-SYNC-7, F-SYNC-8
class SyncSection extends StatefulWidget {
  const SyncSection({super.key});
  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> with _SyncForm {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (err) {
      if (mounted) setState(() => _error = describeError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (repo.text.trim().isEmpty || token.text.trim().isEmpty || _busy) return;
    final session = SessionScope.read(context);
    await _run(() async {
      await session.connectSync(setup);
      repo.clear();
      path.clear();
      token.clear();
    });
  }

  Future<void> _disconnect() async {
    final session = SessionScope.read(context);
    if (!await confirm(context, '断开后这台设备不再同步，GitHub 上的文件会保留。确定断开？', action: '断开')) return;
    await _run(session.disconnectSync);
  }

  Future<void> _overwrite() async {
    final session = SessionScope.read(context);
    if (!await confirm(context, 'GitHub 上的同步文件将被这台设备的数据替换，原文件只能从仓库的提交历史中找回。确定覆盖？',
        action: '覆盖', danger: true)) {
      return;
    }
    await _run(session.overwriteRemote);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final sync = session.sync;
    if (sync == null) {
      final canConnect = repo.text.trim().isNotEmpty && token.text.trim().isNotEmpty && !_busy;
      return SectionCard(title: '同步', children: [
        const MutedText('把加密后的账本存到你自己的 GitHub 私有仓库，多台设备之间自动合并。GitHub 上只有密文，没有主密码无法读取。'),
        const SizedBox(height: 8),
        const _SyncHelp(),
        _SyncFields(repo: repo, path: path, token: token, onChanged: () => setState(() {})),
        if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
        const SizedBox(height: 12),
        FilledButton(onPressed: canConnect ? _connect : null, child: Text(_busy ? '正在检查仓库…' : '开启同步')),
      ]);
    }
    final status = sync.syncing
        ? '正在同步…'
        : sync.lastSyncedAt != null
            ? '上次同步：${_localTime(sync.lastSyncedAt!)}'
            : '尚未同步';
    return SectionCard(title: '同步', children: [
      Text('同步到 ${sync.repo} 的 ${sync.path}'),
      const SizedBox(height: 4),
      MutedText(status),
      if (sync.error != null && !sync.foreign) ...[const SizedBox(height: 8), ErrorText('同步失败：${sync.error}')],
      if (sync.foreign) ...[
        const SizedBox(height: 8),
        ErrorText(sync.error ?? ''),
        const SizedBox(height: 4),
        const MutedText('如果仓库里的文件来自你以前创建的另一个账本，可以用这台设备的数据覆盖它；'
            '如果想改用仓库里的数据，请清空本地数据，然后选择“从 GitHub 恢复”。'),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _overwrite,
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text('用本机数据覆盖 GitHub 上的文件'),
        ),
      ],
      if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
      const SizedBox(height: 12),
      Row(children: [
        FilledButton(onPressed: _busy || sync.syncing ? null : () => _run(session.syncNow), child: const Text('立即同步')),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: _busy ? null : _disconnect, child: const Text('断开同步')),
      ]),
    ]);
  }
}

String _localTime(String iso) {
  final t = DateTime.parse(iso).toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}

/// F-SYNC-6: set up a new device from the vault stored on GitHub.
class RestoreFromGitHub extends StatefulWidget {
  const RestoreFromGitHub({super.key, required this.onCancel});
  final VoidCallback onCancel;
  @override
  State<RestoreFromGitHub> createState() => _RestoreFromGitHubState();
}

class _RestoreFromGitHubState extends State<RestoreFromGitHub> with _SyncForm {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      repo.text.trim().isNotEmpty && token.text.trim().isNotEmpty && _password.text.isNotEmpty && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).restoreFromRemote(setup, _password.text);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = err is WrongPasswordException ? '主密码错误' : describeError(err);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const MutedText('填写在其他设备上开启同步时使用的仓库，以及令牌（可以和其他设备共用一个）。'),
      const SizedBox(height: 8),
      const _SyncHelp(),
      _SyncFields(repo: repo, path: path, token: token, onChanged: () => setState(() {})),
      TextField(
        controller: _password,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(labelText: '主密码'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
      const SizedBox(height: 16),
      FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_busy ? '正在下载并解密…' : '恢复')),
      TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('取消')),
    ]);
  }
}
