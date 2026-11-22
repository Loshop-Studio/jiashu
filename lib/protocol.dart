import 'dart:convert';
import 'package:encrypt/encrypt.dart' as aes;

/// Compatibility encoding from the supplied client. This is not authentication.
class NotesCodec {
  static const alphabet =
      ":F0wKU!Qg3}UkbW+w[:9|D3-5h=:T;7t#_GZ4#G;~ZNSq{8;}QIP>'{q.lje";
  static String key(DateTime instant) {
    final d = instant.toUtc().add(const Duration(hours: 8));
    final offset = (d.year * d.month * d.day) % 60;
    final rotated = alphabet.substring(offset) + alphabet.substring(0, offset);
    return String.fromCharCode(((d.day * d.month * 33 + 33) % 94) + 33) +
        rotated.substring(0, 14) +
        alphabet[d.day + d.month];
  }

  final DateTime instant;
  NotesCodec([DateTime? instant]) : instant = instant ?? DateTime.now();
  aes.Encrypter get cipher => aes.Encrypter(
    aes.AES(
      aes.Key.fromUtf8(key(instant)),
      mode: aes.AESMode.ecb,
      padding: 'PKCS7',
    ),
  );
  String encode(String text) => cipher.encrypt(text).base64;
  dynamic decode(String text) => jsonDecode(cipher.decrypt64(text));
}

class ApiFailure implements Exception {
  final String message;
  final bool auth;
  const ApiFailure(this.message, {this.auth = false});
  @override
  String toString() => message;
}

class LoginRequired extends ApiFailure {
  const LoginRequired(super.message) : super(auth: true);
}

dynamic unwrap(int status, dynamic envelope, {NotesCodec? codec}) {
  if (status == 401 || status == 403) {
    throw ApiFailure(status == 401 ? '登录已失效，请重新登录' : '该通路拒绝访问', auth: true);
  }
  if (status < 200 || status >= 300) throw ApiFailure('服务器返回 HTTP $status');
  if (envelope is! Map) throw const ApiFailure('服务器响应格式不正确');
  if (codec != null) {
    if (envelope['code'].toString() != '0') {
      throw ApiFailure('云笔记未接受请求（${envelope['code'] ?? '未知'}）');
    }
    final data = envelope['data'];
    return data is String && data.isNotEmpty ? codec.decode(data) : data;
  }
  if (envelope['success'] != true) {
    throw const ApiFailure('服务器未接受请求，请检查账号或稍后重试');
  }
  return envelope['result'];
}

String principalFromToken(String token) {
  try {
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final id =
        claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'];
    if (id == null || !RegExp(r'^\d+$').hasMatch('$id')) {
      throw const FormatException();
    }
    return '$id';
  } catch (_) {
    throw const ApiFailure('登录响应缺少学生身份');
  }
}

/// The server's fileId identifies a message; the visible title is just its byline and text.
String letterTitle(String role, String body) {
  if (!['dad', 'mom'].contains(role)) {
    throw const FormatException('Invalid letter identity');
  }
  if (body.trim().isEmpty ||
      body.runes.length > 60 ||
      body.contains(RegExp(r'[\r\n\x00-\x1f]'))) {
    throw const FormatException('请发送 1–60 字的单行短消息');
  }
  return '${role == 'dad' ? '爸爸' : '妈妈'}：$body';
}

String legacyNoteFileId(String id) =>
    'h${BigInt.parse(id, radix: 16).toRadixString(36).padLeft(32, '0')}';

({String? legacyId, String role, String body})? parseLetter(
  String title,
  String fileId, {
  bool topic = false,
}) {
  final match = RegExp(
    r'^(爸爸|妈妈)：(.+?)(?:【JS1:([a-f0-9]{32})】)?$',
  ).firstMatch(title);
  if (match == null) return null;
  final suffix = match[3];
  final legacy =
      suffix != null &&
      (suffix == fileId || (!topic && legacyNoteFileId(suffix) == fileId));
  if (!legacy && !RegExp(r'^[a-f0-9]{32}$').hasMatch(fileId)) return null;
  return (
    legacyId: legacy ? suffix : null,
    role: match[1] == '爸爸' ? 'dad' : 'mom',
    body: legacy ? match[2]! : title.substring(3),
  );
}

String safeError(Object error) =>
    error is ApiFailure || error is FormatException
    ? (error is FormatException ? error.message.toString() : error.toString())
    : '连接失败，请检查网络；发送结果会在下次同步核对';
