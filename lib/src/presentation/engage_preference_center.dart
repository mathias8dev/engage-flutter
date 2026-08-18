import 'package:flutter/material.dart';

import '../application/engage_runtime.dart';
import '../domain/models.dart';

/// Engage's ready-to-use Preference Center content.
///
/// The host owns navigation chrome (`Scaffold`, `AppBar`, `Navigator`) and
/// safe areas. This widget inherits the current Material 3 theme and locale.
final class EngagePreferenceCenter extends StatelessWidget {
  const EngagePreferenceCenter({this.centerKey, this.onError, super.key});

  final String? centerKey;
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    final state = EngageRuntime.client.preferenceCenter.center(centerKey);
    return StreamBuilder<PreferenceCenterSnapshot?>(
      stream: state,
      initialData: state.value,
      builder: (context, snapshot) {
        final center = snapshot.data;
        if (center == null || !_hasVisiblePreferences(center)) {
          return const _EmptyPreferenceCenter();
        }
        return _PreferenceCenterContent(center: center, onError: onError);
      },
    );
  }
}

final class _PreferenceCenterContent extends StatelessWidget {
  const _PreferenceCenterContent({required this.center, this.onError});

  final PreferenceCenterSnapshot center;
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (center.description case final description?) ...[
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
        for (final section in center.sections) ...[
          if (section.title case final title?)
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (section.description case final description?) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          for (final preference in section.subscriptions) ...[
            if (preference.installationChoice case final selected?)
              _PreferenceToggle(
                preference: preference,
                selected: selected,
                onError: onError,
              ),
            for (final choice
                in preference.profileChoices?.entries ??
                    const <MapEntry<Channel, bool>>[])
              _PreferenceToggle(
                preference: preference,
                channel: choice.key,
                selected: choice.value,
                onError: onError,
              ),
          ],
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

final class _PreferenceToggle extends StatefulWidget {
  const _PreferenceToggle({
    required this.preference,
    required this.selected,
    this.channel,
    this.onError,
  });

  final SubscriptionPreference preference;
  final Channel? channel;
  final bool selected;
  final ValueChanged<Object>? onError;

  @override
  State<_PreferenceToggle> createState() => _PreferenceToggleState();
}

final class _PreferenceToggleState extends State<_PreferenceToggle> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = _PreferenceCenterStrings.of(context);
    final channel = widget.channel;
    final subtitle = [
      ?widget.preference.description,
      if (channel != null) strings.channel(channel),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          value: widget.selected,
          onChanged: _updating ? null : _change,
          title: Text(widget.preference.displayName),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
        ),
      ),
    );
  }

  Future<void> _change(bool enabled) async {
    setState(() => _updating = true);
    try {
      final channel = widget.channel;
      if (channel == null) {
        await EngageRuntime.client.installation.editSubscriptions((editor) {
          if (enabled) {
            editor.subscribe(widget.preference.key);
          } else {
            editor.unsubscribe(widget.preference.key);
          }
        });
      } else {
        await EngageRuntime.client.profile.editSubscriptions((editor) {
          if (enabled) {
            editor.subscribe(widget.preference.key, {channel});
          } else {
            editor.unsubscribe(widget.preference.key, {channel});
          }
        });
      }
    } on Object catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
}

final class _EmptyPreferenceCenter extends StatelessWidget {
  const _EmptyPreferenceCenter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = _PreferenceCenterStrings.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 32,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                strings.emptyTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                strings.emptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasVisiblePreferences(PreferenceCenterSnapshot center) =>
    center.sections.any(
      (section) => section.subscriptions.any(
        (preference) =>
            preference.installationChoice != null ||
            (preference.profileChoices?.isNotEmpty ?? false),
      ),
    );

final class _PreferenceCenterStrings {
  const _PreferenceCenterStrings({
    required this.emptyTitle,
    required this.emptyBody,
  });

  final String emptyTitle;
  final String emptyBody;

  static _PreferenceCenterStrings of(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fr'
      ? const _PreferenceCenterStrings(
          emptyTitle: 'Aucune préférence pour le moment',
          emptyBody:
              'Cette application n’a pas encore publié de préférences de communication.',
        )
      : const _PreferenceCenterStrings(
          emptyTitle: 'No preferences yet',
          emptyBody:
              'This app hasn’t published any communication preferences yet.',
        );

  String channel(Channel channel) => switch (channel) {
    Channel.email => 'Email',
    Channel.sms => 'SMS',
    Channel.push => 'Push',
    Channel.whatsapp => 'WhatsApp',
  };
}
