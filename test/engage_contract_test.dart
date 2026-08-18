import 'dart:async';

import 'package:engage_flutter/engage_flutter.dart';
import 'package:flutter/material.dart';
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

    await runZonedGuarded(() async {
      Engage.actions.register('open_order', (_) => ActionResult.completed);
      Engage.preferenceCenter.center('account');
      Engage.inApp.placement('home.hero');
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
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

  testWidgets(
    'embedded preference center inherits Material theme and edits choices',
    (tester) async {
      const primary = Color(0xFF6750A4);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: primary),
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('fr'),
              child: const Scaffold(
                body: SafeArea(child: EngagePreferenceCenter()),
              ),
            ),
          ),
        ),
      );

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

      expect(
        platform.invocations.any(
          (call) => call.method == 'installation.editSubscriptions',
        ),
        isTrue,
      );
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
      Engage.inApp.overlays.displayDelegate = (candidate) {
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
    },
  );
}

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
