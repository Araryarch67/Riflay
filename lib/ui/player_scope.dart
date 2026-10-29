import 'package:flutter/widgets.dart';

import '../services/player_controller.dart';

/// Makes the [PlayerController] available to the widget tree.
class PlayerScope extends InheritedNotifier<PlayerController> {
  PlayerScope({super.key, required PlayerController controller, required Widget child})
    : super(
        notifier: controller,
        child: _PlayerIdentity(controller: controller, child: child),
      );

  /// The controller, rebuilding the caller on every change it notifies.
  static PlayerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;

  /// Access without subscribing to rebuilds (for callbacks).
  static PlayerController read(BuildContext context) => context.getInheritedWidgetOfExactType<PlayerScope>()!.notifier!;

  /// The controller, rebuilding the caller only if a different one takes its
  /// place (tests do that): for widgets that listen to just part of it.
  static PlayerController identity(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlayerIdentity>()!.controller;
}

class _PlayerIdentity extends InheritedWidget {
  const _PlayerIdentity({required this.controller, required super.child});

  final PlayerController controller;

  @override
  bool updateShouldNotify(_PlayerIdentity old) => !identical(controller, old.controller);
}

/// [builder] again for each change the controller notifies, but only while
/// this part of the screen can be seen. A page covered by another (its tickers
/// are off: Home under an album, a hidden phone tab) was rebuilt and laid out
/// for every song change all the same; now it catches up once it's uncovered.
class VisiblePlayerBuilder extends StatefulWidget {
  const VisiblePlayerBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, PlayerController c) builder;

  @override
  State<VisiblePlayerBuilder> createState() => _VisiblePlayerBuilderState();
}

class _VisiblePlayerBuilderState extends State<VisiblePlayerBuilder> {
  PlayerController? _c;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = PlayerScope.identity(context);
    if (!identical(c, _c)) {
      _c?.removeListener(_changed);
      _c = c..addListener(_changed);
    }
    // Runs again (and so builds) when the page is covered or uncovered.
    _visible = TickerMode.valuesOf(context).enabled;
  }

  void _changed() {
    if (_visible) setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c!);
}

/// Rebuilds when [select] picks out something else from the controller, not
/// on each of its changes. [PlayerController] notifies for everything (a song
/// starting, play / pause, buffering, the library), several times a song; a
/// song row only cares whether it is the one playing.
class PlayerSelect<T> extends StatefulWidget {
  const PlayerSelect({super.key, required this.select, required this.builder, this.child});

  /// Compared with `==`: records of plain values work.
  final T Function(PlayerController c) select;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  State<PlayerSelect<T>> createState() => _PlayerSelectState<T>();
}

class _PlayerSelectState<T> extends State<PlayerSelect<T>> {
  PlayerController? _c;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = PlayerScope.identity(context);
    if (identical(c, _c)) return;
    _c?.removeListener(_changed);
    _c = c..addListener(_changed);
    _value = widget.select(c);
  }

  @override
  void didUpdateWidget(PlayerSelect<T> old) {
    super.didUpdateWidget(old);
    // What's selected may depend on the widget's own fields (a row's song).
    _value = widget.select(_c!);
  }

  void _changed() {
    final value = widget.select(_c!);
    if (value != _value) setState(() => _value = value);
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value, widget.child);
}
