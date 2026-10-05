import '../dates.dart';
import '../model.dart';

// Port of src/core/parser/date.ts.

class DateMatch {
  const DateMatch(this.date, this.start, this.end);
  final ISODate date;
  final int start;
  final int end;
}

const _relativeDays = {'大前天': -3, '前天': -2, '昨天': -1, '昨日': -1, '昨晚': -1, '今天': 0, '今日': 0, '今早': 0, '今晚': 0};

const _weekday = {
  '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 0, '天': 0,
  '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 0,
};

typedef _Resolver = ISODate? Function(RegExpMatch m, ISODate today);

ISODate? _validOrNull(ISODate iso) => isValidISODate(iso) ? iso : null;

/// Pattern order matters: more specific forms first.
final List<(RegExp, _Resolver)> _patterns = [
  (
    RegExp(r'(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})[日号]?'),
    (m, _) => _validOrNull(toISODate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))),
  ),
  (
    RegExp(r'(\d{1,2})月(\d{1,2})(?:日|号)?(?!\d)'),
    (m, today) {
      final year = parseISODate(today).year;
      final month = int.parse(m[1]!);
      final day = int.parse(m[2]!);
      final date = _validOrNull(toISODate(year, month, day));
      if (date == null) return null;
      return date.compareTo(today) > 0 ? _validOrNull(toISODate(year - 1, month, day)) : date;
    },
  ),
  (
    RegExp('(大前天|前天|昨天|昨日|昨晚|今天|今日|今早|今晚)'),
    (m, today) => addDays(today, _relativeDays[m[1]!] ?? 0),
  ),
  (
    RegExp('(上上|上)(?:周|星期|礼拜)([一二三四五六日天1-7])'),
    (m, today) {
      final weeksBack = m[1] == '上上' ? 2 : 1;
      final monday = addDays(today, -((dayOfWeek(today) + 6) % 7) - 7 * weeksBack);
      return addDays(monday, (_weekday[m[2]!]! + 6) % 7);
    },
  ),
  (
    RegExp('(?:周|星期|礼拜)([一二三四五六日天1-7])'),
    (m, today) => addDays(today, -((dayOfWeek(today) - _weekday[m[1]!]! + 7) % 7)),
  ),
  (
    RegExp(r'(?<!\d)(\d{1,2})[号日](?![\d线楼院])'),
    (m, today) {
      final day = int.parse(m[1]!);
      final t = parseISODate(today);
      final date = _validOrNull(toISODate(t.year, t.month, day));
      if (date != null && date.compareTo(today) <= 0) return date;
      final prev = parseISODate(addMonths(toISODate(t.year, t.month, 1), -1));
      return _validOrNull(toISODate(prev.year, prev.month, day));
    },
  ),
];

/// Finds the first date expression in normalised text (F-QA-4).
DateMatch? findDate(String text, ISODate today) {
  for (final (re, resolve) in _patterns) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    final date = resolve(m, today);
    if (date != null) return DateMatch(date, m.start, m.end);
  }
  return null;
}
