import 'package:flutter/material.dart';

/// Immutable Material 3 environment passed to Engage-owned native surfaces.
///
/// Capture it from the host widget tree immediately before opening a native
/// surface so runtime theme and locale changes are respected.
@immutable
final class EngageMaterialTheme {
  const EngageMaterialTheme({
    required this.brightness,
    required this.locale,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outlineVariant,
    required this.error,
    required this.onError,
  });

  factory EngageMaterialTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return EngageMaterialTheme(
      brightness: theme.brightness,
      locale: Localizations.localeOf(context),
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      surface: colors.surface,
      surfaceContainerLow: colors.surfaceContainerLow,
      surfaceContainer: colors.surfaceContainer,
      onSurface: colors.onSurface,
      onSurfaceVariant: colors.onSurfaceVariant,
      outlineVariant: colors.outlineVariant,
      error: colors.error,
      onError: colors.onError,
    );
  }

  final Brightness brightness;
  final Locale locale;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outlineVariant;
  final Color error;
  final Color onError;

  Map<String, Object> toPlatform() => {
    'appearance': brightness.name.toUpperCase(),
    'locale': locale.toLanguageTag(),
    'material3': {
      'primary': primary.toARGB32(),
      'onPrimary': onPrimary.toARGB32(),
      'primaryContainer': primaryContainer.toARGB32(),
      'onPrimaryContainer': onPrimaryContainer.toARGB32(),
      'surface': surface.toARGB32(),
      'surfaceContainerLow': surfaceContainerLow.toARGB32(),
      'surfaceContainer': surfaceContainer.toARGB32(),
      'onSurface': onSurface.toARGB32(),
      'onSurfaceVariant': onSurfaceVariant.toARGB32(),
      'outlineVariant': outlineVariant.toARGB32(),
      'error': error.toARGB32(),
      'onError': onError.toARGB32(),
    },
  };
}
