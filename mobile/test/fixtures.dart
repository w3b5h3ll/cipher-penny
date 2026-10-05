import 'dart:convert';
import 'dart:io';

/// Loads a shared, language-neutral test vector from the repo's `fixtures/` directory.
Map<String, Object?> loadFixture(String name) {
  final file = File('../fixtures/$name');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}
