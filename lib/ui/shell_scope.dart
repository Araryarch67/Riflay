import 'package:flutter/widgets.dart';

import '../models/track.dart';
import 'navigation.dart';

/// Layout facts and navigation actions the pages need from the app shell.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.compact,
    required this.width,
    this.history,
    required this.open,
    required this.openCollection,
    required this.openQueue,
    required this.openNowPlaying,
    required this.openLyrics,
    required this.openDownloads,
    required this.importFromYoutube,
    required this.addFiles,
    required this.addFolder,
    required super.child,
  });

  /// Phone layout (bottom tabs + mini player).
  final bool compact;

  /// Width of the content area, for column decisions inside pages.
  final double width;

  /// Desktop's browser-style history (null on phones, which use tab stacks).
  final DesktopHistory? history;

  /// Opens [page]; [location] tells the sidebar what to highlight.
  final void Function(Widget page, {String? location}) open;
  final void Function(Collection collection) openCollection;
  final VoidCallback openQueue;
  final VoidCallback openNowPlaying;
  final VoidCallback openLyrics;
  final VoidCallback openDownloads;

  /// Opens the paste-a-link sheet / dialog.
  final VoidCallback importFromYoutube;
  final VoidCallback addFiles;

  /// Null where folders can't be scanned (mobile).
  final VoidCallback? addFolder;

  /// The same scope around [child]: for what is built in a route of its own (a sheet),
  /// outside the shell's tree.
  Widget wrap(Widget child) => ShellScope(
    compact: compact,
    width: width,
    history: history,
    open: open,
    openCollection: openCollection,
    openQueue: openQueue,
    openNowPlaying: openNowPlaying,
    openLyrics: openLyrics,
    openDownloads: openDownloads,
    importFromYoutube: importFromYoutube,
    addFiles: addFiles,
    addFolder: addFolder,
    child: child,
  );

  static ShellScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()!;

  @override
  bool updateShouldNotify(ShellScope old) => compact != old.compact || width != old.width;
}
