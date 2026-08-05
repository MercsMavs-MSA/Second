import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart' as intl;
import 'package:logger/logger.dart';
import 'package:lottie/lottie.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:second/config_table.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:async/async.dart';
import 'package:second/backend.dart';
import 'package:second/keyboard.dart';
import 'package:second/log_inst.dart';
import 'package:second/log_view.dart';
import 'package:second/rfid_event.dart';
import 'package:second/settings.dart';
import 'package:second/settings_page.dart';
import 'package:second/state.dart';
import 'package:second/user_flow.dart';
import 'package:second/util.dart';
import 'package:second/widgets.dart';
import 'package:second/optimization.dart';

import 'log_printer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsManager();
  await settings.init();

  final controller = ThemeController();
  controller.updateLowResourceMode(
    settings.getValue<bool>("app.lowresources") ??
        settings.getDefault<bool>("app.lowresources")!,
  );
  controller.updateTheme(settings.getValue<String>('app.theme.mode') ?? "dark");
  controller.updateAccent(
    settings.getValue<String>('app.theme.accent') ?? "blue",
  );

  var logger = Logger(
    filter: LevelFilter(
      Level.values.firstWhere(
        (level) =>
            level.value ==
            (settings.getValue<int>("app.loglevel") ??
                settings.getDefault<int>("app.loglevel")!),
      ),
    ),
    printer: BoundedMemoryPrinter(),
    output: null, // Use the default LogOutput (-> send everything to console)
  );
  loggerInstance = logger;

  runApp(MyApp(settings, controller, logger));
}

class MyApp extends StatefulWidget {
  const MyApp(
    this.settingsManager,
    this.themeController,
    this.logger, {
    super.key,
  });

  final SettingsManager settingsManager;
  final ThemeController themeController;
  final Logger logger;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ConfettiController greenCenterConfetti;

  @override
  void initState() {
    super.initState();
    greenCenterConfetti = ConfettiController();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: AlignmentDirectional.center,
      textDirection: TextDirection.ltr,
      children: [
        ValueListenableBuilder(
          valueListenable: widget.themeController.lowResouceMode,
          builder: (context, value, child) {
            return ValueListenableBuilder(
              valueListenable: widget.themeController.themeMode,
              builder: (context, value, child) {
                return ValueListenableBuilder(
                  valueListenable: widget.themeController.accentColor,
                  builder: (context, value, child) {
                    final adjustedColor = HSVColor.fromColor(
                      value,
                    ).withSaturation(0.52).toColor();

                    final darkColorScheme = ColorScheme.fromSeed(
                      seedColor: adjustedColor,
                      brightness: Brightness.dark,
                      primary: adjustedColor,
                    );

                    final lightColorScheme = ColorScheme.fromSeed(
                      seedColor: adjustedColor,
                      brightness: Brightness.light,
                      primary: adjustedColor,
                    );

                    final darkTheme = ThemeData(
                      colorScheme: darkColorScheme,
                      useMaterial3: true,
                      scaffoldBackgroundColor: darkColorScheme.surface,
                      appBarTheme: AppBarTheme(
                        backgroundColor: darkColorScheme.primary,
                        foregroundColor: darkColorScheme.onPrimary,
                      ),
                      pageTransitionsTheme:
                          widget.themeController.lowResouceMode.value
                          ? PageTransitionsTheme(
                              builders: {
                                for (final platform in TargetPlatform.values)
                                  platform: const NoTransitionsBuilder(),
                              },
                            )
                          : null,
                      splashFactory: widget.themeController.lowResouceMode.value
                          ? NoSplash.splashFactory
                          : null,
                    );

                    final lightTheme = ThemeData(
                      colorScheme: lightColorScheme,
                      useMaterial3: true,
                      scaffoldBackgroundColor: lightColorScheme.surface,
                      appBarTheme: AppBarTheme(
                        backgroundColor: lightColorScheme.primary,
                        foregroundColor: lightColorScheme.onPrimary,
                      ),
                      pageTransitionsTheme:
                          widget.themeController.lowResouceMode.value
                          ? PageTransitionsTheme(
                              builders: {
                                for (final platform in TargetPlatform.values)
                                  platform: const NoTransitionsBuilder(),
                              },
                            )
                          : null,
                      splashFactory: widget.themeController.lowResouceMode.value
                          ? NoSplash.splashFactory
                          : null,
                    );

                    return MaterialApp(
                      title: 'Second',
                      themeMode: widget.themeController.themeMode.value,
                      darkTheme: darkTheme,
                      theme: lightTheme,
                      home: HomePage(
                        widget.themeController,
                        widget.settingsManager,
                        widget.logger,
                        greenCenterConfetti,
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        ConfettiWidget(
          confettiController: greenCenterConfetti,
          gravity: 0.0,
          blastDirection: 0,
          minBlastForce: 40.0,
          maxBlastForce: 60.0,
          blastDirectionality: BlastDirectionality.explosive,
          particleDrag: 0.03,
          numberOfParticles: 8,
          colors: [Colors.green[300]!, Colors.green[500]!, Colors.green[600]!],
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage(
    this.themeController,
    this.settingsManager,
    this.logger,
    this.greenCenterConfetti, {
    super.key,
  });

  final ThemeController themeController;
  final SettingsManager settingsManager;
  final Logger logger;

  final ConfettiController greenCenterConfetti;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const lockdownPlatform = MethodChannel(
    'org.mckinneysteamacademy.second/lockdown',
  );

  PackageInfo? packageInfo;

  // clock
  late ValueNotifier<DateTime> _now;
  late Timer _clockTimer;

  // home screen state
  late ValueNotifier<AppState> _homeScreenState;

  // backend
  late AttendanceTrackerBackend _backend;
  late CheckoutScheduler _checkoutScheduler;

  // name search
  final TextEditingController _searchQuery = TextEditingController();
  late ValueNotifier<List<Member>> filteredMembers;

  // sorting options
  bool _sortAscending = true;
  String _sortCriteria = 'name'; // 'name' or 'status'

  // home screen image
  late ValueNotifier<Uint8List> _homeScreenImage;

  // rfid
  bool rfidScanInActive = true;

  // rfid hid
  late StreamController<RfidEvent> _rfidHidStreamController;
  late Stream<RfidEvent> _rfidHidStream;
  final List<RfidEvent> _rfidHidInWaiting = [];
  late RestartableTimer _rfidHidTimeoutTimer;

  void _updateFilteredMembers() {
    final List<Member> members = _backend.attendance.value.where((member) {
      return member.name.toLowerCase().contains(_searchQuery.text.toLowerCase()) && !member.groups.contains("unlisted");
    }).toList();

    members.sort((a, b) {
      int result;
      if (_sortCriteria == 'name') {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else {
        // Status sort: present vs out
        // In backend.dart, AttendanceStatus is: enum AttendanceStatus { present, out }
        // present.index = 0, out.index = 1
        result = a.status.index.compareTo(b.status.index);
      }
      return _sortAscending ? result : -result;
    });

    filteredMembers.value = members;
  }

  @override
  void initState() {
    super.initState();
    // info
    PackageInfo.fromPlatform().then((info) {
      setState(() {
        packageInfo = info;
      });
    });

    // backend
    _backend = AttendanceTrackerBackend(widget.logger);
    _backendStartup();

    _backend.timingsTable?.load();
    _checkoutScheduler = CheckoutScheduler(
      configs: _backend.timingsTable?.entries.value ?? [],
      onTrigger: (CheckoutConfigEntry entry, DateTime appliedTime) async {
        widget.logger.t("Running Auto-Checkout");
        await _backend.instantMemberUpdate();
        for (final member in _backend.attendance.value) {
          if (member.status == AttendanceStatus.present) {
            _backend.clockOut(member.id, time: appliedTime, isAuto: true);
          }
        }
      },
    );
    _checkoutScheduler.start();

    // search filter
    filteredMembers = ValueNotifier(
      _backend.attendance.value
          .where(
            (member) =>
                member.name.toLowerCase().contains(_searchQuery.text.toLowerCase()),
          )
          .toList(),
    );

    // clock
    _now = ValueNotifier(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _now.value = DateTime.now();
    });

    // home screen state
    _homeScreenState = ValueNotifier(AppState.initial);
    Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      _homeScreenState.value = _getStatus();
    });

    // ui
    _homeScreenImage = ValueNotifier(
      base64.decode(
        widget.settingsManager.getValue<String>("app.theme.logo") ??
            widget.settingsManager.getDefault<String>("app.theme.logo")!,
      ),
    );

    // rfid hid
    _rfidHidStreamController = StreamController<RfidEvent>.broadcast();
    _rfidHidStream = _rfidHidStreamController.stream;
    ServicesBinding.instance.keyboard.addHandler((event) {
      if (event is KeyDownEvent && (widget.settingsManager.getValue<String>("rfid.reader") ??
          widget.settingsManager.getDefault<String>("rfid.reader")!) ==
          "disable") {
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          return false;
        } if (event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_searchQuery.text.isNotEmpty) {
            _searchQuery.text = _searchQuery.text.substring(0, _searchQuery.text.length - 1);
          }
        } else {
          _searchQuery.text = _searchQuery.text + (event.character ?? "");
        }
        _searchQuery.selection = TextSelection.collapsed(offset: _searchQuery.text.length);
        _updateFilteredMembers();
        return false;
      }
      if (event is KeyDownEvent &&
          event.character != null &&
          (widget.settingsManager.getValue<String>("rfid.reader") ??
                  widget.settingsManager.getDefault<String>("rfid.reader")!) ==
              "hid") {
        _rfidHidStreamController.sink.add(
          RfidEvent(
            event.character!,
            DateTime.fromMicrosecondsSinceEpoch(event.timeStamp.inMilliseconds),
          ),
        );
      } else if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          (widget.settingsManager.getValue<String>("rfid.reader") ??
                  widget.settingsManager.getDefault<String>("rfid.reader")!) ==
              "hid") {
        // workaround for bug on web
        _rfidHidStreamController.sink.add(
          RfidEvent(
            "\n",
            DateTime.fromMicrosecondsSinceEpoch(event.timeStamp.inMilliseconds),
          ),
        );
      }
      return false; // reject the event, pass to widgets
    });
    _rfidHidTimeoutTimer = RestartableTimer(
      Duration(
        milliseconds:
            ((widget.settingsManager.getValue<double>("rfid.hid.timeout") ??
                        widget.settingsManager.getDefault<double>(
                          "rfid.hid.timeout",
                        )!) *
                    1000)
                .ceil(),
      ),
      () {
        if (_rfidHidInWaiting.isNotEmpty) {
          // quick sanity check
          final Map<String, String?> eolMap = {
            "SPACE": " ",
            "RETURN": "\r",
            "NONE": null,
          };
          if (_rfidHidInWaiting.last.char ==
              eolMap[widget.settingsManager.getValue<String>("rfid.hid.eol") ??
                  widget.settingsManager.getDefault<String>("rfid.hid.eol")!]) {
            return;
          }

          // process
          switch (DataFormat.values.byName(
            widget.settingsManager.getValue<String>("rfid.hid.format") ??
                widget.settingsManager.getDefault<String>("rfid.hid.format")!,
          )) {
            case DataFormat.decAscii:
              _processRfid(
                int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
              );
              break;
            case DataFormat.hexAscii:
              _processRfid(
                int.tryParse(
                  _rfidHidInWaiting.map((ev) => ev.char).join(""),
                  radix: 16,
                ),
              );
              break;
          }
          _rfidHidInWaiting.clear(); // clear the queue
        }
      },
    );
    _rfidHidStream.listen((event) => _rfidHidEventListener(event));

    // kiosk
    if (!kIsWeb && Platform.isAndroid) {
      if (widget.settingsManager.getValue<bool>("android.immersive") ??
          widget.settingsManager.getDefault<bool>("android.immersive")!) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      if (widget.settingsManager.getValue<bool>("android.absorbvolume") ??
          widget.settingsManager.getDefault<bool>("android.absorbvolume")!) {
        lockdownPlatform.invokeMethod('setAbsorbVolumeKeys', {'enabled': true});
      } else {
        lockdownPlatform.invokeMethod('setAbsorbVolumeKeys', {
          'enabled': false,
        });
      }
    }
  }

  void _backendStartup() async {
    await _backend.initialize(
      widget.settingsManager.getValue<String>('google.sheet_id') ?? '',
      widget.settingsManager.getValue<String>('google.oauth_credentials') ??
          '{}',
      pullIntervalActive:
          widget.settingsManager.getValue<int>('backend.interval.activePull') ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.activePull',
          )!,
      pushIntervalActive:
          widget.settingsManager.getValue<int>('backend.interval.activePush') ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.activePush',
          )!,
      pullIntervalInactive:
          widget.settingsManager.getValue<int>(
            'backend.interval.inactivePull',
          ) ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.inactivePull',
          )!,
      pushIntervalInactive:
          widget.settingsManager.getValue<int>(
            'backend.interval.inactivePush',
          ) ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.inactivePush',
          )!,
      activeCooldownInterval:
          widget.settingsManager.getValue<int>(
            'backend.interval.activeCooldown',
          ) ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.activeCooldown',
          )!,
      configPullInterval:
          widget.settingsManager.getValue<int>(
            'backend.interval.configsReload',
          ) ??
          widget.settingsManager.getDefault<int>(
            'backend.interval.configsReload',
          )!,
    );

    _backend.timingsTable?.load();
    _backend.timingsTable?.entries.addListener(() {
      _checkoutScheduler.configs = _backend.timingsTable?.entries.value ?? [];
    });
  }

  Future<void> _rfidHidEventListener(RfidEvent event) async {
    _rfidHidTimeoutTimer.reset(); // reset the timeout
    _rfidHidInWaiting.add(event); // add new event
    final Map<String, String?> eolMap = {
      "SPACE": " ",
      "RETURN": "\r",
      "NONE": null,
    };
    if (event.char ==
        eolMap[widget.settingsManager.getValue<String>("rfid.hid.eol") ??
            widget.settingsManager.getDefault<String>("rfid.hid.eol")!]) {
      // end-of-line
      switch (DataFormat.values.byName(
        widget.settingsManager.getValue<String>("rfid.hid.format") ??
            widget.settingsManager.getDefault<String>("rfid.hid.format")!,
      )) {
        case DataFormat.decAscii:
          _processRfid(
            int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
          );
          break;
        case DataFormat.hexAscii:
          _processRfid(
            int.tryParse(
              _rfidHidInWaiting.map((ev) => ev.char).join(""),
              radix: 16,
            ),
          );
          break;
      }

      _rfidHidInWaiting.clear(); // clear the queue
    }
  }

  void _processRfid(int? code) {
    if (!rfidScanInActive) {
      widget.logger.i("RFID processing paused. Tag = $code");
      return;
    }
    widget.logger.i("Process RFID Tag: $code");
    if (code == null) {
      widget.logger.w("Invalid RFID tag, please try again");
      _displayErrorPopup("Badge Read Error");
      return;
    }
    if (!_backend.isMember(code)) {
      _displayErrorPopup("Member Not Found");
      widget.logger.w("Member not found: $code");
      return;
    }
    beginUserFlow(context, _backend.getMemberById(code), true);
  }

  void _displayErrorPopup(String error) {
    final rootContext = context; // capture once from the widget
    showDialog(
      barrierColor: Colors.red.withAlpha(40),
      barrierDismissible: true,
      context: rootContext,
      builder: (dialogContext) {
        // Schedule dismissal using the rootContext, not dialogContext
        Timer(const Duration(seconds: 1), () {
          if (mounted &&
              Navigator.of(rootContext, rootNavigator: true).canPop()) {
            Navigator.of(rootContext, rootNavigator: true).pop();
          }
        });

        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/fail.json', reverse: true),
              Text(error, style: Theme.of(rootContext).textTheme.titleLarge),
            ],
          ),
          actionsPadding: EdgeInsets.zero,
        );
      },
    );
  }

  void _displaySuccessPopup() async {
    if (!widget.themeController.lowResouceMode.value) {
      widget.greenCenterConfetti.play();
    }
    showDialog(
      barrierColor: Colors.green.withAlpha(40),
      barrierDismissible: true,
      context: context,
      builder: (context) {
        Timer(Duration(seconds: 1), () {
          Navigator.of(context).maybePop();
          widget.greenCenterConfetti.stop(clearAllParticles: true);
        });
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/success.json', reverse: true),
            ],
          ),
          actionsPadding: EdgeInsets.zero,
          actions: [],
        );
      },
    );
  }

  void showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Second',
      applicationVersion:
          "${packageInfo?.version} (Build #${packageInfo?.buildNumber})",
      applicationIcon: Image.asset(
        "assets/icons/icon_96.png",
        width: 96,
        height: 96,
      ),
      applicationLegalese: "Copyright (c) 2025-2026 Kevin Ahr",
      children: [
        Text("An FRC/FTC Attendance Tracker"),
        ListTile(
          leading: Icon(Icons.gavel),
          title: Text("License"),
          subtitle: Text("GPL-3.0"),
          onTap: () {
            launchUrl(
              Uri.parse("https://www.gnu.org/licenses/gpl-3.0.en.html"),
            );
          },
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void beginUserFlow(BuildContext context, Member user, bool fromRfid) {
    rfidScanInActive = false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFlow(
          user,
          _backend,
          allowedLocations:
              widget.settingsManager.getValue<List<String>>(
                'station.locations',
              ) ??
              ["Shop"],
          fixed:
              widget.settingsManager.getValue<bool>('station.fixed') ?? false,
          fixedLocation:
              widget.settingsManager.getValue<String>('station.location') ??
              "Shop",
          fromRfid: fromRfid,
          requirePinEntry: user.groups.contains("require-pin"),
        ),
      ),
    ).then((_) {
      rfidScanInActive = true;
      if (_backend.getMemberById(user.id).status != user.status) {
        _displaySuccessPopup();
      }
    });
  }

  AppState _getStatus() {
    if (_backend.googleConnected.value == false) {
      return AppState(Colors.amber, "Connection Lost", 0);
    } else {
      return AppState(Colors.green, "System Online", _backend.getPushLength());
    }
  }

  List<Widget> _buildContentSections(double iconSize, bool controls) {
    final theme = Theme.of(context);

    return [
      // logo
      if (!controls)
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              if (!controls)
                Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Spacer(),
                    Center(
                      child: ValueListenableBuilder(
                        valueListenable: _now,
                        builder: (context, value, child) {
                          final timeString = intl.DateFormat(
                            'hh:mm:ss a',
                          ).format(_now.value);
                          final dateString = intl.DateFormat(
                            'MMMM d, yyyy',
                          ).format(_now.value);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dateString,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                timeString,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Spacer(flex: 2),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert),
                      tooltip: "",
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Settings'),
                          onTap: () {
                            rfidScanInActive = false;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SettingsPage(
                                  widget.themeController,
                                  widget.logger,
                                  _backend,
                                ),
                              ),
                            ).then((_) {
                              // navigate back
                              rfidScanInActive = true;
                              setState(() {
                                _homeScreenImage.value = base64.decode(
                                  widget.settingsManager.getValue<String>(
                                        "app.theme.logo",
                                      ) ??
                                      widget.settingsManager.getDefault<String>(
                                        "app.theme.logo",
                                      )!,
                                );
                              });

                              // backend
                              _backendStartup();
                            });
                          },
                        ),
                        PopupMenuItem(
                          value: 'logger',
                          child: Text('App Logs'),
                          onTap: () {
                            rfidScanInActive = false;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoggerView(
                                  settings: widget.settingsManager,
                                ),
                              ),
                            ).then((_) {
                              rfidScanInActive = true;
                            });
                          },
                        ),
                        PopupMenuItem(
                          value: 'about',
                          child: Text('About'),
                          onTap: () {
                            showAbout();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              Spacer(),
              ValueListenableBuilder(
                valueListenable: _homeScreenImage,
                builder: (context, image, widget) {
                  return Image.memory(image, width: iconSize, fit: BoxFit.fill);
                },
              ),
              Spacer(),
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ValueListenableBuilder(
                    valueListenable: _homeScreenState,
                    builder: (context, value, child) {
                      return Row(
                        children: [
                          Icon(Icons.circle, color: value.color, size: 18),
                          SizedBox(width: 8),
                          Text(value.description),
                          if (value.pushCount > 0) Spacer(),
                          if (value.pushCount > 0)
                            Transform.rotate(
                              angle: -pi / 4,
                              child: Icon(Icons.double_arrow_rounded, size: 18),
                            ),
                          if (value.pushCount > 0)
                            Text(value.pushCount.toString()),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: _homeScreenImage,
                builder: (context, image, widget) {
                  return Image.memory(image, width: iconSize, fit: BoxFit.fill);
                },
              ),
              Spacer(),
              Center(
                child: ValueListenableBuilder(
                  valueListenable: _now,
                  builder: (context, value, child) {
                    final timeString = intl.DateFormat(
                      'hh:mm:ss a',
                    ).format(_now.value);
                    final dateString = intl.DateFormat(
                      'MMMM d, yyyy',
                    ).format(_now.value);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Card.filled(
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: ValueListenableBuilder(
                              valueListenable: _homeScreenState,
                              builder: (context, value, child) {
                                return Row(
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      color: value.color,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(value.description),
                                    if (value.pushCount > 0)
                                      SizedBox(width: 12),
                                    if (value.pushCount > 0)
                                      Transform.rotate(
                                        angle: -pi / 4,
                                        child: Icon(
                                          Icons.double_arrow_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    if (value.pushCount > 0)
                                      Text(value.pushCount.toString()),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(dateString, style: theme.textTheme.titleMedium),
                        Text(
                          timeString,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Spacer(),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert),
                tooltip: "",
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                    onTap: () {
                      rfidScanInActive = false;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsPage(
                            widget.themeController,
                            widget.logger,
                            _backend,
                          ),
                        ),
                      ).then((_) {
                        // navigate back
                        rfidScanInActive = true;
                        setState(() {
                          _homeScreenImage.value = base64.decode(
                            widget.settingsManager.getValue<String>(
                                  "app.theme.logo",
                                ) ??
                                widget.settingsManager.getDefault<String>(
                                  "app.theme.logo",
                                )!,
                          );
                        });

                        // backend
                        _backendStartup();
                      });
                    },
                  ),
                  PopupMenuItem(
                    value: 'logger',
                    child: Text('App Logs'),
                    onTap: () {
                      rfidScanInActive = false;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              LoggerView(settings: widget.settingsManager),
                        ),
                      ).then((_) {
                        rfidScanInActive = true;
                      });
                    },
                  ),
                  PopupMenuItem(
                    value: 'about',
                    child: Text('About'),
                    onTap: () {
                      showAbout();
                    },
                  ),
                ],
              ),
              SizedBox(width: 8),
            ],
          ),
        ),
      Flexible(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.settingsManager.getValue<String>(
                            "rfid.reader",
                          ) !=
                          "disable")
                        RfidTapCard(
                          isRfidRequired:
                              widget.settingsManager.getValue<bool>(
                                "list.disable",
                              ) ??
                              widget.settingsManager.getDefault<bool>(
                                "list.disable",
                              )!,
                        ),
                      if (widget.settingsManager.getValue<String>(
                            "rfid.reader",
                          ) !=
                          "disable")
                        const SizedBox(height: 8),
                      Expanded(
                        child: Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: VirtualTextField(
                                        controller: _searchQuery,
                                        decoration: InputDecoration(
                                          hintText: 'Search name...',
                                          prefixIcon: Icon(Icons.search),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          _updateFilteredMembers();
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 8.0),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.filter_list),
                                      tooltip: "Sort",
                                      onSelected: (value) {
                                        setState(() {
                                          if (value == 'name_asc') {
                                            _sortCriteria = 'name';
                                            _sortAscending = true;
                                          } else if (value == 'name_desc') {
                                            _sortCriteria = 'name';
                                            _sortAscending = false;
                                          } else if (value == 'status_asc') {
                                            _sortCriteria = 'status';
                                            _sortAscending = true;
                                          } else if (value == 'status_desc') {
                                            _sortCriteria = 'status';
                                            _sortAscending = false;
                                          }
                                          _updateFilteredMembers();
                                        });
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'name_asc',
                                          child: Row(
                                            children: [
                                              Icon(Icons.sort_by_alpha),
                                              SizedBox(width: 8),
                                              Text('Name (A-Z)'),
                                              Spacer(),
                                              if (_sortCriteria == "name" &&
                                                  _sortAscending)
                                                Icon(Icons.check),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'name_desc',
                                          child: Row(
                                            children: [
                                              Icon(Icons.sort_by_alpha),
                                              SizedBox(width: 8),
                                              Text('Name (Z-A)'),
                                              Spacer(),
                                              if (_sortCriteria == "name" &&
                                                  !_sortAscending)
                                                Icon(Icons.check),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'status_asc',
                                          child: Row(
                                            children: [
                                              Icon(Icons.query_stats),
                                              SizedBox(width: 8),
                                              Text('Status (Present First)'),
                                              Spacer(),
                                              if (_sortCriteria == "status" &&
                                                  _sortAscending)
                                                Icon(Icons.check),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'status_desc',
                                          child: Row(
                                            children: [
                                              Icon(Icons.query_stats),
                                              SizedBox(width: 8),
                                              Text('Status (Out First)'),
                                              Spacer(),
                                              if (_sortCriteria == "status" &&
                                                  !_sortAscending)
                                                Icon(Icons.check),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(width: 8.0),
                                    AsyncCompleterButton(
                                      onPressed: () async {
                                        await _backend.instantMemberUpdate();
                                        await _backend.reloadConfig();
                                      },
                                      child: Icon(Icons.refresh),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: ValueListenableBuilder<List<Member>>(
                                  valueListenable: _backend.attendance,
                                  builder: (context, attendanceValue, child) {
                                    _updateFilteredMembers();
                                    return ValueListenableBuilder(
                                      valueListenable: filteredMembers,
                                      builder: (context, filterValue, child) {
                                        return ListView.builder(
                                          itemCount: filterValue.length,
                                          itemBuilder: (context, index) {
                                            final member = filterValue[index];
                                            return ListTile(
                                              leading: Stack(
                                                alignment:
                                                    Alignment.bottomRight,
                                                children: [
                                                  CircleAvatar(
                                                    child: member.pfpUrl != null
                                                        ? ClipOval(
                                                            child: FadeInImage.memoryNetwork(
                                                              placeholder:
                                                                  kTransparentImage,
                                                              image: member
                                                                  .pfpUrl!,
                                                            ),
                                                          )
                                                        : Builder(
                                                            builder: (context) {
                                                              List<String>
                                                              nameParts = member
                                                                  .name
                                                                  .split(' ');
                                                              nameParts
                                                                  .removeWhere(
                                                                    (val) => val
                                                                        .isEmpty,
                                                                  );
                                                              return Text(
                                                                nameParts
                                                                    .map(
                                                                      (part) =>
                                                                          part[0],
                                                                    )
                                                                    .take(2)
                                                                    .join(),
                                                              );
                                                            },
                                                          ),
                                                  ),
                                                  Stack(
                                                    alignment: AlignmentGeometry
                                                        .center,
                                                    children: [
                                                      Icon(
                                                        Icons.circle,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainer,
                                                        size: 16,
                                                      ),
                                                      Icon(
                                                        Icons.circle,
                                                        color:
                                                            member.status ==
                                                                AttendanceStatus
                                                                    .present
                                                            ? Colors.green
                                                            : Colors.red,
                                                        size: 12,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              title: Text(member.name),
                                              subtitle: Text(
                                                member.getTitles()?.join(" · ") ?? "Error loading title, please refresh members",
                                              ),
                                              onTap: () {
                                                if (widget.settingsManager
                                                        .getValue<bool>(
                                                          "list.disable",
                                                        ) ??
                                                    widget.settingsManager
                                                        .getDefault<bool>(
                                                          "list.disable",
                                                        )!) {
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) {
                                                      return AlertDialog(
                                                        title: Text(
                                                          member.name,
                                                        ),
                                                        content: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.block,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              size: 128,
                                                            ),
                                                            Text(
                                                              "RFID badge sign-in is enforced.",
                                                            ),
                                                          ],
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () {
                                                              Navigator.of(
                                                                context,
                                                              ).pop();
                                                            },
                                                            child: Text("OK"),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                                  return;
                                                }
                                                beginUserFlow(
                                                  context,
                                                  member,
                                                  false,
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: Center(
                    child: VirtualKeyboard(
                      rootLayoutPath: "assets/layouts/en-US.xml",
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: OrientationBuilder(
        builder: (context, orientation) {
          return Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: OrientationBuilder(
                    builder: (BuildContext context, Orientation orientation) {
                      if (orientation == Orientation.landscape) {
                        final sections = _buildContentSections(240, false);
                        return Row(
                          children: [
                            SizedBox(width: 300, child: sections[0]),
                            Expanded(
                              flex: 2,
                              child: Column(children: sections.sublist(1)),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: _buildContentSections(120, true),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
