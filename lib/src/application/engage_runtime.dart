import '../domain/engage_platform.dart';
import '../infrastructure/method_channel_engage_platform.dart';
import 'engage_client.dart';

abstract final class EngageRuntime {
  static EngageClient? _storedClient;

  static EngageClient get client =>
      _storedClient ??= EngageClient(MethodChannelEngagePlatform());

  static Future<void> usePlatform(EngagePlatform platform) async {
    await _storedClient?.dispose();
    _storedClient = EngageClient(platform);
  }
}
