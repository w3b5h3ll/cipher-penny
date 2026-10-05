import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/stats.dart';
import '../state/session.dart';
import 'theme.dart';

// Widgets mirroring the web app's CSS classes (src/styles.css) and src/ui/components.

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  /// Rebuilds the caller whenever the session changes.
  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// For callbacks; does not subscribe.
  static Session read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<SessionScope>()!.widget as SessionScope).notifier!;
}

String describeError(Object err) => err.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');

class Lookups {
  Lookups(VaultData data)
      : _categories = {for (final c in data.categories) c.id: c},
        _accounts = {for (final a in data.accounts) a.id: a},
        activeAccounts = [for (final a in data.accounts) if (!a.archived) a];

  final Map<String, Category> _categories;
  final Map<String, Account> _accounts;
  final List<Account> activeAccounts;

  Category? category(String id) => _categories[id];
  Account? account(String id) => _accounts[id];
}

Future<bool> confirm(BuildContext context, String message, {String action = '确定', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        danger
            ? OutlinedButton(onPressed: () => Navigator.pop(context, true), style: dangerButton(context), child: Text(action))
            : FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// `.danger` button: error-coloured outline.
ButtonStyle dangerButton(BuildContext context) {
  final td = Td.of(context);
  return OutlinedButton.styleFrom(
    foregroundColor: td.error,
    side: BorderSide(color: td.error),
  );
}

/// `.stack`: a column with a fixed gap.
class Gap extends StatelessWidget {
  const Gap({super.key, required this.children, this.gap = 12, this.crossAxisAlignment = CrossAxisAlignment.stretch});
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }
}

/// `.card`
class TdCard extends StatelessWidget {
  const TdCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.shadow = false});
  final Widget child;
  final EdgeInsets padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: td.bgContainer,
        border: Border.all(color: td.stroke),
        borderRadius: BorderRadius.circular(Td.radiusMedium),
        boxShadow: shadow ? td.shadow1 : null,
      ),
      child: child,
    );
  }
}

/// `.card.stack` with an `<h2>` title.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TdCard(
      child: Gap(children: [
        if (title != null) Text(title!, style: TdText.titleMedium),
        ...children,
      ]),
    );
  }
}

/// `Field`: label above the control, optional hint below.
class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.child, this.hint, this.hintIsError = false});
  final String label;
  final Widget child;
  final String? hint;
  final bool hintIsError;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Gap(gap: 4, children: [
      Text(label, style: TdText.body.copyWith(color: td.textSecondary)),
      child,
      if (hint != null) Text(hint!, style: TdText.mark.copyWith(color: hintIsError ? td.error : td.textPlaceholder)),
    ]);
  }
}

/// `.muted` (secondary text); `small` adds the `.small` size.
class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.small = false, this.textAlign});
  final String text;
  final bool small;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: textAlign, style: (small ? TdText.mark : TdText.body).copyWith(color: Td.of(context).textSecondary));
}

/// `.error`
class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key, this.small = true});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Text(text, style: (small ? TdText.mark : TdText.body).copyWith(color: Td.of(context).error));
}

/// `<code>`
class Code extends StatelessWidget {
  const Code(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: td.bgSecondaryContainer, borderRadius: BorderRadius.circular(Td.radiusDefault)),
      child: Text(text, style: TdText.mono.copyWith(color: td.textPrimary)),
    );
  }
}

/// `.bullets` list of muted small lines.
class Bullets extends StatelessWidget {
  const Bullets(this.items, {super.key});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final style = TdText.mark.copyWith(color: Td.of(context).textSecondary);
    return Gap(gap: 4, children: [
      for (final item in items)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 18, child: Text('•', style: style)),
          Expanded(child: DefaultTextStyle.merge(style: style, child: item)),
        ]),
    ]);
  }
}

/// `.banner` / `.banner.error` / `.notice`
class TdBanner extends StatelessWidget {
  const TdBanner({super.key, required this.child, this.error = false, this.action, this.onTap});
  final Widget child;
  final bool error;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: error ? td.errorLight : td.brandLight,
          borderRadius: BorderRadius.circular(Td.radiusMedium),
        ),
        child: Row(children: [
          Expanded(child: DefaultTextStyle.merge(style: TdText.body.copyWith(color: error ? td.error : td.textPrimary), child: child)),
          ?action,
        ]),
      ),
    );
  }
}

/// `.badge`
class TdBadge extends StatelessWidget {
  const TdBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: td.brandLight, borderRadius: BorderRadius.circular(Td.radiusDefault)),
      child: Text(text, style: TdText.mark.copyWith(color: td.brand)),
    );
  }
}

/// `.icon-btn`: a bordered button with a text glyph (‹ › ✕).
class IconBtn extends StatelessWidget {
  const IconBtn(this.glyph, {super.key, required this.tooltip, required this.onPressed, this.bordered = true});
  final String glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(Td.compSize, Td.compSize),
        side: bordered ? null : BorderSide.none,
        backgroundColor: bordered ? null : Colors.transparent,
      ),
      child: Text(glyph, style: const TextStyle(fontSize: 16, height: 1)),
    );
    return Tooltip(message: tooltip, child: Semantics(label: tooltip, button: true, excludeSemantics: true, child: button));
  }
}

class _Switcher extends StatelessWidget {
  const _Switcher({required this.label, required this.prevTooltip, required this.nextTooltip, required this.onPrev, required this.onNext});
  final String label;
  final String prevTooltip;
  final String nextTooltip;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconBtn('‹', tooltip: prevTooltip, onPressed: onPrev),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: Text(label, textAlign: TextAlign.center, style: TdText.titleSmall),
      ),
      const SizedBox(width: 4),
      IconBtn('›', tooltip: nextTooltip, onPressed: onNext),
    ]);
  }
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});
  final MonthKey month;
  final ValueChanged<MonthKey> onChanged;

  @override
  Widget build(BuildContext context) => _Switcher(
        label: formatMonthKey(month),
        prevTooltip: '上个月',
        nextTooltip: '下个月',
        onPrev: () => onChanged(addMonthsToKey(month, -1)),
        onNext: () => onChanged(addMonthsToKey(month, 1)),
      );
}

class YearSwitcher extends StatelessWidget {
  const YearSwitcher({super.key, required this.year, required this.onChanged});
  final int year;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _Switcher(
        label: '$year年',
        prevTooltip: '上一年',
        nextTooltip: '下一年',
        onPrev: () => onChanged(year - 1),
        onNext: () => onChanged(year + 1),
      );
}

/// `.segmented`
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: td.bgComponent, borderRadius: BorderRadius.circular(Td.radiusMedium)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final MapEntry(key: option, value: label) in options.entries)
          Padding(
            padding: EdgeInsets.only(left: option == options.keys.first ? 0 : 2),
            child: Semantics(
              selected: option == value,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: Container(
                  height: Td.compSize - 4,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == value ? td.bgContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(Td.radiusDefault),
                  ),
                  child: Text(
                    label,
                    style: option == value
                        ? TdText.titleSmall.copyWith(color: td.textPrimary)
                        : TdText.body.copyWith(color: td.textSecondary),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// `SummaryBar`: total, count and a per-day/per-month average; `periods` is 0 for periods that haven't started.
class SummaryBar extends StatelessWidget {
  const SummaryBar({super.key, required this.spending, required this.periods, required this.averageLabel});
  final Spending spending;
  final int periods;
  final String averageLabel;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final average = periods > 0 ? (spending.total / periods).round() : null;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: TdCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TdText.mark.copyWith(color: td.textSecondary)),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TdText.titleMedium.copyWith(color: color ?? td.textPrimary, fontFeatures: TdText.tabular),
              ),
            ]),
          ),
        );
    return Row(children: [
      cell('支出', formatMoney(spending.total), color: td.expense),
      const SizedBox(width: 8),
      cell('笔数', '${spending.count}'),
      const SizedBox(width: 8),
      cell(averageLabel, average == null ? '—' : formatMoney(average)),
    ]);
  }
}

/// Native `<select>` look: an outlined dropdown.
class _Select<T> extends StatelessWidget {
  const _Select({required this.value, required this.items, required this.onChanged, required this.semanticLabel});
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Semantics(
      label: semanticLabel,
      child: DropdownButtonFormField<T>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        isDense: true,
        style: TdText.body.copyWith(color: td.textPrimary),
        dropdownColor: td.bgContainer,
        borderRadius: BorderRadius.circular(Td.radiusMedium),
        icon: Text('▾', style: TextStyle(color: td.textSecondary)),
        items: items,
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({super.key, required this.categories, required this.value, required this.onChanged});
  final List<Category> categories;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [for (final c in categories) if (c.type == expense && (!c.archived || c.id == value)) c];
    return _Select<String>(
      semanticLabel: '分类',
      value: options.any((c) => c.id == value) ? value : null,
      items: [
        for (final c in options) DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

class AccountDropdown extends StatelessWidget {
  const AccountDropdown({super.key, required this.accounts, required this.value, required this.onChanged});
  final List<Account> accounts;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [for (final a in accounts) if (!a.archived || a.id == value) a];
    return _Select<String>(
      semanticLabel: '账户',
      value: options.any((a) => a.id == value) ? value : null,
      items: [for (final a in options) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

class OptionSelect<T> extends StatelessWidget {
  const OptionSelect({super.key, required this.value, required this.options, required this.onChanged, required this.semanticLabel});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => _Select<T>(
        semanticLabel: semanticLabel,
        value: value,
        items: [for (final MapEntry(:key, :value) in options.entries) DropdownMenuItem(value: key, child: Text(value))],
        onChanged: onChanged,
      );
}

/// `<input type="date">`
/// `onClear` makes the date optional: an empty field shows a placeholder and a set one gets ✕.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.semanticLabel = '日期', this.min, this.onClear});
  final ISODate? value;
  final ValueChanged<ISODate> onChanged;
  final String semanticLabel;
  final ISODate? min;
  final VoidCallback? onClear;

  DateTime _toDateTime(ISODate iso) {
    final (:year, :month, :day) = parseISODate(iso);
    return DateTime(year, month, day);
  }

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final value = this.value;
    final min = this.min;
    final first = min != null ? _toDateTime(min) : DateTime(2000);
    var initial = value != null ? _toDateTime(value) : DateTime.now();
    if (initial.isBefore(first)) initial = first;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: DateTime(2100));
          if (picked != null) onChanged(toISODate(picked.year, picked.month, picked.day));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: value != null && onClear != null ? IconBtn('✕', tooltip: '清除$semanticLabel', bordered: false, onPressed: onClear) : null,
            suffixIconConstraints: const BoxConstraints(minHeight: 32),
          ),
          child: value != null
              ? Text(value, style: TdText.body.copyWith(fontFeatures: TdText.tabular))
              : Text('未设置', style: TdText.body.copyWith(color: td.textPlaceholder)),
        ),
      ),
    );
  }
}

/// Plain text input with the web's look; `label` only feeds accessibility.
class TdInput extends StatelessWidget {
  const TdInput({
    super.key,
    required this.controller,
    this.hint,
    this.semanticLabel,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.style,
    this.minLines,
    this.maxLines = 1,
    this.invalid = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? hint;
  final String? semanticLabel;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final bool invalid;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Semantics(
      label: semanticLabel,
      textField: true,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        autocorrect: !obscure && keyboardType != TextInputType.url,
        enableSuggestions: !obscure && keyboardType != TextInputType.url,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: obscure ? 1 : maxLines,
        textInputAction: textInputAction,
        style: (style ?? TdText.body).copyWith(color: td.textPrimary),
        cursorColor: td.brand,
        decoration: InputDecoration(
          hintText: hint,
          enabledBorder: invalid
              ? OutlineInputBorder(borderRadius: BorderRadius.circular(Td.radiusDefault), borderSide: BorderSide(color: td.error))
              : null,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      ),
    );
  }
}

/// App logo (public/icon.svg rendered to PNG).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset('assets/images/icon.png', width: size, height: size);
}

/// Top bar of pushed screens: ‹ back and the logo; the card below carries the heading.
PreferredSizeWidget subPageBar(BuildContext context) => AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      title: Row(children: [
        IconBtn('‹', tooltip: '返回', bordered: false, onPressed: Navigator.of(context).pop),
        const SizedBox(width: 4),
        const AppLogo(),
      ]),
    );

/// `.small-btn`
class SmallButton extends StatelessWidget {
  const SmallButton(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 24),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: TdText.mark,
        ),
        child: Text(label),
      );
}

/// `.tx-row`; `dimmed` is `.rule.paused`.
class TxRow extends StatelessWidget {
  const TxRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
    this.badge,
    this.dimmed = false,
  });
  final String icon;
  final String title;
  final String? badge;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final opacity = dimmed ? 0.55 : 1.0;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: td.bgSecondaryContainer, borderRadius: BorderRadius.circular(Td.radiusMedium)),
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: opacity,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(title, overflow: TextOverflow.ellipsis, style: TdText.body.copyWith(fontWeight: FontWeight.w500)),
                    ),
                    if (badge != null) ...[const SizedBox(width: 6), TdBadge(badge!)],
                  ]),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TdText.mark.copyWith(color: td.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Opacity(
              opacity: opacity,
              child: Text(amount, style: TdText.body.copyWith(fontWeight: FontWeight.w600, fontFeatures: TdText.tabular)),
            ),
          ]),
        ),
      ),
    );
  }
}
