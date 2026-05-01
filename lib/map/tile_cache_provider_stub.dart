import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Web fallback: no disk access, tiles go directly over the network.
class CachedTileProvider extends TileProvider {
  CachedTileProvider._();

  static Future<CachedTileProvider> create() async => CachedTileProvider._();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return NetworkImage(getTileUrl(coordinates, options));
  }
}
