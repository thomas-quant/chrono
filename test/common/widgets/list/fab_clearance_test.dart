// Narrow headless widget test for the central FAB bottom-clearance fix
// (FAB-01). The FAB is a custom `Positioned` overlay (lib/common/widgets/fab.dart),
// not a Material `Scaffold.floatingActionButton`, so `CustomListView` must
// reserve an explicit bottom inset on its scrollable to keep the last item /
// menu button from being occluded.
//
// This test is intentionally narrow (mirrors test/common/widgets/fields/*_test.dart):
// it pumps a `CustomListView` with an empty item list inside a `MaterialApp`
// whose `ThemeData` carries a `ThemeSettingExtension` (the seam reads
// `theme.extension<ThemeSettingExtension>()!`), then asserts the resolved
// bottom inset on the list's `SliverPadding` clears the FAB extent. It does NOT
// boot the full App/NavScaffold and touches no real storage or audio.
//
// FAB extent reference: this test imports the SHARED geometry constants from
// fab.dart (fabExtent, fabMaterialExtraOffset) rather than re-hardcoding the
// magic numbers, so it catches a fab.dart drift instead of silently agreeing
// with a stale literal in custom_list_view.dart.

import 'package:clock_app/common/types/list_controller.dart';
import 'package:clock_app/common/types/list_item.dart';
import 'package:clock_app/common/widgets/fab.dart';
import 'package:clock_app/common/widgets/list/custom_list_view.dart';
import 'package:clock_app/theme/types/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Required so the statically-constructed appSettings schema that
  // CustomListView.initState reads ("Long Press Action") is reachable.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FAB bottom clearance', () {
    testWidgets('reserves bottom inset >= FAB extent (non-material style)',
        (WidgetTester tester) async {
      await _pumpList(tester, useMaterialStyle: false);

      final double bottom = _resolvedListBottomInset(tester);
      // Must clear the FAB tap target so the last item is not occluded.
      expect(bottom, greaterThanOrEqualTo(fabExtent));
    });

    testWidgets(
        'reserves bottom inset >= FAB extent + Material +20 (material style)',
        (WidgetTester tester) async {
      await _pumpList(tester, useMaterialStyle: true);

      final double bottom = _resolvedListBottomInset(tester);
      // In Material style the FAB sits higher by fabMaterialExtraOffset, so the
      // inset must clear the FAB extent plus that extra offset.
      expect(bottom, greaterThanOrEqualTo(fabExtent + fabMaterialExtraOffset));
    });

    testWidgets('horizontal 16 and top 8 are preserved',
        (WidgetTester tester) async {
      await _pumpList(tester, useMaterialStyle: false);

      final EdgeInsets padding = _resolvedListPadding(tester);
      expect(padding.left, 16);
      expect(padding.right, 16);
      expect(padding.top, 8);
    });
  });
}

Future<void> _pumpList(WidgetTester tester,
    {required bool useMaterialStyle}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: <ThemeExtension<dynamic>>[
          ThemeSettingExtension(useMaterialStyle: useMaterialStyle),
        ],
      ),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: 400,
          child: CustomListView<ListItem>(
            items: const <ListItem>[],
            listController: ListController<ListItem>(),
            itemBuilder: (item) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

// The CustomListView forwards its `padding` to a `SliverPadding` inside the
// underlying CustomScrollView (animated_reorderable_listview.dart:249-250).
EdgeInsets _resolvedListPadding(WidgetTester tester) {
  final SliverPadding sliverPadding =
      tester.widget<SliverPadding>(find.byType(SliverPadding));
  return sliverPadding.padding.resolve(TextDirection.ltr);
}

double _resolvedListBottomInset(WidgetTester tester) =>
    _resolvedListPadding(tester).bottom;
