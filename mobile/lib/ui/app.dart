import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../state/session.dart';
import 'auth_screens.dart';
import 'common.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

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
    final scheme = ColorScheme.fromSeed(seedColor: brandColor, dynamicSchemeVariant: DynamicSchemeVariant.fidelity);
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
          theme: ThemeData(
            colorScheme: scheme,
            scaffoldBackgroundColor: const Color(0xFFF3F3F3),
            cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
            inputDecorationTheme: const InputDecorationTheme(isDense: true),
          ),
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
            child: Padding(padding: const EdgeInsets.all(24), child: ErrorText('无法读取本地数据：${session.errorMessage}')),
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
  static const _titles = ['CipherPenny', '统计', '设置'];

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final created = session.recurringCreated;
    if (created > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已自动生成 $created 笔周期账单')));
        session.clearRecurringNotice();
      });
    }
    final sync = session.sync;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          if (sync != null)
            IconButton(
              tooltip: sync.syncing ? '正在同步' : (sync.error != null ? '同步失败' : '立即同步'),
              onPressed: sync.syncing ? null : session.syncNow,
              icon: sync.syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(sync.error != null ? Icons.sync_problem : Icons.cloud_done_outlined,
                      color: sync.error != null ? Theme.of(context).colorScheme.error : null),
            ),
          IconButton(tooltip: '锁定', icon: const Icon(Icons.lock_outline), onPressed: session.lock),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        HomeScreen(onOpenSettings: () => setState(() => _tab = 2)),
        const StatsScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '账单'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: '统计'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
