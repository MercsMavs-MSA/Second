import 'dart:convert';
import 'dart:io';

import 'package:second/android_lockdown.dart';
import 'package:second/auto_checkout.dart';
import 'package:second/backend.dart';
import 'package:second/settings.dart';
import 'package:second/string_ext.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import 'dev_opts_page.dart';
import 'log_inst.dart';

class PinKeypad extends StatelessWidget {
  final Function(String) onKeyPressed;
  final Function() onClear;
  final Function() onBackspace;

  const PinKeypad({
    super.key,
    required this.onKeyPressed,
    required this.onClear,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '1'),
            const SizedBox(width: 8),
            _buildKey(context, '2'),
            const SizedBox(width: 8),
            _buildKey(context, '3'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '4'),
            const SizedBox(width: 8),
            _buildKey(context, '5'),
            const SizedBox(width: 8),
            _buildKey(context, '6'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '7'),
            const SizedBox(width: 8),
            _buildKey(context, '8'),
            const SizedBox(width: 8),
            _buildKey(context, '9'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, 'C', onPressed: onClear),
            const SizedBox(width: 8),
            _buildKey(context, '0'),
            const SizedBox(width: 8),
            _buildKey(context, '⌫', onPressed: onBackspace),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed ?? () => onKeyPressed(label),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        fixedSize: const Size(64, 64),
        padding: const EdgeInsets.all(8),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(
    this.themeController,
    this.logger,
    this.backend, {
    super.key,
  });

  final ThemeController themeController;
  final Logger logger;
  final AttendanceTrackerBackend backend;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsManager = SettingsManager();
  final _oauthController = TextEditingController();
  final _sheetIdController = TextEditingController();
  final _pinController = TextEditingController();
  String? _currentTheme;
  String? _currentAccentColor;
  String _enteredPin = '';
  bool _isPinVerified = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsManager.init();
    _oauthController.text =
        (_settingsManager.getValue<String>('google.oauth_credentials')) ?? '';
    _sheetIdController.text =
        (_settingsManager.getValue<String>('google.sheet_id')) ?? '';
    _pinController.text =
        (_settingsManager.getValue<String>('security.pin')) ?? '';
    _currentTheme =
        (_settingsManager.getValue<String>('app.theme.mode')) ?? 'light';
    _currentAccentColor =
        (_settingsManager.getValue<String>('app.theme.accent')) ?? 'blue';
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    final storedPin = _settingsManager.getValue<String>('security.pin') ?? '';
    return storedPin.isEmpty || storedPin == enteredPin;
  }

  Widget _buildPinEntry(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings Lock')),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Flex(
              direction: orientation == Orientation.portrait
                  ? Axis.vertical
                  : Axis.horizontal,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Enter PIN',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        6,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index < _enteredPin.length
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: orientation == Orientation.portrait ? 0 : 32,
                  height: orientation == Orientation.portrait ? 32 : 0,
                ),
                PinKeypad(
                  onKeyPressed: (key) async {
                    if (_enteredPin.length < 6) {
                      setState(() {
                        _enteredPin += key;
                      });
                      if (_enteredPin.length == 6) {
                        if (await _verifyPin(_enteredPin)) {
                          setState(() {
                            _isPinVerified = true;
                          });
                          widget.logger.i(
                            "Successful entry into settings dialog by admin",
                          );
                        } else {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Invalid PIN'),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          );
                          setState(() {
                            _enteredPin = '';
                          });
                        }
                      }
                    }
                  },
                  onClear: () {
                    setState(() {
                      _enteredPin = '';
                    });
                  },
                  onBackspace: () {
                    if (_enteredPin.isNotEmpty) {
                      setState(() {
                        _enteredPin = _enteredPin.substring(
                          0,
                          _enteredPin.length - 1,
                        );
                      });
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editAndroidLockdown(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return AndroidLockdownPage();
        },
      ),
    );
  }

  Future<void> _editSheetId(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Sheet ID'),
        content: TextField(
          controller: _sheetIdController,
          decoration: const InputDecoration(hintText: 'Enter Sheet ID'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _settingsManager.setValue(
                'google.sheet_id',
                _sheetIdController.text,
              );
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoogleOauth(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google OAuth Credentials'),
        content: const Text('Select your Google OAuth JSON credentials file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  withData: true, // needed for web
                );
                if (result == null) return;

                String contents;
                if (kIsWeb) {
                  // On web, use in-memory bytes
                  final bytes = result.files.single.bytes;
                  if (bytes == null) return;
                  contents = utf8.decode(bytes);
                } else {
                  // On desktop/mobile, read from file path
                  final path = result.files.single.path;
                  if (path == null) return;
                  final file = File(path);
                  contents = await file.readAsString();
                }

                // Validate JSON
                jsonDecode(contents);

                await _settingsManager.setValue(
                  'google.oauth_credentials',
                  contents,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid JSON file')),
                  );
                }
              }
            },
            child: const Text('Select File'),
          ),
        ],
      ),
    );
  }

  Future<void> _editAppTheme(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'light', label: Text('Light')),
                ButtonSegment(value: 'dark', label: Text('Dark')),
              ],
              selected: {_currentTheme ?? 'dark'},
              onSelectionChanged: (newSelection) {
                final selectedTheme = newSelection.first;
                setState(() => _currentTheme = selectedTheme);
                _settingsManager.setValue('app.theme.mode', selectedTheme);
                widget.themeController.updateTheme(selectedTheme);
              },
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "red");
                      _settingsManager.setValue('app.theme.accent', "red");
                      widget.themeController.updateAccent("red");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.red,
                    ),
                    child: _currentAccentColor == "red"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "orange");
                      _settingsManager.setValue('app.theme.accent', "orange");
                      widget.themeController.updateAccent("orange");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.orange,
                    ),
                    child: _currentAccentColor == "orange"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "yellow");
                      _settingsManager.setValue('app.theme.accent', "yellow");
                      widget.themeController.updateAccent("yellow");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.yellow,
                    ),
                    child: _currentAccentColor == "yellow"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "green");
                      _settingsManager.setValue('app.theme.accent', "green");
                      widget.themeController.updateAccent("green");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.green,
                    ),
                    child: _currentAccentColor == "green"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "blue");
                      _settingsManager.setValue('app.theme.accent', "blue");
                      widget.themeController.updateAccent("blue");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.blue,
                    ),
                    child: _currentAccentColor == "blue"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentAccentColor = "purple");
                      _settingsManager.setValue('app.theme.accent', "purple");
                      widget.themeController.updateAccent("purple");
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.purple,
                    ),
                    child: _currentAccentColor == "purple"
                        ? Icon(Icons.check, color: Colors.black)
                        : Icon(Icons.circle, color: Colors.transparent),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<void> _editAppLogo(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("App Logo"),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                base64.decode(
                  _settingsManager.getValue<String>("app.theme.logo") ??
                      _settingsManager.getDefault<String>("app.theme.logo")!,
                ),
                height: 128,
              ),
              SizedBox(height: 8.0),
              ElevatedButton.icon(
                icon: Icon(Icons.upload),
                label: Text("Upload Image"),
                onPressed: () async {
                  try {
                    final result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
                      withData: true, // required for web
                    );
                    if (result == null) return;

                    String base64Image;
                    if (kIsWeb) {
                      // Web → use in-memory bytes
                      final bytes = result.files.single.bytes;
                      if (bytes == null) return;
                      base64Image = base64Encode(bytes);
                    } else {
                      // Desktop/Mobile → use file path
                      final path = result.files.single.path;
                      if (path == null) return;
                      final file = File(path);
                      final bytes = await file.readAsBytes();
                      base64Image = base64Encode(bytes);
                    }

                    if (!context.mounted) return;
                    setState(() {
                      _settingsManager.setValue("app.theme.logo", base64Image);
                    });
                  } catch (e, st) {
                    loggerInstance?.e("Failed to import image: $e\n$st");
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to import image')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<void> _editStationLocation(BuildContext context) async {
    bool isFixed = _settingsManager.getValue<bool>("station.fixed") ?? false;
    final locationController = TextEditingController(
      text: _settingsManager.getValue<String>("station.location") ?? "",
    );
    final newLocationController = TextEditingController();
    List<String> locations =
        _settingsManager.getValue<List<String>>("station.locations") ??
        ["Shop"];

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Station Settings'),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 400,
            // Use a constrained box instead of SingleChildScrollView
            // so the ReorderableListView can scroll properly
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('Fixed Station'),
                  subtitle: const Text('Permanent location?'),
                  value: isFixed,
                  onChanged: (value) {
                    setState(() {
                      isFixed = value ?? false;
                    });
                  },
                ),

                if (isFixed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter Fixed Station Location',
                        labelText: 'Fixed Location',
                      ),
                    ),
                  ),

                if (!isFixed) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Mobile Station Locations',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Reorderable list area
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: locations.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = locations.removeAt(oldIndex);
                          locations.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final location = locations[index];
                        return ListTile(
                          key: ValueKey(location),
                          title: Text(location),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                locations.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),

                  // Add new location input
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newLocationController,
                            decoration: const InputDecoration(
                              hintText: 'Add New Location',
                              labelText: 'New Location',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (newLocationController.text.isNotEmpty) {
                              setState(() {
                                locations.add(newLocationController.text);
                                newLocationController.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (newLocationController.text.isNotEmpty) {
                locations.add(newLocationController.text);
              }
              await _settingsManager.setValue(
                'station.location',
                locationController.text,
              );
              await _settingsManager.setValue('station.fixed', isFixed);
              await _settingsManager.setValue(
                'station.locations',
                isFixed ? [] : locations,
              );
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPin(BuildContext context) async {
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings PIN'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: _pinController,
            decoration: const InputDecoration(
              hintText: 'Enter new PIN',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            validator: (value) {
              if (value == null || value.length != 6) {
                return 'PIN must be 6 digits';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                await _settingsManager.setValue(
                  'security.pin',
                  _pinController.text,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRfidSettings(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text("RFID Reader"),
            content: SingleChildScrollView(
              // mainAxisSize: MainAxisSize.min,
              child: Column(
                children: [
                  SegmentedButton(
                    segments: [
                      ButtonSegment(
                        value: "hid",
                        label: Text("HID"),
                        icon: Icon(Icons.keyboard),
                      ),
                      ButtonSegment(
                        value: "disable",
                        label: Text("Disabled"),
                        icon: Icon(Icons.block),
                      ),
                    ],
                    selected: {
                      _settingsManager.getValue<String>("rfid.reader") ??
                          _settingsManager.getDefault<String>("rfid.reader")!,
                    },
                    onSelectionChanged: (selection) {
                      setState(() {
                        _settingsManager.setValue(
                          "rfid.reader",
                          selection.first,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportSettings(BuildContext context) async {
    try {
      final json = await _settingsManager.exportToJson();

      // On web/mobile, FilePicker has handle bytes directly
      if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
        final path = await FilePicker.saveFile(
          dialogTitle: 'Save Settings',
          fileName: 'settings.json',
          bytes: Uint8List.fromList(json.codeUnits),
        );
        if (path == null) return; // user cancelled
      } else {
        // On desktop, manually write to the selected path
        final path = await FilePicker.saveFile(
          dialogTitle: 'Save Settings',
          fileName: 'settings.json',
        );
        if (path == null) return; // user cancelled
        final file = File(path);
        await file.writeAsString(json);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings exported successfully')),
      );
    } catch (e, st) {
      widget.logger.e("Failed to export settings $e\n$st");
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export settings: $e')));
    }
  }

  Future<void> _importSettings(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: "Choose Settings File",
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true, // important for web
      );
      if (result == null) return;

      String json;
      if (kIsWeb) {
        // Web → use in-memory bytes
        final bytes = result.files.single.bytes;
        if (bytes == null) return;
        json = utf8.decode(bytes);
      } else {
        // Desktop/Mobile → use file path
        final path = result.files.single.path;
        if (path == null) return;
        final file = File(path);
        json = await file.readAsString();
      }

      await _settingsManager.importFromJson(json);
      await _loadSettings();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings imported successfully')),
      );
    } catch (e, st) {
      loggerInstance?.e('Settings import failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to import settings')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPinVerified) {
      return _buildPinEntry(context);
    }

    return Material(
      child: SafeArea(
        top: false,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "ADMIN",
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    if (!kIsWeb && Platform.isAndroid)
                      ListTile(
                        tileColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        title: Text("Android Device Lockdown"),
                        subtitle: const Text(
                          "Lockdown the device for kiosk use.",
                        ),
                        leading: const Icon(Icons.android),
                        trailing: IconButton(
                          onPressed: () => _editAndroidLockdown(context),
                          icon: const Icon(Icons.edit),
                        ),
                      ),
                    ListTile(
                      title: const Text("Google OAuth JSON Credentials"),
                      subtitle: const Text(
                        "The JSON file containing your Google OAuth credentials for accessing the Google Sheets API.",
                      ),
                      leading: const Icon(Icons.cloud),
                      trailing: IconButton(
                        onPressed: () => _editGoogleOauth(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text('Google Sheet Spreadsheet ID'),
                      subtitle: const Text(
                        'The ID of the Google Sheet used for attendance tracking.',
                      ),
                      leading: const Icon(Icons.pages),
                      trailing: IconButton(
                        onPressed: () => _editSheetId(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text("App Theme"),
                      subtitle: Text(
                        "Mode: ${_currentTheme?.capitalize() ?? ''}, Accent: ${_currentAccentColor?.capitalize() ?? ''}",
                      ),
                      leading: const Icon(Icons.color_lens),
                      trailing: IconButton(
                        onPressed: () => _editAppTheme(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text("App Logo"),
                      subtitle: Text("Logo used in the home screen."),
                      leading: const Icon(Icons.image),
                      trailing: IconButton(
                        onPressed: () => _editAppLogo(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: Text("Low-Resource Mode"),
                      subtitle: Text(
                        "Limited animations and effects for low-resource devices",
                      ),
                      leading: Icon(Icons.bolt),
                      trailing: Switch(
                        value:
                            _settingsManager.getValue<bool>(
                              "app.lowresources",
                            ) ??
                            false,
                        onChanged: (value) {
                          setState(() {
                            _settingsManager.setValue(
                              'app.lowresources',
                              value,
                            );
                            widget.themeController.updateLowResourceMode(value);
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text("Station Location Options"),
                      subtitle: const Text(
                        "Options for if the station is fixed, or floating, and the locations available.",
                      ),
                      leading: const Icon(Icons.location_on),
                      trailing: IconButton(
                        onPressed: () => _editStationLocation(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text("Reset PIN"),
                      subtitle: const Text(
                        "Reset the PIN used for accessing admin settings.",
                      ),
                      leading: const Icon(Icons.lock),
                      trailing: IconButton(
                        onPressed: () => _resetPin(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: Text("Require PIN for Admin Sign-in"),
                      subtitle: Text(
                        "Request the PIN if an ADMIN user signs in/out without a badge",
                      ),
                      leading: Icon(Icons.pin),
                      trailing: Switch(
                        value:
                            _settingsManager.getValue<bool>(
                              "security.pin.require.admin",
                            ) ??
                            true,
                        onChanged: (value) {
                          setState(() {
                            _settingsManager.setValue(
                              "security.pin.require.admin",
                              value,
                            );
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("Require PIN for Mentor Sign-in"),
                      subtitle: Text(
                        "Request the PIN if a MENTOR user signs in/out without a badge",
                      ),
                      leading: Icon(Icons.pin),
                      trailing: Switch(
                        value:
                            _settingsManager.getValue<bool>(
                              "security.pin.require.mentor",
                            ) ??
                            false,
                        onChanged: (value) {
                          setState(() {
                            _settingsManager.setValue(
                              "security.pin.require.mentor",
                              value,
                            );
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("Require PIN for Student Sign-in"),
                      subtitle: Text(
                        "Request the PIN if a STUDENT user signs in/out without a badge",
                      ),
                      leading: Icon(Icons.pin),
                      trailing: Switch(
                        value:
                            _settingsManager.getValue<bool>(
                              "security.pin.require.student",
                            ) ??
                            false,
                        onChanged: (value) {
                          setState(() {
                            _settingsManager.setValue(
                              "security.pin.require.student",
                              value,
                            );
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("Disable Non-RFID sign in"),
                      subtitle: Text("Forces members to sign in using RFID."),
                      leading: Icon(Icons.menu_book),
                      trailing: Switch(
                        value:
                            _settingsManager.getValue<bool>("list.disable") ??
                            false,
                        onChanged: (value) {
                          setState(() {
                            _settingsManager.setValue("list.disable", value);
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("RFID Card Reader Settings"),
                      subtitle: Text("Settings for the RFID Card Reader"),
                      leading: Icon(Icons.contactless),
                      trailing: IconButton(
                        onPressed: () => _editRfidSettings(context),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text("Auto Checkout"),
                      subtitle: const Text(
                        "Options for configuring auto-checkout per day of the week",
                      ),
                      leading: const Icon(Icons.access_time_filled),
                      trailing: IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  AutoClockOutSettings(backend: widget.backend),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                    ListTile(
                      title: const Text("Export Settings"),
                      subtitle: const Text(
                        "Your Google OAuth keys will be saved as PLAIN TEXT",
                        style: TextStyle(color: Colors.red),
                      ),
                      leading: const Icon(Icons.download),
                      trailing: IconButton(
                        onPressed: () => _exportSettings(context),
                        icon: const Icon(Icons.downloading),
                      ),
                    ),
                    ListTile(
                      title: const Text("Import Settings"),
                      subtitle: const Text("Import settings from JSON file"),
                      leading: const Icon(Icons.upload),
                      trailing: IconButton(
                        onPressed: () => _importSettings(context),
                        icon: const Icon(Icons.upload_file),
                      ),
                    ),
                    ListTile(
                      title: const Text("Developer Options"),
                      subtitle: const Text("Not recommended for most users"),
                      leading: const Icon(Icons.developer_mode),
                      trailing: IconButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              icon: Icon(Icons.warning_rounded, size: 128),
                              title: const Text('Warning'),
                              content: const Text(
                                'Using developer options may cause unexpected behavior, and is not supported. Proceed with caution.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DeveloperOptionsPage(
                                              settingsManager: _settingsManager,
                                              logger: widget.logger,
                                            ),
                                      ),
                                    );
                                  },
                                  child: Text("I Understand"),
                                ),
                              ],
                            ),
                          );
                        },

                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
