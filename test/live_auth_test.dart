// Opt-in: one normal login and read-only requests; no credentials in source/logs.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:jiashu/api.dart';
import 'package:jiashu/auth.dart';
import 'package:jiashu/data.dart';
import 'auth_test.dart' show MemoryCredentials;

void main() {
  final raw = Platform.environment['JIASHU_LIVE_SESSION'];
  final password = Platform.environment['JIASHU_LIVE_PASSWORD'];
  test(
    'Real 401 recovers by one normal login and resumes read-only cloud notes access',
    () async {
      final state = jsonDecode(raw!);
      final initial = Session(
        school: 'sxz',
        username: Platform.environment['JIASHU_LIVE_USER']!,
        role: 'dad',
        base: state['baseUri'],
        token: 'expired-session-test',
        client: '',
        userId: '${state['context']['platformUserId']}',
        loginId: 'live-auth-test',
      );
      final vault = MemoryCredentials(SavedLogin(initial, password!, true));
      sqfliteFfiInit();
      if (Platform.isWindows) {
        open.overrideFor(
          OperatingSystem.windows,
          () => DynamicLibrary.open('winsqlite3.dll'),
        );
      }
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE settings(account TEXT,k TEXT,v TEXT,PRIMARY KEY(account,k))',
      );
      var logins = 0;
      final auth = AuthCoordinator(
        initial,
        Store(db, initial.account),
        credentials: vault,
        login: (school, user, pass, role, allowHttp) {
          logins++;
          return SchoolApi.login(school, user, pass, role, allowHttp);
        },
      );
      final api = SchoolApi(
        initial,
        authorize: auth.authorize,
        onLoginRejected: auth.rejectedAfterLogin,
      );
      try {
        await api
            .allNotes(); // Deliberately invalid initial token must receive 401.
        await api
            .allNotes(); // The second call must reuse the newly saved session.
        expect(logins, 1);
        expect(vault.saved!.session.account == initial.account, true);
        expect(
          AuthCoordinator.expiresAt(
            vault.saved!.session.token,
          )!.isAfter(DateTime.now()),
          true,
        );
        expect(
          jsonEncode(await db.query('settings')).contains(password),
          false,
        );
      } finally {
        api.close();
        await db.close();
      }
    },
    skip: raw == null || password == null
        ? 'Requires explicit local password/session injection'
        : false,
  );
}
