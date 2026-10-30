import 'dart:convert';
import 'dart:io';

import 'package:confetti/confetti.dart';
import 'package:easy_stepper/easy_stepper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:lottie/lottie.dart';
import 'package:second/backend.dart';
import 'package:second/main.dart';
import 'package:second/settings.dart';
import 'package:second/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class IntroductionScreen extends StatefulWidget {
  final SettingsManager settingsManager;
  final ThemeController themeController;
  final Logger logger;
  final ConfettiController greenCenterConfetti;
  final VoidCallback? onComplete;

  const IntroductionScreen({
    super.key,
    required this.settingsManager,
    required this.themeController,
    required this.logger,
    required this.greenCenterConfetti,
    this.onComplete,
  });

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  int _currentStep = 0;
  final _sheetIdController = TextEditingController();
  String _enteredPin = '';
  String? _confirmPin;
  bool _hasCredentials = false;

  // Connectivity check state
  bool _isTestingConnection = false;
  bool? _connectionSuccess;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _sheetIdController.text =
        widget.settingsManager.getValue<String>('google.sheet_id') ?? '';
    final creds =
        widget.settingsManager.getValue<String>('google.oauth_credentials');
    _hasCredentials = creds != null && creds.isNotEmpty && creds != '{}';
  }

  Future<void> _complete() async {
    await widget.settingsManager.setValue('app.firstRun', false);
    if (!mounted) return;
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomePage(
            widget.themeController,
            widget.settingsManager,
            widget.logger,
            widget.greenCenterConfetti,
          ),
        ),
      );
    }
  }

  Future<void> _uploadCredentials() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result.isEmpty) return;
      String contents;
      if (kIsWeb) {
        final bytes = await result.first.readAsBytes();
        contents = utf8.decode(bytes);
      } else {
        final path = result.first.path;
        if (path == null) return;
        final file = File(path);
        contents = await file.readAsString();
      }
      jsonDecode(contents);
      await widget.settingsManager.setValue('google.oauth_credentials', contents);
      setState(() {
        _hasCredentials = true;
        _connectionSuccess = null;
        _connectionError = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credentials uploaded')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid JSON file')),
        );
      }
    }
  }

  Future<void> _restoreFromBackup() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result.isEmpty) return;

      String contents;
      if (kIsWeb) {
        final bytes = await result.first.readAsBytes();
        contents = utf8.decode(bytes);
      } else {
        final path = result.first.path;
        if (path == null) return;
        final file = File(path);
        contents = await file.readAsString();
      }

      await widget.settingsManager.importFromJson(contents);

      _sheetIdController.text =
          widget.settingsManager.getValue<String>('google.sheet_id') ?? '';
      final creds =
          widget.settingsManager.getValue<String>('google.oauth_credentials');

      setState(() {
        _hasCredentials = creds != null && creds.isNotEmpty && creds != '{}';
        _currentStep = 2; // Jump to Connectivity Check
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings restored from backup. Testing connection...'),
            backgroundColor: Colors.green,
          ),
        );
        _testConnection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore settings: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionError = null;
      _connectionSuccess = null;
    });

    try {
      final sheetId = _sheetIdController.text.trim();
      final credsJson =
          widget.settingsManager.getValue<String>('google.oauth_credentials') ??
              '{}';

      if (sheetId.isEmpty) {
        throw Exception('Please enter a Google Sheet ID in the Sheets Configuration step.');
      }
      if (credsJson.isEmpty || credsJson == '{}') {
        throw Exception('Please upload OAuth credentials JSON in the Sheets Configuration step.');
      }

      if (!kIsWeb) {
        try {
          final result = await InternetAddress.lookup('google.com')
              .timeout(const Duration(seconds: 5));
          if (result.isEmpty || result[0].rawAddress.isEmpty) {
            throw Exception('No internet connection');
          }
        } catch (_) {
          throw Exception('No internet connection');
        }
      }

      final backend = AttendanceTrackerBackend(widget.logger);
      await backend.initialize(sheetId, credsJson);

      if (backend.googleConnected.value == true) {
        setState(() {
          _isTestingConnection = false;
          _connectionSuccess = true;
        });
      } else {
        throw Exception(
            'Could not connect to Google Sheet. Check Sheet ID and credentials.');
      }
    } catch (e) {
      setState(() {
        _isTestingConnection = false;
        _connectionSuccess = false;
        _connectionError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _buildStepper() {
    final theme = Theme.of(context);
    final stepTitles = ['Welcome', 'Sheets', 'Connectivity', 'PIN', 'Help'];

    return EasyStepper(
      activeStep: _currentStep,
      fitWidth: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      internalPadding: 0,
      showLoadingAnimation: false,
      showStepBorder: false,
      activeStepBorderType: BorderType.normal,
      unreachedStepBorderType: BorderType.normal,
      finishedStepBorderType: BorderType.normal,
      lineStyle: LineStyle(
        lineType: LineType.normal,
        lineThickness: 2,
        lineSpace: 8,
        lineLength: 56,
        activeLineColor: theme.colorScheme.surfaceContainerHigh,
        finishedLineColor: theme.colorScheme.primary,
        unreachedLineColor: theme.colorScheme.surfaceContainerHigh,
      ),
      stepShape: StepShape.circle,
      stepRadius: 18,
      activeStepBorderColor: theme.colorScheme.tertiary,
      activeStepIconColor: theme.colorScheme.primary,
      activeStepBackgroundColor: theme.colorScheme.tertiary,
      finishedStepBackgroundColor: theme.colorScheme.primary,
      finishedStepIconColor: theme.colorScheme.onPrimary,
      finishedStepTextColor: theme.colorScheme.primary,
      activeStepTextColor: theme.colorScheme.tertiary,
      unreachedStepBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      unreachedStepTextColor: theme.colorScheme.onSurfaceVariant,
      onStepReached: (index) {
        if (index < _currentStep) {
          setState(() {
            _currentStep = index;
          });
        }
      },
      steps: [
        for (int i = 0; i < stepTitles.length; i++)
          EasyStep(
            customStep: i < _currentStep
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: theme.colorScheme.onPrimary,
                  )
                : Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == _currentStep
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i <= _currentStep
                          ? theme.colorScheme.onTertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            title: stepTitles[i],
          ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Lottie.asset(
                "assets/animations/introduction.json",
                fit: BoxFit.contain,
              ),
            ),
            Text(
              'Welcome to Second!',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'This app helps track attendance for your team. Let\'s go through the initial setup.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _restoreFromBackup,
              icon: const Icon(Icons.restore),
              label: const Text('Restore from Backup'),
            ),
            const SizedBox(height: 12),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Google Sheets Configuration',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Configure your Google Sheets integration to sync attendance data.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _sheetIdController,
              decoration: const InputDecoration(
                labelText: 'Google Sheet ID',
                hintText: 'e.g. 1BxiMVs0XRra5nFMdACg_q3v6JVY-...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _uploadCredentials,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _hasCredentials
                        ? 'Replace Credentials'
                        : 'Upload OAuth Credentials JSON',
                  ),
                ),
                const SizedBox(width: 8),
                if (_hasCredentials)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Connectivity Check',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Verify that your internet connection and Google Sheets configuration are operational.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_isTestingConnection) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Testing connection...'),
            ] else if (_connectionSuccess == true) ...[
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                'Connected Successfully!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text('Google Sheets integration is online and ready.'),
            ] else if (_connectionError != null) ...[
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Connection Failed',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _connectionError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else ...[
              const Icon(Icons.network_check, size: 64),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Connection Test'),
              ),
            ],
            if (!_isTestingConnection && _connectionSuccess != true) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _confirmPin == null
                  ? 'Set a PIN for admin settings'
                  : 'Confirm your PIN',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
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
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            PinKeypad(
              onKeyPressed: (key) {
                if (_enteredPin.length < 6) {
                  setState(() {
                    _enteredPin += key;
                  });
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
        );
      case 4:
        final theme = Theme.of(context);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.celebration,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You\'re All Set!',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Second is configured and ready to track attendance for your team.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Help & Resources',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(120),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.menu_book),
                      ),
                      title: const Text(
                        'Documentation',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Guides, setup instructions, and feature overview',
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 20),
                      onTap: () {
                        launchUrl(
                          Uri.parse('https://mercsmavs-msa.github.io/Second'),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor:
                            theme.colorScheme.onSecondaryContainer,
                        child: const Icon(Icons.code),
                      ),
                      title: const Text(
                        'GitHub Repository',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Source code, issues, and release notes',
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 20),
                      onTap: () {
                        launchUrl(
                          Uri.parse('https://github.com/MercsMavs-MSA/Second'),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'About',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(120),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        foregroundColor: theme.colorScheme.onTertiaryContainer,
                        child: const Icon(Icons.info_outline),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SECOND Attendance Tracker',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'An open-source FRC & FTC robotics attendance tracker designed for team check-ins, RFID badging, and automated Google Sheets synchronization.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'GPL-3.0 License • Copyright © 2025-2026 Kevin Ahr',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Wizard'),
      ),
      body: Column(
        children: [
          _buildStepper(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildStepContent(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                if (_currentStep > 0)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _currentStep -= 1;
                      });
                    },
                    child: const Text('Back'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    if (_currentStep == 1) {
                      widget.settingsManager.setValue(
                        'google.sheet_id',
                        _sheetIdController.text,
                      );
                    }
                    if (_currentStep == 3) {
                      if (_enteredPin.length == 6 && _confirmPin == null) {
                        setState(() {
                          _confirmPin = _enteredPin;
                          _enteredPin = '';
                        });
                        return;
                      } else if (_enteredPin.length == 6 &&
                          _confirmPin != null) {
                        if (_confirmPin == _enteredPin) {
                          widget.settingsManager.setValue(
                            'security.pin',
                            _enteredPin,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('PINs do not match'),
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                          );
                          setState(() {
                            _enteredPin = '';
                            _confirmPin = null;
                          });
                          return;
                        }
                      } else {
                        return;
                      }
                    }
                    if (_currentStep < 4) {
                      final nextStep = _currentStep + 1;
                      setState(() {
                        _currentStep = nextStep;
                      });
                      if (nextStep == 2) {
                        _testConnection();
                      }
                    } else {
                      _complete();
                    }
                  },
                  child: Text(_currentStep == 4 ? 'Finish' : 'Continue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
