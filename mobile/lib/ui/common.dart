import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/stats.dart';
import '../state/session.dart';

const brandColor = Color(0xFFE37318);

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  /// Rebuilds the caller whenever the session changes.
  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// For callbacks; does not subscribe.
  static Session read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<SessionScope>()!.widget as SessionScope).notifier!;
}

String describeError(Object err) => err.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');

class Lookups {
  Lookups(VaultData data)
      : _categories = {for (final c in data.categories) c.id: c},
        _accounts = {for (final a in data.accounts) a.id: a},
        activeAccounts = [for (final a in data.accounts) if (!a.archived) a];

  final Map<String, Category> _categories;
  final Map<String, Account> _accounts;
  final List<Account> activeAccounts;

  Category? category(String id) => _categories[id];
  Account? account(String id) => _accounts[id];
}

Future<bool> confirm(BuildContext context, String message, {String action = '确定', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: danger ? TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error) : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13));
}

class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13).merge(style),
      );
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});
  final MonthKey month;
  final ValueChanged<MonthKey> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = monthKeyOf(todayISO());
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: '上个月',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(addMonthsToKey(month, -1)),
      ),
      GestureDetector(
        onTap: month == current ? null : () => onChanged(current),
        child: Text(formatMonthKey(month), style: Theme.of(context).textTheme.titleMedium),
      ),
      IconButton(
        tooltip: '下个月',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(addMonthsToKey(month, 1)),
      ),
    ]);
  }
}

class YearSwitcher extends StatelessWidget {
  const YearSwitcher({super.key, required this.year, required this.onChanged});
  final int year;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: '上一年', icon: const Icon(Icons.chevron_left), onPressed: () => onChanged(year - 1)),
      Text('$year年', style: Theme.of(context).textTheme.titleMedium),
      IconButton(tooltip: '下一年', icon: const Icon(Icons.chevron_right), onPressed: () => onChanged(year + 1)),
    ]);
  }
}

/// Total, count and a per-day/per-month average; `periods` is 0 for periods that haven't started.
class SummaryBar extends StatelessWidget {
  const SummaryBar({super.key, required this.spending, required this.periods, required this.averageLabel});
  final Spending spending;
  final int periods;
  final String averageLabel;

  @override
  Widget build(BuildContext context) {
    final average = periods > 0 ? (spending.total / periods).round() : null;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MutedText(label),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        );
    return SectionCard(children: [
      Row(children: [
        cell('支出', formatMoney(spending.total), color: brandColor),
        cell('笔数', '${spending.count}'),
        cell(averageLabel, average == null ? '—' : formatMoney(average)),
      ]),
    ]);
  }
}

class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({super.key, required this.categories, required this.value, required this.onChanged});
  final List<Category> categories;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [for (final c in categories) if (c.type == expense && (!c.archived || c.id == value)) c];
    return DropdownButtonFormField<String>(
      key: ValueKey('cat-$value'),
      initialValue: options.any((c) => c.id == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '分类', isDense: true),
      items: [
        for (final c in options) DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (id) => id == null ? null : onChanged(id),
    );
  }
}

class AccountDropdown extends StatelessWidget {
  const AccountDropdown({super.key, required this.accounts, required this.value, required this.onChanged});
  final List<Account> accounts;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [for (final a in accounts) if (!a.archived || a.id == value) a];
    return DropdownButtonFormField<String>(
      key: ValueKey('acc-$value'),
      initialValue: options.any((a) => a.id == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '账户', isDense: true),
      items: [for (final a in options) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
      onChanged: (id) => id == null ? null : onChanged(id),
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged});
  final ISODate value;
  final ValueChanged<ISODate> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final (:year, :month, :day) = parseISODate(value);
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(year, month, day),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(toISODate(picked.year, picked.month, picked.day));
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '日期', isDense: true),
        child: Text(value),
      ),
    );
  }
}
