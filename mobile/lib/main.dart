import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'state/session.dart';
import 'storage/vault_store.dart';
import 'ui/app.dart';

// cryptography_flutter registers itself, so PBKDF2 / AES-GCM run natively on Android (spec A-5).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session(VaultStore(await getApplicationSupportDirectory()));
  runApp(CipherPennyApp(session: session));
  await session.init();
}
