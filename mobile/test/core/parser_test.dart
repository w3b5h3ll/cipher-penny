import 'package:cipher_penny/core/defaults.dart';
import 'package:cipher_penny/core/parser/chinese_number.dart';
import 'package:cipher_penny/core/parser/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';

void main() {
  final fixture = loadFixture('parser-cases.json');
  final categories = createDefaultCategories();
  final accounts = createDefaultAccounts();
  String? categoryName(String id) => categories.where((c) => c.id == id).firstOrNull?.name;
  String? accountName(String? id) => accounts.where((a) => a.id == id).firstOrNull?.name;

  group('parseEntries — fixtures/parser-cases.json (F-QA-2 ~ F-QA-6)', () {
    for (final c in (fixture['cases'] as List).cast<Map<String, Object?>>()) {
      test('${c['name']}: ${c['input']}', () {
        final drafts = parseEntries(
          c['input'] as String,
          today: fixture['today'] as String,
          categories: categories,
          accounts: accounts,
        );
        final actual = [
          for (final d in drafts)
            {
              'type': d.type,
              'amount': d.amount,
              'category': categoryName(d.categoryId) ?? '?',
              if (d.accountId != null) 'account': accountName(d.accountId) ?? '?',
              'date': d.date,
              'note': d.note,
            },
        ];
        expect(actual, c['expected']);
      });
    }
  });

  group('parseChineseInteger', () {
    const cases = {
      '五': 5, '十': 10, '十五': 15, '二十': 20, '三十五': 35, '一百零五': 105,
      '三百五': 350, '一千二': 1200, '一千二百五十': 1250, '两万': 20000, '两万三': 23000, '一万零五百': 10500,
    };
    cases.forEach((input, expected) {
      test('$input -> $expected', () => expect(parseChineseInteger(input), expected));
    });

    test('rejects non-numerals', () {
      expect(parseChineseInteger('五块'), isNull);
      expect(parseChineseInteger(''), isNull);
    });
  });
}
