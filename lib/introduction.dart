import 'dart:convert';
import 'dart:io';

import 'package:confetti/confetti.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:lottie/lottie.dart';
import 'package:second/main.dart';
import 'package:second/settings.dart';
import 'package:second/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class IntroductionScreen extends StatefulWidget {
  final SettingsManager settingsManager;
  final ThemeController themeController;
  final Logger logger;
  final ConfettiController greenCenterConfetti;

  const IntroductionScreen({
    super.key,
    required this.settingsManager,
    required this.themeController,
    required this.logger,
    required this.greenCenterConfetti,
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

  @override
  void initState() {
    super.initState();
    _sheetIdController.text = widget.settingsManager.getValue<String>('google.sheet_id') ?? '';
    final creds = widget.settingsManager.getValue<String>('google.oauth_credentials');
    _hasCredentials = creds != null && creds.isNotEmpty && creds != '{}';
  }

  Future<void> _complete() async {
    await widget.settingsManager.setValue('app.firstRun', false);
    if (!mounted) return;
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

  Future<void> _uploadCredentials() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.isEmpty) return;
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

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: Lottie.asset("assets/animations/introduction.json", fit: BoxFit.contain)),
            Text(
              'Welcome to Second!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text(
              'This app helps track attendance for your team. Let\'s go through the initial setup.',
              style: TextStyle(fontSize: 16),
            ),
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
            const SizedBox(height: 16),
            const Text('Configure Google Sheets integration'),
            const SizedBox(height: 16),
            TextField(
              controller: _sheetIdController,
              decoration: const InputDecoration(
                labelText: 'Google Sheet ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _uploadCredentials,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_hasCredentials ? 'Replace Credentials' : 'Upload OAuth Credentials JSON'),
                ),
                const SizedBox(width: 8),
                if (_hasCredentials)
                  Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          ],
        );
      case 2:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _confirmPin == null ? 'Set a PIN for admin settings' : 'Confirm your PIN',
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
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Help & Repository',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text('Need help?'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                launchUrl(Uri.parse('https://github.com/MercsMavs-MSA/Second'));
              },
              icon: const Icon(Icons.code),
              label: const Text('GitHub Repository'),
            ),
            const SizedBox(height: 16),
            const Text('You\'re all set! Click Finish to get started.'),
          ],
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              height: 70,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 16,
                    left: 40,
                    right: 40,
                    child: Row(
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          Expanded(
                            child: Divider(
                              color: i < _currentStep
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHigh,
                              thickness: 2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 0; i < 4; i++) ...[
                        Column(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: i <= _currentStep
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHigh,
                              foregroundColor: i <= _currentStep
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                              child: Text('${i + 1}', style: const TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 70,
                              child: Text(
                                ['Welcome', 'Sheets', 'PIN', 'Help'][i],
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
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
                      widget.settingsManager.setValue('google.sheet_id', _sheetIdController.text);
                    }
                    if (_currentStep == 2) {
                      if (_enteredPin.length == 6 && _confirmPin == null) {
                        setState(() {
                          _confirmPin = _enteredPin;
                          _enteredPin = '';
                        });
                        return;
                      } else if (_enteredPin.length == 6 && _confirmPin != null) {
                        if (_confirmPin == _enteredPin) {
                          widget.settingsManager.setValue('security.pin', _enteredPin);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('PINs do not match'),
                              backgroundColor: Theme.of(context).colorScheme.error,
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
                    if (_currentStep < 3) {
                      setState(() {
                        _currentStep += 1;
                      });
                    } else {
                      _complete();
                    }
                  },
                  child: Text(_currentStep == 3 ? 'Finish' : 'Continue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
