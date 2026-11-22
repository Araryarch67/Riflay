import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/services/youtube_importer.dart';

class _Runtime extends Spotiflac {
  final calls = <Map<String, dynamic>>[];
  bool pending = false;

  @override
  Future<void> load() async {}

  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    calls.add({'method': method, ...params});
    if (method == 'pendingAuth') return pending ? {'auth_url': 'https://verify.example/grant'} : null;
    if (method == 'call') {
      pending = true;
      throw const SpotiflacError(verificationRequired: true);
    }
    if (method == 'sessionGrant') return {'success': true};
    return null;
  }
}

class _StaleRuntime extends Spotiflac {
  final calls = <Map<String, dynamic>>[];

  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    calls.add({'method': method, ...params});
    final args = params['args'] as Map;
    if (args['fresh'] != true) throw const SpotiflacError();
    return [
      {'id': '1', 'name': 'Song'},
    ];
  }
}

void main() {
  test('capabilities follow runtime flags, including lyrics-only and download-only extensions', () {
    expect(Spotiflac.capabilitiesOf({'has_lyrics_provider': true}), {SpotiflacCapability.lyrics});
    expect(Spotiflac.capabilitiesOf({'has_download_provider': true}), {SpotiflacCapability.download});
    expect(Spotiflac.capabilitiesOf({'has_metadata_provider': true}), {
      SpotiflacCapability.metadata,
      SpotiflacCapability.search,
    });
    expect(
      Spotiflac.capabilitiesOf({
        'search_behavior': {'enabled': true},
      }),
      {SpotiflacCapability.search},
    );
  });

  test('chosen downloader survives queue persistence for metadata-only songs', () {
    final source = Spotiflac.track('apple-music', {'id': '1630302895', 'name': 'Mantra Hujan'})!;
    final job = DownloadJob(
      videoId: Spotiflac.jobId(source),
      title: source.title,
      channel: source.artist,
      thumbnailUrl: '',
      extensionTrack: source,
      extensionDownloader: 'tidal-web',
      extensionQuality: 'LOSSLESS',
    );
    final restored = YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([job])).single;
    expect(restored.extensionDownloader, 'tidal-web');
    expect(restored.extensionTrack!.extensionId, 'apple-music');
    expect(restored.extensionQuality, 'LOSSLESS');
  });

  test('Apple Music verifies the stable downloader rather than its metadata provider', () async {
    final runtime = _Runtime();
    runtime.plugins = [
      {'id': 'tidal-web', 'enabled': true, 'has_download_provider': true},
      {'id': 'apple-music', 'enabled': true, 'has_download_provider': false},
      {'id': 'amazon', 'enabled': true, 'has_download_provider': true},
    ];
    final source = Spotiflac.track('apple-music', {'id': '1630302895', 'name': 'Mantra Hujan'})!;
    expect(runtime.downloadProviderOf(source), 'amazon');
    runtime.plugins = runtime.plugins.reversed.toList();
    expect(runtime.downloadProviderOf(source), 'amazon');
    expect((await runtime.verificationUrl(source)).host, 'verify.example');
    await runtime.completeVerification(source, 'test-grant');
    expect(runtime.calls.every((call) => call['extension'] == 'amazon'), isTrue);
    expect(runtime.calls.last['method'], 'sessionGrant');
  });

  test('native download providers retain their own verification', () {
    final runtime = _Runtime()
      ..plugins = [
        {'id': 'tidal-web', 'enabled': true, 'has_download_provider': true},
        {'id': 'amazon', 'enabled': true, 'has_download_provider': true},
      ];
    expect(runtime.downloadProviderOf(Spotiflac.track('tidal-web', {'id': '1', 'name': 'Song'})!), 'tidal-web');
    expect(SpotiflacError.fromProvider('Verification required').verificationRequired, isTrue);
  });

  test('search retry requests a fresh runtime and verification targets the catalog provider', () async {
    final runtime = _Runtime()..selected = 'catalog';
    await expectLater(
      runtime.search('song', fresh: true),
      throwsA(isA<SpotiflacError>().having((error) => error.verificationRequired, 'needs verification', isTrue)),
    );
    expect(runtime.calls.single, {
      'method': 'call',
      'extension': 'catalog',
      'operation': 'search',
      'args': {'query': 'song', 'limit': 50, 'fresh': true},
    });
    expect((await runtime.searchVerificationUrl('catalog')).host, 'verify.example');
    await runtime.completeProviderVerification('catalog', 'test-grant');
    expect(runtime.calls.map((call) => call['method']), ['call', 'pendingAuth', 'sessionGrant']);
    expect(runtime.calls.every((call) => call['extension'] == 'catalog'), isTrue);
  });

  test('a failed search rebuilds the provider runtime once before reporting an error', () async {
    final runtime = _StaleRuntime()..selected = 'catalog';
    final songs = await runtime.search('song');
    expect(songs.single.title, 'Song');
    expect(runtime.calls.map((call) => (call['args'] as Map)['fresh']), [null, true]);
  });
}
