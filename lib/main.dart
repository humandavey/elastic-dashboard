import 'dart:io';

import 'package:flutter/material.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:elastic_dashboard/pages/dashboard_page.dart';
import 'package:elastic_dashboard/services/field_images.dart';
import 'package:elastic_dashboard/services/ip_address_util.dart';
import 'package:elastic_dashboard/services/log.dart';
import 'package:elastic_dashboard/services/nt4_connection.dart';
import 'package:elastic_dashboard/services/nt4_widget_builder.dart';
import 'package:elastic_dashboard/services/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final PackageInfo packageInfo = await PackageInfo.fromPlatform();

  await logger.initialize();

  logger.info('[${DateTime.now().toString()}] Starting application');

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.error('Flutter Error', details.exception, details.stack);
  };

  final String appFolderPath = (await getApplicationSupportDirectory()).path;

  // Prevents data loss if shared_preferences.json gets corrupted
  // More info and original implementation: https://github.com/flutter/flutter/issues/89211#issuecomment-915096452
  SharedPreferences preferences;
  try {
    preferences = await SharedPreferences.getInstance();

    // Store a copy of user's preferences on the disk
    await _backupPreferences(appFolderPath);
  } catch (error) {
    logger.warning(
        'Failed to get shared preferences instance, attempting to retrieve from backup',
        error);
    // Remove broken preferences files and restore previous settings
    await _restorePreferencesFromBackup(appFolderPath);
    preferences = await SharedPreferences.getInstance();
  }

  await windowManager.ensureInitialized();

  Settings.ipAddressMode =
      IPAddressMode.fromIndex(preferences.getInt(PrefKeys.ipAddressMode));

  Settings.gridSize =
      preferences.getInt(PrefKeys.gridSize) ?? Settings.gridSize;
  Settings.showGrid =
      preferences.getBool(PrefKeys.showGrid) ?? Settings.showGrid;
  Settings.cornerRadius =
      preferences.getDouble(PrefKeys.cornerRadius) ?? Settings.cornerRadius;
  Settings.autoResizeToDS =
      preferences.getBool(PrefKeys.autoResizeToDS) ?? Settings.autoResizeToDS;

  NT4WidgetBuilder.ensureInitialized();

  Settings.ipAddress =
      preferences.getString(PrefKeys.ipAddress) ?? Settings.ipAddress;

  nt4Connection.nt4Connect(Settings.ipAddress);

  await FieldImages.loadFields('assets/fields/');

  Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
  Size screenSize =
      primaryDisplay.size * (primaryDisplay.scaleFactor?.toDouble() ?? 1.0);

  await windowManager.setMinimumSize(screenSize * 0.60);
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
      windowButtonVisibility: false);

  await windowManager.show();
  await windowManager.focus();

  runApp(Elastic(version: packageInfo.version, preferences: preferences));
}

/// Makes a backup copy of the current shared preferences file.
Future<void> _backupPreferences(String appFolderPath) async {
  try {
    final String original = '$appFolderPath\\shared_preferences.json';
    final String backup = '$appFolderPath\\shared_preferences_backup.json';

    if (await File(backup).exists()) await File(backup).delete(recursive: true);
    await File(original).copy(backup);

    logger.info('Backup up shared_preferences.json to $backup');
  } catch (_) {
    /* Do nothing */
  }
}

/// Removes current version of shared_preferences file and restores previous
/// user settings from a backup file (if it exists).
Future<void> _restorePreferencesFromBackup(String appFolderPath) async {
  try {
    final String original = '$appFolderPath\\shared_preferences.json';
    final String backup = '$appFolderPath\\shared_preferences_backup.json';

    await File(original).delete(recursive: true);

    if (await File(backup).exists()) {
      // Check if current backup copy is not broken by looking for letters and "
      // symbol in it to replace it as an original Settings file
      final String preferences = await File(backup).readAsString();
      if (preferences.contains('"') && preferences.contains(RegExp('[A-z]'))) {
        logger.info('Restoring shared_preferences from backup file at $backup');
        await File(backup).copy(original);
      }
    }
  } catch (_) {
    /* Do nothing */
  }
}

class Elastic extends StatefulWidget {
  final SharedPreferences preferences;
  final String version;

  const Elastic({super.key, required this.version, required this.preferences});

  @override
  State<Elastic> createState() => _ElasticState();
}

class _ElasticState extends State<Elastic> {
  late Color teamColor = Color(
      widget.preferences.getInt(PrefKeys.teamColor) ?? Colors.blueAccent.value);

  @override
  Widget build(BuildContext context) {
    ThemeData theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: teamColor,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Elastic',
      theme: theme,
      home: DashboardPage(
        preferences: widget.preferences,
        version: widget.version,
        onColorChanged: (color) => setState(() {
          teamColor = color;
          widget.preferences.setInt(PrefKeys.teamColor, color.value);
        }),
      ),
    );
  }
}
