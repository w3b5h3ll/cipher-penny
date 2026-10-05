import 'package:flutter/material.dart';

import '../crypto/vault_crypto.dart';
import 'common.dart';
import 'sync_widgets.dart';
import 'theme.dart';

const _minPasswordLength = 8;

/// `.auth`: centred column with the brand block and a shadowed card.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.subtitle, required this.title, required this.children});
  final String subtitle;
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Gap(gap: 24, children: [
                Gap(gap: 8, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const AppLogo(size: 64),
                  Text('CipherPenny', style: TdText.headlineSmall),
                  Text(subtitle, textAlign: TextAlign.center, style: TdText.body.copyWith(color: td.textSecondary)),
                ]),
                TdCard(
                  padding: const EdgeInsets.all(24),
                  shadow: true,
                  child: Gap(gap: 16, children: [
                    if (title != null) Text(title!, style: TdText.titleMedium),
                    ...children,
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

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
    const subtitle = '端到端加密的个人记账本。数据加密保存在这台设备上，也可以加密同步到你自己的 GitHub 私有仓库。';
    if (_restoring) {
      return _AuthScaffold(
        subtitle: subtitle,
        title: '从 GitHub 恢复',
        children: [RestoreFromGitHub(onCancel: () => setState(() => _restoring = false))],
      );
    }
    final tooShort = _password.text.isNotEmpty && _password.text.length < _minPasswordLength;
    final mismatch = _confirm.text.isNotEmpty && _password.text != _confirm.text;
    return _AuthScaffold(
      subtitle: subtitle,
      title: '设置主密码',
      children: [
        Field(
          label: '主密码',
          hint: tooShort ? '至少 $_minPasswordLength 位，建议使用一句容易记住的长口令' : null,
          child: TdInput(controller: _password, obscure: true, semanticLabel: '主密码', onChanged: (_) => setState(() {})),
        ),
        Field(
          label: '确认主密码',
          hint: mismatch ? '两次输入不一致' : null,
          child: TdInput(controller: _confirm, obscure: true, semanticLabel: '确认主密码', onChanged: (_) => setState(() {})),
        ),
        Semantics(
          checked: _acknowledged,
          child: GestureDetector(
            onTap: () => setState(() => _acknowledged = !_acknowledged),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 24,
                height: 22,
                child: Checkbox(
                  value: _acknowledged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(style: TdText.body, children: const [
                  TextSpan(text: '我已了解：主密码只保存在我的脑子里，'),
                  TextSpan(text: '忘记后数据无法恢复', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: '。'),
                ])),
              ),
            ]),
          ),
        ),
        if (_error != null) ErrorText(_error!, small: false),
        FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_busy ? '正在生成密钥…' : '创建加密账本')),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _restoring = true),
          child: const Text('已在其他设备开启同步？从 GitHub 恢复'),
        ),
      ],
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
    if (!mounted || !await confirm(context, '再次确认：没有同步到 GitHub 的数据将永久丢失。', action: '清空', danger: true)) return;
    await session.wipe();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      subtitle: '账本已锁定',
      title: null,
      children: [
        Field(
          label: '主密码',
          child: TdInput(
            controller: _password,
            obscure: true,
            autofocus: true,
            semanticLabel: '主密码',
            onChanged: (_) => setState(() {}),
            onSubmitted: _submit,
          ),
        ),
        if (_error != null) ErrorText(_error!, small: false),
        FilledButton(onPressed: _password.text.isEmpty || _busy ? null : _submit, child: Text(_busy ? '正在解锁…' : '解锁')),
        TextButton(onPressed: () => setState(() => _showForgot = !_showForgot), child: const Text('忘记密码？')),
        if (_showForgot)
          TdBanner(
            child: Gap(gap: 8, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('主密码无法找回，这是端到端加密的代价。你可以清空本地数据重新开始；如果开启过同步，可以再从 GitHub 恢复（需要当时的密码）。'),
              OutlinedButton(onPressed: _wipe, style: dangerButton(context), child: const Text('清空本地数据')),
            ]),
          ),
      ],
    );
  }
}
