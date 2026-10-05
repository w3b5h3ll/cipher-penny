import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/stats.dart';
import 'common.dart';
import 'theme.dart';

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

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 64), children: [
      Gap(children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            _period == _Period.month
                ? MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m))
                : YearSwitcher(year: _year, onChanged: (y) => setState(() => _year = y)),
            Segmented<_Period>(
              options: const {_Period.month: '按月', _Period.year: '按年'},
              value: _period,
              onChanged: _changePeriod,
            ),
          ],
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
      ]),
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
    final td = Td.of(context);
    final months = monthlySpending(transactions, year);
    final active = [for (final m in months) if (m.count > 0) m];
    final currentMonth = monthKeyOf(todayISO());
    final maxTotal = months.fold(0, (s, m) => math.max(s, m.total));
    final cellStyle = TdText.mark.copyWith(fontFeatures: TdText.tabular, color: td.textPrimary);
    final headStyle = TdText.mark.copyWith(color: td.textSecondary);

    if (active.isEmpty) {
      return SectionCard(title: '月度趋势', children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Muted('$year年没有支出记录', textAlign: TextAlign.center)),
      ]);
    }

    Widget cell(Widget child, {bool first = false, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          alignment: first ? Alignment.centerLeft : Alignment.centerRight,
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: td.stroke))),
          child: child,
        );

    return SectionCard(title: '月度趋势', children: [
      SizedBox(
        height: 160,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < 12; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                label: '${i + 1}月：支出 ${formatMoney(months[i].total)}，${months[i].count} 笔',
                child: InkWell(
                  borderRadius: BorderRadius.circular(Td.radiusDefault),
                  onTap: () => onOpenMonth(months[i].month),
                  child: Column(children: [
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: maxTotal == 0 || months[i].total == 0 ? 0 : math.max(0.0125, months[i].total / maxTotal),
                        widthFactor: 0.6,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 16),
                          decoration: BoxDecoration(
                            color: td.expense,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${i + 1}',
                      style: months[i].month == currentMonth
                          ? TdText.mark.copyWith(color: td.brand, fontWeight: FontWeight.w600)
                          : TdText.mark.copyWith(color: td.textSecondary),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
      Table(
        children: [
          TableRow(children: [
            cell(Text('月份', style: headStyle), first: true),
            cell(Text('支出', style: headStyle)),
            cell(Text('笔数', style: headStyle)),
            cell(Text('占全年', style: headStyle)),
          ]),
          for (final (i, m) in active.indexed)
            TableRow(children: [
              cell(
                GestureDetector(
                  onTap: () => onOpenMonth(m.month),
                  child: Text('${int.parse(m.month.substring(5))}月', style: cellStyle.copyWith(color: td.brand)),
                ),
                first: true,
                last: i == active.length - 1,
              ),
              cell(Text(formatCents(m.total), style: cellStyle), last: i == active.length - 1),
              cell(Text('${m.count}', style: cellStyle), last: i == active.length - 1),
              cell(
                Text('${yearTotal == 0 ? '0.0' : (m.total / yearTotal * 100).toStringAsFixed(1)}%', style: cellStyle),
                last: i == active.length - 1,
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
    final td = Td.of(context);
    final maxTotal = totals.firstOrNull?.total ?? 0;
    final small = TdText.mark.copyWith(color: td.textSecondary);
    return SectionCard(title: title, children: [
      if (totals.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Muted('没有支出记录', textAlign: TextAlign.center)),
      for (final t in totals)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: label(t.id)),
                TextSpan(text: ' ${t.count} 笔', style: small),
              ])),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: formatMoney(t.total)),
                TextSpan(text: ' ${(t.ratio * 100).toStringAsFixed(1)}%', style: small),
              ]),
              style: const TextStyle(fontFeatures: TdText.tabular),
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: maxTotal == 0 ? 0 : t.total / maxTotal,
              minHeight: 6,
              color: td.expense,
              backgroundColor: td.bgSecondaryContainer,
            ),
          ),
        ]),
    ]);
  }
}
