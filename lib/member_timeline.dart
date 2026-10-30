import 'dart:async';

import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';
import 'package:second/backend.dart';
import 'package:second/util.dart';

/// Represents a single raw log event read from Google Sheets or pending queue.
class RawLogEvent {
  final int rowIndex; // 1-based row index in Google Sheets
  final DateTime timestamp;
  final String eventType; // "CHECKIN", "CHECKOUT", "CHECKOUTAUTO"
  final String location;
  final String note;
  final bool isPending;

  RawLogEvent({
    required this.rowIndex,
    required this.timestamp,
    required this.eventType,
    required this.location,
    this.note = '',
    this.isPending = false,
  });

  bool get isClockIn => eventType == 'CHECKIN';

  bool get isClockOut =>
      eventType == 'CHECKOUT' || eventType == 'CHECKOUTAUTO';

  bool get isAutoOut => eventType == 'CHECKOUTAUTO';

  Map<String, dynamic> toMap() {
    return {
      'rowIndex': rowIndex,
      'timestamp': timestamp.toIso8601String(),
      'eventType': eventType,
      'location': location,
      'note': note,
      'isPending': isPending,
    };
  }
}

/// Represents a coupled shift consisting of a Clock-In and an optional Clock-Out.
class MemberShift {
  final String id;
  final int memberId;
  final RawLogEvent clockInEvent;
  final RawLogEvent? clockOutEvent;

  MemberShift({
    required this.id,
    required this.memberId,
    required this.clockInEvent,
    this.clockOutEvent,
  });

  DateTime get clockInTime => clockInEvent.timestamp;
  DateTime? get clockOutTime => clockOutEvent?.timestamp;
  String get clockInLocation => clockInEvent.location;
  String? get clockOutLocation => null;

  bool get isOpen => clockOutEvent == null;

  /// Auto-out is ONLY true if the clock-out event is explicitly CHECKOUTAUTO.
  bool get isAutoOut => clockOutEvent?.isAutoOut ?? false;

  Duration? get duration => clockOutTime?.difference(clockInTime);

  /// Returns true if this is an open shift without a clock-out.
  bool get isOnlyClockIn => isOpen;
}

/// Result container for timeline repair operations.
class RepairTimelineResult {
  final bool repaired;
  final String message;
  final int removedEventsCount;
  final int autoClosedShiftsCount;
  final int cleanEventsCount;

  RepairTimelineResult({
    required this.repaired,
    required this.message,
    this.removedEventsCount = 0,
    this.autoClosedShiftsCount = 0,
    this.cleanEventsCount = 0,
  });
}

/// Manager class that interfaces with AttendanceTrackerBackend to provide
/// a bad-data resistant shift timeline for members with full
/// edit/create/remove capabilities for coupled shifts and overlap prevention.
class MemberTimelineManager {
  static const int maxSpreadsheetCells = 10000000;

  final AttendanceTrackerBackend backend;

  MemberTimelineManager(this.backend);

  /// Checks whether a proposed shift time range [clockInTime, clockOutTime]
  /// overlaps with any existing shift for the member.
  static bool hasOverlap({
    required List<MemberShift> existingShifts,
    required DateTime clockInTime,
    DateTime? clockOutTime,
    String? excludeShiftId,
  }) {
    final DateTime newStart = clockInTime;
    final DateTime newEnd = clockOutTime ?? DateTime.now();

    for (final shift in existingShifts) {
      if (excludeShiftId != null && shift.id == excludeShiftId) {
        continue;
      }

      final DateTime existingStart = shift.clockInTime;
      final DateTime existingEnd = shift.clockOutTime ?? DateTime.now();

      // Interval overlap condition: newStart < existingEnd AND existingStart < newEnd
      if (newStart.isBefore(existingEnd) && existingStart.isBefore(newEnd)) {
        return true;
      }
    }
    return false;
  }

  /// Fetches raw header block info for a given member from row 2 of INTERNAL.Log
  Future<({int blockIndex, int startCol, int endCol, int entryCount})?>
      _getMemberBlockInfo(int memberId) async {
    final sheetsClient = backend.sheetsClient;
    final sheetId = backend.sheetId;
    if (sheetsClient == null || sheetId == null) return null;

    try {
      final response = await sheetsClient.spreadsheets.values.get(
        sheetId,
        valueRenderOption: 'UNFORMATTED_VALUE',
        majorDimension: 'ROWS',
        AttendanceTrackerBackend.logSheetHeaderRange,
      );

      final row2 = (response.values != null && response.values!.isNotEmpty)
          ? response.values![0]
          : <dynamic>[];

      for (var i = 0; i < row2.length; i += 4) {
        final rawId = row2[i];
        final id = int.tryParse(rawId.toString());
        if (id == memberId) {
          int count = 0;
          if (i + 2 < row2.length) {
            final rawCount = row2[i + 2];
            count = int.tryParse(rawCount.toString()) ?? 0;
          }
          if (count < 0) count = 0;

          final blockIndex = i ~/ 4;
          final startCol = blockIndex * 4 + 1;
          final endCol = blockIndex * 4 + 4;

          return (
            blockIndex: blockIndex,
            startCol: startCol,
            endCol: endCol,
            entryCount: count,
          );
        }
      }
    } catch (e) {
      backend.logger.e('Failed to fetch member log header info: $e');
    }
    return null;
  }

  /// Locates the 1-based row index for a member ID in the Members sheet (Members!A3:A).
  Future<int?> _getMemberRowInMembersSheet(int memberId) async {
    final sheetsClient = backend.sheetsClient;
    final sheetId = backend.sheetId;
    if (sheetsClient == null || sheetId == null) return null;

    try {
      final response = await sheetsClient.spreadsheets.values.get(
        sheetId,
        AttendanceTrackerBackend.memberSheetIdsRange, // Members!A3:A
      );
      final rows = response.values ?? [];
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].isNotEmpty) {
          final id = int.tryParse(rows[i][0].toString());
          if (id == memberId) {
            return 3 + i; // 1-based row in Members sheet
          }
        }
      }
    } catch (e) {
      backend.logger.e('Failed to find member row in Members sheet: $e');
    }
    return null;
  }

  /// Updates the member's current status and location in the Members sheet and in backend.attendance.
  /// If the latest shift is incomplete/open, sets Status="Present" and Location=clockInLocation.
  /// Otherwise, sets Status="Out" and Location="NULL".
  Future<void> updateMemberStatusFromTimeline(int memberId) async {
    final rawEvents = await fetchRawEventsForMember(memberId);
    final shifts = processEventsIntoShifts(memberId, rawEvents);

    final bool isOpenShift = shifts.isNotEmpty && shifts.first.isOpen;
    final AttendanceStatus newStatus =
        isOpenShift ? AttendanceStatus.present : AttendanceStatus.out;
    final String newLocation =
        isOpenShift ? shifts.first.clockInLocation : 'NULL';

    // 1. Synchronize in-memory backend.attendance list
    final index = backend.attendance.value.indexWhere((m) => m.id == memberId);
    if (index != -1) {
      final old = backend.attendance.value[index];
      backend.attendance.value[index] = Member(
        old.id,
        old.name,
        old.nickname,
        old.titles,
        old.groups,
        newStatus,
        location: newStatus == AttendanceStatus.present ? newLocation : null,
        passwordHash: old.passwordHash,
        pfpUrl: old.pfpUrl,
      );
      backend.attendance.value = List.from(backend.attendance.value);
    }

    // 2. Synchronize Google Sheets Members sheet (Members!G<row>:H<row>)
    final sheetsClient = backend.sheetsClient;
    final sheetId = backend.sheetId;
    if (sheetsClient != null && sheetId != null) {
      final memberRow = await _getMemberRowInMembersSheet(memberId);
      if (memberRow != null) {
        final range = 'Members!G$memberRow:H$memberRow';
        final valueRange = ValueRange(
          range: range,
          values: [
            [
              newStatus == AttendanceStatus.present ? 'Present' : 'Out',
              newStatus == AttendanceStatus.present ? newLocation : 'NULL',
            ],
          ],
        );
        try {
          await sheetsClient.spreadsheets.values.update(
            valueRange,
            sheetId,
            range,
            valueInputOption: 'USER_ENTERED',
          );
        } catch (e) {
          backend.logger.e('Failed to update member status in Members sheet: $e');
        }
      }
    }
  }

  /// Parses various Google Sheets / string timestamp representations into a valid DateTime.
  /// All sheet values are in UTC and converted to local device time via .toLocal().
  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;

    if (raw is num) {
      // If it looks like epoch milliseconds (UTC)
      if (raw > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true).toLocal();
      }
      if (raw > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000, isUtc: true).toLocal();
      }
      // Excel / Google Sheets serial date number in UTC (days since Dec 30, 1899)
      if (raw > 30000 && raw < 80000) {
        final millis = ((raw - 25569) * 86400 * 1000).round();
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
      }
    }

    final str = raw.toString().trim();
    if (str.isEmpty) return null;

    // Try standard ISO 8601 string
    final isoParsed = DateTime.tryParse(str);
    if (isoParsed != null) {
      if (isoParsed.isUtc) {
        return isoParsed.toLocal();
      } else {
        return DateTime.utc(
          isoParsed.year,
          isoParsed.month,
          isoParsed.day,
          isoParsed.hour,
          isoParsed.minute,
          isoParsed.second,
          isoParsed.millisecond,
          isoParsed.microsecond,
        ).toLocal();
      }
    }

    // Try epoch integer in string form
    final intParsed = int.tryParse(str);
    if (intParsed != null) {
      if (intParsed > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(intParsed, isUtc: true).toLocal();
      }
      if (intParsed > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(intParsed * 1000, isUtc: true).toLocal();
      }
    }

    // Common date format strings fallback (parsed as UTC)
    final formats = [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'MM/dd/yyyy HH:mm:ss',
      'MM/dd/yyyy hh:mm:ss a',
      'M/d/yyyy H:m:s',
      'dd/MM/yyyy HH:mm:ss',
    ];

    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseUtc(str).toLocal();
      } catch (_) {}
    }

    return null;
  }

  /// Normalizes event action strings strictly to CHECKIN, CHECKOUT, or CHECKOUTAUTO.
  static String _normalizeEventType(dynamic raw) {
    if (raw == null) return 'CHECKIN';
    final s = raw.toString().trim().toUpperCase().replaceAll('-', '').replaceAll('_', '');
    if (s.contains('CHECKOUTAUTO') || s.contains('AUTOOUT') || s.contains('CHECKOUTA')) {
      return 'CHECKOUTAUTO';
    }
    if (s.contains('CHECKOUT') || s.contains('OUT') || s.contains('LOGOUT')) {
      return 'CHECKOUT';
    }
    if (s.contains('CHECKIN') || s.contains('IN') || s.contains('LOGIN')) {
      return 'CHECKIN';
    }
    return 'CHECKIN';
  }

  /// Fetches raw log events for a member from Google Sheets and merges pending local entries.
  Future<List<RawLogEvent>> fetchRawEventsForMember(int memberId) async {
    final List<RawLogEvent> events = [];

    final blockInfo = await _getMemberBlockInfo(memberId);
    if (blockInfo != null && backend.sheetsClient != null && backend.sheetId != null) {
      final requestedRowCount = blockInfo.entryCount + 101;
      final requestedColumnCount = blockInfo.endCol - blockInfo.startCol + 1;
      final requestedCellCount = requestedRowCount * requestedColumnCount;
      if (requestedCellCount > maxSpreadsheetCells) {
        throw Exception(
          'Cannot load the full timeline for member $memberId: the requested '
          'log range contains $requestedCellCount cells, which exceeds the '
          'Google Sheets limit of $maxSpreadsheetCells cells.',
        );
      }

      final startColLetter = columnToReference(blockInfo.startCol);
      final endColLetter = columnToReference(blockInfo.endCol);

      // Read rows starting from row 4
      final range =
          '${AttendanceTrackerBackend.logSheetName}!${startColLetter}4:$endColLetter${4 + blockInfo.entryCount + 100}';

      try {
        final response = await backend.sheetsClient!.spreadsheets.values.get(
          backend.sheetId!,
          range,
          valueRenderOption: 'UNFORMATTED_VALUE',
          dateTimeRenderOption: 'FORMATTED_STRING',
        );

        final rows = response.values ?? [];
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          if (row.isEmpty) continue;

          final rowIndex = 4 + i;
          final rawTime = row.isNotEmpty ? row[0] : null;
          final rawEvent = row.length > 1 ? row[1] : null;
          final rawLoc = row.length > 2 ? row[2] : null;
          final rawNote = row.length > 3 ? row[3] : null;

          final timestamp = _parseTimestamp(rawTime);
          if (timestamp == null) continue; // Skip bad row without crashing

          final eventType = _normalizeEventType(rawEvent);
          final location = rawLoc?.toString().trim() ?? 'Shop';
          final note = rawNote?.toString().trim() ?? '';

          events.add(
            RawLogEvent(
              rowIndex: rowIndex,
              timestamp: timestamp,
              eventType: eventType,
              location: location,
              note: note,
            ),
          );
        }
      } catch (e) {
        backend.logger.e('Failed to fetch raw log rows for member $memberId: $e');
      }
    }

    return events;
  }

  /// Pairs raw log events into shifts chronologically.
  /// Does NOT assume CHECKOUTAUTO for unclosed check-ins.
  /// Auto-out is only true if the event in the sheet is explicitly CHECKOUTAUTO.
  static List<MemberShift> processEventsIntoShifts(
    int memberId,
    List<RawLogEvent> rawEvents,
  ) {
    if (rawEvents.isEmpty) return [];

    // 1. Sort raw events chronologically by timestamp (and rowIndex as tiebreaker)
    final sorted = List<RawLogEvent>.from(rawEvents)
      ..sort((a, b) {
        final cmp = a.timestamp.compareTo(b.timestamp);
        if (cmp != 0) return cmp;
        return a.rowIndex.compareTo(b.rowIndex);
      });

    final List<MemberShift> shifts = [];
    RawLogEvent? openClockIn;

    for (var i = 0; i < sorted.length; i++) {
      final ev = sorted[i];

      if (ev.isClockIn) {
        if (openClockIn != null) {
          // Unclosed previous check-in remains an open shift (no assumed auto-out).
          shifts.add(
            MemberShift(
              id: 'shift_${memberId}_${openClockIn.rowIndex}_open',
              memberId: memberId,
              clockInEvent: openClockIn,
              clockOutEvent: null,
            ),
          );
        }
        openClockIn = ev;
      } else if (ev.isClockOut) {
        if (openClockIn != null) {
          // Matched CHECKIN + CHECKOUT/CHECKOUTAUTO shift
          shifts.add(
            MemberShift(
              id: 'shift_${memberId}_${openClockIn.rowIndex}_${ev.rowIndex}',
              memberId: memberId,
              clockInEvent: openClockIn,
              clockOutEvent: ev,
            ),
          );
          openClockIn = null;
        }
      }
    }

    // Trailing open clock-in
    if (openClockIn != null) {
      shifts.add(
        MemberShift(
          id: 'shift_${memberId}_${openClockIn.rowIndex}_open',
          memberId: memberId,
          clockInEvent: openClockIn,
          clockOutEvent: null,
        ),
      );
    }

    // Reverse to show latest shifts first in timeline
    return shifts.reversed.toList();
  }

  /// Analyzes a member's raw log events, fixes broken ordering, duplicate check-ins/check-outs,
  /// orphan check-outs, and rewrites a clean balanced timeline back to Google Sheets.
  Future<RepairTimelineResult> repairMemberTimeline(int memberId) async {
    final rawEvents = await fetchRawEventsForMember(memberId);
    if (rawEvents.isEmpty) {
      return RepairTimelineResult(
        repaired: false,
        message: 'No log events found for this member.',
      );
    }

    // 1. Sort raw events chronologically by timestamp (and rowIndex as tiebreaker)
    final sorted = List<RawLogEvent>.from(rawEvents)
      ..sort((a, b) {
        final cmp = a.timestamp.compareTo(b.timestamp);
        if (cmp != 0) return cmp;
        return a.rowIndex.compareTo(b.rowIndex);
      });

    final List<RawLogEvent> cleanEvents = [];
    int removedEventsCount = 0;
    int autoClosedShiftsCount = 0;

    bool isClockedIn = false;
    RawLogEvent? lastInEvent;

    for (var i = 0; i < sorted.length; i++) {
      final ev = sorted[i];

      if (ev.isClockIn) {
        if (!isClockedIn) {
          cleanEvents.add(ev);
          isClockedIn = true;
          lastInEvent = ev;
        } else {
          // Duplicate CHECKIN while already clocked in!
          // Check if duplicate CHECKIN occurred within 5 minutes of previous CHECKIN
          if (lastInEvent != null &&
              ev.timestamp.difference(lastInEvent.timestamp).inMinutes < 5) {
            // Rapid duplicate check-in: discard redundant event
            removedEventsCount++;
          } else {
            // Check-in occurred later: auto-close previous shift with CHECKOUTAUTO 1 second before new check-in
            final autoOutTime = ev.timestamp.subtract(const Duration(seconds: 1));
            cleanEvents.add(
              RawLogEvent(
                rowIndex: -1,
                timestamp: autoOutTime,
                eventType: 'CHECKOUTAUTO',
                location: 'NULL',
                note: 'Auto-closed during timeline repair',
              ),
            );
            autoClosedShiftsCount++;

            // Add the new check-in
            cleanEvents.add(ev);
            lastInEvent = ev;
          }
        }
      } else if (ev.isClockOut) {
        if (isClockedIn) {
          cleanEvents.add(
            RawLogEvent(
              rowIndex: ev.rowIndex,
              timestamp: ev.timestamp,
              eventType: ev.eventType, // Keep CHECKOUT or CHECKOUTAUTO
              location: 'NULL',
              note: ev.note,
            ),
          );
          isClockedIn = false;
          lastInEvent = null;
        } else {
          // Orphan CHECKOUT without prior CHECKIN: remove
          removedEventsCount++;
        }
      }
    }

    // Check if any repair changes were made
    bool needsRepair = (cleanEvents.length != rawEvents.length) ||
        removedEventsCount > 0 ||
        autoClosedShiftsCount > 0;

    if (!needsRepair) {
      // Check if ordering or format in sheet differed
      for (var i = 0; i < cleanEvents.length; i++) {
        if (cleanEvents[i].rowIndex != rawEvents[i].rowIndex ||
            cleanEvents[i].eventType != rawEvents[i].eventType) {
          needsRepair = true;
          break;
        }
      }
    }

    if (!needsRepair) {
      return RepairTimelineResult(
        repaired: false,
        message: 'Timeline is healthy and balanced. No repairs needed.',
      );
    }

    // Apply repair to Google Sheets
    final blockInfo = await _getMemberBlockInfo(memberId);
    if (blockInfo == null || backend.sheetsClient == null || backend.sheetId == null) {
      throw Exception('Member block info not found or Google Sheets disconnected.');
    }

    final startColLetter = columnToReference(blockInfo.startCol);
    final endColLetter = columnToReference(blockInfo.endCol);

    final maxRow = 4 + (rawEvents.length > cleanEvents.length ? rawEvents.length : cleanEvents.length) + 10;

    // Clear old rows for member
    final clearRows = List.generate(
      maxRow - 4,
      (_) => ['', '', '', ''],
    );

    if (clearRows.isNotEmpty) {
      final clearRange =
          '${AttendanceTrackerBackend.logSheetName}!${startColLetter}4:$endColLetter$maxRow';
      await backend.sheetsClient!.spreadsheets.values.update(
        ValueRange(range: clearRange, values: clearRows),
        backend.sheetId!,
        clearRange,
        valueInputOption: 'USER_ENTERED',
      );
    }

    // Write clean repaired events
    if (cleanEvents.isNotEmpty) {
      final repairedRows = cleanEvents.map((e) {
        return [
          '=EPOCHTODATE(${e.timestamp.toUtc().millisecondsSinceEpoch}, 2)',
          e.eventType,
          e.isClockIn ? e.location : 'NULL',
          e.note,
        ];
      }).toList();

      final updateRange =
          '${AttendanceTrackerBackend.logSheetName}!${startColLetter}4:$endColLetter${3 + cleanEvents.length}';

      await backend.sheetsClient!.spreadsheets.values.update(
        ValueRange(range: updateRange, values: repairedRows),
        backend.sheetId!,
        updateRange,
        valueInputOption: 'USER_ENTERED',
      );
    }

    // Synchronize member status in Members sheet & in memory
    await updateMemberStatusFromTimeline(memberId);

    return RepairTimelineResult(
      repaired: true,
      message: 'Timeline successfully repaired! '
          'Removed $removedEventsCount invalid/duplicate event(s), '
          'auto-closed $autoClosedShiftsCount shift(s).',
      removedEventsCount: removedEventsCount,
      autoClosedShiftsCount: autoClosedShiftsCount,
      cleanEventsCount: cleanEvents.length,
    );
  }

  /// Fetches the full shift timeline for a given member.
  Future<List<MemberShift>> getMemberTimeline(int memberId) async {
    final rawEvents = await fetchRawEventsForMember(memberId);
    return processEventsIntoShifts(memberId, rawEvents);
  }

  /// Creates a new shift (both CHECKIN and optional CHECKOUT) for a member.
  /// Prevents overlapping shifts and updates Members sheet status.
  Future<void> createShift(
    int memberId, {
    required DateTime clockInTime,
    required String clockInLocation,
    DateTime? clockOutTime,
  }) async {
    if (clockOutTime != null && !clockOutTime.isAfter(clockInTime)) {
      throw Exception('Clock-out time must be after clock-in time.');
    }

    final rawEvents = await fetchRawEventsForMember(memberId);
    final existingShifts = processEventsIntoShifts(memberId, rawEvents);

    if (hasOverlap(
      existingShifts: existingShifts,
      clockInTime: clockInTime,
      clockOutTime: clockOutTime,
    )) {
      throw Exception(
          'Cannot create shift: Proposed shift time range overlaps with an existing shift.');
    }

    final blockInfo = await _getMemberBlockInfo(memberId);
    if (blockInfo == null || backend.sheetsClient == null || backend.sheetId == null) {
      throw Exception('Member block info not found or Google Sheets disconnected.');
    }

    final startColLetter = columnToReference(blockInfo.startCol);
    final endColLetter = columnToReference(blockInfo.endCol);

    final rowsToAppend = [
      [
        "=EPOCHTODATE(${clockInTime.toUtc().millisecondsSinceEpoch}, 2)",
        "CHECKIN",
        clockInLocation,
        "",
      ],
      if (clockOutTime != null)
        [
          "=EPOCHTODATE(${clockOutTime.toUtc().millisecondsSinceEpoch}, 2)",
          "CHECKOUT",
          "NULL",
          "",
        ],
    ];

    final appendRowIndex = 4 + blockInfo.entryCount;
    final range =
        '${AttendanceTrackerBackend.logSheetName}!$startColLetter$appendRowIndex:$endColLetter${appendRowIndex + rowsToAppend.length - 1}';

    final valueRange = ValueRange(
      range: range,
      values: rowsToAppend,
    );

    await backend.sheetsClient!.spreadsheets.values.update(
      valueRange,
      backend.sheetId!,
      range,
      valueInputOption: 'USER_ENTERED',
    );

    // Synchronize member status in Members sheet & in memory
    await updateMemberStatusFromTimeline(memberId);
  }

  /// Edits an existing coupled shift in Google Sheets.
  /// Prevents overlapping shifts and updates Members sheet status.
  Future<void> editShift(
    MemberShift shift, {
    required DateTime newClockInTime,
    required String newClockInLocation,
    DateTime? newClockOutTime,
  }) async {
    if (newClockOutTime != null && !newClockOutTime.isAfter(newClockInTime)) {
      throw Exception('Clock-out time must be after clock-in time.');
    }

    final rawEvents = await fetchRawEventsForMember(shift.memberId);
    final existingShifts = processEventsIntoShifts(shift.memberId, rawEvents);

    if (hasOverlap(
      existingShifts: existingShifts,
      clockInTime: newClockInTime,
      clockOutTime: newClockOutTime,
      excludeShiftId: shift.id,
    )) {
      throw Exception(
          'Cannot update shift: Proposed shift time range overlaps with an existing shift.');
    }

    final blockInfo = await _getMemberBlockInfo(shift.memberId);
    if (blockInfo == null || backend.sheetsClient == null || backend.sheetId == null) {
      throw Exception('Member block info not found or Google Sheets disconnected.');
    }

    final startColLetter = columnToReference(blockInfo.startCol);
    final endColLetter = columnToReference(blockInfo.endCol);

    final List<ValueRange> updates = [];

    // 1. Update CHECKIN row
    final inRow = shift.clockInEvent.rowIndex;
    if (inRow >= 4) {
      updates.add(
        ValueRange(
          range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$inRow:$endColLetter$inRow',
          values: [
            [
              "=EPOCHTODATE(${newClockInTime.toUtc().millisecondsSinceEpoch}, 2)",
              "CHECKIN",
              newClockInLocation,
              "",
            ],
          ],
        ),
      );
    }

    // 2. Update or append CHECKOUT row
    if (shift.clockOutEvent != null) {
      final outRow = shift.clockOutEvent!.rowIndex;
      if (outRow >= 4) {
        if (newClockOutTime != null) {
          updates.add(
            ValueRange(
              range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$outRow:$endColLetter$outRow',
              values: [
                [
                  "=EPOCHTODATE(${newClockOutTime.toUtc().millisecondsSinceEpoch}, 2)",
                  "CHECKOUT",
                  "NULL",
                  "",
                ],
              ],
            ),
          );
        } else {
          // Clear CHECKOUT row if removed
          updates.add(
            ValueRange(
              range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$outRow:$endColLetter$outRow',
              values: [
                ["", "", "", ""],
              ],
            ),
          );
        }
      }
    } else if (newClockOutTime != null) {
      // Append new CHECKOUT row for previously open shift
      final appendRow = 4 + blockInfo.entryCount;
      updates.add(
        ValueRange(
          range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$appendRow:$endColLetter$appendRow',
          values: [
            [
              "=EPOCHTODATE(${newClockOutTime.toUtc().millisecondsSinceEpoch}, 2)",
              "CHECKOUT",
              "NULL",
              "",
            ],
          ],
        ),
      );
    }

    if (updates.isNotEmpty) {
      final batchRequest = BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: updates,
      );
      await backend.sheetsClient!.spreadsheets.values.batchUpdate(
        batchRequest,
        backend.sheetId!,
      );
    }

    // Synchronize member status in Members sheet & in memory
    await updateMemberStatusFromTimeline(shift.memberId);
  }

  /// Removes a shift. Per requirements, in/out events for a shift are coupled
  /// and cannot be deleted independently, unless only clocking in as the last event.
  /// Synchronizes member status in Members sheet after deletion.
  Future<void> deleteShift(MemberShift shift) async {
    final blockInfo = await _getMemberBlockInfo(shift.memberId);
    if (blockInfo == null || backend.sheetsClient == null || backend.sheetId == null) {
      throw Exception('Member block info not found or Google Sheets disconnected.');
    }

    final startColLetter = columnToReference(blockInfo.startCol);
    final endColLetter = columnToReference(blockInfo.endCol);

    final List<ValueRange> updates = [];

    // Clear CHECKIN row
    final inRow = shift.clockInEvent.rowIndex;
    if (inRow >= 4) {
      updates.add(
        ValueRange(
          range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$inRow:$endColLetter$inRow',
          values: [
            ["", "", "", ""],
          ],
        ),
      );
    }

    // Clear CHECKOUT row if present (coupled deletion)
    if (shift.clockOutEvent != null) {
      final outRow = shift.clockOutEvent!.rowIndex;
      if (outRow >= 4) {
        updates.add(
          ValueRange(
            range: '${AttendanceTrackerBackend.logSheetName}!$startColLetter$outRow:$endColLetter$outRow',
            values: [
              ["", "", "", ""],
            ],
          ),
        );
      }
    }

    if (updates.isNotEmpty) {
      final batchRequest = BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: updates,
      );
      await backend.sheetsClient!.spreadsheets.values.batchUpdate(
        batchRequest,
        backend.sheetId!,
      );
    }

    // Synchronize member status in Members sheet & in memory
    await updateMemberStatusFromTimeline(shift.memberId);
  }
}
