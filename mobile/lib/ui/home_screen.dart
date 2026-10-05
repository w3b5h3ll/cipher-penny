import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/stats.dart';
import 'common.dart';
import 'quick_add.dart';
import 'theme.dart';
import 'tx_edit_screen.dart';

/// F-TX-2: the month's spending grouped by day, with quick add on top.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MonthKey _month = monthKeyOf(todayISO());

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final session = SessionScope.of(context);
    final data = session.data;
    final lookups = Lookups(data);
    final today = todayISO();
    final monthTxs = transactionsInMonth(data.transactions, _month);
    final groups = groupByDate(monthTxs);

    return RefreshIndicator(
      onRefresh: session.syncNow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
        children: [
          Gap(children: [
            const QuickAdd(),
            Row(children: [
              MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(TxEditScreen.route()),
                child: const Text('+ 手动记一笔'),
              ),
            ]),
            SummaryBar(spending: spending(monthTxs), periods: daysElapsed(_month, today), averageLabel: '日均'),
            if (groups.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Muted('这个月还没有账单', textAlign: TextAlign.center)),
            for (final g in groups)
              TdCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(children: [
                      Text(formatDayLabel(g.date, today), style: TdText.titleSmall),
                      const Spacer(),
                      Text('支出 ${formatMoney(g.total)}', style: TdText.mark.copyWith(color: td.textSecondary)),
                    ]),
                  ),
                  for (final t in g.items)
                    _TxRow(
                      icon: lookups.category(t.categoryId)?.icon ?? '❔',
                      title: lookups.category(t.categoryId)?.name ?? '未知分类',
                      recurring: t.recurringId != null,
                      subtitle: [t.note, lookups.account(t.accountId)?.name ?? ''].where((s) => s.isNotEmpty).join(' · '),
                      amount: formatCents(t.amount),
                      onTap: () => Navigator.of(context).push(TxEditScreen.route(id: t.id)),
                    ),
                ]),
              ),
          ]),
        ],
      ),
    );
  }
}

/// `.tx-row`
class _TxRow extends StatelessWidget {
  const _TxRow({
    required this.icon,
    required this.title,
    required this.recurring,
    required this.subtitle,
    required this.amount,
    required this.onTap,
  });
  final String icon;
  final String title;
  final bool recurring;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: td.bgSecondaryContainer, borderRadius: BorderRadius.circular(Td.radiusMedium)),
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(title, overflow: TextOverflow.ellipsis, style: TdText.body.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  if (recurring) ...[const SizedBox(width: 6), const TdBadge('周期')],
                ]),
                if (subtitle.isNotEmpty)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.mark.copyWith(color: td.textSecondary)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(amount, style: TdText.body.copyWith(fontWeight: FontWeight.w600, fontFeatures: TdText.tabular)),
          ]),
        ),
      ),
    );
  }
}
