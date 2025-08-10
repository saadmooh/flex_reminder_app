import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ar.dart';
import 'app_localizations_zh.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> get _localizedValues {
    switch (locale.languageCode) {
      case 'ar':
        return arabicTranslations;
      case 'zh':
        return chineseTranslations;
      case 'en':
      default:
        return englishTranslations;
    }
  }

  // Helper function to retrieve localized values
  String _getValue(String key, {String defaultValue = 'Missing translation'}) {
    return _localizedValues[key] ?? defaultValue;
  }

  // App-wide translations
  String get appTitle => _getValue('appTitle');
  String get searchPosts => _getValue('searchPosts');
  String navigationFailed(String message) =>
      _getValue('navigationFailed').replaceFirst('{message}', message);
  String get filterPressed => _getValue('filterPressed');
  String get timeSlots => _getValue('timeSlots');
  String get workingOffline => _getValue('workingOffline');
  String get notificationSettings => _getValue('notificationSettings');
  String get subscriptionManagement => _getValue('subscriptionManagement');
  String get stats => _getValue('stats');
  String get logout => _getValue('logout');
  String get reminderRescheduled => _getValue('reminderRescheduled');
  String get rescheduleReminder => _getValue('rescheduleReminder');
  String get searchReminders => _getValue('searchReminders');
  String get unexpectedError => _getValue('unexpectedError');
  String get unauthorizedError => _getValue('unauthorizedError');
  String get remindersTitle => _getValue('remindersTitle');
  String get unreadReminders => _getValue('unreadReminders');
  String get readReminders => _getValue('readReminders');
  String get noUnreadReminders => _getValue('noUnreadReminders');
  String get noReadReminders => _getValue('noReadReminders');
  String get ofRemindersOpened => _getValue('ofRemindersOpened');
  String get openingPercentage => _getValue('openingPercentage');
  String get filters => _getValue('filters');
  String get categories => _getValue('categories');
  String get complexity => _getValue('complexity');
  String get domains => _getValue('domains');
  String get clearFilters => _getValue('clearFilters');
  String get loading => _getValue('loading');
  String get close => _getValue('close');
  String get postNotificationTitle => _getValue('postNotificationTitle');
  String get postNotificationSummary => _getValue('postNotificationSummary');
  String get urlRequired => _getValue('urlRequired');
  String get importanceRequired => _getValue('importanceRequired');
  String get nextReminderTimeMissing => _getValue('nextReminderTimeMissing');
  String get titleMissing => _getValue('titleMissing');
  String get urlLabel => _getValue('urlLabel');
  String get invalidUrl => _getValue('invalidUrl');
  String get importanceLabel => _getValue('importanceLabel');
  String get saveButton => _getValue('saveButton');
  String get profileUpdate => _getValue('profileUpdate');
  String get profileUpdateSuccess => _getValue('profileUpdateSuccess');
  String get profileUpdateFailed => _getValue('profileUpdateFailed');
  String get uploadPhoto => _getValue('uploadPhoto');
  String get changeLanguage => _getValue('changeLanguage');
  String get languageUpdated => _getValue('languageUpdated');
  String get languageUpdateFailed => _getValue('languageUpdateFailed');
  String get currentLanguage => _getValue('currentLanguage');
  String get selectLanguage => _getValue('selectLanguage');
  String get profileSettings => _getValue('profileSettings');
  String get editProfile => _getValue('editProfile');
  String get saveChanges => _getValue('saveChanges');
  String get cancel => _getValue('cancel');
  String get userProfile => _getValue('userProfile');
  String get tapToChangePhoto => _getValue('tapToChangePhoto');
  String get name => _getValue('name');
  String postSavedSuccess(String title, String time) =>
      _getValue('postSavedSuccess')
          .replaceFirst('%s', title)
          .replaceFirst('%s', time);
  String get engagementTimesLastWeek => _getValue('engagementTimesLastWeek');
  String get postOpeningTrendLastWeek => _getValue('postOpeningTrendLastWeek');
  String get recommendations => _getValue('recommendations');
  String get optimalTimes => _getValue('optimalTimes');
  String get noRecommendations => _getValue('noRecommendations');
  String get noOptimalTimesAvailable => _getValue('noOptimalTimesAvailable');
  String get oldDataNotAnalyzed => _getValue('oldDataNotAnalyzed');
  String get unknown => _getValue('unknown');
  String get created => _getValue('created');
  String get opened => _getValue('opened');
  String get yes => _getValue('yes');
  String get no => _getValue('no');
  String errorSchedulingNotification(String error) =>
      _getValue('errorSchedulingNotification').replaceFirst('{error}', error);
  String get home => _getValue('home');
  String get freeTimes => _getValue('freeTimes');
  String get addFreeTime => _getValue('addFreeTime');
  String get editFreeTime => _getValue('editFreeTime');
  String get day => _getValue('day');
  String get startTime => _getValue('startTime');
  String get endTime => _getValue('endTime');
  String get delete => _getValue('delete');
  String get confirmDelete => _getValue('confirmDelete');
  String get areYouSureDelete => _getValue('areYouSureDelete');
  String get noFreeTimes => _getValue('noFreeTimes');
  String get dayOff => _getValue('dayOff');
  String errorLoadingFreeTimes(String error) =>
      _getValue('errorLoadingFreeTimes').replaceFirst('{error}', error);
  String errorDeletingFreeTime(String error) =>
      _getValue('errorDeletingFreeTime').replaceFirst('{error}', error);
  String errorUpdatingDayOff(String error) =>
      _getValue('errorUpdatingDayOff').replaceFirst('{error}', error);
  String get noDaysAvailable => _getValue('noDaysAvailable');
  String get invalidTimeRange => _getValue('invalidTimeRange');
  String get overlapDetected => _getValue('overlapDetected');
  String overlapMessage(String count) =>
      _getValue('overlapMessage').replaceFirst('{count}', count);
  String get merge => _getValue('merge');
  String updateFailed(String message) =>
      _getValue('updateFailed').replaceFirst('{message}', message);
  String error(String error) =>
      _getValue('error').replaceFirst('{error}', error);
  String get monday => _getValue('monday');
  String get tuesday => _getValue('tuesday');
  String get wednesday => _getValue('wednesday');
  String get thursday => _getValue('thursday');
  String get friday => _getValue('friday');
  String get saturday => _getValue('saturday');
  String get sunday => _getValue('sunday');
  String get editReminderTitle => _getValue('editReminderTitle');
  String get requiredField => _getValue('requiredField');
  String get notSpecified => _getValue('notSpecified');
  String get editImportanceButton => _getValue('editImportanceButton');
  String get editNextReminderTimeButton =>
      _getValue('editNextReminderTimeButton');
  String get reminderUpdatedSuccess => _getValue('reminderUpdatedSuccess');
  String reminderUpdateError(String error) =>
      _getValue('reminderUpdateError').replaceFirst('%s', error);
  String postNotificationBody(String title) =>
      _getValue('postNotificationBody').replaceFirst('{title}', title);
  String postSaveFailed(String error) =>
      _getValue('postSaveFailed').replaceFirst('{error}', error);
  String postSaveError(String error) =>
      _getValue('postSaveError').replaceFirst('{error}', error);
  String get titleLabel => _getValue('titleLabel');
  String get nextReminderTimeLabel => _getValue('nextReminderTimeLabel');
  String get noDataAvailable => _getValue('noDataAvailable');
  String timeToReview(String title) =>
      _getValue('timeToReview').replaceFirst('{title}', title);
  String get tapToViewDetails => _getValue('tapToViewDetails');
  String get email => _getValue('email');
  String get password => _getValue('password');
  String get forgotPassword => _getValue('forgotPassword');
  String get alreadyHaveAccount => _getValue('alreadyHaveAccount');
  String get dontHaveAccount => _getValue('dontHaveAccount');
  String get login => _getValue('login');
  String get signUp => _getValue('signUp');
  String get invalidEmail => _getValue('invalidEmail');
  String get noTitle => _getValue('noTitle');
  String get noDate => _getValue('noDate');
  String get noReminderSet => _getValue('noReminderSet');
  String get unableToOpenLink => _getValue('unableToOpenLink');
  String get deleteReminder => _getValue('deleteReminder');
  String get confirmDeleteReminder => _getValue('confirmDeleteReminder');
  String get reminderNotProvided => _getValue('reminderNotProvided');
  String get importancePrefix => _getValue('importancePrefix');
  String get goTo => _getValue('goTo');

  // Subscription-related translations
  String get manageSubscription => _getValue('manageSubscription');
  String get subscriptionStatus => _getValue('subscriptionStatus');
  String get youAreSubscribed => _getValue('youAreSubscribed');
  String get subscriptionPaused => _getValue('subscriptionPaused');
  String get notSubscribed => _getValue('notSubscribed');
  String get currentSubscription => _getValue('currentSubscription');
  String get availablePlans => _getValue('availablePlans');
  String get noPlansAvailable => _getValue('noPlansAvailable');
  String get unnamedPlan => _getValue('unnamedPlan');
  String get noDescriptionAvailable => _getValue('noDescriptionAvailable');
  String get pausePlan => _getValue('pausePlan');
  String get cancelPlan => _getValue('cancelPlan');
  String get resumePlan => _getValue('resumePlan');
  String get changePlan => _getValue('changePlan');
  String get subscribe => _getValue('subscribe');
  String get currentPlan => _getValue('currentPlan');
  String get checkout => _getValue('checkout');
  String get errorLoadingInitialData => _getValue('errorLoadingInitialData');
  String get errorLoadingSubscriptionData =>
      _getValue('errorLoadingSubscriptionData');
  String get errorLoadingCustomerPortal =>
      _getValue('errorLoadingCustomerPortal');
  String get errorLoadingPlans => _getValue('errorLoadingPlans');
  String get errorSubscribing => _getValue('errorSubscribing');
  String get errorCancellingSubscription =>
      _getValue('errorCancellingSubscription');
  String get errorPausingSubscription => _getValue('errorPausingSubscription');
  String get errorResumingSubscription =>
      _getValue('errorResumingSubscription');
  String get errorChangingSubscription =>
      _getValue('errorChangingSubscription');

  // Email verification translations
  String get verifyYourEmail => _getValue('verifyYourEmail');
  String get verificationCodeSent => _getValue('verificationCodeSent');
  String get verificationCode => _getValue('verificationCode');
  String get pleaseEnterCode => _getValue('pleaseEnterCode');
  String get resendCode => _getValue('resendCode');
  String get verify => _getValue('verify');
  String get emailVerifiedSuccess => _getValue('emailVerifiedSuccess');
  String get pleaseEnterVerificationCode =>
      _getValue('pleaseEnterVerificationCode');
  String get verificationCodeResent => _getValue('verificationCodeResent');
  String get anErrorOccurred => _getValue('anErrorOccurred');
  String get success => _getValue('success');
  String get okay => _getValue('okay');

  // Subscription related translations
  String get subscriptionPausedSuccessfully =>
      _getValue('subscriptionPausedSuccessfully');
  String get subscriptionCancelledSuccessfully =>
      _getValue('subscriptionCancelledSuccessfully');
  String get subscriptionResumedSuccessfully =>
      _getValue('subscriptionResumedSuccessfully');
  String get planChangedSuccessfully => _getValue('planChangedSuccessfully');
  String get paymentCompletedSuccessfully =>
      _getValue('paymentCompletedSuccessfully');
  String get noCurrentSubscription => _getValue('noCurrentSubscription');
  String get errorPerformingAction => _getValue('errorPerformingAction');
  String get errorLoadingPage => _getValue('errorLoadingPage');
  String status(String status) =>
      _getValue('status').replaceFirst('{status}', status);
  String price(String price) =>
      _getValue('price').replaceFirst('{price}', price);
  String duration(String duration) =>
      _getValue('duration').replaceFirst('{duration}', duration);
  String advancedFeatures(String value) =>
      _getValue('advancedFeatures').replaceFirst('{value}', value);
  String renewsAt(String date) =>
      _getValue('renewsAt').replaceFirst('{date}', date);
  String restoreBy(String date) =>
      _getValue('restoreBy').replaceFirst('{date}', date);
  String get confirmAction => _getValue('confirmAction');
  String confirmSubscription(String planName) =>
      _getValue('confirmSubscription').replaceFirst('{planName}', planName);
  String get confirm => _getValue('confirm');
  String savePercent(String percent) =>
      _getValue('savePercent').replaceFirst('{percent}', percent);
  String timeRemaining(String time) =>
      _getValue('timeRemaining').replaceFirst('{time}', time);
  String get currentOffer => _getValue('currentOffer');
  String get swapOffer => _getValue('swapOffer');
  String get offerSwappedSuccessfully => _getValue('offerSwappedSuccessfully');
  String get errorSwappingOffer => _getValue('errorSwappingOffer');

  // Reset password translations
  String get resetCodeSent => _getValue('resetCodeSent');
  String get newResetCodeSent => _getValue('newResetCodeSent');
  String get codeVerifiedSuccessfully => _getValue('codeVerifiedSuccessfully');
  String get passwordUpdatedSuccessfully =>
      _getValue('passwordUpdatedSuccessfully');
  String get pleaseEnterResetCode => _getValue('pleaseEnterResetCode');
  String get passwordsDoNotMatch => _getValue('passwordsDoNotMatch');
  String get passwordMinLength => _getValue('passwordMinLength');
  String get resetPassword => _getValue('resetPassword');
  String get resetCode => _getValue('resetCode');
  String get verifyCode => _getValue('verifyCode');
  String get enterCodeSentToEmail => _getValue('enterCodeSentToEmail');
  String get enterNewPassword => _getValue('enterNewPassword');
  String get confirmPassword => _getValue('confirmPassword');
  String get updatePassword => _getValue('updatePassword');
  String get failedToSendCode => _getValue('failedToSendCode');
  String get invalidCode => _getValue('invalidCode');
  String get failedToString => _getValue('failedToUpdatePassword');
  String get registrationSuccessful => _getValue('registrationSuccessful');
  String get loginSuccessful => _getValue('loginSuccessful');
  String get failedToUpdatePassword => _getValue('failedToUpdatePassword');
  // Notification settings translations
  String get saveSettings => _getValue('saveSettings');
  String get silentMode => _getValue('silentMode');
  String get enableSilentMode => _getValue('enableSilentMode');
  String get disableSoundAndVibration => _getValue('disableSoundAndVibration');
  String get soundSettings => _getValue('soundSettings');
  String get enableSound => _getValue('enableSound');
  String get playNotificationSound => _getValue('playNotificationSound');
  String get notificationSound => _getValue('notificationSound');
  String get volumeLevel => _getValue('volumeLevel');
  String get vibrationSettings => _getValue('vibrationSettings');
  String get enableVibration => _getValue('enableVibration');
  String get vibrateOnNotification => _getValue('vibrateOnNotification');
  String get testNotification => _getValue('testNotification');
  String get information => _getValue('information');
  String get silentModeDisablesSoundAndVibration =>
      _getValue('silentModeDisablesSoundAndVibration');
  String get testSettingsBeforeSaving => _getValue('testSettingsBeforeSaving');
  String get settingsApplyToNewNotifications =>
      _getValue('settingsApplyToNewNotifications');
  String get selectNotificationSound => _getValue('selectNotificationSound');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => true;
}
