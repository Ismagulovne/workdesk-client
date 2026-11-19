// WorkDesk+Claude: вкладка «Claude» — компьютеры с агентом, чат с Claude Code и терминал.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../common/widgets/login.dart';
import '../../models/claude_model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

const _permissionTitles = {
  'default': 'Спрашивать перед действиями',
  'acceptEdits': 'Разрешить правку файлов',
  'plan': 'Только чтение и план',
};

class ClaudePage extends StatefulWidget implements PageShape {
  @override
  final title = 'Claude';
  @override
  final icon = const Icon(Icons.auto_awesome);
  @override
  final appBarActions = <Widget>[];

  ClaudePage({Key? key}) : super(key: key);

  @override
  State<ClaudePage> createState() => _ClaudePageState();
}

class _ClaudePageState extends State<ClaudePage> {
  final relay = ClaudeRelay.instance;

  @override
  void initState() {
    super.initState();
    relay.addListener(_changed);
    relay.connect();
  }

  @override
  void dispose() {
    relay.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _login() async {
    if (await loginDialog() == true) {
      relay.disconnect();
      relay.connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bind.mainGetLocalOption(key: 'access_token').isEmpty) {
      return _hint(Icons.person, 'Войдите в учетную запись WorkDesk, чтобы работать с Claude на своих компьютерах.',
          action: ElevatedButton(onPressed: _login, child: const Text('Войти')));
    }
    if (!relay.connected) {
      return _hint(Icons.cloud_off, relay.connecting ? 'Подключение к серверу…' : relay.error,
          action: relay.connecting ? const CircularProgressIndicator() : TextButton(onPressed: relay.connect, child: const Text('Повторить')));
    }
    if (relay.agents.isEmpty) {
      return _hint(Icons.computer,
          'Нет компьютеров в сети.\n\nНа компьютере: установите Claude Code и войдите в него своим аккаунтом, '
          'затем запустите агент WorkDesk+Claude:\nworkdesk-claude login\nworkdesk-claude run');
    }
    return RefreshIndicator(
      onRefresh: () async => relay.send({'t': 'list'}),
      child: ListView(
        children: relay.agents.map((a) {
          final ready = a.claudeVersion.isNotEmpty;
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ListTile(
              leading: const Icon(Icons.computer, size: 36),
              title: Text(a.title),
              subtitle: Text([
                'ID ${a.device} · ${a.os}',
                ready ? 'Claude Code ${a.claudeVersion}${a.claudeLoggedIn ? '' : ' — проверьте вход в Claude'}' : 'Claude Code не установлен',
              ].join('\n')),
              isThreeLine: true,
              enabled: ready,
              onTap: () => _choose(a),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _hint(IconData icon, String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 16),
            SelectableText(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action],
          ]),
        ),
      );

  void _choose(ClaudeAgent a) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold))),
          ..._permissionTitles.entries.map((e) => ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('Чат с Claude'),
                subtitle: Text(e.value),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ClaudeChatPage(agent: a, permission: e.key)));
                },
              )),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Терминал Claude Code'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ClaudeTerminalPage(agent: a)));
            },
          ),
        ]),
      ),
    );
  }
}

// ---------- Чат ----------

class _Item {
  final String kind; // user | text | tool | result | error | info
  final String text;
  _Item(this.kind, this.text);
}

class ClaudeChatPage extends StatefulWidget {
  final ClaudeAgent agent;
  final String permission;
  const ClaudeChatPage({Key? key, required this.agent, required this.permission}) : super(key: key);

  @override
  State<ClaudeChatPage> createState() => _ClaudeChatPageState();
}

class _ClaudeChatPageState extends State<ClaudeChatPage> {
  final relay = ClaudeRelay.instance;
  final input = TextEditingController();
  final scroll = ScrollController();
  final items = <_Item>[];
  StreamSubscription? sub;
  String? sid;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    sub = relay.messages.listen(_onMessage);
    _open();
  }

  Future<void> _open() async {
    try {
      sid = await relay.open(widget.agent.device, 'chat', permission: widget.permission, cwd: widget.agent.cwd);
      _add(_Item('info', 'Папка: ${widget.agent.cwd}\n${_permissionTitles[widget.permission]}'));
    } catch (e) {
      _add(_Item('error', '$e'));
    }
  }

  @override
  void dispose() {
    if (sid != null) relay.send({'t': 'close', 'sid': sid});
    sub?.cancel();
    super.dispose();
  }

  void _add(_Item i) {
    if (!mounted) return;
    setState(() => items.add(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['t'] == 'disconnected') {
      setState(() => busy = false);
      return _add(_Item('error', 'Связь с сервером потеряна'));
    }
    if (m['sid'] != sid) return;
    switch (m['t']) {
      case 'event':
        _onEvent((m['event'] as Map?)?.cast<String, dynamic>() ?? {});
        break;
      case 'ask':
        _ask(m);
        break;
      case 'exit':
        setState(() => busy = false);
        _add(_Item('error', '${m['error'] ?? 'Сеанс завершен'}'));
        break;
      case 'error':
        _add(_Item('error', '${m['message']}'));
        break;
    }
  }

  void _onEvent(Map<String, dynamic> ev) {
    final type = ev['type'];
    if (type == 'assistant') {
      final content = (ev['message']?['content'] as List?) ?? [];
      for (final b in content.whereType<Map>()) {
        if (b['type'] == 'text' && '${b['text']}'.trim().isNotEmpty) _add(_Item('text', '${b['text']}'.trim()));
        if (b['type'] == 'tool_use') _add(_Item('tool', '${b['name']}: ${_short(b['input'])}'));
      }
    } else if (type == 'result') {
      setState(() => busy = false);
      if (ev['is_error'] == true) _add(_Item('error', '${ev['result'] ?? 'Ошибка Claude Code'}'));
    } else if (type == 'workdesk') {
      setState(() => busy = false);
      if (ev['subtype'] == 'error') _add(_Item('error', '${ev['message']}'));
      if (ev['subtype'] == 'interrupted') _add(_Item('info', 'Остановлено'));
    }
  }

  static String _short(dynamic v) {
    final s = v is Map && v['command'] != null ? '${v['command']}' : v is Map && v['file_path'] != null ? '${v['file_path']}' : jsonEncode(v);
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Future<void> _ask(Map<String, dynamic> m) async {
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Разрешить: ${m['tool']}?'),
        content: SingleChildScrollView(child: SelectableText('Компьютер: ${widget.agent.title}\n\n${_short(m['input'])}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Запретить')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Разрешить')),
        ],
      ),
    );
    relay.send({'t': 'answer', 'sid': sid, 'id': m['id'], 'allow': allow == true});
    _add(_Item('info', '${m['tool']}: ${allow == true ? 'разрешено' : 'запрещено'}'));
    if (allow == true) setState(() => busy = true);
  }

  void _send() {
    final text = input.text.trim();
    if (text.isEmpty || sid == null) return;
    relay.send({'t': 'input', 'sid': sid, 'text': text});
    input.clear();
    setState(() => busy = true);
    _add(_Item('user', text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Claude · ${widget.agent.title}'), actions: [
        if (busy) IconButton(tooltip: 'Остановить', icon: const Icon(Icons.stop_circle), onPressed: () => relay.send({'t': 'interrupt', 'sid': sid})),
      ]),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final it = items[i];
              final mine = it.kind == 'user';
              final color = switch (it.kind) {
                'user' => theme.colorScheme.primary.withOpacity(0.15),
                'tool' => theme.colorScheme.secondary.withOpacity(0.10),
                'error' => Colors.red.withOpacity(0.12),
                'info' => Colors.transparent,
                _ => theme.cardColor,
              };
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: SelectableText(it.kind == 'tool' ? '⚙ ${it.text}' : it.text,
                      style: TextStyle(
                          fontFamily: it.kind == 'tool' ? 'monospace' : null,
                          fontSize: it.kind == 'info' || it.kind == 'tool' ? 12 : 15,
                          color: it.kind == 'info' ? theme.hintColor : null)),
                ),
              );
            },
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Задача для Claude на этом компьютере', border: OutlineInputBorder()),
                ),
              ),
              IconButton(icon: const Icon(Icons.send), onPressed: sid == null ? null : _send),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------- Терминал ----------

class ClaudeTerminalPage extends StatefulWidget {
  final ClaudeAgent agent;
  const ClaudeTerminalPage({Key? key, required this.agent}) : super(key: key);

  @override
  State<ClaudeTerminalPage> createState() => _ClaudeTerminalPageState();
}

class _ClaudeTerminalPageState extends State<ClaudeTerminalPage> {
  final relay = ClaudeRelay.instance;
  final terminal = Terminal(maxLines: 10000);
  StreamSubscription? sub;
  String? sid;
  int cols = 80, rows = 24;

  @override
  void initState() {
    super.initState();
    sub = relay.messages.listen(_onMessage);
    terminal.onOutput = (data) {
      if (sid != null) relay.send({'t': 'in', 'sid': sid, 'data': base64Encode(utf8.encode(data))});
    };
    terminal.onResize = (w, h, pw, ph) {
      cols = w;
      rows = h;
      if (sid != null) relay.send({'t': 'resize', 'sid': sid, 'cols': w, 'rows': h});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      sid = await relay.open(widget.agent.device, 'term', cwd: widget.agent.cwd, cols: cols, rows: rows);
    } catch (e) {
      terminal.write('\r\n$e\r\n');
    }
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['t'] == 'disconnected') return terminal.write('\r\n[Связь с сервером потеряна]\r\n');
    if (m['sid'] != sid) return;
    if (m['t'] == 'out') terminal.write(utf8.decode(base64Decode('${m['data']}'), allowMalformed: true));
    if (m['t'] == 'exit') terminal.write('\r\n[${m['error'] ?? 'Claude Code завершил работу'}]\r\n');
  }

  @override
  void dispose() {
    if (sid != null) relay.send({'t': 'close', 'sid': sid});
    sub?.cancel();
    super.dispose();
  }

  void _key(String s) {
    if (sid != null) relay.send({'t': 'in', 'sid': sid, 'data': base64Encode(utf8.encode(s))});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Терминал · ${widget.agent.title}')),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: TerminalView(terminal, autofocus: true)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final k in const {'Esc': '\x1b', 'Tab': '\t', '↑': '\x1b[A', '↓': '\x1b[B', 'Ctrl+C': '\x03', 'Enter': '\r'}.entries)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _key(k.value);
                    },
                    child: Text(k.key),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
