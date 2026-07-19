import 'package:clock_app/common/types/json.dart';
import 'package:clock_app/common/utils/list_storage.dart';

/// Runs a cancel/process/save update only after the source list has loaded
/// successfully.
///
/// Returns false when the source read fails. In that case neither [cancel] nor
/// [save] is called, so a transient read failure cannot turn into a destructive
/// empty-list update. A successful empty list is still processed and saved.
Future<bool> runSafeListUpdate<T extends JsonSerializable>({
  required Future<ListLoadResult<T>> Function() load,
  required Future<void> Function() cancel,
  required Future<void> Function(List<T> items) process,
  required Future<void> Function(List<T> items) save,
}) async {
  final result = await load();
  if (result is! ListLoadSuccess<T>) {
    return false;
  }

  final items = result.items;
  await cancel();
  await process(items);
  await save(items);
  return true;
}
