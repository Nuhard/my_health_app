import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializeDatabaseFactory() async {
  if (kIsWeb) {
    // WEB: Skip SQLite entirely - use Firestore directly
    print('🌐 Running on WEB - SQLite disabled, using Firestore only');
    return;
  } else if (Platform.isAndroid || Platform.isIOS) {
    // MOBILE: sqflite works automatically
    print('📱 Running on MOBILE - Using native SQLite');
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // DESKTOP: Use FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    print('💻 Running on DESKTOP - Using SQLite FFI');
  }
}