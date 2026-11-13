// WorkDesk: проверка обновлений из окна настроек (добавлено prepare_fork.py).
// Сервер WorkDesk отдает последнюю сборку для платформы: GET <api-server>/api/workdesk/update?platform=...
// Сравнение — по дате сборки (у всех сборок одна версия RustDesk), скачивание — в системном браузере.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/platform_model.dart';

String _workdeskPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return 'other';
}

/// Проверяет обновление и показывает окно с результатом.
Future<void> workdeskCheckUpdate(BuildContext context) async {
  final api = (await bind.mainGetApiServer()).trim();
  final buildDate = (await bind.mainGetBuildDate()).trim();
  String title;
  String text;
  String? url;
  String? page;
  try {
    if (api.isEmpty) throw Exception('не задан сервер');
    final r = await http
        .get(Uri.parse('$api/api/workdesk/update?platform=${_workdeskPlatform()}'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    page = d['page'] as String?;
    final latest = (d['build'] ?? '').toString();
    if (d['url'] == null || latest.isEmpty) {
      title = 'Обновление WorkDesk';
      text = 'Для этой системы на сервере пока нет файла обновления.';
    } else if (latest.compareTo(buildDate) > 0) {
      title = 'Доступно обновление';
      text = 'Новая сборка WorkDesk от $latest (у вас — от $buildDate).\n'
          '${d['title'] ?? ''}, ${((d['size'] ?? 0) / 1048576).toStringAsFixed(1)} МБ.\n'
          'Файл откроется в браузере; после скачивания установите его поверх текущей версии.';
      url = d['url'] as String?;
    } else {
      title = 'Установлена последняя версия';
      text = 'Ваша сборка от $buildDate — самая свежая на сервере.';
    }
  } catch (e) {
    title = 'Не удалось проверить обновления';
    text = 'Сервер WorkDesk не ответил: $e';
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        if (page != null && url == null)
          TextButton(
              onPressed: () => launchUrl(Uri.parse(page!), mode: LaunchMode.externalApplication),
              child: const Text('Все версии')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Закрыть')),
        if (url != null)
          FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
              },
              child: const Text('Скачать')),
      ],
    ),
  );
}
