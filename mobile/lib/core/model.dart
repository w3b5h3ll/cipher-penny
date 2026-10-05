// Plaintext vault data. Normative definition: docs/vault-format.md §3.
//
// Every record wraps its raw JSON map so fields this client does not know about
// survive a read-modify-write round trip (vault-format §3). Maps are never mutated
// in place; edits build new maps.

typedef Json = Map<String, Object?>;

/// Local calendar date, `YYYY-MM-DD`.
typedef ISODate = String;

const expense = 'expense';
const income = 'income';

const frequencyLabel = {'weekly': '周', 'monthly': '月', 'yearly': '年'};

abstract class VaultRecord {
  const VaultRecord(this.raw);
  final Json raw;

  String get id => raw['id'] as String;
  String? get updatedAt => raw['updatedAt'] as String?;
}

class Account extends VaultRecord {
  const Account(super.raw);
  String get name => raw['name'] as String;
  String get kind => raw['kind'] as String;
  bool get archived => raw['archived'] == true;
}

class Category extends VaultRecord {
  const Category(super.raw);
  String get name => raw['name'] as String;
  String get type => raw['type'] as String;
  String get icon => raw['icon'] as String? ?? '';
  List<String> get keywords => [for (final k in raw['keywords'] as List? ?? const []) k as String];
  bool get archived => raw['archived'] == true;
}

class Transaction extends VaultRecord {
  const Transaction(super.raw);
  String get type => raw['type'] as String;
  int get amount => (raw['amount'] as num).toInt();
  String get categoryId => raw['categoryId'] as String;
  String get accountId => raw['accountId'] as String;
  ISODate get date => raw['date'] as String;
  String get note => raw['note'] as String? ?? '';
  String get createdAt => raw['createdAt'] as String;
  @override
  String get updatedAt => raw['updatedAt'] as String;
  String? get recurringId => raw['recurringId'] as String?;

  Transaction copyWith(Json patch) => Transaction({...raw, ...patch});
}

class RecurringRule extends VaultRecord {
  const RecurringRule(super.raw);
  String get name => raw['name'] as String;
  String get type => raw['type'] as String;
  int get amount => (raw['amount'] as num).toInt();
  String get categoryId => raw['categoryId'] as String;
  String get accountId => raw['accountId'] as String;
  String get note => raw['note'] as String? ?? '';
  String get frequency => raw['frequency'] as String;
  int get interval => (raw['interval'] as num).toInt();
  ISODate get startDate => raw['startDate'] as String;
  ISODate? get endDate => raw['endDate'] as String?;
  bool get active => raw['active'] == true;
  ISODate? get lastGenerated => raw['lastGenerated'] as String?;
}

class Settings {
  const Settings(this.raw);
  final Json raw;
  int get autoLockMinutes => (raw['autoLockMinutes'] as num? ?? 5).toInt();
  String? get updatedAt => raw['updatedAt'] as String?;
}

class Deletion {
  const Deletion(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get deletedAt => raw['deletedAt'] as String;
}

List<T> _wrap<T>(Object? list, T Function(Json) wrap) =>
    [for (final item in list as List? ?? const []) wrap((item as Map).cast<String, Object?>())];

class VaultData {
  VaultData(this.raw);
  final Json raw;

  late final List<Account> accounts = _wrap(raw['accounts'], Account.new);
  late final List<Category> categories = _wrap(raw['categories'], Category.new);
  late final List<Transaction> transactions = _wrap(raw['transactions'], Transaction.new);
  late final List<RecurringRule> recurring = _wrap(raw['recurring'], RecurringRule.new);
  late final Settings settings = Settings((raw['settings'] as Map).cast<String, Object?>());
  late final List<Deletion> deletions = _wrap(raw['deletions'], Deletion.new);

  VaultData copyWith({
    List<Account>? accounts,
    List<Category>? categories,
    List<Transaction>? transactions,
    List<RecurringRule>? recurring,
    Settings? settings,
    List<Deletion>? deletions,
  }) {
    return VaultData({
      ...raw,
      if (accounts != null) 'accounts': [for (final x in accounts) x.raw],
      if (categories != null) 'categories': [for (final x in categories) x.raw],
      if (transactions != null) 'transactions': [for (final x in transactions) x.raw],
      if (recurring != null) 'recurring': [for (final x in recurring) x.raw],
      if (settings != null) 'settings': settings.raw,
      if (deletions != null) 'deletions': [for (final x in deletions) x.raw],
    });
  }
}

const accountKindLabel = {
  'cash': '现金',
  'ewallet': '电子钱包',
  'debit': '储蓄卡',
  'credit': '信用卡',
  'other': '其他',
};
