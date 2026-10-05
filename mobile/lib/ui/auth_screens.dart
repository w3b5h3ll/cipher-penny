import 'package:flutter/material.dart';

import '../crypto/vault_crypto.dart';
import 'common.dart';
import 'sync_widgets.dart';

const _minPasswordLength = 8;

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.subtitle, required this.child});
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.lock_outline, size: 56, color: brandColor),
                const SizedBox(height: 8),
                Text('CipherPenny',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                MutedText(subtitle, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 20),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

TextField passwordField(TextEditingController controller,
        {required String label, String? errorText, bool autofocus = false, VoidCallback? onSubmitted, ValueChanged<String>? onChanged}) =>
    TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      autofocus: autofocus,
      decoration: InputDecoration(labelText: label, errorText: errorText),
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    );

/// F-VAULT-1, plus the entry to F-SYNC-6.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;
  bool _restoring = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _password.text.length >= _minPasswordLength && _password.text == _confirm.text && _acknowledged && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).create(_password.text);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = describeError(err);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return _AuthScaffold(
        subtitle: '从 GitHub 私有仓库下载加密账本，用主密码解密后保存在这台设备上。',
        child: SectionCard(title: '从 GitHub 恢复', children: [
          RestoreFromGitHub(onCancel: () => setState(() => _restoring = false)),
        ]),
      );
    }
    final tooShort = _password.text.isNotEmpty && _password.text.length < _minPasswordLength;
    final mismatch = _confirm.text.isNotEmpty && _password.text != _confirm.text;
    return _AuthScaffold(
      subtitle: '端到端加密的个人记账本。数据加密保存在这台设备上，也可以加密同步到你自己的 GitHub 私有仓库。',
      child: SectionCard(title: '设置主密码', children: [
        passwordField(_password,
            label: '主密码',
            errorText: tooShort ? '至少 $_minPasswordLength 位，建议使用一句容易记住的长口令' : null,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        passwordField(_confirm,
            label: '确认主密码', errorText: mismatch ? '两次输入不一致' : null, onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _acknowledged,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() => _acknowledged = v ?? false),
          title: const Text('我已了解：主密码只保存在我的脑子里，忘记后数据无法恢复。', style: TextStyle(fontSize: 14)),
        ),
        if (_error != null) ErrorText(_error!),
        const SizedBox(height: 8),
        FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_busy ? '正在生成密钥…' : '创建加密账本')),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _restoring = true),
          child: const Text('已在其他设备开启同步？从 GitHub 恢复'),
        ),
      ]),
    );
  }
}

/// F-VAULT-2
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _showForgot = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).unlock(_password.text);
    } catch (err) {
      _password.clear();
      if (mounted) {
        setState(() {
          _error = switch (err) {
            WrongPasswordException() => '密码错误',
            CorruptedVaultException() => '本地数据已损坏或被篡改，无法解密',
            _ => describeError(err),
          };
          _busy = false;
        });
      }
    }
  }

  Future<void> _wipe() async {
    final session = SessionScope.read(context);
    if (!await confirm(context, '确定清空这台设备上的全部账本数据吗？此操作无法撤销。', action: '清空', danger: true)) return;
    if (!mounted || !await confirm(context, '再次确认：没有备份或同步的数据将永久丢失。', action: '清空', danger: true)) return;
    await session.wipe();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      subtitle: '账本已锁定',
      child: SectionCard(children: [
        passwordField(_password, label: '主密码', autofocus: true, onSubmitted: _submit, onChanged: (_) => setState(() {})),
        if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _password.text.isEmpty || _busy ? null : _submit,
          child: Text(_busy ? '正在解锁…' : '解锁'),
        ),
        TextButton(onPressed: () => setState(() => _showForgot = !_showForgot), child: const Text('忘记密码？')),
        if (_showForgot) ...[
          const MutedText('主密码无法找回，这是端到端加密的代价。你可以清空本地数据重新开始；如果开启过同步，可以再从 GitHub 恢复（需要当时的密码）。'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _wipe,
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('清空本地数据'),
          ),
        ],
      ]),
    );
  }
}
