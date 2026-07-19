import 'package:clock_app/common/logic/safe_list_update.dart';
import 'package:clock_app/common/types/schedule_id.dart';
import 'package:clock_app/common/utils/list_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read failure skips cancel and save', () async {
    final calls = <String>[];
    List<ScheduleId>? savedItems;

    final updated = await runSafeListUpdate<ScheduleId>(
      load: () async => ListLoadFailure<ScheduleId>(
        StateError('transient read failure'),
        StackTrace.current,
      ),
      cancel: () async => calls.add('cancel'),
      process: (_) async => calls.add('process'),
      save: (items) async {
        calls.add('save');
        savedItems = items;
      },
    );

    expect(updated, isFalse);
    expect(calls, isEmpty);
    expect(savedItems, isNull,
        reason: 'a read failure must not save an empty fallback');
  });

  test('successfully loaded empty list still cancels and saves []', () async {
    final calls = <String>[];
    List<ScheduleId>? savedItems;

    final updated = await runSafeListUpdate<ScheduleId>(
      load: () async => const ListLoadSuccess<ScheduleId>([]),
      cancel: () async => calls.add('cancel'),
      process: (items) async {
        calls.add('process');
        expect(items, isEmpty);
      },
      save: (items) async {
        calls.add('save');
        savedItems = items;
      },
    );

    expect(updated, isTrue);
    expect(calls, ['cancel', 'process', 'save']);
    expect(savedItems, isEmpty);
  });
}
