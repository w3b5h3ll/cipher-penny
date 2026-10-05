import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../state/session.dart';
import 'auth_screens.dart';
import 'common.dart';
import 'home_screen.dart';
import 'recurring_screens.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';

class CipherPennyApp extends StatefulWidget {
  const CipherPennyApp({super.key, required this.session});
  final Session session;
  @override
  State<CipherPennyApp> createState() => _CipherPennyAppState();
}

class _CipherPennyAppState extends State<CipherPennyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  SessionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: widget.session.onBackground, onShow: widget.session.onForeground);
    widget.session.addListener(_onSession);
  }

  /// Pops pushed screens (e.g. the editor) when the vault locks, so no plaintext stays on screen.
  void _onSession() {
    final status = widget.session.status;
    if (status != _lastStatus && status != SessionStatus.unlocked) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    _lastStatus = status;
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.session.touch(),
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'CipherPenny',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Td.light, Brightness.light),
          darkTheme: buildTheme(Td.dark, Brightness.dark),
          themeMode: ThemeMode.system,
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return switch (session.status) {
      SessionStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      SessionStatus.error => Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: ErrorText('无法读取本地数据：${session.errorMessage}', small: false)),
          ),
        ),
      SessionStatus.empty => const SetupScreen(),
      SessionStatus.locked => const UnlockScreen(),
      SessionStatus.unlocked => const _MainShell(),
    };
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _tab = 0;
  static const _tabs = ['账单', '统计', '周期', '设置'];
  static const _settingsTab = 3;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    final session = SessionScope.of(context);
    final sync = session.sync;
    final banners = [
      if (session.saveError != null) TdBanner(error: true, child: Text('保存失败：${session.saveError}')),
      if (session.recurringCreated > 0)
        TdBanner(
          action: TextButton(onPressed: session.clearRecurringNotice, child: const Text('知道了')),
          child: Text('已自动记入 ${session.recurringCreated} 笔周期账单。'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: SizedBox(
          height: 56,
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            return Row(children: [
              GestureDetector(
                onTap: () => setState(() => _tab = 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const AppLogo(),
                  if (!narrow) ...[const SizedBox(width: 8), Text('CipherPenny', style: TdText.titleMedium.copyWith(color: td.textPrimary))],
                ]),
              ),
              SizedBox(width: narrow ? 8 : 16),
              Expanded(
                child: Row(children: [
                  for (final (i, label) in _tabs.indexed)
                    _NavTab(label: label, active: _tab == i, compact: narrow, onTap: () => setState(() => _tab = i)),
                ]),
              ),
              if (sync != null && sync.error != null) ...[
                _SyncAlert(message: sync.error!, onTap: () => setState(() => _tab = _settingsTab)),
                const SizedBox(width: 8),
              ],
            ]);
          }),
        ),
        actions: [
          IconBtn('🔒', tooltip: '立即锁定', bordered: false, onPressed: session.lock),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        if (banners.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Gap(gap: 8, children: banners)),
        Expanded(
          child: IndexedStack(index: _tab, children: const [HomeScreen(), StatsScreen(), RecurringScreen(), SettingsScreen()]),
        ),
      ]),
    );
  }
}

/// `.topbar nav a`
class _NavTab extends StatelessWidget {
  const _NavTab({required this.label, required this.active, required this.compact, required this.onTap});
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Semantics(
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(width: 2, color: active ? td.brand : Colors.transparent)),
          ),
          child: Text(
            label,
            style: TdText.body.copyWith(
              color: active ? td.brand : td.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.topbar .sync-alert`
class _SyncAlert extends StatelessWidget {
  const _SyncAlert({required this.message, required this.onTap});
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final td = Td.of(context);
    return Tooltip(
      message: message,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 24),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: td.errorLight,
            border: Border.all(color: td.error),
            borderRadius: BorderRadius.circular(Td.radiusDefault),
          ),
          child: Text('同步失败', style: TdText.mark.copyWith(color: td.error)),
        ),
      ),
    );
  }
}
