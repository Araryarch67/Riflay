import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/extensions/extension_models.dart';

void main() {
  const url = 'https://example.com/registry.json';

  group('registry.json', () {
    // The shape both suggested registries serve.
    const body = '''
{
  "version": 1,
  "updated_at": "2026-11-03T00:00:00Z",
  "extensions": [
    {
      "id": "soundcloud",
      "name": "soundcloud",
      "display_name": "SoundCloud",
      "version": "1.0.14",
      "description": "SoundCloud metadata and download provider.",
      "download_url": "https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/extensions/soundcloud.sflx",
      "sha256": "1F0D062FCD604C226655104D494A5EFEDED60545E4DB6C8C0AE10ED66656B72D",
      "category": "download",
      "tags": ["soundcloud", "download", 3],
      "downloads": 0,
      "min_app_version": "4.9.1"
    },
    {"id": "../escape", "version": "1.0.0", "download_url": "https://example.com/x.sflx"},
    {"id": "nover", "download_url": "https://example.com/x.sflx"},
    {"id": "ftp", "version": "1.0.0", "download_url": "ftp://example.com/x.sflx"},
    {"id": "soundcloud", "version": "9.9.9", "download_url": "https://example.com/dupe.sflx"},
    "junk"
  ]
}''';

    test('reads the entries, skipping unusable and repeated ones', () {
      final r = ExtensionRegistry.parse(body, url: url);
      expect(r.updatedAt, DateTime.utc(2026, 11, 3));
      expect(r.entries, hasLength(1));
      final e = r.entries.single;
      expect(e.id, 'soundcloud');
      expect(e.displayName, 'SoundCloud');
      expect(e.version, '1.0.14');
      expect(e.downloadUrl.path, endsWith('/soundcloud.sflx'));
      expect(e.sha256, '1f0d062fcd604c226655104d494a5efeded60545e4db6c8c0ae10ed66656b72d');
      expect(e.tags, ['soundcloud', 'download']);
      expect(e.minAppVersion, '4.9.1');
      expect(e.registry, url);
    });

    test('a bare list is accepted; anything else is not a registry', () {
      expect(
        ExtensionRegistry.parse('[{"id":"a","version":"1","download_url":"https://x.y/a.sflx"}]', url: url).entries,
        hasLength(1),
      );
      expect(() => ExtensionRegistry.parse('<html>', url: url), throwsFormatException);
      expect(() => ExtensionRegistry.parse('{"version": 1}', url: url), throwsFormatException);
    });

    test('a checksum that isn\'t sha256 is dropped', () {
      final e = RegistryEntry.tryParse({
        'id': 'a',
        'version': '1',
        'download_url': 'https://x.y/a.sflx',
        'sha256': 'abc',
      });
      expect(e!.sha256, isNull);
    });
  });

  group('manifest.json', () {
    const soundcloud = '''
{
  "name": "soundcloud",
  "displayName": "SoundCloud",
  "version": "1.0.14",
  "type": ["metadata_provider", "download_provider"],
  "requiredRuntimeFeatures": ["preparedContext@1"],
  "permissions": {"network": ["soundcloud.com", "*.sndcdn.com", "API-v2.soundcloud.com"], "storage": true},
  "capabilities": {"networkTimeoutSeconds": 15},
  "searchBehavior": {"enabled": true, "placeholder": "Search SoundCloud..."},
  "settings": [{"key": "lang", "label": "Language", "type": "select", "default": "en"}, {"label": "no key"}]
}''';

    test('reads what Riflay uses', () {
      final m = ExtensionManifest.parse(soundcloud);
      expect(m.id, 'soundcloud');
      expect(m.displayName, 'SoundCloud');
      expect(m.isMetadataProvider, isTrue);
      expect(m.isDownloadProvider, isTrue);
      expect(m.isLyricsProvider, isFalse);
      expect(m.canSearch, isTrue);
      expect(m.searchPlaceholder, 'Search SoundCloud...');
      expect(m.networkTimeout, const Duration(seconds: 15));
      expect(m.requiredRuntimeFeatures, ['preparedContext@1']);
      expect(m.settings.single.key, 'lang');
      expect(m.defaultConfig, {'lang': 'en'});
    });

    test('network permissions: exact hosts and *.wildcards, http(s) only', () {
      final m = ExtensionManifest.parse(soundcloud);
      expect(m.allows(Uri.parse('https://soundcloud.com/x')), isTrue);
      expect(m.allows(Uri.parse('https://api-v2.soundcloud.com/search')), isTrue);
      expect(m.allows(Uri.parse('https://cf-media.sndcdn.com/a.mp3')), isTrue);
      expect(m.allows(Uri.parse('https://sndcdn.com/')), isTrue);
      expect(m.allows(Uri.parse('https://evil-sndcdn.com/')), isFalse);
      expect(m.allows(Uri.parse('https://m.soundcloud.com/')), isFalse);
      expect(m.allows(Uri.parse('https://soundcloud.com.evil.net/')), isFalse);
      expect(m.allows(Uri.parse('file:///etc/passwd')), isFalse);
      expect(ExtensionManifest.parse('{"name":"a","version":"1"}').allows(Uri.parse('https://a.com')), isFalse);
    });

    test('a single type string and a missing search block', () {
      final m = ExtensionManifest.parse('{"name":"lrc","version":"1","type":"lyrics_provider"}');
      expect(m.types, ['lyrics_provider']);
      expect(m.canSearch, isFalse);
    });

    test('unusable manifests are refused', () {
      expect(() => ExtensionManifest.parse('nope'), throwsFormatException);
      expect(() => ExtensionManifest.parse('{"version":"1"}'), throwsFormatException);
      expect(() => ExtensionManifest.parse('{"name":"../x","version":"1"}'), throwsFormatException);
      expect(() => ExtensionManifest.parse('{"name":"Upper","version":"1"}'), throwsFormatException);
      expect(() => ExtensionManifest.parse('{"name":"a"}'), throwsFormatException);
    });
  });

  group('search results', () {
    test('SpotiFLAC track objects become hits; other kinds and junk are kept apart', () {
      final hits = ExtensionSearchHit.parseList([
        {
          'id': 123,
          'name': 'Get Lucky',
          'artists': 'Daft Punk, Pharrell Williams',
          'album_name': 'Random Access Memories',
          'duration_ms': 369629,
          'cover_url': 'https://img.example/c.jpg',
          'isrc': 'USQX91300108',
          'item_type': 'track',
        },
        {'id': 'a1', 'name': 'An album', 'item_type': 'album'},
        {'name': 'no id'},
        'junk',
      ], extensionId: 'apple-music');
      expect(hits, hasLength(2));
      final t = hits.first;
      expect(t.id, '123');
      expect(t.isTrack, isTrue);
      expect(t.duration, const Duration(milliseconds: 369629));
      expect(t.foreign.toString(), 'Daft Punk, Pharrell Williams - Get Lucky');
      expect(t.previewTrack.id, 'ext:apple-music:123');
      expect(t.previewTrack.artworkUrl, 'https://img.example/c.jpg');
      expect(hits.last.isTrack, isFalse);
    });

    test('artists as a list of objects, results under "tracks"', () {
      final hits = ExtensionSearchHit.parseList({
        'tracks': [
          {
            'id': 'x',
            'title': 'Song',
            'artists': [
              {'name': 'A'},
              {'name': 'B'},
            ],
            'images': ['https://i/1.jpg'],
          },
        ],
      }, extensionId: 'e');
      expect(hits.single.artist, 'A, B');
      expect(hits.single.coverUrl, 'https://i/1.jpg');
      expect(hits.single.kind, 'track');
    });
  });

  test('versions compare by number', () {
    expect(compareVersions('1.10.6', '1.9.0'), greaterThan(0));
    expect(compareVersions('2.0', '2.0.0'), 0);
    expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
  });

  test('both suggested registries are offered', () {
    expect(suggestedRegistries.map((r) => r.url), [officialRegistry, communityRegistry]);
  });
}
