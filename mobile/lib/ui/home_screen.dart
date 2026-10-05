import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/stats.dart';
import 'common.dart';
import 'quick_add.dart';
import 'tx_edit_screen.dart';

/// F-TX-2: the month's spending grouped by day, with quick add on top.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenSettings});
  final VoidCallback onOpenSettings;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MonthKey _month = monthKeyOf(todayISO());

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final data = session.data;
    final lookups = Lookups(data);
    final today = todayISO();
    final monthTxs = transactionsInMonth(data.transactions, _month);
    final groups = groupByDate(monthTxs);
    final sync = session.sync;

    return RefreshIndicator(
      onRefresh: session.syncNow,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          if (sync?.error != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.sync_problem),
                title: Text(sync!.foreign ? '同步已暂停' : '同步失败'),
                subtitle: Text(sync.error!, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: widget.onOpenSettings,
              ),
            ),
          if (session.saveError != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(leading: const Icon(Icons.error_outline), title: Text('保存失败：${session.saveError}')),
            ),
          const QuickAdd(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('手动记一笔'),
                onPressed: () => Navigator.of(context).push(TxEditScreen.route()),
              ),
              const SizedBox(width: 8),
            ]),
          ),
          SummaryBar(spending: spending(monthTxs), periods: daysElapsed(_month, today), averageLabel: '日均'),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: MutedText('这个月还没有账单')),
            ),
          for (final g in groups)
            SectionCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              children: [
                Row(children: [
                  Text(formatDayLabel(g.date, today), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  MutedText('支出 ${formatMoney(g.total)}'),
                ]),
                for (final t in g.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Text(lookups.category(t.categoryId)?.icon ?? '❔', style: const TextStyle(fontSize: 22)),
                    title: Row(children: [
                      Flexible(child: Text(lookups.category(t.categoryId)?.name ?? '未知分类', overflow: TextOverflow.ellipsis)),
                      if (t.recurringId != null) ...[
                        const SizedBox(width: 6),
                        const _Badge('周期'),
                      ],
                    ]),
                    subtitle: Text(
                      [t.note, lookups.account(t.accountId)?.name ?? ''].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(formatCents(t.amount),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    onTap: () => Navigator.of(context).push(TxEditScreen.route(id: t.id)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: brandColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: const Text('周期', style: TextStyle(fontSize: 11, color: brandColor)),
      );
}
