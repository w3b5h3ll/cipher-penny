import 'chinese_number.dart';

// Port of src/core/parser/amount.ts.

const _cn = '[$cnNumeralChars]+';
const _currencyUnit = '块钱|块|元|圆|毛|角|rmb|RMB';
const _spendVerb = '花了|花费了?|花掉了?|消费了?|付了|支付了?|用了|收到了?|收入了?|赚了|进账|到账|一共|总共|共计|共';

/// Full-width -> half-width, ¥ prefix -> 元 suffix, so later regexes only see one form.
String normalizeText(String input) {
  return input
      .replaceAllMapped(RegExp('[\uFF01-\uFF5E]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xfee0))
      .replaceAll('\u3000', ' ')
      .replaceAllMapped(RegExp(r'[¥￥]\s*(\d+(?:\.\d+)?)'), (m) => '${m[1]}元');
}

String _toDigits(String cn) => parseChineseInteger(cn)?.toString() ?? cn;

final _spendVerbAtEnd = RegExp('(?:$_spendVerb)\\s*\$');
final _moneyNext = RegExp('[钱\\d零〇一二两三四五六七八九十毛角]');

/// Rewrites Chinese numerals that are clearly amounts into digits: those followed by a
/// currency unit ("三十五块") or preceded by a spend verb ("花了三十五").
String convertChineseAmounts(String text) {
  return text
      .replaceAllMapped(RegExp('($_cn)(\\s*)($_currencyUnit)'), (m) {
        final cn = m[1]!;
        final unit = m[3]!;
        final full = m.input;
        // "一块" also means "together" ("一块吃饭"); only treat it as money when context says so.
        if (cn == '一' && unit == '块') {
          final next = m.end < full.length ? full[m.end] : null;
          final moneyNext = next != null && _moneyNext.hasMatch(next);
          if (!moneyNext && !_spendVerbAtEnd.hasMatch(full.substring(0, m.start))) return m[0]!;
        }
        return _toDigits(cn) + m[2]! + unit;
      })
      .replaceAllMapped(RegExp('($_spendVerb)($_cn)'), (m) => m[1]! + _toDigits(m[2]!))
      .replaceAllMapped(
        RegExp(r'(\d)(块|元)([一二两三四五六七八九])(?![零〇一二两三四五六七八九十百千万])'),
        (m) => '${m[1]}${m[2]}${parseChineseInteger(m[3]!)}',
      );
}

class AmountMatch {
  const AmountMatch(this.cents, this.start, this.end, this.hasUnit);
  final int cents;
  final int start;
  final int end;
  final bool hasUnit;
}

// Numbers followed by these are counts, times or dates, not money ("2杯", "8点", "5号").
final _notMoneySuffix =
    RegExp(r'^\s*(?:个|杯|次|斤|件|瓶|盒|份|张|本|人|位|点|号|日|月|天|周|年|岁|楼|层|路|公里|km|小时|分钟|折|%|G|g|kg|ml)');

final _amountRe =
    RegExp(r'(\d+(?:\.\d+)?)(\s*(?:块钱|块|元|圆|毛|角|rmb)(?:\s*(\d)(?:\s*(?:毛|角))?)?)?', caseSensitive: false);
final _digitOrDot = RegExp(r'[\d.]');
final _jiaoUnit = RegExp('毛|角');

const _maxSafeInteger = 9007199254740991;

/// Finds money-like numbers in already-normalised text.
List<AmountMatch> findAmounts(String text) {
  final result = <AmountMatch>[];
  for (final m in _amountRe.allMatches(text)) {
    final start = m.start;
    if (start > 0 && _digitOrDot.hasMatch(text[start - 1])) continue;
    final num = m[1];
    final unitPart = m[2];
    final jiao = m[3];
    if (num == null) continue;
    final end = m.end;
    if (unitPart == null && _notMoneySuffix.hasMatch(text.substring(end))) continue;

    final value = double.parse(num);
    final trimmed = unitPart?.trim() ?? '';
    final int cents;
    if (unitPart != null && trimmed.isNotEmpty && _jiaoUnit.hasMatch(trimmed.substring(0, 1))) {
      cents = (value * 10).round();
    } else {
      cents = (value * 100).round() + (jiao != null ? int.parse(jiao) * 10 : 0);
    }
    if (cents <= 0 || cents > _maxSafeInteger) continue;
    result.add(AmountMatch(cents, start, end, unitPart != null));
  }
  return result;
}

/// Picks the amount: the first one with a currency unit, otherwise the last number (F-QA-3).
AmountMatch? pickAmount(List<AmountMatch> matches) {
  for (final m in matches) {
    if (m.hasUnit) return m;
  }
  return matches.isEmpty ? null : matches.last;
}
