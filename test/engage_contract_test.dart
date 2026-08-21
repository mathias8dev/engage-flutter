import 'dart:async';

import 'package:engage_flutter/engage_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engage_platform.dart';

void main() {
  late FakeEngagePlatform platform;

  setUp(() async {
    platform = FakeEngagePlatform();
    await Engage.usePlatformForTesting(platform);
  });

  test('start forwards the app configuration and updates lifecycle', () async {
    await Engage.start(
      config: const EngageConfig(
        appKey: 'eng_app_test',
        endpoint: 'https://edge.example.test/v1/',
        legacyEndpoints: ['https://old-edge.example.test/v1/'],
        logLevel: EngageLogLevel.warning,
      ),
    );

    expect(Engage.state.value, EngageLifecycle.started);
    expect(platform.invocations.single.method, 'start');
    expect(
      platform.invocations.single.arguments,
      containsPair('appKey', 'eng_app_test'),
    );
    expect(
      platform.invocations.single.arguments,
      containsPair('logLevel', 'WARNING'),
    );
    expect(
      platform.invocations.single.arguments,
      containsPair('legacyEndpoints', ['https://old-edge.example.test/v1/']),
    );
  });

  test(
    'start rejects a non-HTTP endpoint before crossing the bridge',
    () async {
      expect(
        () => Engage.start(
          config: const EngageConfig(
            appKey: 'eng_app_test',
            endpoint: 'not-an-http-endpoint',
          ),
        ),
        throwsArgumentError,
      );
      expect(platform.invocations, isEmpty);
    },
  );

  test(
    'start rejects an invalid legacy endpoint before crossing the bridge',
    () async {
      expect(
        () => Engage.start(
          config: const EngageConfig(
            appKey: 'eng_app_test',
            legacyEndpoints: ['not-an-http-endpoint'],
          ),
        ),
        throwsArgumentError,
      );
      expect(platform.invocations, isEmpty);
    },
  );

  test(
    'state streams replay and multicast without native resubscription',
    () async {
      final first = <String?>[];
      final second = <String?>[];
      final firstSubscription = Engage.installation.id.listen(first.add);

      platform.emit('installation.id', 'installation-1');
      final secondSubscription = Engage.installation.id.listen(second.add);
      platform.emit('installation.id', 'installation-2');

      expect(first, [null, 'installation-1', 'installation-2']);
      expect(second, ['installation-1', 'installation-2']);
      expect(
        platform.invocations.where(
          (call) => call.method.contains('installation.id'),
        ),
        isEmpty,
      );
      await firstSubscription.cancel();
      await secondSubscription.cancel();
    },
  );

  test(
    'profile and installation edits preserve domain mutation shapes',
    () async {
      await Engage.installation.editAttributes((attributes) {
        attributes.set('store_id', 'paris-12');
        attributes.remove('legacy_attribute');
      });
      await Engage.profile.editSubscriptions((subscriptions) {
        subscriptions.subscribe('marketing', {Channel.push, Channel.email});
      });

      final attributes = platform.invocations[0].arguments! as JsonMap;
      expect(attributes['set'], {'store_id': 'paris-12'});
      expect(attributes['remove'], ['legacy_attribute']);

      final subscriptions = platform.invocations[1].arguments! as JsonMap;
      expect(subscriptions['changes'], hasLength(2));
      expect(
        subscriptions['changes'],
        contains(
          predicate<JsonMap>(
            (change) =>
                change['list'] == 'marketing' &&
                change['channel'] == 'PUSH' &&
                change['subscribed'] == true,
          ),
        ),
      );
    },
  );

  test('binding uses only an opaque binding code', () async {
    platform.responses['installation.issueBindingCode'] = 'binding-code';

    expect(await Engage.installation.issueBindingCode(), 'binding-code');
    expect(platform.invocations.single.method, 'installation.issueBindingCode');
    expect(platform.invocations.single.arguments, isNull);
  });

  test('native actions execute the registered Dart handler', () async {
    final registration = Engage.actions.register('open_order', (action) {
      expect(action.arguments.requireString('order_id'), 'order-42');
      return ActionResult.completed;
    });

    final response = await platform.callDart('actions.execute', {
      'name': 'open_order',
      'arguments': {'order_id': 'order-42'},
    });

    expect(response, 'COMPLETED');
    await registration.cancel();
    expect(platform.invocations.last.method, 'actions.unregister');
  });

  test('background bridge registration failures are contained', () async {
    final failing = FailingBackgroundPlatform();
    await Engage.usePlatformForTesting(failing);
    final uncaught = <Object>[];
    late EngageState<PreferenceCenterResource> preferenceResource;

    await runZonedGuarded(() async {
      Engage.actions.register('open_order', (_) => ActionResult.completed);
      preferenceResource = Engage.preferenceCenter.resource('account');
      Engage.inApp.placement('home.hero');
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
    expect(
      preferenceResource.value.status,
      PreferenceCenterResourceStatus.error,
    );
    expect(failing.invocations, hasLength(3));
  });

  test(
    'preference center forwards the captured Material 3 environment',
    () async {
      await Engage.preferenceCenter.display(
        key: 'account',
        theme: const EngageMaterialTheme(
          brightness: Brightness.dark,
          locale: Locale('fr', 'FR'),
          primary: Color(0xFF006A60),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFF9EF2E4),
          onPrimaryContainer: Color(0xFF00201C),
          surface: Color(0xFF151211),
          surfaceContainerLow: Color(0xFF1E1A19),
          surfaceContainer: Color(0xFF231F1E),
          onSurface: Color(0xFFE9E1DF),
          onSurfaceVariant: Color(0xFFCABFBC),
          outlineVariant: Color(0xFF4A4543),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
        ),
      );

      expect(platform.invocations.single.method, 'preferenceCenter.display');
      expect(platform.invocations.single.arguments, {
        'key': 'account',
        'appearance': 'DARK',
        'locale': 'fr-FR',
        'material3': {
          'primary': 0xFF006A60,
          'onPrimary': 0xFFFFFFFF,
          'primaryContainer': 0xFF9EF2E4,
          'onPrimaryContainer': 0xFF00201C,
          'surface': 0xFF151211,
          'surfaceContainerLow': 0xFF1E1A19,
          'surfaceContainer': 0xFF231F1E,
          'onSurface': 0xFFE9E1DF,
          'onSurfaceVariant': 0xFFCABFBC,
          'outlineVariant': 0xFF4A4543,
          'error': 0xFFFFB4AB,
          'onError': 0xFF690005,
        },
      });
    },
  );

  test('preference center refresh crosses the native bridge', () async {
    await Engage.preferenceCenter.refresh();

    expect(platform.invocations.single.method, 'preferenceCenter.refresh');
    expect(platform.invocations.single.arguments, isNull);
  });

  test(
    'preference center resource owns refresh loading and success states',
    () async {
      final deferred = DeferredPreferenceRefreshPlatform();
      await Engage.usePlatformForTesting(deferred);
      final resource = Engage.preferenceCenter.resource();
      await Future<void>.delayed(Duration.zero);

      expect(resource.value.status, PreferenceCenterResourceStatus.success);

      final refresh = Engage.preferenceCenter.refresh();
      expect(resource.value.status, PreferenceCenterResourceStatus.loading);

      deferred.refresh!.complete();
      await refresh;
      expect(resource.value.status, PreferenceCenterResourceStatus.success);
    },
  );

  test(
    'preference center remains loading until the native bridge replays a snapshot',
    () async {
      final noReplay = NoReplayPreferenceCenterPlatform();
      await Engage.usePlatformForTesting(noReplay);

      final resource = Engage.preferenceCenter.resource('account');
      await Future<void>.delayed(Duration.zero);

      expect(resource.value.status, PreferenceCenterResourceStatus.loading);
      await Engage.preferenceCenter.refresh();
      expect(resource.value.status, PreferenceCenterResourceStatus.loading);

      noReplay.emit('preferenceCenter.center', null, scope: 'account');
      expect(resource.value.status, PreferenceCenterResourceStatus.success);
      expect(resource.value.data, isNull);
    },
  );

  test(
    'preference center projection shares one native observation per key',
    () async {
      final center = Engage.preferenceCenter.center('account');
      final resource = Engage.preferenceCenter.resource('account');
      await Future<void>.delayed(Duration.zero);

      expect(
        platform.invocations.where(
          (call) => call.method == 'preferenceCenter.observe',
        ),
        hasLength(1),
      );

      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(key: 'account'),
        scope: 'account',
      );

      expect(center.value, same(resource.value.data));
      expect(resource.value.data?.key, 'account');
    },
  );

  test(
    'preference center resource preserves stale data on refresh failure',
    () async {
      final failing = FailingPreferenceCenterRefreshPlatform();
      await Engage.usePlatformForTesting(failing);
      final resource = Engage.preferenceCenter.resource();
      await Future<void>.delayed(Duration.zero);
      failing.emit('preferenceCenter.center', _preferenceCenterPayload());

      await expectLater(
        Engage.preferenceCenter.refresh(),
        throwsA(isA<StateError>()),
      );

      expect(resource.value.status, PreferenceCenterResourceStatus.error);
      expect(resource.value.data?.key, 'default');
      expect(resource.value.error, isA<StateError>());
    },
  );

  test('preference center coalesces concurrent refresh requests', () async {
    final deferred = DeferredPreferenceRefreshPlatform();
    await Engage.usePlatformForTesting(deferred);

    final first = Engage.preferenceCenter.refresh();
    final second = Engage.preferenceCenter.refresh();

    expect(identical(first, second), isTrue);
    expect(
      deferred.invocations.where(
        (call) => call.method == 'preferenceCenter.refresh',
      ),
      hasLength(1),
    );

    deferred.refresh!.complete();
    await Future.wait([first, second]);
  });

  testWidgets('embedded preference center supports pull refresh', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EngagePreferenceCenter())),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No preferences yet'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(
      platform.invocations.where(
        (call) => call.method == 'preferenceCenter.refresh',
      ),
      hasLength(1),
    );
    expect(find.text('No preferences yet'), findsOneWidget);
  });

  testWidgets('embedded preference center exposes refresh errors and retry', (
    tester,
  ) async {
    platform.deferPreferenceRefresh = true;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EngagePreferenceCenter())),
    );
    await tester.pump();

    final failure = expectLater(
      Engage.preferenceCenter.refresh(),
      throwsA(isA<StateError>()),
    );
    platform.deferredPreferenceRefresh!.completeError(
      StateError('refresh unavailable'),
    );
    await tester.pump();
    await failure;
    await tester.pump();

    expect(find.text('Preferences unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    platform.deferredPreferenceRefresh!.completeError(
      StateError('refresh unavailable'),
    );
    await tester.pump();

    expect(find.text('Preferences unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'embedded preference center inherits Material theme and edits choices',
    (tester) async {
      const primary = Color(0xFF6750A4);
      platform.deferSubscriptionEdits = true;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            EngageLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: EngageLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: primary),
            useMaterial3: true,
          ),
          home: const Scaffold(body: SafeArea(child: EngagePreferenceCenter())),
        ),
      );

      await tester.pump();
      await tester.pump();
      expect(find.text('Aucune préférence pour le moment'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      platform.emit('preferenceCenter.center', {
        'key': 'default',
        'displayName': 'Communications',
        'description':
            'Choisissez les communications que vous souhaitez recevoir.',
        'sections': [
          {
            'key': 'news',
            'title': 'Actualités',
            'description': null,
            'subscriptions': [
              {
                'key': 'product.news',
                'displayName': 'Nouveautés produit',
                'description': 'Conseils et annonces',
                'profileChoices': null,
                'installationChoice': false,
              },
            ],
          },
        ],
      }, scope: '');
      await tester.pump();

      expect(find.text('Actualités'), findsOneWidget);
      expect(find.text('Nouveautés produit'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      platform.deferredSubscriptionEdit!.complete();
      await tester.pump();

      expect(
        platform.invocations.any(
          (call) => call.method == 'installation.editSubscriptions',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'embedded preference center changes center without accepting stale events',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EngagePreferenceCenter(centerKey: 'first')),
        ),
      );
      await tester.pump();
      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(
          key: 'first',
          preferenceName: 'First preference',
        ),
        scope: 'first',
      );
      await tester.pump();
      expect(find.text('First preference'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EngagePreferenceCenter(centerKey: 'second')),
        ),
      );
      await tester.pump();
      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(
          key: 'first',
          preferenceName: 'Stale preference',
        ),
        scope: 'first',
      );
      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(
          key: 'second',
          preferenceName: 'Second preference',
        ),
        scope: 'second',
      );
      await tester.pump();

      expect(find.text('Stale preference'), findsNothing);
      expect(find.text('Second preference'), findsOneWidget);
    },
  );

  testWidgets(
    'preference mutation state follows its stable key after server reorder',
    (tester) async {
      platform.deferSubscriptionEdits = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EngagePreferenceCenter())),
      );
      await tester.pump();
      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(
          subscriptions: [
            _installationPreference('first', 'First preference'),
            _installationPreference('second', 'Second preference'),
          ],
        ),
        scope: '',
      );
      await tester.pump();

      final firstTile = find.ancestor(
        of: find.text('First preference'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: firstTile, matching: find.byType(Switch)),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: firstTile,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      platform.emit(
        'preferenceCenter.center',
        _preferenceCenterPayload(
          subscriptions: [
            _installationPreference('second', 'Second preference'),
            _installationPreference('first', 'First preference'),
          ],
        ),
        scope: '',
      );
      await tester.pump();

      final reorderedFirstTile = find.ancestor(
        of: find.text('First preference'),
        matching: find.byType(ListTile),
      );
      final reorderedSecondTile = find.ancestor(
        of: find.text('Second preference'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: reorderedFirstTile,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: reorderedSecondTile,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      platform.deferredSubscriptionEdit!.complete();
      await tester.pump();
    },
  );

  test(
    'Inbox entries keep the application payload flat and headless',
    () async {
      final pager = Engage.messageCenter.inbox.pager(
        pageSize: 20,
        sortOrder: InboxSortOrder.oldestFirst,
      );
      final states = <InboxPagerState>[];
      final subscription = pager.state.listen(states.add);

      platform.emit('messageCenter.pager', {
        'entries': [
          {
            'id': 'entry-1',
            'key': 'order.shipped',
            'payload': {'order_id': 'order-42', 'carrier': 'DHL'},
            'sentAt': '2026-08-02T10:00:00Z',
            'expiresAt': null,
            'readAt': null,
          },
        ],
        'isRefreshing': false,
        'isLoadingMore': false,
        'hasMore': true,
        'error': null,
      }, scope: 'flutter-1');

      final entry = states.last.entries.single;
      expect(entry.key, 'order.shipped');
      expect(entry.payload, {'order_id': 'order-42', 'carrier': 'DHL'});
      expect(entry.payload, isNot(contains('title')));
      expect(platform.invocations.first.arguments, {
        'pagerId': 'flutter-1',
        'pageSize': 20,
        'sortOrder': 'OLDEST_FIRST',
      });
      await pager.close();
      await subscription.cancel();
    },
  );

  test('Message Center display optionally targets a concrete entry', () async {
    await Engage.messageCenter.display();
    await Engage.messageCenter.display(entryId: InboxEntryId('entry-42'));

    expect(platform.invocations[0].method, 'messageCenter.display');
    expect(platform.invocations[0].arguments, isEmpty);
    expect(platform.invocations[1].method, 'messageCenter.display');
    expect(platform.invocations[1].arguments, {'entryId': 'entry-42'});
  });

  test('embedded Message Center widgets expose local navigation callbacks', () {
    const layout = EngageMessageCenterLayout(
      horizontalPadding: 20,
      itemSpacing: 8,
      itemCornerRadius: 16,
    );
    final list = EngageMessageCenterList(
      onEntryTap: (_) {},
      layout: layout,
      sortOrder: InboxSortOrder.oldestFirst,
    );
    final detail = EngageMessageCenterDetail(
      entryId: InboxEntryId('entry-42'),
      layout: layout,
    );

    expect(list.onEntryTap, isNotNull);
    expect(list.layout, same(layout));
    expect(list.sortOrder, InboxSortOrder.oldestFirst);
    expect(list.onError, isNull);
    expect(detail.entryId.value, 'entry-42');
    expect(detail.layout, same(layout));
    expect(detail.onUnavailable, isNull);
    expect(detail.onError, isNull);
  });

  test(
    'Inbox pagers have independent windows and shared unread state',
    () async {
      final first = Engage.messageCenter.inbox.pager(pageSize: 10);
      final second = Engage.messageCenter.inbox.pager(pageSize: 50);
      final firstStates = <InboxPagerState>[];
      final secondStates = <InboxPagerState>[];
      final firstSubscription = first.state.listen(firstStates.add);
      final secondSubscription = second.state.listen(secondStates.add);

      platform.emit('messageCenter.unreadCount', 7);
      platform.emit(
        'messageCenter.pager',
        _pagerPayload('first'),
        scope: 'flutter-1',
      );
      platform.emit(
        'messageCenter.pager',
        _pagerPayload('second'),
        scope: 'flutter-2',
      );

      expect(Engage.messageCenter.inbox.unreadCount.value, 7);
      expect(firstStates.last.entries.single.id.value, 'first');
      expect(secondStates.last.entries.single.id.value, 'second');
      await first.close();
      await second.close();
      await firstSubscription.cancel();
      await secondSubscription.cancel();
    },
  );

  test('Inbox operations wait for native pager creation', () async {
    final platform = DeferredPagerPlatform();
    await Engage.usePlatformForTesting(platform);

    final pager = Engage.messageCenter.inbox.pager();
    final refresh = pager.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(platform.invocations.map((call) => call.method), [
      'messageCenter.pager.create',
    ]);

    platform.completeCreation();
    await refresh;
    expect(platform.invocations.map((call) => call.method), [
      'messageCenter.pager.create',
      'messageCenter.pager.refresh',
    ]);
    await pager.close();
  });

  test('flag getters remain typed and use the required fallback', () async {
    platform.responses['flags.getBoolean'] = true;
    platform.responses['flags.getJson'] = {'limit': 12};

    expect(
      await Engage.flags.getBoolean('checkout_v2', defaultValue: false),
      isTrue,
    );
    expect(
      await Engage.flags.getJson<int>(
        'recommendation_configuration',
        defaultValue: 10,
        encode: (value) => {'limit': value},
        decode: (json) => json['limit']! as int,
      ),
      12,
    );
  });

  test(
    'overlay decisions cross the bridge without exposing rendering data',
    () async {
      late InAppContent received;
      Engage.inApp.overlays.displayDelegate = (candidate) {
        received = candidate;
        expect(candidate.payload, {'step': 'payment'});
        return DisplayDecision.defer;
      };

      final response = await platform.callDart('inApp.overlays.decide', {
        'candidate': {
          'experienceId': 'experience-1',
          'messageId': 'message-1',
          'variantId': 'variant-a',
          'type': 'SCENE',
          'payload': {'step': 'payment'},
          'automation': {
            'automationId': 'automation-1',
            'automationVersion': 3,
            'runId': 'run-1',
            'nodeId': 'node-1',
            'experienceVersion': 5,
            'outcomeKeys': ['accepted', 'declined'],
          },
          'presentation': {
            'kind': 'OVERLAY',
            'format': 'MODAL',
            'position': 'CENTER',
            'backdrop': 'DIMMED',
            'dismissal': 'USER_DISMISSIBLE',
            'animation': 'FADE',
            'autoDismissAfterSeconds': null,
          },
        },
      });

      expect(response, 'DEFER');
      expect(received.automation?.runId, 'run-1');
      expect(received.automation?.outcomeKeys, {'accepted', 'declined'});

      platform.responses['inApp.trackOutcome'] = true;
      expect(
        await Engage.inApp.trackOutcome(
          received,
          'accepted',
          properties: {'plan': 'pro'},
        ),
        isTrue,
      );
      expect(platform.invocations.single.method, 'inApp.trackOutcome');
      expect(platform.invocations.single.arguments, {
        'messageId': 'message-1',
        'key': 'accepted',
        'properties': {'plan': 'pro'},
      });
    },
  );
}

JsonMap _preferenceCenterPayload({
  String key = 'default',
  String preferenceName = 'Product news',
  List<JsonMap>? subscriptions,
}) => {
  'key': key,
  'displayName': 'Communications',
  'description': 'Choose which communications you want to receive.',
  'sections': [
    {
      'key': 'news',
      'title': 'News',
      'description': null,
      'subscriptions':
          subscriptions ??
          [_installationPreference('product.news', preferenceName)],
    },
  ],
};

JsonMap _installationPreference(String key, String name) => {
  'key': key,
  'displayName': name,
  'description': 'Tips and announcements',
  'profileChoices': null,
  'installationChoice': false,
};

JsonMap _pagerPayload(String id) => {
  'entries': [
    {
      'id': id,
      'key': 'generic.entry',
      'payload': <String, Object?>{},
      'sentAt': '2026-08-02T10:00:00Z',
      'expiresAt': null,
      'readAt': null,
    },
  ],
  'isRefreshing': false,
  'isLoadingMore': false,
  'hasMore': false,
  'error': null,
};
