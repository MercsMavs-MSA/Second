import 'dart:convert';

import 'package:second/image_util.dart';
import 'package:second/util.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);
  final ValueNotifier<Color> accentColor = ValueNotifier(Colors.blue);
  final ValueNotifier<bool> lowResouceMode = ValueNotifier(false);

  void updateTheme(String mode) {
    themeMode.value = mode == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  void updateAccent(String name) {
    final colorMap = {
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purpleAccent[100],
    };
    accentColor.value = colorMap[name] ?? Colors.blue;
  }

  void updateLowResourceMode(bool isLowResource) {
    lowResouceMode.value = isLowResource;
  }
}

class SettingsManager {
  static const String _prefix = 'settings.';
  SharedPreferences? prefs;

  Map<String, dynamic> _defaultSettings = {};
  Map<String, Type> _developerOptions = {};

  SettingsManager._privateConstructor();
  static final SettingsManager _instance =
      SettingsManager._privateConstructor();
  factory SettingsManager() => _instance;

  static SettingsManager get getInstance => _instance;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    for (var entry in _defaultSettings.entries) {
      if (prefs == null || !prefs!.containsKey(_prefix + entry.key)) {
        await setValue(entry.key, entry.value);
      }
    }
    _defaultSettings = {
      'google.oauth_credentials': '{}',
      'google.sheet_id': '',
      'android.immersive': true,
      'android.absorbvolume': false,
      'app.loglevel': Level.info.value,
      'app.theme.mode': 'dark',
      'app.theme.accent': 'blue',
      'app.theme.logo': await assetPngToBase64(
        "assets/icons/punch_clock_240.png",
      ),
      'app.lowresources': false,
      'station.fixed': true,
      'station.locations': [],
      'station.location': null,
      'security.pin': '000000',
      'list.disable': false,
      'rfid.reader': 'hid',
      'rfid.hid.timeout': 0.2,
      'rfid.hid.eol': 'RETURN',
      'rfid.hid.format': 'decAscii',
      'backend.interval.activePull': 20,
      'backend.interval.activePush': 10,
      'backend.interval.inactivePull': 90,
      'backend.interval.inactivePush': 60,
      'backend.interval.activeCooldown': 60,
      'backend.interval.configsReload': 360,
    };

    _developerOptions = {
      'rfid.hid.timeout': double,
      'rfid.hid.eol': String,
      'rfid.hid.format': DataFormat,
      'backend.interval.activePull': int,
      'backend.interval.activePush': int,
      'backend.interval.inactivePull': int,
      'backend.interval.inactivePush': int,
      'backend.interval.activeCooldown': int,
      'backend.interval.configsReload': int,
    };
  }

  Map<String, Type> get developerOptions => _developerOptions;

  T? getDefault<T>(String key) {
    if (_defaultSettings.containsKey(key)) {
      return _defaultSettings[key];
    } else {
      return null;
    }
  }

  T? getValue<T>(String key) {
    String fullKey = _prefix + key;
    if (T == String) {
      return prefs?.getString(fullKey) as T?;
    } else if (T == bool) {
      return prefs?.getBool(fullKey) as T?;
    } else if (T == int) {
      return prefs?.getInt(fullKey) as T?;
    } else if (T == double) {
      return prefs?.getDouble(fullKey) as T?;
    } else if (T == List<String>) {
      return prefs?.getStringList(fullKey) as T?;
    }
    throw Exception('Unsupported type: $T');
  }

  dynamic getDynamic(String key) {
    String fullKey = _prefix + key;
    return prefs?.get(fullKey);
  }

  Future<void> setValue(String key, dynamic value) async {
    String fullKey = _prefix + key;
    if (value is String) {
      await prefs?.setString(fullKey, value);
    } else if (value is bool) {
      await prefs?.setBool(fullKey, value);
    } else if (value is int) {
      await prefs?.setInt(fullKey, value);
    } else if (value is double) {
      await prefs?.setDouble(fullKey, value);
    } else if (value is List<String>) {
      await prefs?.setStringList(fullKey, value);
    } else {
      return;
    }
  }

  Future<Map<String, dynamic>> exportSettings() async {
    Map<String, dynamic> settings = {};
    for (var key in _defaultSettings.keys) {
      // IMPORTANT: do not export anything that isn't a setting (ex. offline queues)
      settings[key] = getDynamic(key);
    }
    return settings;
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    for (var entry in settings.entries) {
      if (_defaultSettings.containsKey(entry.key)) {
        await setValue(entry.key, entry.value);
      }
    }
  }

  Future<String> exportToJson() async {
    final settings = await exportSettings();
    return jsonEncode(settings);
  }

  Future<void> importFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> settings = jsonDecode(jsonString);
      await importSettings(settings);
    } catch (e) {
      throw Exception('Invalid JSON format');
    }
  }
}
