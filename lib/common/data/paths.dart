import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

const _appDataDirectory = "Clock";
const _ringtonesDirectory = "ringtones";
String _appDataDirectoryPath = "";

Future<void> initializeAppDataDirectory() async {
  _appDataDirectoryPath = await getAppDataDirectoryPath();

  if (!await Directory(_appDataDirectoryPath).exists()) {
    await Directory(_appDataDirectoryPath).create();
  }

  await Directory(getRingtonesDirectoryPathSync()).create(recursive: true);
}

String getAppDataDirectoryPathSync() {
  if (_appDataDirectoryPath.isEmpty) {
    throw Exception(
        "App data directory path is not initialized. Call 'initializeAppDataDirectory()' first.");
  }
  return _appDataDirectoryPath;
}

/// Test-only hook to point the storage layer at a real on-disk directory
/// without invoking the platform-only `getApplicationDocumentsDirectory()`.
/// Pass an empty string to reset between tests. Not used in production code.
@visibleForTesting
void setAppDataDirectoryPathForTesting(String path) {
  _appDataDirectoryPath = path;
}

Future<String> getAppDataDirectoryPath() async {
  return path.join(
      (await getApplicationDocumentsDirectory()).path, _appDataDirectory);
}

Future<String> getRingtonesDirectoryPath() async {
  return path.join(await getAppDataDirectoryPath(), _ringtonesDirectory);
}

String getRingtonesDirectoryPathSync() {
  return path.join(getAppDataDirectoryPathSync(), _ringtonesDirectory);
}

Future<String> getTimezonesDatabasePath() async {
  return path.join(await getAppDataDirectoryPath(), 'timezones.db');
}

Future<String> getLogsFilePath() async {
  return path.join(await getAppDataDirectoryPath(), "logs.txt");
}

String getLogsFilePathSync(){
  return path.join(getAppDataDirectoryPathSync(), "logs.txt");
}
