import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';

/// The desktop title bar's search box, shared with the search page: typing
/// there drives the page's results.
class SearchInput {
  final controller = TextEditingController();
  final focus = FocusNode();

  /// Enter (or a picked suggestion): search now, with this text.
  final submitted = ValueNotifier<(String, int)>(('', 0));

  void submit(String query) => submitted.value = (query, submitted.value.$2 + 1);

  void dispose() {
    controller.dispose();
    focus.dispose();
    submitted.dispose();
  }
}

/// Searches you made, newest first, for the empty search box.
abstract final class RecentSearches {
  static const _key = 'search.recent.v1';
  static const _max = 8;

  static Future<List<String>> load() async => (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];

  static Future<void> add(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      query,
      ...(prefs.getStringList(_key) ?? const <String>[]).where((q) => q.toLowerCase() != query.toLowerCase()),
    ];
    await prefs.setStringList(_key, list.take(_max).toList());
  }

  static Future<void> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [...(prefs.getStringList(_key) ?? const <String>[])..remove(query)]);
  }
}
