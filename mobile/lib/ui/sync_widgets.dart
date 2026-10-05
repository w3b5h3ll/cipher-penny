import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/vault_crypto.dart';
import '../state/session.dart';
import 'common.dart';
import 'theme.dart';

const _tokenUrl = 'https://github.com/settings/personal-access-tokens/new';

class _SyncHelp extends StatelessWidget {
  const _SyncHelp();

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final strong = TextStyle(fontWeight: FontWeight.w600, color: td.textPrimary);
    final code = TdText.mono.copyWith(fontSize: 12, color: td.textPrimary);
    return Bullets([
      Text.rich(TextSpan(children: [
        const TextSpan(text: '在 GitHub 新建一个'),
        TextSpan(text: '私有', style: strong),
        const TextSpan(text: '仓库专门放数据，例如 '),
        TextSpan(text: 'cipher-penny-data', style: code),
        const TextSpan(text: '。不要用存放代码的公开仓库。'),
      ])),
      Text.rich(TextSpan(children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: _tokenUrl));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制，请在浏览器中打开')));
            },
            child: Text('创建 fine-grained 令牌（点按复制链接）', style: TdText.mark.copyWith(color: td.brand)),
          ),
        ),
        const TextSpan(text: '：Repository access 选 '),
        TextSpan(text: 'Only select repositories', style: code),
        const TextSpan(text: ' 并只勾选这个仓库；Permissions 里把 '),
        TextSpan(text: 'Contents', style: code),
        const TextSpan(text: ' 设为 '),
        TextSpan(text: 'Read and write', style: code),
        const TextSpan(text: '。'),
      ])),
      const Text('把生成的令牌粘贴到下面。令牌用你的数据密钥加密后只保存在这台设备上，不会进入同步文件。'),
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
    return Gap(children: [
      Field(
        label: '仓库',
        child: TdInput(
          controller: repo,
          hint: 'owner/cipher-penny-data',
          semanticLabel: '仓库',
          keyboardType: TextInputType.url,
          onChanged: (_) => onChanged(),
        ),
      ),
      Field(
        label: '文件路径',
        child: TdInput(controller: path, hint: defaultSyncPath, semanticLabel: '文件路径', keyboardType: TextInputType.url),
      ),
      Field(
        label: 'GitHub 令牌',
        child: TdInput(
          controller: token,
          hint: 'github_pat_…',
          semanticLabel: 'GitHub 令牌',
          obscure: true,
          keyboardType: TextInputType.visiblePassword,
          onChanged: (_) => onChanged(),
        ),
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

/// F-SYNC-1, F-SYNC-3, F-SYNC-7, F-SYNC-8, F-SYNC-9
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
        const Muted('把加密后的账本存到你自己的 GitHub 私有仓库，多台设备之间自动合并。GitHub 上只有密文，没有主密码无法读取。', small: true),
        const _SyncHelp(),
        _SyncFields(repo: repo, path: path, token: token, onChanged: () => setState(() {})),
        if (_error != null) ErrorText(_error!),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: canConnect ? _connect : null, child: Text(_busy ? '正在检查仓库…' : '开启同步')),
        ),
      ]);
    }
    final status = sync.syncing
        ? '正在同步…'
        : sync.lastSyncedAt != null
            ? '上次同步：${_localTime(sync.lastSyncedAt!)}'
            : '尚未同步';
    return SectionCard(title: '同步', children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
        Text('同步到', style: TdText.mark),
        Code(sync.repo),
        Text('的', style: TdText.mark),
        Code(sync.path),
      ]),
      Muted(status, small: true),
      if (sync.error != null && !sync.foreign) ErrorText('同步失败：${sync.error}'),
      if (sync.foreign)
        TdBanner(
          child: Gap(gap: 8, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ErrorText(sync.error ?? ''),
            Text(
              '如果仓库里的文件来自你以前创建的另一个账本，可以用这台设备的数据覆盖它；如果想改用仓库里的数据，请清空本地数据，然后选择“从 GitHub 恢复”。',
              style: TdText.mark,
            ),
            OutlinedButton(onPressed: _busy ? null : _overwrite, style: dangerButton(context), child: const Text('用本机数据覆盖 GitHub 上的文件')),
          ]),
        ),
      if (_error != null) ErrorText(_error!),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy || sync.syncing ? null : () => _run(session.syncNow), child: const Text('立即同步')),
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
    return Gap(gap: 16, children: [
      const Muted('填写在其他设备上开启同步时使用的仓库，以及这台设备专用的令牌（也可以和其他设备共用一个）。', small: true),
      const _SyncHelp(),
      _SyncFields(repo: repo, path: path, token: token, onChanged: () => setState(() {})),
      Field(
        label: '主密码',
        child: TdInput(
          controller: _password,
          obscure: true,
          semanticLabel: '主密码',
          onChanged: (_) => setState(() {}),
          onSubmitted: _submit,
        ),
      ),
      if (_error != null) ErrorText(_error!, small: false),
      Row(children: [
        FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_busy ? '正在下载并解密…' : '恢复')),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _busy ? null : widget.onCancel, child: const Text('取消')),
      ]),
    ]);
  }
}
