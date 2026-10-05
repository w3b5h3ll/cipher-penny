import '../defaults.dart';
import '../model.dart';
import 'amount.dart';
import 'date.dart';

// Port of src/core/parser/parse.ts. Behaviour is pinned by fixtures/parser-cases.json.

class Draft {
  const Draft({
    required this.type,
    required this.amount,
    required this.categoryId,
    this.accountId,
    required this.date,
    required this.note,
    required this.source,
  });

  final String type;
  final int amount;
  final String categoryId;
  final String? accountId;
  final ISODate date;
  final String note;

  /// The text segment this draft came from, for display.
  final String source;
}

final _segmentSeparator = RegExp(r'[,;。!?\n]+|然后|还有|另外|以及');
final _incomeHint = RegExp('收到|收入|到账|入账|进账|赚');
final _leadingFiller = RegExp(r'^(?:\s|用|通过|在)+');
final _trailingFiller =
    RegExp(r'(?:花了|花费了?|花掉了?|消费了?|付了|付款|支付了?|用了|一共|总共|共计|共|大概|大约|是|收到了?|赚了|入账|到账|进账|\s)+$');
final _afterAmountFiller = RegExp(r'^(?:左右|多|整|\s)+');
final _amountThenSpace = RegExp(r'\d(?:\.\d+)?\s*(?:块钱|块|元|圆)?\s+(?=\D)');
final _digit = RegExp(r'\d');

/// Splits on punctuation/conjunctions, and on whitespace after an amount when another amount follows.
List<String> splitSegments(String text) {
  final coarse = text.split(_segmentSeparator).map((s) => s.trim()).where((s) => s.isNotEmpty);
  final result = <String>[];
  for (final seg in coarse) {
    var rest = seg;
    for (;;) {
      final m = _amountThenSpace.firstMatch(rest);
      if (m == null) break;
      final tail = rest.substring(m.end);
      if (!_digit.hasMatch(tail)) break;
      result.add(rest.substring(0, m.end).trim());
      rest = tail;
    }
    if (rest.trim().isNotEmpty) result.add(rest.trim());
  }
  return result;
}

Category? _longestKeywordMatch(String text, Iterable<Category> categories) {
  final lower = text.toLowerCase();
  Category? best;
  var bestLen = 0;
  for (final c in categories) {
    for (final kw in [c.name, ...c.keywords]) {
      final k = kw.trim().toLowerCase();
      if (k.isEmpty || !lower.contains(k)) continue;
      // Ties keep the earlier category; defaults list expense categories first.
      if (k.length > bestLen) {
        best = c;
        bestLen = k.length;
      }
    }
  }
  return best;
}

/// F-QA-5: income hint words bias towards income categories; otherwise longest keyword wins.
Category? matchCategory(String text, List<Category> categories) {
  final active = categories.where((c) => !c.archived).toList();
  final incomeHint = _incomeHint.hasMatch(text);
  if (incomeHint) {
    final inc = _longestKeywordMatch(text, active.where((c) => c.type == income));
    if (inc != null) return inc;
  }
  return _longestKeywordMatch(text, active) ?? fallbackCategory(active, incomeHint ? income : expense);
}

Account? _matchAccount(String text, List<Account> accounts) {
  Account? best;
  for (final a in accounts) {
    if (a.archived || a.name.isEmpty || !text.contains(a.name)) continue;
    if (best == null || a.name.length > best.name.length) best = a;
  }
  return best;
}

String _cleanNote(String text) {
  return text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,.:;，。：；、-]+|[\s,.:;，。：；、-]+$'), '')
      .trim();
}

/// Parses free text (typed or dictated) into transaction drafts (F-QA-2 ~ F-QA-6).
List<Draft> parseEntries(String input, {required ISODate today, required List<Category> categories, List<Account>? accounts}) {
  final text = convertChineseAmounts(normalizeText(input));
  final drafts = <Draft>[];
  var contextDate = today;

  for (final segment in splitSegments(text)) {
    var rest = segment;

    final dateMatch = findDate(rest, today);
    if (dateMatch != null) {
      contextDate = dateMatch.date;
      rest = '${rest.substring(0, dateMatch.start)} ${rest.substring(dateMatch.end)}';
    }

    final amount = pickAmount(findAmounts(rest));
    if (amount == null) continue;

    final before = rest.substring(0, amount.start);
    final after = rest.substring(amount.end);
    // Classify on the unstripped text so hint words like "收到" still count.
    final withoutAmount = '$before $after';
    final category = matchCategory(withoutAmount, categories);
    if (category == null) continue;
    final account = accounts == null ? null : _matchAccount(withoutAmount, accounts);

    var note = '${before.replaceFirst(_trailingFiller, '')} ${after.replaceFirst(_afterAmountFiller, '')}';
    if (account != null) note = note.replaceFirst(account.name, ' ');
    note = _cleanNote(note.replaceFirst(_leadingFiller, '').replaceFirst(_trailingFiller, ''));

    drafts.add(Draft(
      type: category.type,
      amount: amount.cents,
      categoryId: category.id,
      accountId: account?.id,
      date: contextDate,
      note: note,
      source: segment.trim(),
    ));
  }
  return drafts;
}
