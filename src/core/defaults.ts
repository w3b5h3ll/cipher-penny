import { newId } from './id';
import type { Account, AccountKind, Category, TxType, VaultData } from './model';

const DEFAULT_ACCOUNTS: Array<[string, AccountKind]> = [
  ['现金', 'cash'],
  ['微信', 'ewallet'],
  ['支付宝', 'ewallet'],
  ['银行卡', 'debit'],
];

const DEFAULT_CATEGORIES: Array<[TxType, string, string, string[]]> = [
  ['expense', '餐饮', '🍜', ['饭', '餐', '早餐', '早饭', '午饭', '午餐', '晚饭', '晚餐', '夜宵', '宵夜', '外卖', '吃', '咖啡', '奶茶', '饮料', '零食', '水果', '火锅', '烧烤', '面包']],
  ['expense', '交通', '🚇', ['打车', '出租', '滴滴', '地铁', '公交', '高铁', '火车', '机票', '飞机', '加油', '停车', '过路费', '单车', '充电']],
  ['expense', '购物', '🛍️', ['买', '淘宝', '京东', '拼多多', '衣服', '鞋', '超市', '日用', '数码']],
  ['expense', '居住', '🏠', ['房租', '水费', '电费', '燃气', '煤气', '物业', '宽带', '水电']],
  ['expense', '通讯', '📱', ['话费', '流量', '手机费', '充值']],
  ['expense', '订阅', '🔁', ['订阅', '会员', '续费', 'iCloud', 'Netflix', 'Spotify', 'ChatGPT', 'Claude', 'Cursor', 'YouTube', 'GitHub']],
  ['expense', '娱乐', '🎮', ['电影', '游戏', 'KTV', '演唱会', '门票', '旅游', '酒店', '景点']],
  ['expense', '医疗', '💊', ['医院', '药', '看病', '挂号', '体检', '牙']],
  ['expense', '教育', '📚', ['书', '课程', '培训', '学费', '考试']],
  ['expense', '人情', '🎁', ['红包', '礼物', '份子钱', '请客', '随礼']],
  ['expense', '其他', '📦', []],
  ['income', '工资', '💼', ['工资', '薪水', '薪资']],
  ['income', '奖金', '🏆', ['奖金', '年终奖', '绩效']],
  ['income', '理财', '📈', ['利息', '分红', '理财', '收益', '股息']],
  ['income', '兼职', '🧑‍💻', ['兼职', '外快', '稿费', '副业']],
  ['income', '报销', '🧾', ['报销']],
  ['income', '退款', '↩️', ['退款', '退货', '返现']],
  ['income', '红包收入', '🧧', ['红包']],
  ['income', '其他收入', '💰', []],
];

export function createDefaultAccounts(): Account[] {
  return DEFAULT_ACCOUNTS.map(([name, kind]) => ({
    id: newId(),
    name,
    kind,
    initialBalance: 0,
    archived: false,
  }));
}

export function createDefaultCategories(): Category[] {
  return DEFAULT_CATEGORIES.map(([type, name, icon, keywords]) => ({
    id: newId(),
    name,
    type,
    icon,
    keywords,
    archived: false,
  }));
}

export function createDefaultVault(): VaultData {
  return {
    schemaVersion: 1,
    accounts: createDefaultAccounts(),
    categories: createDefaultCategories(),
    transactions: [],
    recurring: [],
    settings: { autoLockMinutes: 5 },
  };
}

/** Category used when nothing matches: prefers one named "其他…", else the first of that type. */
export function fallbackCategory(categories: Category[], type: TxType): Category | undefined {
  const active = categories.filter((c) => c.type === type && !c.archived);
  return active.find((c) => c.name.startsWith('其他')) ?? active[0];
}
