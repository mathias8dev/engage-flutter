import 'dart:async';

import 'package:flutter/material.dart';

import '../application/engage_runtime.dart';
import '../domain/engage_platform.dart';
import '../domain/models.dart';
import 'engage_localizations.dart';

/// Engage's ready-to-use Preference Center content.
///
/// The host owns navigation chrome (`Scaffold`, `AppBar`, `Navigator`) and
/// safe areas. This widget inherits the current Material 3 theme and locale.
final class EngagePreferenceCenter extends StatefulWidget {
  const EngagePreferenceCenter({this.centerKey, this.onError, super.key});

  final String? centerKey;
  final ValueChanged<Object>? onError;

  @override
  State<EngagePreferenceCenter> createState() => _EngagePreferenceCenterState();
}

final class _EngagePreferenceCenterState extends State<EngagePreferenceCenter> {
  late EngageState<PreferenceCenterResource> _resource;
  late PreferenceCenterResource _currentResource;
  StreamSubscription<PreferenceCenterResource>? _resourceSubscription;

  @override
  void initState() {
    super.initState();
    _bindResource();
  }

  @override
  void didUpdateWidget(covariant EngagePreferenceCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerKey == widget.centerKey) return;
    _bindResource();
  }

  void _bindResource() {
    unawaited(_resourceSubscription?.cancel());
    final resource = EngageRuntime.client.preferenceCenter.resource(
      widget.centerKey,
    );
    _resource = resource;
    _currentResource = resource.value;
    _resourceSubscription = resource.listen((value) {
      if (!identical(_resource, resource)) return;
      if (identical(value, _currentResource)) return;
      if (!mounted) return;
      setState(() => _currentResource = value);
    });
  }

  @override
  void dispose() {
    unawaited(_resourceSubscription?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await EngageRuntime.client.preferenceCenter.refresh();
    } on Object catch (error) {
      widget.onError?.call(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resource = _currentResource;
    final center = resource.data;
    final hasContent = center != null && _hasVisiblePreferences(center);
    final Widget content = switch ((resource.status, hasContent)) {
      (PreferenceCenterResourceStatus.loading, false) =>
        const _LoadingPreferenceCenter(),
      (PreferenceCenterResourceStatus.error, false) => _ErrorPreferenceCenter(
        onRetry: _refresh,
      ),
      (_, false) => const _EmptyPreferenceCenter(),
      (_, true) => _PreferenceCenterContent(
        center: center!,
        status: resource.status,
        onRetry: _refresh,
        onError: widget.onError,
      ),
    };
    return RefreshIndicator(onRefresh: _refresh, child: content);
  }
}

final class _PreferenceCenterContent extends StatelessWidget {
  const _PreferenceCenterContent({
    required this.center,
    required this.status,
    required this.onRetry,
    this.onError,
  });

  final PreferenceCenterSnapshot center;
  final PreferenceCenterResourceStatus status;
  final Future<void> Function() onRetry;
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (status == PreferenceCenterResourceStatus.loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
        ],
        if (status == PreferenceCenterResourceStatus.error) ...[
          _RefreshErrorNotice(onRetry: onRetry),
          const SizedBox(height: 20),
        ],
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
                key: ValueKey('installation:${preference.key}'),
                preference: preference,
                selected: selected,
                onError: onError,
              ),
            for (final choice
                in preference.profileChoices?.entries ??
                    const <MapEntry<Channel, bool>>[])
              _PreferenceToggle(
                key: ValueKey('profile:${preference.key}:${choice.key.name}'),
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
    super.key,
  });

  final SubscriptionPreference preference;
  final Channel? channel;
  final bool selected;
  final ValueChanged<Object>? onError;

  @override
  State<_PreferenceToggle> createState() => _PreferenceToggleState();
}

final class _PreferenceToggleState extends State<_PreferenceToggle> {
  _PreferenceEditStatus _status = _PreferenceEditStatus.idle;

  @override
  void didUpdateWidget(covariant _PreferenceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected &&
        _status != _PreferenceEditStatus.saving) {
      _status = _PreferenceEditStatus.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = EngageLocalizations.of(context);
    final channel = widget.channel;
    final subtitle = [
      ?widget.preference.description,
      if (channel != null) _localizedChannel(strings, channel),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: _status == _PreferenceEditStatus.saving
              ? null
              : () => _change(!widget.selected),
          title: Text(widget.preference.displayName),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          trailing: _PreferenceTrailing(
            status: _status,
            selected: widget.selected,
            onChanged: _change,
          ),
        ),
      ),
    );
  }

  Future<void> _change(bool enabled) async {
    if (_status == _PreferenceEditStatus.saving) return;
    setState(() => _status = _PreferenceEditStatus.saving);
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
      if (mounted) {
        setState(() => _status = _PreferenceEditStatus.idle);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _status = _PreferenceEditStatus.failed);
      }
      widget.onError?.call(error);
    }
  }
}

final class _PreferenceTrailing extends StatelessWidget {
  const _PreferenceTrailing({
    required this.status,
    required this.selected,
    required this.onChanged,
  });

  final _PreferenceEditStatus status;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (status == _PreferenceEditStatus.saving) {
      return const SizedBox.square(
        dimension: 32,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == _PreferenceEditStatus.failed) ...[
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 4),
        ],
        Switch(value: selected, onChanged: onChanged),
      ],
    );
  }
}

enum _PreferenceEditStatus { idle, saving, failed }

final class _RefreshErrorNotice extends StatelessWidget {
  const _RefreshErrorNotice({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = EngageLocalizations.of(context);
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.preferenceCenterRefreshErrorBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(strings.retry)),
          ],
        ),
      ),
    );
  }
}

final class _LoadingPreferenceCenter extends StatelessWidget {
  const _LoadingPreferenceCenter();

  @override
  Widget build(BuildContext context) =>
      const _CenteredPreferenceCenterState(child: CircularProgressIndicator());
}

final class _ErrorPreferenceCenter extends StatelessWidget {
  const _ErrorPreferenceCenter({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = EngageLocalizations.of(context);
    return _CenteredPreferenceCenterState(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: colors.error),
          const SizedBox(height: 20),
          Text(
            strings.preferenceCenterRefreshErrorTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            strings.preferenceCenterRefreshErrorBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(onPressed: onRetry, child: Text(strings.retry)),
        ],
      ),
    );
  }
}

final class _CenteredPreferenceCenterState extends StatelessWidget {
  const _CenteredPreferenceCenterState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        SizedBox(
          height: (constraints.maxHeight - 64).clamp(0, double.infinity),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: child,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _EmptyPreferenceCenter extends StatelessWidget {
  const _EmptyPreferenceCenter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = EngageLocalizations.of(context);
    return _CenteredPreferenceCenterState(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
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
            strings.preferenceCenterEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            strings.preferenceCenterEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
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

String _localizedChannel(EngageLocalizations strings, Channel channel) =>
    switch (channel) {
      Channel.email => strings.channelEmail,
      Channel.sms => strings.channelSms,
      Channel.push => strings.channelPush,
      Channel.whatsapp => strings.channelWhatsapp,
    };
