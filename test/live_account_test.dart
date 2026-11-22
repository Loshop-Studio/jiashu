// Opt-in integration test. The session arrives only via the parent process's
// environment; no account credential or token is stored in this repository.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:jiashu/api.dart';
import 'package:jiashu/data.dart';
import 'package:jiashu/sync.dart';
import 'package:jiashu/native_note.dart';
import 'package:jiashu/protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = Platform.environment['JIASHU_LIVE_SESSION'];
  if (raw != null) {
    HttpOverrides.global = null; // Explicit opt-in real HTTP test.
  }
  test(
    'Authenticated topic tree holds two peer notes in a nested folder and verifies eighteen objects',
    () async {
      final state = jsonDecode(raw!);
      final context = state['context'];
      final s = Session(
        school: 'sxz',
        username: 'live-test',
        role: 'dad',
        base: state['baseUri'],
        token: state['accessToken'],
        client: '${state['clientCode'] ?? ''}',
        userId: '${context['platformUserId']}',
      );
      final folder = SyncEngine.newId();
      sqfliteFfiInit();
      if (Platform.isWindows) {
        open.overrideFor(
          OperatingSystem.windows,
          () => DynamicLibrary.open('winsqlite3.dll'),
        );
      }
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE messages(account TEXT,id TEXT,role TEXT,body TEXT,time INTEGER,status TEXT,source TEXT,version TEXT,unread INTEGER,images TEXT,PRIMARY KEY(account,id))',
      );
      await db.execute(
        'CREATE TABLE settings(account TEXT,k TEXT,v TEXT,PRIMARY KEY(account,k))',
      );
      final store = Store(db, s.account), api = SchoolApi(s);
      await Store.upgradeTopics(db);
      final created = <String>[];
      try {
        await api
            .allNotes(); // Validates the supplied account before any writes.
        created.add(folder);
        final rootName = '家书话题联调-${folder.substring(0, 6)}';
        await api.addFolder(folder, '0', rootName);
        final before = await api.allNotes();
        expect(
          before.any(
            (n) =>
                n['fileId'] == folder &&
                n['fileName'] == rootName &&
                n['shared'] == false,
          ),
          true,
        );
        await store.set('folder', folder);
        await store.set('folderVerified', '1');
        final engine = SyncEngine(
          s,
          store,
          apiFactory: (session) => SchoolApi(
            session,
            pageRenderer: (_) =>
                File('test/fixtures/native-page.png').readAsBytes(),
          ),
        );
        final topic = await engine.enqueue('家书话题联调，测试后清理', topic: true);
        created.add(topic);
        final branch = await engine.enqueue(
          '分支话题联调',
          topicId: topic,
          topic: true,
        );
        created.add(branch);
        final first = await engine.enqueue('同一话题里的第一条独立消息', topicId: branch);
        created.add(NativeNote.fileId(first));
        final second = await engine.enqueue('同一话题里的第二条独立消息', topicId: branch);
        created.add(NativeNote.fileId(second));
        final result = await engine.run(checkColumns: true);
        expect(result.status, '同步完成');
        final sent = await store.get(first);
        expect(sent!.status, 'synced');
        expect(result.incoming, 0);
        await engine.run();
        final after = await api.allNotes();
        expect(
          after
              .where(
                (n) =>
                    [
                      NativeNote.fileId(first),
                      NativeNote.fileId(second),
                    ].contains(n['fileId']) &&
                    n['parentId'] == branch &&
                    '${n['type']}' == '12',
              )
              .length,
          2,
        );
        expect(
          after.singleWhere((n) => n['fileId'] == topic)['parentId'],
          folder,
        );
        expect(
          after.singleWhere((n) => n['fileId'] == branch)['parentId'],
          topic,
        );
        expect((await store.get(first))!.topicId, branch);
        expect((await store.get(second))!.topicId, branch);
        for (final id in [
          NativeNote.fileId(first),
          NativeNote.fileId(second),
        ]) {
          expect(id, matches(RegExp(r'^[a-f0-9]{32}$')));
          expect(
            Uri.parse(
              '${after.singleWhere((n) => n['fileId'] == id)['fileUrl']}',
            ).scheme,
            'http',
          );
          expect(
            int.parse(
              '${after.singleWhere((n) => n['fileId'] == id)['version']}',
            ),
            greaterThanOrEqualTo(1),
          );
          final d = await api.call(
            '/CloudNotes/api/Resources/GetByFileId?${NotesCodec().encode('fileId=$id')}',
            notes: true,
          );
          expect('${d['userId']}', s.userId);
          final resources = d['resourceList'] as List;
          expect(resources.length, 9);
          final download = http.Client();
          try {
            for (final r in resources) {
              expect('${r['fileId']}', id);
              expect('${r['userId']}', s.userId);
              final uri = Uri.parse(r['ossImageUrl']);
              expect(uri.scheme, 'http');
              NativeNote.endpoint(uri.replace(path: '').toString());
              final response = await download
                  .get(uri.replace(scheme: 'https'))
                  .timeout(const Duration(seconds: 25));
              expect(response.statusCode, 200);
              expect(
                md5.convert(response.bodyBytes).toString().toUpperCase(),
                '${r['md5']}'.toUpperCase(),
              );
            }
          } finally {
            download.close();
          }
        }
      } finally {
        // Leaf-first deletion is confined to newly generated IDs in our private test folder.
        for (final id in created.reversed) {
          await api.call(
            '/CloudNotes/api/Notes/Delete',
            body: [id],
            notes: true,
          );
          final cleaned = await api.allNotes();
          expect(
            cleaned.any((n) => n['fileId'] == id),
            false,
            reason: 'Isolated test message must be removed',
          );
        }
        api.close();
        await db.close();
      }
    },
    skip: raw == null
        ? 'Requires explicitly supplied local test session'
        : false,
  );
}
