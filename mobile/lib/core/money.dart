// Port of src/core/money.ts. Amounts are integer fen (1/100 CNY).

const _maxCents = 1000000000000;
final _amountRe = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$');

/// Parses user input like "35", "35.5", "1,234.56", "¥20" into cents; null if invalid.
int? parseAmount(String input) {
  final s = input.trim().replaceAll(RegExp(r'[,，\s]'), '').replaceFirst(RegExp(r'^[¥￥]'), '');
  final m = _amountRe.firstMatch(s);
  if (m == null) return null;
  final yuan = int.tryParse(m.group(1)!);
  if (yuan == null) return null;
  final fen = int.parse((m.group(2) ?? '').padRight(2, '0'));
  final cents = yuan * 100 + fen;
  return cents > _maxCents ? null : cents;
}

/// 123456 -> "1,234.56"
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final yuan = (abs ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final fen = (abs % 100).toString().padLeft(2, '0');
  return '$sign$yuan.$fen';
}

/// 123456 -> "¥1,234.56"
String formatMoney(int cents) => cents < 0 ? '-¥${formatCents(-cents)}' : '¥${formatCents(cents)}';

/// 3500 -> "35", 3550 -> "35.50"
String centsToInput(int cents) {
  final yuan = cents ~/ 100;
  final fen = cents % 100;
  return fen == 0 ? '$yuan' : '$yuan.${fen.toString().padLeft(2, '0')}';
}
