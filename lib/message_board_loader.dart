import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:googleapis/sheets/v4.dart';

class MessageBoardEntry {
  String title;
  String message;
  int? timeout;
  bool requireAccept;
  List<String> targets;

  MessageBoardEntry(this.title, this.message, this.timeout, this.requireAccept, this.targets);
}

class MessageBoardConfigurationTable {
  Spreadsheet spreadsheet;
  SheetsApi api;
  String sheetName;
  late List<String> headerOrder;

  ValueNotifier<List<MessageBoardEntry>> entries = ValueNotifier(
    <MessageBoardEntry>[],
  );

  MessageBoardConfigurationTable(
    this.api,
    this.spreadsheet,
    this.sheetName, {
    this.headerOrder = const [
      "title",
      "message",
      "timeout",
      "require-accept",
      "target",
      "read-by",
    ],
  });

  Future<void> load() async {
    ValueRange request;
    try {
      request = await api.spreadsheets.values.get(
        spreadsheet.spreadsheetId ?? "",
        "$sheetName!A1:${headerOrder.length}",
        majorDimension: "COLUMNS",
        valueRenderOption: 'FORMULA',
      );
    } catch (e) {
      // If we can't even get the sheet, it might be newly created and completely empty
      await _initializeSheet();
      entries.value = [];
      return;
    }

    final allValues = request.values ?? const <List<Object?>>[];

    if (allValues.isEmpty) {
      await _initializeSheet();
      entries.value = [];
      return;
    }

    // Check if the first row matches our header order
    final firstRow = allValues[0]
        .map((e) => e?.toString().toLowerCase() ?? "")
        .toList();
    bool headersMatch = true;
    for (int i = 0; i < headerOrder.length; i++) {
      if (i >= firstRow.length || firstRow[i] != headerOrder[i].toLowerCase()) {
        headersMatch = false;
        break;
      }
    }

    if (!headersMatch) {
      await _initializeSheet();
      // Re-load if we just initialized it, although it should be empty now
      entries.value = [];
      return;
    }

    final values = allValues.skip(1); // Skip header row

    List<MessageBoardEntry> newEntries = [];

    for (final rawEntry in values) {
      if (rawEntry.length == headerOrder.length - 1) {
        rawEntry.add("");
      }
      if (rawEntry.length < headerOrder.length) continue;
      newEntries.add(
        MessageBoardEntry(
          rawEntry[0].toString(),
          rawEntry[1].toString(),
          int.tryParse(rawEntry[2].toString()),
          rawEntry[3].toString().toLowerCase() == "true",
          rawEntry[4].toString().split(",")
        ),
      );
    }

    entries.value = newEntries;
  }

  Future<void> _initializeSheet() async {
    await api.spreadsheets.values.update(
      ValueRange(values: [headerOrder], majorDimension: "COLUMNS"),
      spreadsheet.spreadsheetId ?? "",
      "$sheetName!A1:${headerOrder.length}1",
      valueInputOption: "USER_ENTERED",
    );
  }
}
