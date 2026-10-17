/// Shared copy for custom and desktop-fallback connection notifications.
const bridgeNotificationTitle = 'Orion Bridge';

String bridgeNotificationSubject(String executorName) {
  final name = executorName.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (name.isEmpty || name.toLowerCase() == 'unknown') {
    return 'Executor Connected!';
  }
  return 'Executor Connected! ($name)';
}
