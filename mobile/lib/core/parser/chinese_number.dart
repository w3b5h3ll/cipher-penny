// Port of src/core/parser/chineseNumber.ts.

const _digits = {'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
const _units = {'十': 10, '百': 100, '千': 1000};

const cnNumeralChars = '零〇一二两三四五六七八九十百千万';

/// "三十五" -> 35, "一百零五" -> 105; colloquial "三百五" -> 350, "两万三" -> 23000.
/// Returns null for strings with unsupported characters.
int? parseChineseInteger(String text) {
  if (text.isEmpty) return null;
  final chars = text.split('');
  var total = 0;
  var section = 0;
  var digit = -1;
  var lastUnit = 0;

  for (final ch in chars) {
    final d = _digits[ch];
    final u = _units[ch];
    if (d != null) {
      digit = d;
    } else if (u != null) {
      section += (digit == -1 ? 1 : digit) * u;
      digit = -1;
      lastUnit = u;
    } else if (ch == '万') {
      total += (section + (digit > 0 ? digit : 0)) * 10000;
      section = 0;
      digit = -1;
      lastUnit = 10000;
    } else {
      return null;
    }
  }

  if (digit > 0) {
    final colloquial = lastUnit >= 100 && chars.length >= 2 && _isUnitChar(chars[chars.length - 2]);
    section += colloquial ? digit * (lastUnit ~/ 10) : digit;
  }
  return total + section;
}

bool _isUnitChar(String ch) => ch == '十' || ch == '百' || ch == '千' || ch == '万';
