import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'state/session.dart';
import 'storage/vault_store.dart';
import 'ui/app.dart';

// cryptography_flutter registers itself, so PBKDF2 / AES-GCM run natively on Android (spec A-5).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
  });
  final session = Session(VaultStore(await getApplicationSupportDirectory()));
  runApp(CipherPennyApp(session: session));
  await session.init();
}
