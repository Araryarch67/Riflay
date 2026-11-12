import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auto_eq.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../theme.dart';

/// Picks a headphone or IEM from AutoEQ and sets the equalizer for it. A sheet, so the equalizer can open it from
/// Settings and from the expanded player's side panel alike.
Future<void> showAutoEqPicker(BuildContext context) {
  final c = PlayerScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevated,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => PlayerScope(controller: c, child: const _AutoEqSheet()),
  );
}

class _AutoEqSheet extends StatefulWidget {
  const _AutoEqSheet();

  @override
  State<_AutoEqSheet> createState() => _AutoEqSheetState();
}

class _AutoEqSheetState extends State<_AutoEqSheet> {
  late Future<List<AutoEqEntry>> _index = AutoEq.index();
  final _query = TextEditingController();
  AutoEqEntry? _applying;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _apply(AutoEqEntry e) async {
    final audio = PlayerScope.read(context).audio;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _applying = e;
      _error = null;
    });
    try {
      final fit = await AutoEq.fitFor(e);
      await audio.applyEqProfile('${e.name} (${e.source})', fit.bands);
      if (!mounted) return;
      Navigator.pop(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            fit.error < 0.05 ? tr.autoEqApplied(e.name) : tr.autoEqAppliedFitted(e.name, fit.error.toStringAsFixed(1)),
          ),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = tr.autoEqFailed('$err'));
    } finally {
      if (mounted) setState(() => _applying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(tr.autoEq, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(tr.autoEqSubtitle, style: muted),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr.autoEqSearch,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(error, style: muted?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder(
                future: _index,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr.autoEqFailed('${snap.error}'), style: muted),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () => setState(() => _index = AutoEq.index()),
                            child: Text(tr.retry),
                          ),
                        ],
                      ),
                    );
                  }
                  final all = snap.data;
                  if (all == null) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 16),
                          Expanded(child: Text(tr.autoEqLoading, style: muted)),
                        ],
                      ),
                    );
                  }
                  final found = AutoEq.search(all, _query.text);
                  if (_query.text.trim().isEmpty || found.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.text.trim().isEmpty ? tr.autoEqModels(all.length) : tr.autoEqNoResults,
                        style: muted,
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: found.length,
                    itemBuilder: (context, i) {
                      final e = found[i];
                      return ListTile(
                        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(e.by, style: muted),
                        trailing: _applying == e
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                        onTap: _applying == null ? () => unawaited(_apply(e)) : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
