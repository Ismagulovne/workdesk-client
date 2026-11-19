// WorkDesk+Claude: соединение телефона с релеем workdesk.kz (протокол: console/docs/CLAUDE_RELAY.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_model.dart';

class ClaudeAgent {
  final String device;
  final String hostname;
  final String os;
  final String claudeVersion;
  final bool claudeLoggedIn;
  final String cwd;

  ClaudeAgent.fromJson(Map<String, dynamic> j)
      : device = '${j['device'] ?? ''}',
        hostname = '${j['hostname'] ?? ''}',
        os = '${j['os'] ?? ''}',
        claudeVersion = '${j['claude_version'] ?? ''}',
        claudeLoggedIn = j['claude_logged_in'] == true,
        cwd = '${j['cwd'] ?? ''}';

  String get title => hostname.isEmpty ? device : hostname;
}

/// Одно соединение на приложение; сеансы различаются по sid.
class ClaudeRelay extends ChangeNotifier {
  ClaudeRelay._();
  static final ClaudeRelay instance = ClaudeRelay._();

  WebSocket? _ws;
  bool connecting = false;
  String error = '';
  List<ClaudeAgent> agents = [];
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _retry;
  bool _wanted = false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  bool get connected => _ws != null;

  static Future<Uri?> _url() async {
    final api = (await bind.mainGetApiServer()).trim();
    if (api.isEmpty) return null;
    final base = Uri.parse(api.endsWith('/') ? api.substring(0, api.length - 1) : api);
    return base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: '${base.path}/api/claude/ws',
      queryParameters: {'role': 'phone'},
    );
  }

  Future<void> connect() async {
    _wanted = true;
    if (_ws != null || connecting) return;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token.isEmpty) {
      error = 'Войдите в учетную запись WorkDesk';
      notifyListeners();
      return;
    }
    final url = await _url();
    if (url == null) {
      error = 'Не задан сервер WorkDesk';
      notifyListeners();
      return;
    }
    connecting = true;
    error = '';
    notifyListeners();
    try {
      final ws = await WebSocket.connect(url.toString(), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      ws.listen(_onData, onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
    } catch (e) {
      error = e is WebSocketException && '$e'.contains('401')
          ? 'Сеанс WorkDesk истек, войдите заново'
          : 'Нет связи с сервером WorkDesk';
      _scheduleRetry();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _wanted = false;
    _retry?.cancel();
    _ws?.close();
    _ws = null;
    agents = [];
    notifyListeners();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (_wanted) _retry = Timer(const Duration(seconds: 5), connect);
  }

  void _onDone() {
    _ws = null;
    agents = [];
    _messages.add({'t': 'disconnected'});
    notifyListeners();
    _scheduleRetry();
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['t'] == 'agents') {
      agents = ((m['items'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ClaudeAgent.fromJson)
          .toList();
      notifyListeners();
    }
    _messages.add(m);
  }

  void send(Map<String, dynamic> m) => _ws?.add(jsonEncode(m));

  /// Открывает сеанс и возвращает его sid (из ответа агента `opened`).
  Future<String> open(String device, String mode,
      {String permission = 'default', String cwd = '', String resume = '', int cols = 80, int rows = 24}) async {
    final first = messages.firstWhere((m) => m['t'] == 'opened' || m['t'] == 'error' || m['t'] == 'exit')
        .timeout(const Duration(seconds: 20));
    send({'t': 'open', 'device': device, 'mode': mode, 'permission': permission, 'cwd': cwd, 'resume': resume, 'cols': cols, 'rows': rows});
    final m = await first;
    if (m['t'] != 'opened') throw '${m['message'] ?? m['error'] ?? 'Не удалось открыть сеанс'}';
    return '${m['sid']}';
  }
}
