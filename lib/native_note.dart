import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'data.dart';
import 'protocol.dart';

/// Image-note layout from the supplied zy_upload.py. Binary references and
/// image filename must remain together; no borrowed ObjectBox database is used.
class NativeNote {
  static const page = 'a888b5fb-e65d-4611-a3af-1f80a0fb6ced';
  static const imageName =
      'B466246B6F67160E63431159941CD9A9screenCaptureb59d24b6-00fa-4f53-bc4f-1df255a5101a.webp';
  static const templatePaths = [
    'page_router.bin',
    '$page/059848e4-1971-47fb-9e47-517266cdef05_matrix.bin',
    '$page/a2b4fb47-3623-45be-9fe9-57fc62e66651_file.bin',
    '$page/e339e39b-64d9-4de0-bfaa-dace2a3f8e7d_command.bin',
    '$page/header.bin',
    '$page/router.bin',
    '$page/snapshot.bin',
  ];
  // 1.13.6 tablet probes: 32 hex IDs render both native and image notes.
  // Keep the old mapping only for recognizing already registered history.
  static String fileId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid letter identity');
    }
    return id;
  }

  static String legacyFileId(String id) => legacyNoteFileId(id);
  static String chinaDay(DateTime instant) {
    final d = instant.toUtc().add(const Duration(hours: 8));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  static Uri endpoint(Object? value) {
    final uri = Uri.tryParse('$value');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !RegExp(
          r'^ezy-[a-z0-9-]+\.oss-cn-[a-z0-9-]+\.aliyuncs\.com$',
        ).hasMatch(uri.host)) {
      throw const ApiFailure('上传地址不在已验证的存储范围');
    }
    return uri.replace(scheme: 'https', port: 443, path: '/');
  }

  static Future<Uint8List> render(Message message) async {
    // Exact canvas dimensions used by the working image-note template.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xfffffdf6), ui.BlendMode.src);
    void text(String value, double y, double size, {bool bold = false}) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textDirection: ui.TextDirection.ltr,
                fontSize: size,
                height: 1.6,
                fontFamily: 'sans-serif',
                locale: const ui.Locale('zh', 'CN'),
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xff243f34),
                fontWeight: bold ? ui.FontWeight.w600 : ui.FontWeight.normal,
              ),
            )
            ..addText(value);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 1640));
      canvas.drawParagraph(paragraph, ui.Offset(140, y));
      paragraph.dispose();
    }

    final who = message.role == 'dad' ? '爸爸' : '妈妈';
    final date = DateTime.fromMillisecondsSinceEpoch(
      message.time,
      isUtc: true,
    ).add(const Duration(hours: 8));
    text('家书 · 来自$who', 140, 76, bold: true);
    text(message.text, 390, 70);
    text(
      '${date.toIso8601String().substring(0, 16).replaceAll('T', ' ')}（北京时间）',
      1810,
      34,
    );
    text('可在本笔记续写，或在同一话题新建笔记；保存并同步。', 1930, 34);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1920, 2184);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const ApiFailure('无法生成笔记页面');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  final String uid, id, day, pageHash;
  final Map<String, Uint8List> blobs;
  NativeNote(this.uid, this.id, this.day, this.pageHash, this.blobs);
  static Future<NativeNote> prepare(
    String uid,
    Message message,
    DateTime now, {
    Uint8List? pageImage,
  }) async {
    return NativeNote(
      uid,
      fileId(message.id),
      chinaDay(now),
      '${message.time}',
      await pageBlobs(pageImage ?? await render(message)),
    );
  }

  static Future<Map<String, Uint8List>> pageBlobs(Uint8List png) async {
    final blobs = <String, Uint8List>{};
    for (final path in templatePaths) {
      final b = await rootBundle.load('assets/native_note/$path');
      blobs[path] = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
    }
    blobs['$page/screenshot.png'] = png;
    // Despite the fixed .webp name, the existing template accepts PNG bytes.
    blobs[imageName] = png;
    return blobs;
  }

  String get prefix => 'note_v2/res/$uid/$day/$id/';
  String get pageBase =>
      '/storage/emulated/0/Android/data/com.friday.cloudsnote/userNote/$uid/note/$id/$pageHash';
  String key(String path) => '$prefix$pageHash/$path';
  List<Map<String, Object>> resources(
    Uri root,
    DateTime instant, {
    String? pageName,
    int pageIndex = 0,
  }) {
    final base = pageName ?? pageBase;
    final stamp = instant
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('T', ' ');
    return blobs.entries
        .map(
          (entry) => <String, Object>{
            'id':
                '$base/${entry.key == imageName ? 'res/image/$imageName' : entry.key}',
            'fileId': id,
            'pageName': base,
            'pageIndex': pageIndex,
            'md5': md5.convert(entry.value).toString().toUpperCase(),
            'resourceType': entry.key == imageName
                ? 0
                : entry.key.endsWith('.png')
                ? 2
                : 1,
            'ossImageUrl': root.resolve(key(entry.key)).toString(),
            'createTimeStamp': stamp,
            'updateTimeStamp': stamp,
            'toBeUploaded': false,
            'wasDeleted': false,
          },
        )
        .toList();
  }

  Map<String, Object> tokenRequest(DateTime now) {
    final ts = now.millisecondsSinceEpoch;
    final sign = md5
        .convert(utf8.encode('$uid+note_v2+res+2++0+$id+$ts'))
        .toString()
        .toUpperCase();
    return {
      'fc': 1,
      'fr': 1,
      'ft': 2,
      'fe': '',
      'fo': '0',
      'nonce': id,
      'ts': ts,
      'sign': sign,
    };
  }

  Future<void> upload(
    http.Client client,
    Map sts, {
    Future<void> Function()? checkpoint,
  }) async {
    final root = endpoint(sts['endpoint']);
    final bucket = '${sts['bucket']}';
    if (root.host.split('.').first != bucket ||
        [
          'accessKeyId',
          'accessKeySecret',
          'securityToken',
        ].any((k) => sts[k] is! String || (sts[k] as String).isEmpty)) {
      throw const ApiFailure('临时上传凭据格式不正确');
    }
    for (final entry in blobs.entries) {
      await checkpoint?.call();
      final date = HttpDate.format(DateTime.now().toUtc());
      final type = entry.key.endsWith('.bin')
          ? 'application/octet-stream'
          : 'image/png';
      final canonical =
          'PUT\n\n$type\n$date\nx-oss-security-token:${sts['securityToken']}\n/$bucket/${key(entry.key)}';
      final signature = base64Encode(
        Hmac(
          sha1,
          utf8.encode(sts['accessKeySecret']),
        ).convert(utf8.encode(canonical)).bytes,
      );
      final request = http.Request('PUT', root.resolve(key(entry.key)))
        ..followRedirects = false
        ..headers.addAll({
          'Date': date,
          'Content-Type': type,
          'x-oss-security-token': sts['securityToken'],
          'Authorization': 'OSS ${sts['accessKeyId']}:$signature',
        })
        ..bodyBytes = entry.value;
      // Do not forward the school bearer token to object storage.
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw ApiFailure('笔记资源上传失败（HTTP ${response.statusCode}）');
      }
    }
  }
}
