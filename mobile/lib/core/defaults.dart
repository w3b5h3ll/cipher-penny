import 'dart:math';

import 'model.dart';

// Port of src/core/defaults.ts. Keep the lists identical so both clients create the same vault.

final _random = Random.secure();

/// UUID v4 (vault-format §3: new records use UUID v4).
String newId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

const _defaultAccounts = [
  ('微信', 'ewallet'),
  ('支付宝', 'ewallet'),
  ('银行卡', 'debit'),
  ('现金', 'cash'),
];

const _defaultCategories = [
  (expense, '餐饮', '🍜', ['饭', '餐', '早餐', '早饭', '午饭', '午餐', '晚饭', '晚餐', '夜宵', '宵夜', '外卖', '吃', '咖啡', '奶茶', '饮料', '零食', '水果', '火锅', '烧烤', '面包']),
  (expense, '交通', '🚇', ['打车', '出租', '滴滴', '地铁', '公交', '高铁', '火车', '机票', '飞机', '加油', '停车', '过路费', '单车', '充电']),
  (expense, '购物', '🛍️', ['买', '淘宝', '京东', '拼多多', '衣服', '鞋', '超市', '日用', '数码']),
  (expense, '居住', '🏠', ['房租', '水费', '电费', '燃气', '煤气', '物业', '宽带', '水电']),
  (expense, '通讯', '📱', ['话费', '流量', '手机费', '充值']),
  (expense, '订阅', '🔁', ['订阅', '会员', '续费', 'iCloud', 'Netflix', 'Spotify', 'ChatGPT', 'Claude', 'Cursor', 'YouTube', 'GitHub']),
  (expense, '娱乐', '🎮', ['电影', '游戏', 'KTV', '演唱会', '门票', '旅游', '酒店', '景点']),
  (expense, '医疗', '💊', ['医院', '药', '看病', '挂号', '体检', '牙']),
  (expense, '教育', '📚', ['书', '课程', '培训', '学费', '考试']),
  (expense, '人情', '🎁', ['红包', '礼物', '份子钱', '请客', '随礼']),
  (expense, '其他', '📦', <String>[]),
  (income, '工资', '💼', ['工资', '薪水', '薪资']),
  (income, '奖金', '🏆', ['奖金', '年终奖', '绩效']),
  (income, '理财', '📈', ['利息', '分红', '理财', '收益', '股息']),
  (income, '兼职', '🧑‍💻', ['兼职', '外快', '稿费', '副业']),
  (income, '报销', '🧾', ['报销']),
  (income, '退款', '↩️', ['退款', '退货', '返现']),
  (income, '红包收入', '🧧', ['红包']),
  (income, '其他收入', '💰', <String>[]),
];

List<Account> createDefaultAccounts() => [
      for (final (name, kind) in _defaultAccounts)
        Account({'id': newId(), 'name': name, 'kind': kind, 'initialBalance': 0, 'archived': false}),
    ];

List<Category> createDefaultCategories() => [
      for (final (type, name, icon, keywords) in _defaultCategories)
        Category({'id': newId(), 'name': name, 'type': type, 'icon': icon, 'keywords': [...keywords], 'archived': false}),
    ];

VaultData createDefaultVault() => VaultData({
      'schemaVersion': 1,
      'accounts': [for (final a in createDefaultAccounts()) a.raw],
      'categories': [for (final c in createDefaultCategories()) c.raw],
      'transactions': <Object?>[],
      'recurring': <Object?>[],
      'settings': {'autoLockMinutes': 5},
    });

/// Category used when nothing matches: prefers one named "其他…", else the first of that type.
Category? fallbackCategory(List<Category> categories, String type) {
  final active = categories.where((c) => c.type == type && !c.archived).toList();
  for (final c in active) {
    if (c.name.startsWith('其他')) return c;
  }
  return active.isEmpty ? null : active.first;
}
