import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/stats.dart';
import 'common.dart';

enum _Period { month, year }

/// F-STAT-1 ~ F-STAT-4
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Period _period = _Period.month;
  MonthKey _month = monthKeyOf(todayISO());
  int _year = int.parse(todayISO().substring(0, 4));

  void _changePeriod(_Period next) {
    final today = todayISO();
    setState(() {
      if (next == _Period.year) {
        _year = int.parse(_month.substring(0, 4));
      } else if (!_month.startsWith('$_year-')) {
        _month = _year == int.parse(today.substring(0, 4)) ? monthKeyOf(today) : '$_year-01';
      }
      _period = next;
    });
  }

  void _openMonth(MonthKey key) => setState(() {
        _month = key;
        _period = _Period.month;
      });

  @override
  Widget build(BuildContext context) {
    final data = SessionScope.of(context).data;
    final lookups = Lookups(data);
    final today = todayISO();
    final txs = _period == _Period.month
        ? transactionsInMonth(data.transactions, _month)
        : transactionsInYear(data.transactions, _year);
    final total = spending(txs);

    return ListView(padding: const EdgeInsets.only(top: 6, bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          _period == _Period.month
              ? MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m))
              : YearSwitcher(year: _year, onChanged: (y) => setState(() => _year = y)),
          const Spacer(),
          SegmentedButton<_Period>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Period.month, label: Text('按月')),
              ButtonSegment(value: _Period.year, label: Text('按年')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => _changePeriod(s.first),
          ),
          const SizedBox(width: 12),
        ]),
      ),
      _period == _Period.month
          ? SummaryBar(spending: total, periods: daysElapsed(_month, today), averageLabel: '日均')
          : SummaryBar(spending: total, periods: monthsElapsed(_year, today), averageLabel: '月均'),
      if (_period == _Period.year)
        _YearTrend(transactions: data.transactions, year: _year, yearTotal: total.total, onOpenMonth: _openMonth),
      _TotalsCard(
        title: '分类',
        totals: spendingByCategory(txs),
        label: (id) {
          final c = lookups.category(id);
          return c == null ? '未知分类' : '${c.icon} ${c.name}';
        },
      ),
      _TotalsCard(title: '账户', totals: spendingByAccount(txs), label: (id) => lookups.account(id)?.name ?? '未知账户'),
    ]);
  }
}

class _YearTrend extends StatelessWidget {
  const _YearTrend({required this.transactions, required this.year, required this.yearTotal, required this.onOpenMonth});
  final List<Transaction> transactions;
  final int year;
  final int yearTotal;
  final ValueChanged<MonthKey> onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final months = monthlySpending(transactions, year);
    final active = [for (final m in months) if (m.count > 0) m];
    final currentMonth = monthKeyOf(todayISO());
    final maxTotal = months.fold(0, (s, m) => math.max(s, m.total));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (active.isEmpty) {
      return SectionCard(title: '月度趋势', children: [MutedText('$year年没有支出记录')]);
    }
    return SectionCard(title: '月度趋势', children: [
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: InkWell(
                onTap: () => onOpenMonth(months[i].month),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: maxTotal == 0 || months[i].total == 0 ? 0 : math.max(0.02, months[i].total / maxTotal),
                        widthFactor: 0.6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: months[i].month == currentMonth ? brandColor : brandColor.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${i + 1}', style: TextStyle(fontSize: 11, color: muted)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.6), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(1)},
        children: [
          TableRow(children: [
            for (final h in ['月份', '支出', '笔数', '占全年'])
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: MutedText(h)),
          ]),
          for (final m in active)
            TableRow(children: [
              InkWell(
                onTap: () => onOpenMonth(m.month),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('${int.parse(m.month.substring(5))}月', style: const TextStyle(color: brandColor)),
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(formatCents(m.total))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('${m.count}')),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${yearTotal == 0 ? '0.0' : (m.total / yearTotal * 100).toStringAsFixed(1)}%'),
              ),
            ]),
        ],
      ),
    ]);
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.title, required this.totals, required this.label});
  final String title;
  final List<GroupTotal> totals;
  final String Function(String id) label;

  @override
  Widget build(BuildContext context) {
    final maxTotal = totals.firstOrNull?.total ?? 0;
    return SectionCard(title: title, children: [
      if (totals.isEmpty) const MutedText('没有支出记录'),
      for (final t in totals)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text.rich(TextSpan(children: [
                TextSpan(text: label(t.id)),
                TextSpan(text: '  ${t.count} 笔', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]))),
              Text.rich(TextSpan(children: [
                TextSpan(text: formatMoney(t.total)),
                TextSpan(
                  text: '  ${(t.ratio * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ])),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxTotal == 0 ? 0 : t.total / maxTotal,
                minHeight: 6,
                color: brandColor,
                backgroundColor: brandColor.withValues(alpha: 0.1),
              ),
            ),
          ]),
        ),
    ]);
  }
}
