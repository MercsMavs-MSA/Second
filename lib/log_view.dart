import 'package:second/log_printer.dart';
import 'package:second/settings.dart';
import 'package:second/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:second/widgets.dart';

class LoggerView extends StatefulWidget {
  const LoggerView({super.key, required this.settings});

  final SettingsManager settings;

  @override
  State<LoggerView> createState() => _LoggerViewState();
}

class _LoggerViewState extends State<LoggerView> {
  String _enteredPin = '';
  bool _isPinVerified = false;

  String levelToEmoji(Level level) {
    switch (level) {
      case Level.trace:
        return '🔍';
      case Level.debug:
        return '🐛';
      case Level.info:
        return 'ℹ️';
      case Level.warning:
        return '⚠️';
      case Level.error:
        return '❌';
      case Level.fatal:
        return '💀';
      default:
        return '';
    }
  }

  Future<bool> _verifyPin(String enteredPin) async {
    final storedPin = widget.settings.getValue<String>('security.pin') ?? '';
    return storedPin.isEmpty || storedPin == enteredPin;
  }

  Widget _buildPinEntry(BuildContext context) {
    return OrientationBuilder(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Log Viewer"),
        actions: [
          if (_isPinVerified)
            IconButton(
              icon: Icon(Icons.delete_sweep),
              onPressed: () {
                BoundedMemoryPrinter.logs.value = [];
              },
            ),
        ],
      ),
      body: !_isPinVerified
          ? _buildPinEntry(context)
          : ValueListenableBuilder(
              valueListenable: BoundedMemoryPrinter.logs,
              builder: (context, value, child) {
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Text(
                        levelToEmoji(value.reversed.elementAt(index).level),
                        style: TextStyle(fontSize: 20),
                      ),
                      title: Text(
                        "${value.reversed.elementAt(index).time} - ${value.reversed.elementAt(index).level.toString().split('.').last.toUpperCase()}",
                      ),
                      subtitle: Text(value.reversed.elementAt(index).message),
                      tileColor: index % 2 == 1
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : null,
                    );
                  },
                );
              },
            ),
    );
  }
}
