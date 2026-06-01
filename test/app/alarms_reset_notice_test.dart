import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/common/logic/salvage_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Widget-level coverage for the Phase-1 Test 2 (BOOT-04 / D-06) "alarms were
/// reset" notice.
///
/// SCOPE / BOUNDARY: the full `App` widget cannot be pumped in a unit test — its
/// `initState` boots `appSettings`, notification listeners, the background
/// service and dynamic color, all of which need platform channels. So this test
/// drives the notice through a minimal harness that reproduces the EXACT
/// notice mechanism from `_AppState._showAlarmsResetNoticeIfNeeded`
/// (lib/app.dart): same `SalvageReport` gate, the same real generated
/// `alarmsResetNotice` localized string, and the same SnackBar config
/// (Semantics liveRegion, 10s duration, horizontal swipe-dismiss, floating,
/// clear-after-show). The onboarding-route gate (`GetStorage().read('onboarded')`)
/// is the one production branch NOT reproduced here — it needs GetStorage's
/// platform init — and remains a documented on-device/manual check.
///
/// If the production SnackBar in lib/app.dart changes, keep `_showNotice` below
/// in sync.

/// Faithful mirror of `_AppState._showAlarmsResetNoticeIfNeeded` (sans the
/// GetStorage onboarding gate — see header).
void _showNotice(GlobalKey<ScaffoldMessengerState> messengerKey) {
  if (!SalvageReport.alarmsWereLost) return;

  final messengerState = messengerKey.currentState;
  final messengerContext = messengerKey.currentContext;
  if (messengerState == null || messengerContext == null) return;

  final localizations = AppLocalizations.of(messengerContext);
  if (localizations == null) return;
  final String message = localizations.alarmsResetNotice;

  messengerState.showSnackBar(
    SnackBar(
      content: Semantics(
        liveRegion: true,
        label: message,
        child: Text(message),
      ),
      duration: const Duration(seconds: 10),
      dismissDirection: DismissDirection.horizontal,
      behavior: SnackBarBehavior.floating,
    ),
  );

  SalvageReport.clear();
}

/// Minimal stand-in for `App`: registers the same post-frame callback that
/// `_AppState.initState` uses, so timing matches production.
class _NoticeHarness extends StatefulWidget {
  const _NoticeHarness();

  @override
  State<_NoticeHarness> createState() => _NoticeHarnessState();
}

class _NoticeHarnessState extends State<_NoticeHarness> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNotice(_messengerKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.expand()),
    );
  }
}

String _noticeText(WidgetTester tester) {
  final BuildContext context = tester.element(find.byType(Scaffold));
  return AppLocalizations.of(context)!.alarmsResetNotice;
}

void main() {
  setUp(SalvageReport.clear);
  tearDown(SalvageReport.clear);

  group('alarms-reset notice', () {
    testWidgets('shows exactly once when an alarm was lost, then clears the flag',
        (WidgetTester tester) async {
      SalvageReport.markEntryDropped<Alarm>();

      await tester.pumpWidget(const _NoticeHarness());
      await tester.pumpAndSettle();

      final message = _noticeText(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      // Shown-once: the flag is cleared after display so a later launch is silent.
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    testWidgets('notice content is a live region (TalkBack announce contract)',
        (WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      SalvageReport.markEntryDropped<Alarm>();

      await tester.pumpWidget(const _NoticeHarness());
      await tester.pumpAndSettle();

      final message = _noticeText(tester);
      final node = tester.getSemantics(find.text(message));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue,
          reason: 'screen readers only auto-announce live-region nodes');

      handle.dispose();
    });

    testWidgets('notice is swipe-dismissible', (WidgetTester tester) async {
      SalvageReport.markEntryDropped<Alarm>();

      await tester.pumpWidget(const _NoticeHarness());
      await tester.pumpAndSettle();

      final message = _noticeText(tester);
      expect(find.text(message), findsOneWidget);

      await tester.drag(find.text(message), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text(message), findsNothing);
    });

    testWidgets('negative case: no notice when no alarm was lost',
        (WidgetTester tester) async {
      // Routine recovery (timer/city/settings) leaves the flag false.
      SalvageReport.markEntryDropped<String>();

      await tester.pumpWidget(const _NoticeHarness());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
