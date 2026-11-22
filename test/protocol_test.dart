import 'package:flutter_test/flutter_test.dart';
import 'package:jiashu/protocol.dart';

void main() {
  test('AES matches independent .NET client-compatible vector', () {
    final codec = NotesCodec(DateTime.utc(2026, 11, 17, 4));
    expect(
      codec.encode('{"hello":"家书"}'),
      '+XEkh506/b4v+cxrcLp7pu2h4SH844tG/cIGLQKv3K0=',
    );
    expect(codec.decode('+XEkh506/b4v+cxrcLp7pu2h4SH844tG/cIGLQKv3K0='), {
      'hello': '家书',
    });
  });
  test('China calendar boundary is independent of phone timezone', () {
    expect(
      NotesCodec.key(DateTime.parse('2026-11-16T16:01:00Z')),
      NotesCodec.key(DateTime.parse('2026-11-17T00:01:00+08:00')),
    );
    expect(
      NotesCodec.key(DateTime.parse('2026-11-16T15:59:00Z')),
      isNot(NotesCodec.key(DateTime.parse('2026-11-16T16:01:00Z'))),
    );
  });
  test('HTTP 200 business failure is not success', () {
    expect(
      () => unwrap(200, {'success': false, 'result': {}}),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => unwrap(200, {'code': 1001, 'data': null}, codec: NotesCodec()),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => unwrap(403, {'success': true, 'result': {}}),
      throwsA(isA<ApiFailure>().having((e) => e.auth, 'auth', true)),
    );
  });
  test('Message identity survives Chinese and emoji', () {
    const id = '0123456789abcdef0123456789abcdef';
    final title = letterTitle('mom', '今天怎么样？🌷');
    expect(title, '妈妈：今天怎么样？🌷');
    expect(parseLetter(title, id), (
      legacyId: null,
      role: 'mom',
      body: '今天怎么样？🌷',
    ));
    expect(parseLetter('$title【JS1:$id】', id), (
      legacyId: id,
      role: 'mom',
      body: '今天怎么样？🌷',
    ));
    expect(parseLetter('孩子的回信', id), isNull);
    expect(() => letterTitle('dad', '字' * 61), throwsFormatException);
    expect(() => letterTitle('dad', 'a\nb'), throwsFormatException);
    expect(() => letterTitle('admin', '你好'), throwsFormatException);
  });
  test('Malformed tokens fail without exposing token', () {
    expect(
      () => principalFromToken('private-bad-token'),
      throwsA(isA<ApiFailure>()),
    );
    expect(safeError(Exception('secret token')), isNot(contains('secret')));
  });
}
