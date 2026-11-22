import 'data.dart';

/// Parent IDs determine topic membership. Notes are always leaf messages.
class NoteTree {
  final String root;
  final Map<String, Map<String, dynamic>> nodes = {};
  final Set<String> folders = {};
  int excluded = 0;
  NoteTree(
    List<Map<String, dynamic>> records,
    this.root, {
    Set<String> hiddenFolders = const {},
  }) {
    final counts = <String, int>{};
    for (final n in records) {
      final id = '${n['fileId']}';
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final children = <String, List<Map<String, dynamic>>>{};
    for (final n in records) {
      if (counts['${n['fileId']}'] != 1) {
        excluded++;
        continue;
      }
      children.putIfAbsent('${n['parentId']}', () => []).add(n);
    }
    folders.add(root);
    final queue = <(String, int)>[(root, 0)];
    for (var i = 0; i < queue.length; i++) {
      final (parent, depth) = queue[i];
      for (final n in children[parent] ?? <Map<String, dynamic>>[]) {
        final id = '${n['fileId']}', type = '${n['type']}';
        if (id == root || nodes.containsKey(id)) continue;
        // Do not traverse locally deleted topics, including new descendants
        // that the student creates after this installation hid the folder.
        if (hiddenFolders.contains(id)) continue;
        if (n['isRecycleBin'] == true ||
            n['isRecycleBin'] == 1 ||
            n['shared'] == true ||
            n['shared'] == 1) {
          excluded++;
          continue;
        }
        if (type != '0' && type != '12') continue;
        if (type == '0' &&
            (!(n['shared'] == false || n['shared'] == 0) || depth >= 64)) {
          excluded++;
          continue;
        }
        nodes[id] = n;
        if (type == '0') {
          folders.add(id);
          queue.add((id, depth + 1));
        }
      }
    }
  }
}

class TopicView {
  final List<Message> messages;
  late final Map<String, Message> folders = {
    for (final m in messages.where((m) => m.isTopic)) m.remoteId: m,
  };
  TopicView(this.messages);
  List<Message> children(String topic) =>
      messages.where((m) => m.topicId == topic).toList();
  List<String> path(String topic) {
    final result = <String>[], seen = <String>{};
    while (topic.isNotEmpty && seen.add(topic) && result.length < 64) {
      final m = folders[topic];
      if (m == null) break;
      result.insert(0, topic);
      topic = m.topicId;
    }
    return result;
  }

  int unreadBelow(String topic) {
    final scopes = <String>{topic};
    var more = true;
    while (more) {
      more = false;
      for (final m in folders.values) {
        if (scopes.contains(m.topicId) && scopes.add(m.remoteId)) more = true;
      }
    }
    return messages
        .where(
          (m) =>
              !m.deleted &&
              m.unread &&
              (scopes.contains(m.topicId) || m.remoteId == topic),
        )
        .length;
  }
}
