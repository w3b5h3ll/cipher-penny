import 'dart:io';

import 'package:cipher_penny/crypto/vault_crypto.dart';
import 'package:cipher_penny/state/session.dart';
import 'package:cipher_penny/storage/vault_store.dart';
import 'package:cipher_penny/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session work started from widget callbacks runs in the fake-async zone but also does real
/// file IO, so alternate real waits with pumps until it finishes.
Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  testWidgets('setup, quick add, stats, settings and lock render and work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 860));
    final dir = Directory.systemTemp.createTempSync('cipher_penny_ui');
    final session = Session(VaultStore(dir), iterations: minIterations);
    await tester.runAsync(session.init);
    await tester.pumpWidget(CipherPennyApp(session: session));
    await tester.pump();
    expect(find.text('设置主密码'), findsOneWidget);

    await tester.runAsync(() => session.create('pass-word-1'));
    await tester.pump();
    expect(find.text('这个月还没有账单'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '午饭 35，打车 28');
    await tester.pump();
    await tester.tap(find.text('识别'));
    await tester.pump();
    expect(find.text('保存 2 笔'), findsOneWidget);
    await tester.tap(find.text('保存 2 笔'));
    await tester.pump();
    expect(find.text('已保存 2 笔，共 ¥63.00'), findsOneWidget);
    expect(session.data.transactions, hasLength(2));

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按年'));
    await tester.pumpAndSettle();
    expect(find.text('月度趋势'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('开启同步'), findsOneWidget);

    await tester.tap(find.byTooltip('立即锁定'));
    await until(tester, () => session.status == SessionStatus.locked);
    expect(find.text('账本已锁定'), findsOneWidget);
    expect(File('${dir.path}/vault.json').readAsStringSync(), isNot(contains('午饭')));

    session.dispose();
    dir.deleteSync(recursive: true);
  });

  testWidgets('dark mode uses the dark tokens', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.binding.setSurfaceSize(const Size(400, 860));
    final dir = Directory.systemTemp.createTempSync('cipher_penny_ui');
    final session = Session(VaultStore(dir), iterations: minIterations);
    await tester.runAsync(session.init);
    await tester.runAsync(() => session.create('pass-word-1'));
    await tester.pumpWidget(CipherPennyApp(session: session));
    await tester.pump();

    final context = tester.element(find.text('这个月还没有账单'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xFF181818));
    expect(tester.takeException(), isNull);

    session.dispose();
    dir.deleteSync(recursive: true);
  });
}
