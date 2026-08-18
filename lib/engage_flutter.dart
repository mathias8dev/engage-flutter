library;

import 'package:meta/meta.dart';

import 'src/application/engage_client.dart';
import 'src/application/engage_runtime.dart';
import 'src/domain/engage_platform.dart';
import 'src/domain/models.dart';

export 'src/application/engage_client.dart'
    show
        ActionHandler,
        ActionRegistration,
        ActionsApi,
        EventsApi,
        FeatureFlagsApi,
        InboxApi,
        InboxPager,
        InAppApi,
        InAppOverlayDisplayDelegate,
        InAppOverlaysApi,
        InstallationApi,
        MessageCenterApi,
        PreferenceCenterApi,
        PrivacyApi,
        ProfileApi,
        PushApi,
        SdkFeaturesApi;
export 'src/domain/editors.dart'
    show
        AttributeEditor,
        EventEditor,
        InstallationSubscriptionEditor,
        ProfileSubscriptionEditor,
        SdkFeatureEditor,
        TagEditor;
export 'src/domain/engage_platform.dart'
    show EngagePlatform, EngageState, NativeMethodHandler;
export 'src/domain/models.dart';
export 'src/presentation/engage_in_app_placement.dart';
export 'src/presentation/engage_material_theme.dart';
export 'src/presentation/engage_message_center.dart';
export 'src/presentation/engage_preference_center.dart';

abstract final class Engage {
  static EngageClient get _client => EngageRuntime.client;

  static EngageState<EngageLifecycle> get state => _client.lifecycle;
  static InstallationApi get installation => _client.installation;
  static ProfileApi get profile => _client.profile;
  static EventsApi get events => _client.events;
  static ActionsApi get actions => _client.actions;
  static SdkFeaturesApi get sdkFeatures => _client.sdkFeatures;
  static FeatureFlagsApi get flags => _client.flags;
  static PreferenceCenterApi get preferenceCenter => _client.preferenceCenter;
  static PrivacyApi get privacy => _client.privacy;
  static PushApi get push => _client.push;
  static InAppApi get inApp => _client.inApp;
  static MessageCenterApi get messageCenter => _client.messageCenter;

  static Future<void> start({required EngageConfig config}) =>
      _client.start(config);

  @visibleForTesting
  static Future<void> usePlatformForTesting(EngagePlatform platform) =>
      EngageRuntime.usePlatform(platform);
}
