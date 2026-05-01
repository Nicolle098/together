// Conditional export: native platforms get disk caching, web gets the stub.
export 'tile_cache_provider_stub.dart'
    if (dart.library.io) 'tile_cache_provider_io.dart';
