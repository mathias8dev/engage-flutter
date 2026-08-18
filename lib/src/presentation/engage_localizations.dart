import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Localized product vocabulary used by Engage's ready-made Flutter UI.
///
/// Apps may register their own [LocalizationsDelegate] for this type to
/// override the built-in copy. When no delegate is registered, Engage falls
/// back to its bundled catalog for the current locale.
abstract class EngageLocalizations {
  const EngageLocalizations(this.localeName);

  final String localeName;

  static const LocalizationsDelegate<EngageLocalizations> delegate =
      _EngageLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('fr')];

  static EngageLocalizations of(BuildContext context) =>
      Localizations.of<EngageLocalizations>(context, EngageLocalizations) ??
      lookup(Localizations.localeOf(context));

  static EngageLocalizations lookup(Locale locale) =>
      switch (locale.languageCode) {
        'fr' => const _EngageLocalizationsFr(),
        _ => const _EngageLocalizationsEn(),
      };

  String get preferenceCenterEmptyTitle;
  String get preferenceCenterEmptyBody;
  String get preferenceCenterRefreshErrorTitle;
  String get preferenceCenterRefreshErrorBody;
  String get retry;
  String get channelEmail;
  String get channelSms;
  String get channelPush;
  String get channelWhatsapp;
}

final class _EngageLocalizationsDelegate
    extends LocalizationsDelegate<EngageLocalizations> {
  const _EngageLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => EngageLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<EngageLocalizations> load(Locale locale) =>
      SynchronousFuture(EngageLocalizations.lookup(locale));

  @override
  bool shouldReload(_EngageLocalizationsDelegate old) => false;
}

final class _EngageLocalizationsEn extends EngageLocalizations {
  const _EngageLocalizationsEn() : super('en');

  @override
  String get preferenceCenterEmptyTitle => 'No preferences yet';
  @override
  String get preferenceCenterEmptyBody =>
      'This app hasn’t published any communication preferences yet.';
  @override
  String get preferenceCenterRefreshErrorTitle => 'Preferences unavailable';
  @override
  String get preferenceCenterRefreshErrorBody =>
      'Unable to refresh your preferences right now.';
  @override
  String get retry => 'Retry';
  @override
  String get channelEmail => 'Email';
  @override
  String get channelSms => 'SMS';
  @override
  String get channelPush => 'Push';
  @override
  String get channelWhatsapp => 'WhatsApp';
}

final class _EngageLocalizationsFr extends EngageLocalizations {
  const _EngageLocalizationsFr() : super('fr');

  @override
  String get preferenceCenterEmptyTitle => 'Aucune préférence pour le moment';
  @override
  String get preferenceCenterEmptyBody =>
      'Cette application n’a pas encore publié de préférences de communication.';
  @override
  String get preferenceCenterRefreshErrorTitle => 'Préférences indisponibles';
  @override
  String get preferenceCenterRefreshErrorBody =>
      'Impossible d’actualiser vos préférences pour le moment.';
  @override
  String get retry => 'Réessayer';
  @override
  String get channelEmail => 'E-mail';
  @override
  String get channelSms => 'SMS';
  @override
  String get channelPush => 'Push';
  @override
  String get channelWhatsapp => 'WhatsApp';
}
