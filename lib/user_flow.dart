import 'package:glob/glob.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:second/backend.dart';
import 'package:second/message_board_loader.dart';
import 'package:second/passwords.dart';
import 'package:second/settings.dart';
import 'package:second/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';

bool filterTarget(Iterable<String>? groups, String id, List<String> targets) {
  if ((groups??[]).contains("skip-messageboard")) {return false;}

  for (final group in groups ?? []) {
    if (targets.contains(group) || targets.isEmpty) {
      return true;
    }
  }
  for (final target in targets) {
    if (Glob(target).matches(id)) {
      return true;
    }
  }
  return false;
}

List<MessageBoardEntry> myMessages(
  Iterable<String>? groups,
  String id,
  List<MessageBoardEntry> entries,
) {
  List<MessageBoardEntry> newEntries = [];
  for (final entry in entries) {
    if (filterTarget(groups, id, entry.targets)) {
      newEntries.add(entry);
    }
  }
  return newEntries;
}

class UserFlow extends StatefulWidget {
  final Member user;
  final AttendanceTrackerBackend backend;
  final bool fromRfid;
  final bool requirePinEntry;
  final String? fixedLocation;
  final List<String>? allowedLocations;
  final bool fixed;

  const UserFlow(
    this.user,
    this.backend, {
    super.key,
    this.fromRfid = false,
    this.requirePinEntry = true,
    this.fixedLocation,
    this.allowedLocations,
    this.fixed = false,
  });

  @override
  State<UserFlow> createState() => _UserFlowState();
}

class _UserFlowState extends State<UserFlow> with TickerProviderStateMixin {
  final _settingsManager = SettingsManager();
  String _enteredPin = '';
  bool _isPinVerified = false;
  bool _readMessages = false;
  String? _selectedLocation;
  bool _isSettingPin = false;
  bool _isResettingPin = false;
  String _newPin = '';
  String _pinError = '';
  bool _isMessageTimeoutCanceled = false;
  ValueNotifier<bool> isTimerRunning = ValueNotifier(true);

  int _page = 0;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _page = 0;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _selectedLocation = widget.allowedLocations?.first;
    _loadSettings();
    if ((widget.user.passwordHash == null ||
            !isValidHash(widget.user.passwordHash!)) &&
        widget.requirePinEntry) {
      _isSettingPin = true;
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await _settingsManager.init();
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    return widget.user.passwordHash == hashPin(enteredPin);
  }

  Widget _buildPinSetter(BuildContext context) {
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
                    _isResettingPin ? "Please Wait" : 'Set a 6-digit PIN',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!_isResettingPin)
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
                            color: index < _newPin.length
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                          ),
                        ),
                      ),
                    ),
                  if (_pinError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _pinError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_isResettingPin)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              SizedBox(
                width: orientation == Orientation.portrait ? 0 : 32,
                height: orientation == Orientation.portrait ? 32 : 0,
              ),
              if (!_isResettingPin)
                PinKeypad(
                  onKeyPressed: (key) async {
                    if (_newPin.length < 6) {
                      setState(() {
                        _newPin += key;
                        _pinError = '';
                      });
                      if (_newPin.length == 6) {
                        setState(() {
                          _isResettingPin = true;
                        });
                        try {
                          await widget.backend.resetPassword(
                            widget.user.id,
                            _newPin,
                          );
                          setState(() {
                            _isSettingPin = false;
                            _isResettingPin = false;
                            _enteredPin = '';
                            _pinError = '';
                            _isPinVerified = true;
                          });
                        } catch (e) {
                          setState(() {
                            _pinError = 'Failed to set PIN. Please try again.';
                            _newPin = '';
                            _isResettingPin = false;
                          });
                        }
                      }
                    }
                  },
                  onClear: () {
                    setState(() {
                      _newPin = '';
                      _pinError = '';
                    });
                  },
                  onBackspace: () {
                    if (_newPin.isNotEmpty) {
                      setState(() {
                        _newPin = _newPin.substring(0, _newPin.length - 1);
                        _pinError = '';
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
    if (_isSettingPin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          title: Text(widget.user.getVisualName()),
        ),
        body: _buildPinSetter(context),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(widget.user.getVisualName()),
        actions: [
          IconButton(
            onPressed: () {
              isTimerRunning.value = false;
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(widget.user.name),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("ID: ${widget.user.id}"),
                        Text("Nickname: ${widget.user.nickname}"),
                        Text("Status: ${widget.user.status}"),
                        Text("Current Location: ${widget.user.location}"),
                        Text("Titles: ${widget.user.getTitles()}"),
                        Text("Groups: ${widget.user.getGroups()}"),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                },
              );
            },
            icon: Icon(Icons.info),
          ),
        ],
      ),
      body: !widget.fromRfid && !_isPinVerified && widget.requirePinEntry
          ? _buildPinEntry(context)
          : !_readMessages &&
                myMessages(
                  widget.user.getGroups(),
                  widget.user.id.toString(),
                  widget.backend.messageTable?.entries.value ?? [],
                ).isNotEmpty
          ? Builder(
              builder: (context) {
                final entry = myMessages(
                  widget.user.getGroups(),
                  widget.user.id.toString(),
                  widget.backend.messageTable?.entries.value ?? [],
                )[_page];
                return GestureDetector(
                  onTapDown: (x) {
                    setState(() {
                      _isMessageTimeoutCanceled = true;
                    });
                  },
                  onTap: () {
                    setState(() {
                      _isMessageTimeoutCanceled = true;
                    });
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                entry.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: MarkdownWidget(data: entry.message),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (entry.timeout != null &&
                          !entry.requireAccept &&
                          !_isMessageTimeoutCanceled)
                        TweenAnimationBuilder<double>(
                          key: ValueKey("timer_$_page"),
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(seconds: entry.timeout!),
                          builder: (context, value, child) {
                            if (value == 1) {
                              Future.microtask(() {
                                if (!context.mounted) return;
                                setState(() {
                                  _isMessageTimeoutCanceled = false;
                                  if (_page <
                                      myMessages(
                                        widget.user.getGroups(),
                                            widget.user.id.toString(),
                                            widget
                                                    .backend
                                                    .messageTable
                                                    ?.entries
                                                    .value ??
                                                [],
                                          ).length -
                                          1) {
                                    _page += 1;
                                  } else {
                                    _readMessages = true;
                                  }
                                });
                              });
                            }
                            return LinearProgressIndicator(value: value);
                          },
                        ),
                      if (entry.timeout != null &&
                          !entry.requireAccept &&
                          _isMessageTimeoutCanceled)
                        const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController!,
                              builder: (context, child) {
                                double scale = 1.0;
                                if (entry.requireAccept) {
                                  scale = 1.0 + (_pulseController!.value * 0.1);
                                }
                                return Transform.scale(
                                  scale: scale,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isMessageTimeoutCanceled = false;
                                        if (_page <
                                            myMessages(
                                              widget.user.getGroups(),
                                                  widget.user.id.toString(),
                                                  widget
                                                          .backend
                                                          .messageTable
                                                          ?.entries
                                                          .value ??
                                                      [],
                                                ).length -
                                                1) {
                                          _page += 1;
                                        } else {
                                          _readMessages = true;
                                        }
                                      });
                                    },
                                    child: Text(
                                      (_page <
                                              myMessages(
                                                widget.user.getGroups(),
                                                    widget.user.id.toString(),
                                                    widget
                                                            .backend
                                                            .messageTable
                                                            ?.entries
                                                            .value ??
                                                        [],
                                                  ).length -
                                                  1)
                                          ? "Next"
                                          : "Done",
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : GestureDetector(
              onTap: () {
                isTimerRunning.value = false;
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              widget.user.getTitles()?.join(" • ") ??
                                  "Unknown Title, please refresh members",
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text("ID: ${widget.user.id}"),
                            Spacer(),
                            CircleAvatar(
                              radius: 128,
                              child: widget.user.pfpUrl != null
                                  ? ClipOval(
                                      child: FadeInImage.memoryNetwork(
                                        placeholder: kTransparentImage,
                                        image: widget.user.pfpUrl!,
                                      ),
                                    )
                                  : Builder(
                                      builder: (context) {
                                        List<String> nameParts = widget
                                            .user
                                            .name
                                            .split(' ');
                                        nameParts.removeWhere(
                                          (val) => val.isEmpty,
                                        );
                                        return Text(
                                          nameParts
                                              .map((part) => part[0])
                                              .take(2)
                                              .join(),
                                          style: TextStyle(
                                            fontSize: 84,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            Spacer(),
                            if (widget.user.status == AttendanceStatus.present)
                              Text(
                                "Leaving: ${widget.user.location}",
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            else if (widget.fixed)
                              Text(
                                "Location: ${widget.fixedLocation}",
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24.0,
                                  right: 24.0,
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedLocation,

                                  onChanged: (value) {
                                    setState(() {
                                      _selectedLocation = value!;
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: "Location",
                                  ),
                                  items: widget.allowedLocations!.map((
                                    location,
                                  ) {
                                    return DropdownMenuItem<String>(
                                      value: location,
                                      child: Text(location),
                                    );
                                  }).toList(),
                                ),
                              ),
                            SizedBox(height: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 16),
                                Expanded(
                                  child: FilledButton(
                                    onPressed:
                                        widget.user.status ==
                                            AttendanceStatus.out
                                        ? () {
                                            setState(() {
                                              widget.backend.clockIn(
                                                widget.user.id,
                                                widget.fixed
                                                    ? widget.fixedLocation!
                                                    : _selectedLocation!,
                                              );
                                            });
                                            Navigator.of(context).pop();
                                          }
                                        : null,
                                    style: ButtonStyle(
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadiusGeometry.all(
                                                Radius.circular(16.0),
                                              ),
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Text(
                                        "Clock In",
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: FilledButton(
                                    onPressed:
                                        widget.user.status ==
                                            AttendanceStatus.present
                                        ? () {
                                            setState(() {
                                              widget.backend.clockOut(
                                                widget.user.id,
                                              );
                                            });
                                            Navigator.of(context).pop();
                                          }
                                        : null,
                                    style: ButtonStyle(
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadiusGeometry.all(
                                                Radius.circular(16.0),
                                              ),
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Text(
                                        "Clock Out",
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: isTimerRunning,
                    builder: (context, value, child) {
                      if (value) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(seconds: 5),
                          builder: (context, value, child) {
                            if (value == 1 && isTimerRunning.value) {
                              Future.microtask(() {
                                isTimerRunning.value = false;
                                if (!context.mounted) return false;
                                if (widget.user.status ==
                                    AttendanceStatus.present) {
                                  widget.backend.clockOut(widget.user.id);
                                  Navigator.of(context).pop();
                                } else {
                                  widget.backend.clockIn(
                                    widget.user.id,
                                    widget.fixed
                                        ? widget.fixedLocation!
                                        : _selectedLocation!,
                                  );
                                  Navigator.of(context).pop();
                                }
                                return true;
                              });
                            }
                            return LinearProgressIndicator(
                              value: value,
                              year2023: false,
                            );
                          },
                        );
                      } else {
                        return SizedBox(height: 4);
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
