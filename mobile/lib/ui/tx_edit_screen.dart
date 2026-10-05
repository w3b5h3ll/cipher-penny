import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/defaults.dart';
import '../core/ledger.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../state/session.dart';
import 'common.dart';
import 'theme.dart';

/// F-TX-1, F-TX-3. `id` null means a new transaction.
class TxEditScreen extends StatefulWidget {
  const TxEditScreen({super.key, this.id});
  final String? id;

  static Route<void> route({String? id}) => MaterialPageRoute(builder: (_) => TxEditScreen(id: id));

  @override
  State<TxEditScreen> createState() => _TxEditScreenState();
}

class _TxEditScreenState extends State<TxEditScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _categoryId = '';
  String _accountId = '';
  ISODate _date = todayISO();
  Transaction? _existing;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final session = SessionScope.read(context);
    if (session.status != SessionStatus.unlocked) return;
    final data = session.data;
    _existing = widget.id == null ? null : data.transactions.where((t) => t.id == widget.id).firstOrNull;
    final e = _existing;
    if (e != null) {
      _amount.text = centsToInput(e.amount);
      _note.text = e.note;
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _date = e.date;
    } else {
      _categoryId = fallbackCategory(data.categories, expense)?.id ?? '';
      _accountId = Lookups(data).activeAccounts.firstOrNull?.id ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0 || _categoryId.isEmpty || _accountId.isEmpty) return;
    final input = TransactionInput(
      type: _existing?.type ?? expense,
      amount: amount,
      categoryId: _categoryId,
      accountId: _accountId,
      date: _date,
      note: _note.text.trim(),
    );
    final session = SessionScope.read(context);
    final existing = _existing;
    if (existing != null) {
      session.update((v) => updateTransaction(v, existing.id, input.toJson()));
    } else {
      session.update((v) => addTransactions(v, [input]));
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final session = SessionScope.read(context);
    final navigator = Navigator.of(context);
    if (!await confirm(context, '确定删除这笔账单？', action: '删除', danger: true)) return;
    session.update((v) => deleteTransaction(v, existing.id));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (session.status != SessionStatus.unlocked) return const Scaffold();
    final data = session.data;
    final existing = _existing;
    final title = existing != null ? '编辑账单' : '记一笔';
    if (widget.id != null && existing == null) {
      return Scaffold(
        appBar: subPageBar(context),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SectionCard(children: [
            const Text('账单不存在或已删除。'),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: Navigator.of(context).pop, child: const Text('返回'))),
          ]),
        ),
      );
    }
    final amount = parseAmount(_amount.text);
    final valid = amount != null && amount > 0 && _categoryId.isNotEmpty && _accountId.isNotEmpty;
    final ruleId = existing?.recurringId;
    final rule = ruleId == null ? null : data.recurring.where((r) => r.id == ruleId).firstOrNull;

    return Scaffold(
      appBar: subPageBar(context),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 64), children: [
        SectionCard(title: title, children: [
          Field(
            label: '金额（元）',
            child: TdInput(
              controller: _amount,
              autofocus: existing == null,
              hint: '0.00',
              semanticLabel: '金额',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TdText.headlineSmall.copyWith(fontFeatures: TdText.tabular),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Field(
            label: '分类',
            child: CategoryDropdown(categories: data.categories, value: _categoryId, onChanged: (id) => setState(() => _categoryId = id)),
          ),
          Field(
            label: '账户',
            child: AccountDropdown(accounts: data.accounts, value: _accountId, onChanged: (id) => setState(() => _accountId = id)),
          ),
          Field(label: '日期', child: DateField(value: _date, onChanged: (d) => setState(() => _date = d))),
          Field(label: '备注', child: TdInput(controller: _note, hint: '可选', semanticLabel: '备注')),
          if (rule != null) Muted('由周期账单「${rule.name}」自动生成。修改这一笔不会影响规则。', small: true),
          Row(children: [
            FilledButton(onPressed: valid ? _save : null, child: const Text('保存')),
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
