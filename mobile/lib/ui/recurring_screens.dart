import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/defaults.dart';
import '../core/ledger.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/recurring.dart';
import '../state/session.dart';
import 'common.dart';
import 'theme.dart';

String describeFrequency(String frequency, int interval) =>
    interval == 1 ? '每${frequencyLabel[frequency]}' : '每 $interval ${frequencyLabel[frequency]}';

/// F-REC-4
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final session = SessionScope.of(context);
    final data = session.data;
    final lookups = Lookups(data);
    final today = todayISO();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 64), children: [
      Gap(children: [
        Row(children: [
          Expanded(child: Text('周期账单', style: TdText.titleMedium.copyWith(color: td.textPrimary))),
          FilledButton(onPressed: () => Navigator.of(context).push(RecurringEditScreen.route()), child: const Text('+ 新建')),
        ]),
        const Muted('订阅、房租、话费等固定支出。每次解锁时会自动补记到今天为止应发生的账单。', small: true),
        if (data.recurring.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Muted('还没有周期账单', textAlign: TextAlign.center))
        else
          TdCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (i, r) in data.recurring.indexed)
                Container(
                  padding: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    border: i == data.recurring.length - 1 ? null : Border(bottom: BorderSide(color: td.stroke)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TxRow(
                        icon: lookups.category(r.categoryId)?.icon ?? '🔁',
                        title: r.name,
                        subtitle: describeFrequency(r.frequency, r.interval) + _status(r, today),
                        amount: formatMoney(r.amount),
                        dimmed: !r.active,
                        onTap: () => Navigator.of(context).push(RecurringEditScreen.route(id: r.id)),
                      ),
                    ),
                    SmallButton(
                      r.active ? '暂停' : '恢复',
                      onPressed: () => session.update((d) => setRecurringActive(d, r.id, !r.active, todayISO())),
                    ),
                  ]),
                ),
            ]),
          ),
      ]),
    ]);
  }

  static String _status(RecurringRule r, ISODate today) {
    if (!r.active) return ' · 已暂停';
    final next = nextOccurrence(r, today);
    return next != null ? ' · 下次 ${formatDayLabel(next, today)}' : ' · 已结束';
  }
}

/// F-REC-1, F-REC-4. `id` null means a new rule.
class RecurringEditScreen extends StatefulWidget {
  const RecurringEditScreen({super.key, this.id});
  final String? id;

  static Route<void> route({String? id}) => MaterialPageRoute(builder: (_) => RecurringEditScreen(id: id));

  @override
  State<RecurringEditScreen> createState() => _RecurringEditScreenState();
}

class _RecurringEditScreenState extends State<RecurringEditScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _interval = TextEditingController(text: '1');
  final _note = TextEditingController();
  String _categoryId = '';
  String _accountId = '';
  String _frequency = 'monthly';
  ISODate _startDate = todayISO();
  ISODate? _endDate;
  RecurringRule? _existing;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final session = SessionScope.read(context);
    if (session.status != SessionStatus.unlocked) return;
    final data = session.data;
    _existing = widget.id == null ? null : data.recurring.where((r) => r.id == widget.id).firstOrNull;
    final e = _existing;
    if (e != null) {
      _name.text = e.name;
      _amount.text = centsToInput(e.amount);
      _interval.text = '${e.interval}';
      _note.text = e.note;
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _frequency = e.frequency;
      _startDate = e.startDate;
      _endDate = e.endDate;
    } else {
      final subscription = data.categories.where((c) => c.name == '订阅' && !c.archived).firstOrNull;
      _categoryId = subscription?.id ?? fallbackCategory(data.categories, expense)?.id ?? '';
      _accountId = Lookups(data).activeAccounts.firstOrNull?.id ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _interval.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _intervalValue {
    final n = int.tryParse(_interval.text.trim());
    return n != null && n >= 1 && n <= 99 ? n : null;
  }

  bool get _valid {
    final amount = parseAmount(_amount.text);
    final end = _endDate;
    return _name.text.trim().isNotEmpty &&
        amount != null &&
        amount > 0 &&
        _categoryId.isNotEmpty &&
        _accountId.isNotEmpty &&
        _intervalValue != null &&
        (end == null || end.compareTo(_startDate) >= 0);
  }

  void _save() {
    if (!_valid) return;
    final existing = _existing;
    final raw = <String, Object?>{
      ...?existing?.raw,
      'id': existing?.id ?? newId(),
      'name': _name.text.trim(),
      'type': existing?.type ?? expense,
      'amount': parseAmount(_amount.text)!,
      'categoryId': _categoryId,
      'accountId': _accountId,
      'note': _note.text.trim(),
      'frequency': _frequency,
      'interval': _intervalValue!,
      'startDate': _startDate,
      'endDate': _endDate,
      'active': existing?.active ?? true,
    };
    if (_endDate == null) raw.remove('endDate');
    final today = todayISO();
    SessionScope.read(context).update((d) => applyRecurring(upsertRecurring(d, RecurringRule(raw)), today).data);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final session = SessionScope.read(context);
    final navigator = Navigator.of(context);
    if (!await confirm(context, '删除周期账单「${existing.name}」？已生成的账单会保留。', action: '删除', danger: true)) return;
    session.update((d) => deleteRecurring(d, existing.id));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (session.status != SessionStatus.unlocked) return const Scaffold();
    final data = session.data;
    final existing = _existing;
    if (widget.id != null && existing == null) {
      return Scaffold(
        appBar: subPageBar(context),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SectionCard(children: [
            const Text('周期账单不存在。'),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: Navigator.of(context).pop, child: const Text('返回'))),
          ]),
        ),
      );
    }
    final backfills = existing == null && _startDate.compareTo(todayISO()) < 0;
    void changed(String _) => setState(() {});

    return Scaffold(
      appBar: subPageBar(context),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 64), children: [
        SectionCard(title: existing != null ? '编辑周期账单' : '新建周期账单', children: [
          Field(
            label: '名称',
            child: TdInput(
              controller: _name,
              hint: '例如：iCloud 200GB',
              semanticLabel: '名称',
              autofocus: existing == null,
              onChanged: changed,
            ),
          ),
          Field(
            label: '金额（元）',
            child: TdInput(
              controller: _amount,
              hint: '0.00',
              semanticLabel: '金额',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TdText.headlineSmall.copyWith(fontFeatures: TdText.tabular),
              onChanged: changed,
            ),
          ),
          Field(
            label: '频率',
            child: Row(children: [
              const Text('每'),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TdInput(
                  controller: _interval,
                  semanticLabel: '间隔',
                  keyboardType: TextInputType.number,
                  invalid: _intervalValue == null,
                  onChanged: changed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OptionSelect<String>(
                  semanticLabel: '周期单位',
                  value: _frequency,
                  options: frequencyLabel,
                  onChanged: (f) => setState(() => _frequency = f),
                ),
              ),
            ]),
          ),
          Field(
            label: '分类',
            child: CategoryDropdown(categories: data.categories, value: _categoryId, onChanged: (id) => setState(() => _categoryId = id)),
          ),
          Field(
            label: '账户',
            child: AccountDropdown(accounts: data.accounts, value: _accountId, onChanged: (id) => setState(() => _accountId = id)),
          ),
          Field(
            label: '开始日期',
            hint: '按月的规则以这一天为准，短月份取月底',
            child: DateField(semanticLabel: '开始日期', value: _startDate, onChanged: (d) => setState(() => _startDate = d)),
          ),
          Field(
            label: '结束日期（可选）',
            hint: _endDate != null && _endDate!.compareTo(_startDate) < 0 ? '结束日期不能早于开始日期' : null,
            hintIsError: true,
            child: DateField(
              semanticLabel: '结束日期',
              value: _endDate,
              min: _startDate,
              onChanged: (d) => setState(() => _endDate = d),
              onClear: () => setState(() => _endDate = null),
            ),
          ),
          Field(label: '账单备注（留空则使用名称）', child: TdInput(controller: _note, semanticLabel: '账单备注')),
          if (backfills)
            TdBanner(child: Text('开始日期早于今天：保存后会补记从开始日期到今天的账单。', style: TdText.mark.copyWith(color: Td.of(context).textPrimary))),
          Row(children: [
            FilledButton(onPressed: _valid ? _save : null, child: const Text('保存')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: Navigator.of(context).pop, child: const Text('取消')),
            const Spacer(),
            if (existing != null) OutlinedButton(onPressed: _delete, style: dangerButton(context), child: const Text('删除')),
          ]),
        ]),
      ]),
    );
  }
}
