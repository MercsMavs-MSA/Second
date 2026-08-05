import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:second/log_inst.dart';
import 'package:second/message_board_loader.dart';
import 'package:second/passwords.dart';
import 'package:second/settings.dart';
import 'package:second/string_ext.dart';
import 'package:second/util.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'config_table.dart';

enum AttendanceStatus { present, out }

enum MemberLoggerAction { created, checkIn, checkOut, checkOutAuto, disabled, error }

abstract class SerializableItem {
  Map<String, dynamic> serialize();
}

typedef Deserializer<T> = T Function(Map<String, dynamic>);

class CachedQueue<T> {
  final String id;
  final Queue<T> _queue = Queue<T>();
  final Deserializer<T> _deserializer;

  CachedQueue(this.id, this._deserializer) {
    final storedRaw =
        SettingsManager.getInstance.prefs?.getStringList(id) ?? [];
    loggerInstance?.d(
      "Restoring CachedQueue<$T> with id '$id' from cache, ${storedRaw.length} items found.",
    );
    for (var raw in storedRaw) {
      Map<String, dynamic> item;
      item = jsonDecode(raw) as Map<String, dynamic>;
      _queue.add(_deserializer(item));
    }
  }

  bool contains(T value) => _queue.contains(value);

  void add(T value) {
    _queue.add(value);
    _updateCache();
  }

  T removeFirst() {
    final r = _queue.removeFirst();
    _updateCache();
    return r;
  }

  void clear() {
    _queue.clear();
    _updateCache();
  }

  void remove(T value) {
    _queue.remove(value);
    _updateCache();
  }

  void removeWhere(bool Function(T element) test) {
    _queue.removeWhere(test);
    _updateCache();
  }

  void _updateCache() {
    if (SettingsManager.getInstance.prefs == null) {
      loggerInstance?.e(
        "Cannot update cache for CachedQueue<$T> with id '$id': SettingsManager prefs is null.",
      );
    }
    SettingsManager.getInstance.prefs?.setStringList(id, toSerialStringList());
  }

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  @override
  String toString() => 'CachedQueue($id): ${_queue.toString()}';

  List<T> toList() => _queue.toList();

  List<Map<String, dynamic>> toSerialList() {
    return _queue.map((e) => (e as SerializableItem).serialize()).toList();
  }

  List<String> toSerialStringList() {
    return _queue
        .map((e) => jsonEncode((e as SerializableItem).serialize()))
        .toList();
  }
}

class Member {
  final int id;
  final String name;
  final AttendanceStatus status;
  final String? location;
  final String? passwordHash;
  final String titles;
  final String groups;
  final String? pfpUrl;
  Member(
    this.id,
    this.name,
    this.titles,
    this.groups,
    this.status, {
    this.location,
    this.passwordHash,
    this.pfpUrl,
  });

  Iterable<String>? getTitles() {
    if (titles.isEmpty) {
      return null;
    }
    return titles.split(",").map((s){return s.trim();});
  }

  Iterable<String>? getGroups() {
    if (groups.isEmpty) {
      return null;
    }
    return groups.split(",").map((s){return s.trim();});
  }

  @override
  String toString() {
    return 'Member{id: $id, name: $name, titles: $titles, status: $status, location: $location, groups: $groups, passwordHash: $passwordHash}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'titles': titles,
      'groups': groups,
      'status': status.name,
      'location': location,
      'passwordHash': passwordHash,
      'pfp': pfpUrl,
    };
  }

  static Member fromMap(Map<String, dynamic> data) {
    return Member(
      data['id'] is int
          ? data['id'] as int
          : int.tryParse(data['id'].toString()) ?? -1,
      data['name'] as String,
      (data['titles'] as String? ?? "Error loading title, please refresh members"),
      (data['groups'] as String? ?? ""),
      AttendanceStatus.values.byName((data['status'] as String).toLowerCase()),
      location: data['location'] as String?,
      passwordHash: data['passwordHash'] as String?,
      pfpUrl: data["pfpUrl"] as String?,
    );
  }
}

class MemberLogEntry extends SerializableItem {
  final int memberId;
  final MemberLoggerAction action;
  final DateTime time;
  final String location;

  MemberLogEntry(this.memberId, this.action, this.time, this.location);

  @override
  String toString() {
    return 'MemberLogEntry{memberId: $memberId, action: $action, time: $time, location: $location}';
  }

  static MemberLogEntry fromMap(Map<String, dynamic> data) {
    final memberId = data['memberId'] is int
        ? data['memberId'] as int
        : int.tryParse(data['memberId'].toString()) ?? -1;
    if (data["time"].runtimeType == String) {
      data["time"] = DateTime.parse(data["time"]).millisecondsSinceEpoch;
    }
    return MemberLogEntry(
      memberId,
      MemberLoggerAction.values.byName(data['action'] as String),
      DateTime.fromMillisecondsSinceEpoch(data["time"]),
      data['location'] as String,
    );
  }

  @override
  Map<String, dynamic> serialize() {
    return {
      'memberId': memberId,
      'action': action.name,
      'time': time.toUtc().millisecondsSinceEpoch,
      'location': location,
    };
  }
}

class TimeClockEvent extends SerializableItem {
  final int memberId;
  final DateTime time;
  TimeClockEvent(this.memberId, this.time);

  static TimeClockEvent fromMap(Map<String, dynamic> data) {
    if (data["time"].runtimeType == String) {
      data["time"] = DateTime.parse(data["time"]).millisecondsSinceEpoch;
    }
    // prefer more specific subclasses if fields are present
    if (data.containsKey('newHash')) {
      return PasswordResetEvent(
        data['memberId'] is int
            ? data['memberId'] as int
            : int.parse(data['memberId'].toString()),
        DateTime.fromMillisecondsSinceEpoch(data["time"]),
        data['newHash'] as String,
      );
    }
    if (data.containsKey('location')) {
      return ClockInEvent(
        data['memberId'] is int
            ? data['memberId'] as int
            : int.parse(data['memberId'].toString()),
        DateTime.fromMillisecondsSinceEpoch(data["time"]),
        data['location'] as String,
      );
    }
    return ClockOutEvent(
      data['memberId'] is int
          ? data['memberId'] as int
          : int.parse(data['memberId'].toString()),
      DateTime.fromMillisecondsSinceEpoch(data["time"]),
    );
  }

  @override
  Map<String, dynamic> serialize() {
    return {'memberId': memberId, 'time': time.toUtc().millisecondsSinceEpoch};
  }
}

class ClockInEvent extends TimeClockEvent {
  final String location;

  ClockInEvent(super.memberId, super.time, this.location);

  @override
  Map<String, dynamic> serialize() {
    final base = super.serialize();
    base['location'] = location;
    return base;
  }

  static ClockInEvent fromMap(Map<String, dynamic> data) {
    return ClockInEvent(
      data['memberId'] is int
          ? data['memberId'] as int
          : int.parse(data['memberId'].toString()),
      DateTime.parse(data['time'] as String),
      data['location'] as String,
    );
  }
}

class ClockOutEvent extends TimeClockEvent {
  final bool isAuto;
  ClockOutEvent(super.memberId, super.time, {this.isAuto = false});
}

class PasswordResetEvent extends TimeClockEvent {
  final String newHash;

  PasswordResetEvent(super.memberId, super.time, this.newHash);
}

class TimeoutClient extends http.BaseClient {
  final http.Client _inner;
  final Duration timeout;

  TimeoutClient(this._inner, this.timeout);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }
}

class AdjustableRestartableTimer {
  RestartableTimer? _timer;
  final void Function() callback;

  AdjustableRestartableTimer(this.callback);

  void start(Duration duration) {
    _timer?.cancel();
    _timer = RestartableTimer(duration, callback);
  }

  void restartWith(Duration duration) => start(duration);

  void reset() => _timer?.reset();

  void cancel() => _timer?.cancel();
}

class AttendanceTrackerBackend {
  static const memberSheetName = "Members";
  static const logSheetName = "Log";
  static const configSheetName = "LogoutTiming";
  static const configMessagesName = "MessageBoard";
  static const memberSheetContentsRange = "$memberSheetName!A3:G";
  static const memberSheetContentsRangeWithHeader = "$memberSheetName!A2:L";
  static const memberSheetIdsRange = "$memberSheetName!A3:A";
  static const logSheetContentsRange = "$logSheetName!A3:";
  static const logSheetHeaderRange = "$logSheetName!A2:2";
  static const logSheetHeaderStart = "$logSheetName!A2";

  static const appMembersSchema = ["ID", "BadgeIDs",	"Name", "Nickname",	"Titles", "Groups", "Status", "Location","PasswordHash", "PFP", "Events", "TotalHours"];

  ValueNotifier<List<Member>> attendance = ValueNotifier([]);

  // google
  Map<String, dynamic>? _oauthCredentials;
  String? _sheetId;
  ServiceAccountCredentials? _credentials;
  AutoRefreshingAuthClient? _authClient;
  SheetsApi? _sheetsClient;
  Spreadsheet? _spreadsheet;

  CheckoutConfigurationTable? timingsTable;
  MessageBoardConfigurationTable? messageTable;

  // tasks
  AdjustableRestartableTimer? _memberFetchTimer;
  AdjustableRestartableTimer? _updateTimer;
  AdjustableRestartableTimer? _configReloadTimer;
  RestartableTimer? _googleAttemptBringupTimer;

  Duration? pushDuration;
  Duration? pullDuration;
  Duration? configReloadDuration;

  Duration? pushDurationActive;
  Duration? pullDurationActive;
  Duration? pushDurationInactive;
  Duration? pullDurationInactive;

  Duration? activeCooldownDuration;
  RestartableTimer? activeCooldownTimer;

  // language: dart
  final _clockInQueue = CachedQueue<TimeClockEvent>(
    "queues.clockIn",
    (m) => TimeClockEvent.fromMap(m),
  );
  final _clockOutQueue = CachedQueue<TimeClockEvent>(
    "queues.clockOut",
    (m) => TimeClockEvent.fromMap(m),
  );
  final _logQueue = CachedQueue<MemberLogEntry>(
    "queues.log",
    (m) => MemberLogEntry.fromMap(m),
  );
  final _updatesQueue = CachedQueue<TimeClockEvent>(
    "queues.updates",
    (m) => TimeClockEvent.fromMap(m),
  );

  // google connected flag
  // this must NOT become false on rate limit, null = not initialized
  ValueNotifier<bool?> googleConnected = ValueNotifier(null);
  final Logger logger;

  AttendanceTrackerBackend(this.logger) {
    googleConnected.addListener(() {
      if (googleConnected.value != true) {
        _onGoogleDisconnected();
      }
    });
  }

  Future<void> initialize(
    String sheetId,
    String oauthCredentialString, {
    int pullIntervalActive = 5,
    int pushIntervalActive = 2,
    int pullIntervalInactive = 10,
    int pushIntervalInactive = 4,
    int activeCooldownInterval = 10,
    int configPullInterval = 360,
  }) async {
    _oauthCredentials = jsonDecode(oauthCredentialString);
    _sheetId = sheetId;

    _clockInQueue.clear();
    _clockOutQueue.clear();
    _logQueue.clear();
    _updatesQueue.clear();

    // attendance.value = [];
    if (SettingsManager.getInstance.prefs != null) {
      attendance.value =
          (SettingsManager.getInstance.prefs!.getStringList('cached.members') ??
                  [])
              .map((e) => Member.fromMap(jsonDecode(e) as Map<String, dynamic>))
              .toList();
      attendance.addListener(() {
        SettingsManager.getInstance.prefs?.setStringList(
          'cached.members',
          attendance.value.map((e) => jsonEncode(e.toMap())).toList(),
        );
      });
    }

    pullDuration = Duration(seconds: pullIntervalInactive);
    pushDuration = Duration(seconds: pushIntervalInactive);
    activeCooldownDuration = Duration(seconds: activeCooldownInterval);

    pullDurationActive = Duration(seconds: pullIntervalActive);
    pushDurationActive = Duration(seconds: pushIntervalActive);
    pullDurationInactive = Duration(seconds: pullIntervalInactive);
    pushDurationInactive = Duration(seconds: pushIntervalInactive);
    configReloadDuration = Duration(seconds: configPullInterval);

    activeCooldownTimer = RestartableTimer(activeCooldownDuration!, () {
      pullDuration = pullDurationInactive;
      pushDuration = pushDurationInactive;
      logger.d(
        "Switched to inactive sync intervals: pull=${pullDuration!.inSeconds}s, push=${pushDuration!.inSeconds}s",
      );
    });

    // try to init google
    try {
      final baseClient = http.Client();
      final timeoutClient = TimeoutClient(
        baseClient,
        const Duration(seconds: 5),
      );

      _credentials = ServiceAccountCredentials.fromJson(_oauthCredentials);
      _authClient = await clientViaServiceAccount(_credentials!, [
        SheetsApi.spreadsheetsScope,
      ], baseClient: timeoutClient);

      _sheetsClient = SheetsApi(_authClient!);
      _spreadsheet = await _sheetsClient?.spreadsheets.get(_sheetId!);
      timingsTable = CheckoutConfigurationTable(
        _sheetsClient!,
        _spreadsheet!,
        AttendanceTrackerBackend.configSheetName,
      );
      messageTable = MessageBoardConfigurationTable(
        _sheetsClient!,
        _spreadsheet!,
        AttendanceTrackerBackend.configMessagesName,
      );

      final existingTitles =
          _spreadsheet?.sheets
              ?.map((s) => s.properties?.title)
              .whereType<String>()
              .toList() ??
          [];

      final initRequests = [
        if (!existingTitles.contains(AttendanceTrackerBackend.memberSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.memberSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.logSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.logSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.configSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.configSheetName,
              ),
            ),
          ),
      ];
      if (initRequests.isNotEmpty) {
        final request = BatchUpdateSpreadsheetRequest(requests: initRequests);
        await _sheetsClient?.spreadsheets.batchUpdate(request, _sheetId!);
      }

      googleConnected.value = _spreadsheet != null;
      logger.i("Loaded spreadsheet: ${_sheetId!}");
    } catch (e) {
      googleConnected.value = false;
      logger.e('Error initializing SheetsClient: $e');
    }

    if (_memberFetchTimer != null) {
      _memberFetchTimer!.cancel();
    }
    _memberFetchTimer = AdjustableRestartableTimer(() async {
      await _waitUntilQueuesEmpty();
      await _updateMembers();
      _memberFetchTimer?.restartWith(pullDuration!);
    });
    if (_updateTimer != null) {
      _updateTimer!.cancel();
    }
    reloadConfig();
    _updateTimer = AdjustableRestartableTimer(() async {
      await _update();
      await _updateLog();
      _updateTimer?.restartWith(pushDuration!);
    });
    _updateMembers(); // no await = schedule for background

    if (_configReloadTimer != null) {
      _configReloadTimer!.cancel();
    }
    _configReloadTimer = AdjustableRestartableTimer(() async {
      logger.t("Reloading config...");
      reloadConfig();
      _configReloadTimer?.restartWith(configReloadDuration!);
    });
    _configReloadTimer?.start(configReloadDuration!);
  }

  Future<void> reloadConfig() async {
    timingsTable?.load();
    messageTable?.load();
  }

  Future<void> _waitUntilQueuesEmpty({
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    while (_clockInQueue.isNotEmpty || _clockOutQueue.isNotEmpty) {
      await Future.delayed(checkInterval);
    }
  }

  Future<void> _waitUntilMembersLoaded({
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    while (attendance.value.isEmpty) {
      await Future.delayed(checkInterval);
    }
  }

  Future<void> _onGoogleDisconnected() async {
    // we will re-authenticate
    try {
      final baseClient = http.Client();
      final timeoutClient = TimeoutClient(
        baseClient,
        const Duration(seconds: 5),
      );

      _credentials = ServiceAccountCredentials.fromJson(_oauthCredentials);
      _authClient = await clientViaServiceAccount(_credentials!, [
        SheetsApi.spreadsheetsScope,
      ], baseClient: timeoutClient);

      _sheetsClient = SheetsApi(_authClient!);
      _spreadsheet = await _sheetsClient?.spreadsheets.get(_sheetId!);

      final existingTitles =
          _spreadsheet?.sheets
              ?.map((s) => s.properties?.title)
              .whereType<String>()
              .toList() ??
          [];

      final initRequests = [
        if (!existingTitles.contains(AttendanceTrackerBackend.memberSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.memberSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.logSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.logSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.configSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.configSheetName,
              ),
            ),
          ),
      ];
      if (initRequests.isNotEmpty) {
        final request = BatchUpdateSpreadsheetRequest(requests: initRequests);
        await _sheetsClient?.spreadsheets.batchUpdate(request, _sheetId!);
      }

      googleConnected.value = _spreadsheet != null;
      logger.i("Loaded spreadsheet: ${_sheetId!}");
    } catch (e) {
      googleConnected.value = false;
      logger.e('Error initializing SheetsClient: $e');
      if (_googleAttemptBringupTimer == null) {
        _googleAttemptBringupTimer = RestartableTimer(Duration(seconds: 1), () {
          _onGoogleDisconnected();
        });
      } else {
        _googleAttemptBringupTimer?.reset();
      }
    }
  }

  List<String> _pullSchema(List<dynamic> header) {
    List<String> output = [];
    for (String col in header) {
      output.add(col.replaceAll(RegExp(r'\s*\([^)]*\)|\s+'), ''));
    }
    return output;
  }

  bool _verifyMemberSchema(List<dynamic> memberSheetEntry) {
    // TODO: we may need to perform more extensive checks later
    if (memberSheetEntry.length != AttendanceTrackerBackend.appMembersSchema.length) {
      logger.w("Member ${memberSheetEntry[0].toString()} contains an unknown field issue, skipping addition");
      return false;
    } if (memberSheetEntry[0].toString().isEmpty) {
      logger.w("Member ${memberSheetEntry[2].toString()} must have a unique ID at column A, skipping addition");
      return false;
    } if (memberSheetEntry[2].toString().isEmpty) {
      logger.w("Member ${memberSheetEntry[0].toString()} must have a name at column C, skipping addition");
      return false;
    } if (memberSheetEntry[2].toString().isEmpty) {
      logger.w("Member ${memberSheetEntry[0].toString()} must have a title at column D (such as Student, Volunteer, Coach), skipping addition");
      return false;
    } if (!["Present", "Out"].contains(memberSheetEntry[appMembersSchema.indexOf("Status")].toString())) {
      logger.w("Member ${memberSheetEntry[0].toString()} must have a status of Present or Out");
      return false;
    }
    return true;
  }

  Future<void> _updateMembers() async {
    if (googleConnected.value != true) {
      return;
    }

    ValueRange? membersTableResponse;
    try {
      membersTableResponse = await _sheetsClient?.spreadsheets.values.get(
        _sheetId ?? "",
        valueRenderOption: 'FORMULA', // for representation if =IMAGE() in pfp
        majorDimension: 'ROWS',
        AttendanceTrackerBackend.memberSheetContentsRangeWithHeader,
      );
    } on SocketException catch (e) {
      logger.w("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      logger.w("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    } on DetailedApiRequestError catch (e) {
      logger.w("Google is down with error!!! $e");
      googleConnected.value = false;
      return;
    }

    if (membersTableResponse == null || membersTableResponse.values == null) {
      return;
    }

    if (!listEquals(_pullSchema(membersTableResponse.values![0]), AttendanceTrackerBackend.appMembersSchema)) {
      logger.e("Member sheet header not correct, aborting member update got ${_pullSchema(membersTableResponse.values![0])} expected $appMembersSchema");
      return;
    } else {
      logger.t("Member list header verified");
      membersTableResponse.values!.removeAt(0);
    }

    // apply members
    List<Member> newMembers = [];
    for (List<dynamic> googleMember in membersTableResponse.values!) {
      if (!_verifyMemberSchema(googleMember)) {
        // password fields may or may not be present
        logger.w(
          "Malformed user detected, skipping user addition, schema validation error",
        );
        continue;
      }
      var parsedPfp = googleMember.elementAtOrNull(appMembersSchema.indexOf("PFP")) as String?;
      if ((parsedPfp?.startsWith("=IMAGE(\"") ?? false) ||
          (parsedPfp?.startsWith("=image(\"") ?? false)) {
        parsedPfp = parsedPfp?.replaceFirst("=IMAGE(\"", "");
        parsedPfp = parsedPfp?.replaceFirst("=image(\"", "");
        parsedPfp = parsedPfp?.substring(0, parsedPfp.length - 2).trim();
      }
      newMembers.add(
        Member(
          int.tryParse(googleMember[appMembersSchema.indexOf("ID")].toString()) ?? -1,
          googleMember[appMembersSchema.indexOf("Name")] as String,
          googleMember[appMembersSchema.indexOf("Titles")] as String,
          googleMember[appMembersSchema.indexOf("Groups")] as String,
          AttendanceStatus.values.byName(
            (googleMember[appMembersSchema.indexOf("Status")] as String).toLowerCase(),
          ),
          location: googleMember[appMembersSchema.indexOf("Location")] as String,
          passwordHash: googleMember.elementAtOrNull(appMembersSchema.indexOf("PasswordHash")) as String?,
          pfpUrl: (parsedPfp == null || parsedPfp.isEmpty) ? null : parsedPfp,
        ),
      );
    }
    attendance.value = newMembers;
    // cache members
  }

  Future<void> _update() async {
    if (googleConnected.value != true) {
      return;
    }

    // these will be used in the log for full data
    final frozenClockInQueue = _clockInQueue.toList();
    final frozenClockOutQueue = _clockOutQueue.toList();
    final frozenUpdatesQueue = _updatesQueue.toList();
    List<TimeClockEvent> timeClockEvents =
        (frozenClockInQueue + frozenClockOutQueue + frozenUpdatesQueue)
          ..sort((a, b) => a.time.compareTo(b.time));

    // these will be used in the member table for current data
    Map<int, List<AttendanceStatus>> userStatusUpdates = {};
    Map<int, String> userLocationUpdates = {};
    Map<int, String> passwordHashUpdates = {};

    ValueRange? memberIdTableResponse;
    try {
      memberIdTableResponse = await _sheetsClient?.spreadsheets.values.get(
        _sheetId ?? "",
        AttendanceTrackerBackend.memberSheetIdsRange,
      );
    } on SocketException catch (e) {
      logger.w("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      logger.w("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    } on DetailedApiRequestError catch (e) {
      logger.w("Google is down with error!!! $e");
      googleConnected.value = false;
      return;
    }

    if (memberIdTableResponse == null || memberIdTableResponse.values == null) {
      return;
    }
    List<int> memberIds = [];
    for (var item in memberIdTableResponse.values!) {
      if (item.isEmpty) {
        logger.w(
          "Malformed user ID detected in member ID table, skipping member update, ID is empty",
        );
        continue;
      }
      memberIds.add(int.parse(item[0].toString()));
    }

    for (TimeClockEvent event in timeClockEvents) {
      if (!memberIds.contains(event.memberId)) {
        logger.w(
          "Member ID ${event.memberId} not found in table, maybe the member list was remotely updated?",
        );
        continue;
      }
      if (event is PasswordResetEvent) {
        passwordHashUpdates[event.memberId] = event.newHash;
        continue;
      }

      if (event is ClockOutEvent) {
        _logQueue.add(
          MemberLogEntry(
            event.memberId,
            event.isAuto ? MemberLoggerAction.checkOutAuto : MemberLoggerAction.checkOut,
            event.time,
            "NULL",
          ),
        );
      } else if (event is ClockInEvent) {
        _logQueue.add(
          MemberLogEntry(
            event.memberId,
            MemberLoggerAction.checkIn,
            event.time,
            event.location,
          ),
        );
      }

      userStatusUpdates.update(
        event.memberId,
        (list) => list
          ..add(
            event is ClockInEvent
                ? AttendanceStatus.present
                : AttendanceStatus.out,
          ),
        ifAbsent: () => [
          event is ClockInEvent
              ? AttendanceStatus.present
              : AttendanceStatus.out,
        ],
      );
      if (event is ClockInEvent) {
        userLocationUpdates[event.memberId] = event.location;
      } else {
        userLocationUpdates[event.memberId] = "NULL";
      }
    }

    try {
      // Build ValueRange updates
      final List<ValueRange> updates = [];

      for (final entry in userStatusUpdates.entries) {
        final memberId = entry.key;
        final statusUpdates = entry.value;

        final index = memberIds.indexOf(memberId);

        if (index == -1) continue; // skip if ID not found

        final row = index + 3;
        final range = '${memberSheetContentsRange.split("!").first}!D$row';
        updates.add(
          ValueRange(
            range: range,
            values: [
              [
                statusUpdates.last.toString().split('.').last.capitalize(),
                userLocationUpdates[memberId]?.isEmpty ?? true
                    ? "NULL"
                    : userLocationUpdates[memberId] ?? "NULL",
              ],
            ],
          ),
        );
      }

      // Add password hash updates
      for (final entry in passwordHashUpdates.entries) {
        final memberId = entry.key;
        final hash = entry.value;
        final index = memberIds.indexOf(memberId);
        if (index == -1) continue;
        final row = index + 3;
        final range = '${memberSheetContentsRange.split("!").first}!F$row';
        updates.add(
          ValueRange(
            range: range,
            values: [
              [hash],
            ],
          ),
        );
      }

      final batchRequest = BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED', // preserve dropdown formatting
        data: updates,
      );

      await _sheetsClient?.spreadsheets.values.batchUpdate(
        batchRequest,
        _sheetId ?? "",
      );
    } on SocketException catch (e) {
      logger.w("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      logger.w("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    } on DetailedApiRequestError catch (e) {
      logger.w("Google is down with error!!! $e");
      googleConnected.value = false;
      return;
    }

    _clockInQueue.removeWhere(
      (element) => frozenClockInQueue.contains(element),
    );
    _clockOutQueue.removeWhere(
      (element) => frozenClockOutQueue.contains(element),
    );
    _updatesQueue.removeWhere(
      (element) => frozenUpdatesQueue.contains(element),
    );
  }

  Future<void> _updateLog() async {
    if (googleConnected.value != true) {
      return;
    }

    // fetch log header
    ValueRange? header;
    try {
      header = await _sheetsClient?.spreadsheets.values.get(
        _sheetId ?? "",
        AttendanceTrackerBackend.logSheetHeaderRange,
      );
    } on SocketException catch (e) {
      logger.w("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      logger.w("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    } on DetailedApiRequestError catch (e) {
      logger.w("Google is down with error!!! $e");
      googleConnected.value = false;
      return;
    }

    if (header?.values == null) {
      // construct header from members
      await _waitUntilMembersLoaded();
      List<List<String>> newMemberHeader = [[], [], []];
      for (final member in attendance.value) {
        newMemberHeader[0].add(member.id.toString());
        newMemberHeader[0].add(member.name);
        newMemberHeader[0].add(
          "=MAX(FILTER(ROW(${columnToReference(newMemberHeader[0].length - 1)}3:${columnToReference(newMemberHeader[0].length + 1)}), BYROW(${columnToReference(newMemberHeader[0].length - 1)}3:${columnToReference(newMemberHeader[0].length + 1)}, LAMBDA(r, COUNTA(r) > 0))))",
        );
        newMemberHeader[0].add("");
        newMemberHeader[1].add("Timestamp");
        newMemberHeader[1].add("Location");
        newMemberHeader[1].add("Action");
        newMemberHeader[1].add("");
        newMemberHeader[2].add(
          "=EPOCHTODATE(${DateTime.now().toUtc().millisecondsSinceEpoch}, 2)",
        );
        newMemberHeader[2].add("NULL");
        newMemberHeader[2].add("CREATED");
        newMemberHeader[2].add("");
      }
      try {
        await _sheetsClient?.spreadsheets.values.update(
          ValueRange(
            values: newMemberHeader,
            range: AttendanceTrackerBackend.logSheetHeaderStart,
          ),
          _sheetId!,
          AttendanceTrackerBackend.logSheetHeaderStart,
          valueInputOption: "USER_ENTERED",
        );
      } on SocketException catch (e) {
        logger.w("Google is down!!! $e");
        googleConnected.value = false;
        return;
      } on TimeoutException catch (e) {
        logger.w("Google is down with timeout!!! $e");
        googleConnected.value = false;
        return;
      } on DetailedApiRequestError catch (e) {
        logger.w("Google is down with error!!! $e");
        googleConnected.value = false;
        return;
      }
      // TODO: this can be updated in-memory without a request
      // fetch log header
      try {
        header = await _sheetsClient?.spreadsheets.values.get(
          _sheetId ?? "",
          AttendanceTrackerBackend.logSheetHeaderRange,
        );
      } on SocketException catch (e) {
        logger.w("Google is down!!! $e");
        googleConnected.value = false;
        return;
      } on TimeoutException catch (e) {
        logger.w("Google is down with timeout!!! $e");
        googleConnected.value = false;
        return;
      } on DetailedApiRequestError catch (e) {
        logger.w("Google is down with error!!! $e");
        googleConnected.value = false;
        return;
      }
    } else {
      // format: ID, Name, " ", " ", ...
      // get remote ids
      List<int> remoteIds = [];
      for (int i = 0; i < (header?.values?[0].length ?? 0); i += 4) {
        final intId = int.tryParse(header?.values?[0][i].toString() ?? "");
        if (intId == null) {
          continue;
        }
        remoteIds.add(intId);
      }

      // now, check if there are different local ids than remote ids (must sync)
      List<int> mustSyncIds = [];
      for (final localId in attendance.value.map((member) => member.id)) {
        if (!remoteIds.contains(localId)) {
          mustSyncIds.add(localId);
        }
      }

      String nextUpdateRef = columnToReference(
        (header?.values?[0].length ?? 0) +
            2, // index at 1, 2 extra for space and next col
      );
      int nextRefUpdateIndex = (header?.values?[0].length ?? 0) + 2;

      List<ValueRange> headerUpdates = [];

      for (final syncId in mustSyncIds) {
        List<List<String>> newMemberLog = [
          [
            syncId.toString(),
            getMemberById(syncId).name,
            "=MAX(FILTER(ROW(${columnToReference(nextRefUpdateIndex)}3:${columnToReference(nextRefUpdateIndex + 2)}), BYROW(${columnToReference(nextRefUpdateIndex)}3:${columnToReference(nextRefUpdateIndex + 2)}, LAMBDA(r, COUNTA(r) > 0))))",
          ],
          ["Timestamp", "Location", "Action"],
          [
            "=EPOCHTODATE(${DateTime.now().toUtc().millisecondsSinceEpoch}, 2)",
            "NULL",
            "CREATED",
          ],
        ];

        final origin = "$logSheetName!${nextUpdateRef}2"; // starting cell
        headerUpdates.add(ValueRange(range: origin, values: newMemberLog));

        nextRefUpdateIndex += 4;
        nextUpdateRef = columnToReference(nextRefUpdateIndex);
      }

      // expand if needed
      Spreadsheet? sheetMetadata;
      try {
        sheetMetadata = await _sheetsClient!.spreadsheets.get(
          _sheetId!,
          ranges: [logSheetName],
        );
      } on SocketException catch (e) {
        logger.w("Google is down!!! $e");
        googleConnected.value = false;
        return;
      } on TimeoutException catch (e) {
        logger.w("Google is down with timeout!!! $e");
        googleConnected.value = false;
        return;
      } on DetailedApiRequestError catch (e) {
        logger.w("Google is down with error!!! $e");
        googleConnected.value = false;
        return;
      }

      final sheetProps = sheetMetadata.sheets!
          .firstWhere((s) => s.properties!.title == logSheetName)
          .properties!;
      final currentCols = sheetProps.gridProperties!.columnCount!;

      if (nextRefUpdateIndex > currentCols) {
        final resizeRequest = BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              updateSheetProperties: UpdateSheetPropertiesRequest(
                properties: SheetProperties(
                  sheetId: sheetProps.sheetId,
                  gridProperties: GridProperties(
                    columnCount: nextRefUpdateIndex,
                  ),
                ),
                fields: 'gridProperties.columnCount',
              ),
            ),
          ],
        );
        await _sheetsClient!.spreadsheets.batchUpdate(resizeRequest, _sheetId!);
      }

      final batchRequest = BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: headerUpdates,
      );

      // send
      try {
        await _sheetsClient?.spreadsheets.values.batchUpdate(
          batchRequest,
          _sheetId ?? "",
        );
      } on SocketException catch (e) {
        logger.w("Google is down!!! $e");
        googleConnected.value = false;
        return;
      } on TimeoutException catch (e) {
        logger.w("Google is down with timeout!!! $e");
        googleConnected.value = false;
        return;
      } on DetailedApiRequestError catch (e) {
        logger.w("Google is down with error!!! $e");
        googleConnected.value = false;
        return;
      }

      // update logs
      List<ValueRange> logUpdates = [];
      List<MemberLogEntry> toRemove = [];

      // get log counts WITHOUT making tons of API requests
      // Log lengths are calculated on Google's end by using a formula in the header
      // ex: =MAX(FILTER(ROW(A3:C), BYROW(A3:C, LAMBDA(r, COUNTA(r) > 0))))
      int maxRowNeeded = 0; // Track the deepest row we need to write

      for (final entry in _logQueue.toList()) {
        final startCol =
            header?.values?[0]
                .map((element) => element.toString())
                .toList(growable: false)
                .indexOf(entry.memberId.toString()) ??
            -2 + 1;
        if (startCol == -1) {
          logger.e(
            "User ID ${entry.memberId} not found in logs!!! Cancelling update",
          );
          return;
        }

        final memberEntriesBefore = _logQueue
            .toList()
            .sublist(0, _logQueue.toList().indexOf(entry))
            .where((e) => e.memberId == entry.memberId)
            .length;

        final safeNextLogRow =
            memberEntriesBefore +
            (int.tryParse((header?.values?[0][startCol + 2]).toString()) ??
                -2) +
            1;

        if (safeNextLogRow == -1) {
          logger.e(
            "Something is wrong with the log count for user ${entry.memberId}!!! Check the log header for errors. Cancelling update.",
          );
          return;
        }

        maxRowNeeded = safeNextLogRow > maxRowNeeded
            ? safeNextLogRow
            : maxRowNeeded;

        final logOrigin =
            "$logSheetName!${columnToReference(startCol + 1)}$safeNextLogRow";
        logUpdates.add(
          ValueRange(
            range: logOrigin,
            values: [
              [
                "=EPOCHTODATE(${entry.time.toUtc().millisecondsSinceEpoch}, 2)",
                entry.location,
                entry.action.name.toUpperCase(),
              ],
            ],
          ),
        );
        logger.t("Updated entry: $entry");
        toRemove.add(entry);
      }

      final currentRows = sheetProps.gridProperties!.rowCount!;

      if (maxRowNeeded > currentRows) {
        final resizeRequest = BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              updateSheetProperties: UpdateSheetPropertiesRequest(
                properties: SheetProperties(
                  sheetId: sheetProps.sheetId,
                  gridProperties: GridProperties(rowCount: maxRowNeeded),
                ),
                fields: 'gridProperties.rowCount',
              ),
            ),
          ],
        );
        await _sheetsClient!.spreadsheets.batchUpdate(resizeRequest, _sheetId!);
      }

      try {
        await _sheetsClient?.spreadsheets.values.batchUpdate(
          BatchUpdateValuesRequest(
            data: logUpdates,
            valueInputOption: "USER_ENTERED",
          ),
          _sheetId ?? "",
        );
        for (var entry in toRemove) {
          _logQueue.remove(entry);
        }
      } on SocketException catch (e) {
        logger.w("Google is down!!! $e");
        googleConnected.value = false;
        return;
      } on TimeoutException catch (e) {
        logger.w("Google is down with timeout!!! $e");
        googleConnected.value = false;
        return;
      } on DetailedApiRequestError catch (e) {
        logger.w("Google is down with error!!! $e");
        googleConnected.value = false;
        return;
      }
    }
  }

  List<String> getNames() {
    return attendance.value.map((member) => member.name).toList();
  }

  Member getMemberById(int id) {
    return attendance.value.firstWhere((member) => member.id == id);
  }

  bool isMember(int id) {
    return attendance.value.any((member) => member.id == id);
  }

  void clockOut(int memberId, {DateTime? time, bool isAuto = false}) {
    time ??= DateTime.now();

    if (!attendance.value.any((member) => member.id == memberId)) {
      throw Exception('Member with ID $memberId not found');
    }

    final event = ClockOutEvent(memberId, time, isAuto: isAuto);
    _clockOutQueue.add(event);
    // if (_clockInQueue
    //     .map((e) => e is ClockInEvent ? e.memberId : null)
    //     .contains(memberId)) {
    //   _clockInQueue.removeWhere(
    //     (e) => (e is ClockInEvent ? e.memberId : null) == memberId,
    //   );
    // }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        attendance.value[memberIndex].titles,
        attendance.value[memberIndex].groups,
        AttendanceStatus.out,
        location: null,
        passwordHash: attendance.value[memberIndex].passwordHash,
        pfpUrl: attendance.value[memberIndex].pfpUrl,
      );
      attendance.value = [
        ...attendance.value,
      ]; // I think this is a bug in ValueNotifier
    }
    logger.d('Member with ID $memberId marked for clock out');

    _reactivateCooldown();
  }

  void clockIn(int memberId, String location) {
    if (!attendance.value.any((member) => member.id == memberId)) {
      throw Exception('Member with ID $memberId not found');
    }

    final event = ClockInEvent(memberId, DateTime.now(), location);
    _clockInQueue.add(event);
    // if (_clockOutQueue
    //     .map((e) => e is ClockOutEvent ? e.memberId : null)
    //     .contains(memberId)) {
    //   _clockOutQueue.removeWhere(
    //     (e) => (e is ClockOutEvent ? e.memberId : null) == memberId,
    //   );
    // }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        attendance.value[memberIndex].titles,
        attendance.value[memberIndex].groups,
        AttendanceStatus.present,
        location: location,
        passwordHash: attendance.value[memberIndex].passwordHash,
        pfpUrl: attendance.value[memberIndex].pfpUrl,
      );
      attendance.value = [
        ...attendance.value,
      ]; // I think this is a bug in ValueNotifier
    }
    logger.d('Member with ID $memberId marked for clock in');

    _reactivateCooldown();
  }

  Future<void> resetPassword(int memberId, String passwordString) async {
    String hash = hashPin(passwordString);
    final event = PasswordResetEvent(memberId, DateTime.now(), hash);
    _updatesQueue.add(event);
    while (_updatesQueue.contains(event)) {
      await Future.delayed(const Duration(milliseconds: 100));
      await _update();
      await _waitUntilQueuesEmpty();
      await _updateMembers();
    }

    _reactivateCooldown();
  }

  Future<void> instantMemberUpdate() async {
    await _update();
    await _waitUntilQueuesEmpty();
    await _updateMembers();
  }

  int getPushLength() {
    return _clockInQueue.toList().length + _clockOutQueue.toList().length;
  }

  void _reactivateCooldown() {
    bool wasActive = pullDuration == pullDurationActive;
    pullDuration = pullDurationActive;
    pushDuration = pushDurationActive;
    if (!wasActive) {
      _updateTimer?.restartWith(pushDuration!);
      _memberFetchTimer?.restartWith(pullDuration!);
    }
    activeCooldownTimer?.reset();
    logger.d(
      "Switched to active sync intervals: pull=${pullDuration!.inSeconds}s, push=${pushDuration!.inSeconds}s",
    );
  }
}
