import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/ledger.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/parser/parse.dart';
import 'common.dart';

class _DraftForm {
  _DraftForm({required int amount, required this.categoryId, required this.accountId, required this.date, required String note})
      : amount = TextEditingController(text: centsToInput(amount)),
        note = TextEditingController(text: note);

  final TextEditingController amount;
  final TextEditingController note;
  String categoryId;
  String accountId;
  ISODate date;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

/// F-QA-1 ~ F-QA-7. Voice input comes from the keyboard's dictation key (spec A-1).
class QuickAdd extends StatefulWidget {
  const QuickAdd({super.key});
  @override
  State<QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<QuickAdd> {
  final _text = TextEditingController();
  final _drafts = <_DraftForm>[];
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    _clearDrafts();
    super.dispose();
  }

  void _clearDrafts() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts.clear();
  }

  void _parse() {
    final input = _text.text.trim();
    if (input.isEmpty) return;
    final data = SessionScope.read(context).data;
    final defaultAccountId = Lookups(data).activeAccounts.firstOrNull?.id ?? '';
    final skipped = <String>[];
    final drafts = <_DraftForm>[];
    for (final d in parseEntries(input, today: todayISO(), categories: data.categories, accounts: data.accounts)) {
      if (d.type == income) {
        skipped.add('${d.note.isEmpty ? '收入' : d.note} ${formatMoney(d.amount)}');
        continue;
      }
      drafts.add(_DraftForm(
        amount: d.amount,
        categoryId: d.categoryId,
        accountId: d.accountId ?? defaultAccountId,
        date: d.date,
        note: d.note,
      ));
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _clearDrafts();
      _drafts.addAll(drafts);
      _message = skipped.isNotEmpty
          ? '已跳过收入：${skipped.join('、')}。目前只记录支出。'
          : drafts.isEmpty
              ? '没有识别到金额，试试“午饭 35”这样的说法'
              : null;
    });
  }

  bool get _invalid => _drafts.any((d) {
        final amount = parseAmount(d.amount.text);
        return amount == null || amount <= 0 || d.categoryId.isEmpty || d.accountId.isEmpty;
      });

  void _saveAll() {
    if (_invalid || _drafts.isEmpty) return;
    final inputs = [
      for (final d in _drafts)
        TransactionInput(
          type: expense,
          amount: parseAmount(d.amount.text)!,
          categoryId: d.categoryId,
          accountId: d.accountId,
          date: d.date,
          note: d.note.text.trim(),
        ),
    ];
    SessionScope.read(context).update((v) => addTransactions(v, inputs));
    final total = inputs.fold(0, (s, i) => s + i.amount);
    setState(() {
      _message = '已保存 ${inputs.length} 笔，共 ${formatMoney(total)}';
      _clearDrafts();
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = SessionScope.of(context).data;
    return SectionCard(children: [
      TextField(
        controller: _text,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: '说或输入：昨天打车28，晚上和朋友吃饭260',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: '识别',
            icon: const Icon(Icons.auto_awesome),
            color: brandColor,
            onPressed: _parse,
          ),
        ),
        onSubmitted: (_) => _parse(),
      ),
      for (final d in _drafts) ...[
        const SizedBox(height: 12),
        _DraftCard(
          key: ObjectKey(d),
          draft: d,
          data: data,
          onChanged: () => setState(() {}),
          onRemove: () => setState(() {
            _drafts.remove(d);
            d.dispose();
          }),
        ),
      ],
      if (_drafts.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => setState(_clearDrafts), child: const Text('取消')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _invalid ? null : _saveAll, child: Text('保存 ${_drafts.length} 笔')),
        ]),
      ],
      if (_message != null) ...[const SizedBox(height: 8), MutedText(_message!)],
    ]);
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({super.key, required this.draft, required this.data, required this.onChanged, required this.onRemove});
  final _DraftForm draft;
  final VaultData data;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final amount = parseAmount(draft.amount.text);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: draft.amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: '¥ ',
                isDense: true,
                errorText: amount == null || amount <= 0 ? '金额无效' : null,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          IconButton(tooltip: '删除这条', icon: const Icon(Icons.close), onPressed: onRemove),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: CategoryDropdown(
                  categories: data.categories,
                  value: draft.categoryId,
                  onChanged: (id) {
                    draft.categoryId = id;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AccountDropdown(
                  accounts: data.accounts,
                  value: draft.accountId,
                  onChanged: (id) {
                    draft.accountId = id;
                    onChanged();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DateField(
                  value: draft.date,
                  onChanged: (date) {
                    draft.date = date;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.note,
                  decoration: const InputDecoration(labelText: '备注', isDense: true),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
