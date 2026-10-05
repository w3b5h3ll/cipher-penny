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
                    TxRow(
                      icon: lookups.category(t.categoryId)?.icon ?? '❔',
                      title: lookups.category(t.categoryId)?.name ?? '未知分类',
                      badge: t.recurringId != null ? '周期' : null,
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

