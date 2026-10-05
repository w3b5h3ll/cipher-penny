import 'package:flutter/material.dart';

import '../core/ledger.dart';
import 'common.dart';
import 'sync_widgets.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _wipe(BuildContext context) async {
    final session = SessionScope.read(context);
    if (!await confirm(context, '确定清空这台设备上的全部账本数据吗？此操作无法撤销。', action: '清空', danger: true)) return;
    if (!context.mounted ||
        !await confirm(context, '再次确认：没有同步到 GitHub 的数据将永久丢失。', action: '清空', danger: true)) {
      return;
    }
    await session.wipe();
  }

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final session = SessionScope.of(context);
    final settings = session.data.settings;
    final code = TdText.mono.copyWith(fontSize: 12, color: td.textPrimary);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 64), children: [
      Gap(children: [
        SectionCard(title: '安全', children: [
          Field(
            label: '闲置自动锁定',
            hint: 'App 在前台闲置或切到后台超过这个时间后自动锁定。',
            child: OptionSelect<int>(
              semanticLabel: '闲置自动锁定',
              value: settings.autoLockMinutes,
              options: const {1: '1 分钟', 5: '5 分钟', 15: '15 分钟', 30: '30 分钟', 60: '60 分钟', 0: '关闭'},
              onChanged: (m) => session.update((d) => updateSettings(d, {'autoLockMinutes': m})),
            ),
          ),
        ]),
        const SyncSection(),
        SectionCard(title: '隐私与数据', children: [
          Bullets([
            Text.rich(TextSpan(children: [
              const TextSpan(text: '账本只以 '),
              TextSpan(text: 'AES-256-GCM', style: code),
              const TextSpan(text: ' 密文保存在本机的应用私有目录中，密钥由主密码经 '),
              TextSpan(text: 'PBKDF2-SHA256', style: code),
              const TextSpan(text: ' 派生。主密码和明文不会上传到任何服务器；开启同步后，只有密文会上传到你自己的 GitHub 私有仓库。'),
            ])),
            const Text('Android 版暂不支持修改主密码、管理账户和分类、备份导入导出，请在网页版操作，改动会通过同步过来。'),
            const Text('卸载 App 或清除应用数据会删除本机账本；开启了同步的话可以再从 GitHub 恢复。'),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: () => _wipe(context), style: dangerButton(context), child: const Text('清空本地数据')),
          ),
        ]),
      ]),
    ]);
  }
}
