import 'package:flutter/material.dart';

class AppState {
  final Color color;
  final String description;
  final int pushCount;

  AppState(this.color, this.description, this.pushCount);

  static AppState initial = AppState(Colors.white, 'Connecting...', 0);
}
