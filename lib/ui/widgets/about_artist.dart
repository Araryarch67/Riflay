import 'package:flutter/material.dart';

import '../../services/artist_channels.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/ytmusic_web.dart' show WebArtistInfo;
import '../theme.dart';
import 'skeleton.dart';

/// About the artist: photo, name, followers, a few lines about them and Follow, from YouTube Music. For a
/// song from a file (or a streamed one whose channel isn't known) the artist is looked up by [name]; only an
/// artist of exactly that name is taken, so a different one is never shown. Nothing shows when there is none.
class AboutArtist extends StatefulWidget {
  const AboutArtist({super.key, required this.name, this.channelId, this.onOpen, this.full = false});

  final String name;

  /// The artist's YouTube Music channel (`UC…`), when known.
  final String? channelId;
  final VoidCallback? onOpen;

  /// On the artist's own page: all of the text, behind Show more.
  final bool full;

  @override
  State<AboutArtist> createState() => _AboutArtistState();
}

class _AboutArtistState extends State<AboutArtist> {
  late Future<({String id, WebArtistInfo info})?> _about = _load();
  bool _more = false;

  @override
  void didUpdateWidget(AboutArtist old) {
    super.didUpdateWidget(old);
    if (old.channelId != widget.channelId || old.name != widget.name) {
      _about = _load();
      _more = false;
    }
  }

  Future<({String id, WebArtistInfo info})?> _load() async {
    final account = PlayerScope.read(context).ytMusic;
    try {
      final id = widget.channelId ?? await ArtistChannels.find(account, widget.name);
      if (id == null) return null;
      final info = await account.artistInfo(id);
      return info == null ? null : (id: id, info: info);
    } catch (e) {
      debugPrint('About the artist: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final account = PlayerScope.read(context).ytMusic;
    return FutureBuilder(
      future: _about,
      builder: (context, snap) {
        final found = snap.data;
        if (found == null) {
          if (snap.connectionState == ConnectionState.done) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.elevated, borderRadius: LayoutPrefs.corner(8)),
            child: const ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 110, height: 16),
                  SizedBox(height: 12),
                  SkeletonRow(size: 56, circle: true, trailing: false),
                  SizedBox(height: 8),
                  SkeletonText(lines: 3),
                ],
              ),
            ),
          );
        }
        final (:id, :info) = found;
        final photo = info.thumbnailUrl;
        final about = info.description;
        return Material(
          color: AppColors.elevated,
          borderRadius: LayoutPrefs.corner(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr.aboutTheArtist, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (photo != null) ...[
                    ClipOval(
                      child: Image.network(
                        photo,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        cacheWidth: 216,
                        errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(info.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          info.subscribers ?? '',
                          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      if (account.canEdit)
                        ListenableBuilder(
                          listenable: account,
                          builder: (context, _) {
                            final following = account.isFollowing(id);
                            return OutlinedButton(
                              onPressed: () => account.setFollowing(id, !following),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                shape: const StadiumBorder(),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(following ? tr.following : tr.follow),
                            );
                          },
                        ),
                    ],
                  ),
                  if (about != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      about,
                      maxLines: widget.full && _more ? null : (widget.full ? 5 : 3),
                      overflow: widget.full && _more ? null : TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4),
                    ),
                    if (widget.full)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() => _more = !_more),
                        child: Text(_more ? tr.showLess : tr.showMore),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
