import 'package:flutter/material.dart';

import '../core/ledger.dart';
import 'common.dart';
import 'sync_widgets.dart';

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
    final session = SessionScope.of(context);
    final settings = session.data.settings;
    return ListView(padding: const EdgeInsets.only(top: 6, bottom: 24), children: [
      const SyncSection(),
      SectionCard(title: '安全', children: [
        DropdownButtonFormField<int>(
          key: ValueKey(settings.autoLockMinutes),
          initialValue: settings.autoLockMinutes,
          decoration: const InputDecoration(labelText: '闲置自动锁定'),
          items: [
            for (final m in [1, 5, 15, 30, 60]) DropdownMenuItem(value: m, child: Text('$m 分钟')),
            const DropdownMenuItem(value: 0, child: Text('关闭')),
          ],
          onChanged: (m) {
            if (m != null) session.update((d) => updateSettings(d, {'autoLockMinutes': m}));
          },
        ),
        const SizedBox(height: 8),
        const MutedText('App 在前台闲置或切到后台超过这个时间后自动锁定。'),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: const Icon(Icons.lock_outline), label: const Text('立即锁定'), onPressed: session.lock),
      ]),
      SectionCard(title: '数据', children: [
        const MutedText('Android 版目前不支持修改主密码、管理账户和分类、周期账单规则和备份导入导出，请在网页版操作，改动会通过同步过来。'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _wipe(context),
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text('清空本地数据'),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: MutedText('CipherPenny · 数据只以密文形式保存在本机和你的 GitHub 私有仓库')),
      ),
    ]);
  }
}
