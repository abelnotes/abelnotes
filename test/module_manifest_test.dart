import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/modules/builtin_modules.dart';
import 'package:abelnotes/features/modules/module_manifest.dart';

Map<String, dynamic> valid() => {
      'id': 'org.example.stamps',
      'version': '0.2.0',
      'apiVersion': 1,
      'license': 'MIT',
      'name': {'en': 'Stamps', 'it': 'Timbri'},
      'permissions': ['selection.read', 'selection.write'],
      'assets': [
        {'path': 'models/stamps.ablm', 'sha256': 'a' * 64, 'license': 'CC-BY-4.0'},
      ],
      'contributes': {
        'selectionActions': ['org.example.stamps.apply'],
      },
    };

void main() {
  test('parses a valid manifest', () {
    final m = ModuleManifest.fromJson(valid());
    expect(m.id, 'org.example.stamps');
    expect(m.source, ModuleSource.external);
    expect(m.entitlement, ModuleEntitlement.free);
    expect(m.permissions, {ModulePermission.selectionRead, ModulePermission.selectionWrite});
    expect(m.assets.single.license, 'CC-BY-4.0');
    expect(m.selectionActions, ['org.example.stamps.apply']);
    expect(m.nameIn('it'), 'Timbri');
    expect(m.nameIn('de'), 'Stamps');
  });

  test('parses the entitlement without enforcing it', () {
    final j = valid()..['entitlement'] = 'supporter';
    expect(ModuleManifest.fromJson(j).entitlement, ModuleEntitlement.supporter);
  });

  void rejects(String why, void Function(Map<String, dynamic> j) mutate) {
    test('rejects $why', () {
      final j = valid();
      mutate(j);
      expect(() => ModuleManifest.fromJson(j), throwsFormatException);
    });
  }

  rejects('a bad id', (j) => j['id'] = 'Stamps');
  rejects('a single-segment id', (j) => j['id'] = 'stamps');
  rejects('an id in the reserved namespace', (j) {
    j['id'] = 'abelnotes.stamps';
    j['contributes'] = {'selectionActions': ['abelnotes.stamps.apply']};
  });
  rejects('a bad version', (j) => j['version'] = '1.0');
  rejects('a newer API', (j) => j['apiVersion'] = kModuleApiVersion + 1);
  rejects('an unknown permission', (j) => (j['permissions'] as List).add('fs.write'));
  rejects('a missing name', (j) => j.remove('name'));
  rejects('an unknown entitlement', (j) => j['entitlement'] = 'gold');
  rejects('a bad sha256', (j) => (j['assets'] as List).first['sha256'] = 'xyz');
  for (final path in ['../x', '/etc/passwd', 'a//b', 'a/./b', r'a\b', 'C:x', '']) {
    rejects('asset path "$path"', (j) => (j['assets'] as List).first['path'] = path);
  }
  rejects('actions without selection.write',
      (j) => j['permissions'] = ['selection.read']);
  rejects('an action id outside the module',
      (j) => j['contributes'] = {'selectionActions': ['org.other.apply']});
  rejects('a contribution kind this app has no extension point for',
      (j) => j['contributes'] = {'strokeRecognizers': ['org.example.stamps.star']});

  test('built-in manifests are internally consistent', () {
    final ids = <String>{};
    for (final m in builtinModules) {
      expect(ids.add(m.manifest.id), isTrue, reason: 'duplicate ${m.manifest.id}');
      expect(m.manifest.source, ModuleSource.builtin);
      expect(m.manifest.entitlement, ModuleEntitlement.free);
      expect(m.manifest.selectionActions, isNotEmpty, reason: '${m.manifest.id} contributes nothing');
      expect(m.manifest.permissions, contains(ModulePermission.selectionWrite));
      for (final a in m.manifest.selectionActions) {
        expect(a, startsWith('${m.manifest.id}.'));
      }
    }
  });
}
