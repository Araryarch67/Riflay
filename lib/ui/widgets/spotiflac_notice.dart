import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/layout_prefs.dart';

/// Explains why extension search results need to be downloaded before playback.
class SpotiflacNotice extends StatelessWidget {
  const SpotiflacNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: LayoutPrefs.corner(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr.spotiflacDownloadOnly,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
