import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

class CachedTileProvider extends TileProvider {
  CachedTileProvider._({required String? tileDirPath})
      : _tileDirPath = tileDirPath;

  final String? _tileDirPath;

  /// Creates a [CachedTileProvider] backed by the app's cache directory.
  ///
  /// Falls back to uncached network tiles if the cache directory cannot be
  /// created (e.g. permissions issue).
  static Future<CachedTileProvider> create() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final tileDir = Directory('${cacheDir.path}/osm_tiles');
      await tileDir.create(recursive: true);
      return CachedTileProvider._(tileDirPath: tileDir.path);
    } catch (_) {
      return CachedTileProvider._(tileDirPath: null);
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    if (_tileDirPath == null) {
      return NetworkImage(url);
    }
    return _CachedTileImage(url: url, tileDirPath: _tileDirPath);
  }
}

// ---------------------------------------------------------------------------

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({required this.url, required this.tileDirPath});

  final String url;
  final String tileDirPath;

  /// Stable filename derived from the tile URL path segments.
  /// e.g. ".../15/18432/11264.png" → "15_18432_11264.png"
  String get _fileName {
    final segments = Uri.parse(url).pathSegments;
    // Guard against empty or degenerate URLs
    if (segments.isEmpty) return url.hashCode.toString();
    return segments.join('_');
  }

  File _cacheFile() => File('$tileDirPath/$_fileName');

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<String>('Tile URL', key.url),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) async {
    final file = key._cacheFile();
    final Uint8List bytes;

    if (file.existsSync()) {
      // Serve from disk — works fully offline.
      bytes = await file.readAsBytes();
    } else {
      // Fetch from the network and cache for future offline use.
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client
            .getUrl(Uri.parse(key.url))
            .timeout(const Duration(seconds: 12));
        request.headers
          ..set(HttpHeaders.userAgentHeader, 'together-app/1.0 flutter_map')
          ..set(HttpHeaders.acceptHeader, 'image/png,image/*;q=0.8');

        final response =
            await request.close().timeout(const Duration(seconds: 15));

        if (response.statusCode != HttpStatus.ok) {
          throw NetworkImageLoadException(
            statusCode: response.statusCode,
            uri: Uri.parse(key.url),
          );
        }

        bytes = await consolidateHttpClientResponseBytes(response);

        // Write to cache — failure here is non-fatal; tile still renders.
        try {
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      } finally {
        client.close();
      }
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
