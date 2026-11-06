import 'package:second/settings.dart';
import 'package:second/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import 'backend.dart';

class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({
    super.key,
    required this.backend,
    required this.settingsManager,
    required this.logger,
  });

  final AttendanceTrackerBackend backend;
  final SettingsManager settingsManager;
  final Logger logger;

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Options')),
      body: ListView.builder(
        itemCount: widget.settingsManager.developerOptions.length + 3,
        itemBuilder: (context, index) {
          if (index == 0) {
            return ListTile(
              tileColor: Theme.of(context).colorScheme.errorContainer,
              leading: Icon(
                Icons.info,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text('Warning'),
              subtitle: Text(
                'Changing these settings may cause unexpected behavior. Proceed with caution! A restart may be required for changes to take effect.',
              ),
            );
          }
          if (index == 1) {
            return ListTile(
              title: const Text("Log Level"),
              subtitle: Text(
                "Restart required to apply",
                style: TextStyle(color: Colors.orange),
              ),
              leading: const Icon(Icons.info),
              trailing: DropdownButton<Level>(
                items: Level.values
                    .where(
                      (level) =>
                          !level.toString().contains('verbose') &&
                          !level.toString().contains('wtf') &&
                          !level.toString().contains('off'),
                    )
                    .map((level) {
                      return DropdownMenuItem(
                        value: level,
                        child: Text(
                          level.toString().split('.').last.toUpperCase(),
                        ),
                      );
                    })
                    .toList(),
                value: Level.values.firstWhere(
                  (level) =>
                      level.value ==
                      (widget.settingsManager.getValue<int>("app.loglevel") ??
                          widget.settingsManager.getDefault<int>(
                            "app.loglevel",
                          )),
                  orElse: () => Level.info,
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      widget.settingsManager.setValue(
                        "app.loglevel",
                        value.value,
                      );
                    });
                  }
                },
              ),
            );
          }

          if (index == 2) {
            return ListTile(
              title: const Text("Force clock in all members"),
              subtitle: const Text(
                "All members will be checked in to 'Debug Location'",
                style: TextStyle(color: Colors.orange),
              ),
              leading: const Icon(Icons.system_security_update),
              onTap: () {
                for (Member member in widget.backend.attendance.value) {
                  widget.backend.clockIn(member.id, "Debug Location");
                }
              },
            );
          }

          index -= 3;
          return ListTile(
            minTileHeight: 64,
            leading: Icon(Icons.settings),
            title: Text(
              widget.settingsManager.developerOptions.keys.elementAt(index),
            ),
            trailing: switch (widget.settingsManager.developerOptions.values
                .elementAt(index)) {
              double => SizedBox(
                width: 180,
                child: TextFormField(
                  initialValue: widget.settingsManager
                      .getValue<double>(
                        widget.settingsManager.developerOptions.keys.elementAt(
                          index,
                        ),
                      )
                      .toString(),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Value',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final doubleValue = double.tryParse(value);
                    if (doubleValue != null) {
                      setState(() {
                        widget.settingsManager.setValue(
                          widget.settingsManager.developerOptions.keys
                              .elementAt(index),
                          doubleValue,
                        );
                      });
                    }
                  },
                ),
              ),
              int => SizedBox(
                width: 180,
                child: TextFormField(
                  initialValue: widget.settingsManager
                      .getValue<int>(
                        widget.settingsManager.developerOptions.keys.elementAt(
                          index,
                        ),
                      )
                      .toString(),
                  keyboardType: TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Value',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final doubleValue = int.tryParse(value);
                    if (doubleValue != null) {
                      setState(() {
                        widget.settingsManager.setValue(
                          widget.settingsManager.developerOptions.keys
                              .elementAt(index),
                          doubleValue,
                        );
                      });
                    }
                  },
                ),
              ),
              String => SizedBox(
                width: 180,
                child: TextFormField(
                  initialValue: widget.settingsManager.getValue<String>(
                    widget.settingsManager.developerOptions.keys.elementAt(
                      index,
                    ),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Value',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      widget.settingsManager.setValue(
                        widget.settingsManager.developerOptions.keys.elementAt(
                          index,
                        ),
                        value,
                      );
                    });
                  },
                ),
              ),
              DataFormat => SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.settingsManager.getValue<String>(
                    widget.settingsManager.developerOptions.keys.elementAt(
                      index,
                    ),
                  ),
                  items: DataFormat.values.map((format) {
                    return DropdownMenuItem<String>(
                      value: format.toString().split('.').last,
                      child: Text(format.toString().split('.').last),
                    );
                  }).toList(),
                  decoration: const InputDecoration(
                    labelText: 'Value',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      widget.settingsManager.setValue(
                        widget.settingsManager.developerOptions.keys.elementAt(
                          index,
                        ),
                        value,
                      );
                    });
                  },
                ),
              ),
              Type() => throw UnimplementedError(
                "Type ${widget.settingsManager.developerOptions.values.elementAt(index)} is not a supported DevOpt",
              ),
            },
          );
        },
      ),
    );
  }
}
