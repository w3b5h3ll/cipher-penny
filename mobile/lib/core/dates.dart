import 'model.dart';

// Port of src/core/dates.ts. All arithmetic goes through UTC so DST and the
// device time zone never shift a date.

String _pad(int n) => n.toString().padLeft(2, '0');

ISODate toISODate(int year, int month, int day) => '${year.toString().padLeft(4, '0')}-${_pad(month)}-${_pad(day)}';

ISODate todayISO([DateTime? now]) {
  final n = now ?? DateTime.now();
  return toISODate(n.year, n.month, n.day);
}

({int year, int month, int day}) parseISODate(ISODate iso) {
  final parts = iso.split('-');
  return (year: int.parse(parts[0]), month: int.parse(parts[1]), day: int.parse(parts[2]));
}

final _isoRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isValidISODate(String iso) {
  if (!_isoRe.hasMatch(iso)) return false;
  final d = parseISODate(iso);
  return d.month >= 1 && d.month <= 12 && d.day >= 1 && d.day <= daysInMonth(d.year, d.month);
}

int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

ISODate _fromUtc(DateTime d) => toISODate(d.year, d.month, d.day);

ISODate addDays(ISODate iso, int days) {
  final d = parseISODate(iso);
  return _fromUtc(DateTime.utc(d.year, d.month, d.day + days));
}

/// Adds months, clamping to the last day of the target month. `anchorDay` keeps the
/// intended day across short months (Jan 31 -> Feb 28 -> Mar 31).
ISODate addMonths(ISODate iso, int months, [int? anchorDay]) {
  final d = parseISODate(iso);
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12 - (total < 0 && total % 12 != 0 ? 1 : 0);
  final m = total - y * 12 + 1;
  final day = anchorDay ?? d.day;
  final dim = daysInMonth(y, m);
  return toISODate(y, m, day < dim ? day : dim);
}

/// 0 = Sunday ... 6 = Saturday
int dayOfWeek(ISODate iso) {
  final d = parseISODate(iso);
  return DateTime.utc(d.year, d.month, d.day).weekday % 7;
}

/// `YYYY-MM`
typedef MonthKey = String;

MonthKey monthKeyOf(ISODate iso) => iso.substring(0, 7);

MonthKey addMonthsToKey(MonthKey key, int months) => addMonths('$key-01', months).substring(0, 7);

String formatMonthKey(MonthKey key) {
  final parts = key.split('-');
  return '${parts[0]}年${int.parse(parts[1])}月';
}

const _weekdayLabel = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/// "10月5日 周一", with "今天"/"昨天" when applicable.
String formatDayLabel(ISODate iso, ISODate today) {
  final d = parseISODate(iso);
  final base = '${d.month}月${d.day}日 ${_weekdayLabel[dayOfWeek(iso)]}';
  if (iso == today) return '今天 · $base';
  if (iso == addDays(today, -1)) return '昨天 · $base';
  return base;
}
