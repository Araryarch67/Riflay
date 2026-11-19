/// One web page is one copy of Riflay: nothing to hand a link to.
Future<void> startDesktopRelay(
  List<String> links, {
  required void Function(String text) onLink,
  required void Function() onActivate,
}) async {}

/// What the installed web app was shared (its manifest's `share_target`), or a `?url=` / `?text=` link,
/// as one text: the link may be in any of them.
List<String> pageLinks() {
  final q = Uri.base.queryParameters;
  final text = [
    for (final key in const ['url', 'text', 'title'])
      if (q[key] case final value? when value.trim().isNotEmpty) value,
  ].join('\n');
  return text.isEmpty ? const [] : [text];
}
