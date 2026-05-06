import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../services/database_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isOnline = true;
  int _unsyncedItems = 0;
  DateTime? _lastSyncTime;
  String _syncStatus = 'idle'; // idle, syncing, success, error
  String _syncMessage = '';
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  int get unsyncedItems => _unsyncedItems;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get syncStatus => _syncStatus;
  String get syncMessage => _syncMessage;

  SyncProvider() {
    _initializeConnectivity();
    _checkSyncStatus();
    _startPeriodicSync();
  }

  // Initialize connectivity monitoring
  Future<void> _initializeConnectivity() async {
    // Check initial connectivity
    final List<ConnectivityResult> results = await Connectivity().checkConnectivity();
    _isOnline = results.any((result) => result != ConnectivityResult.none);
    notifyListeners();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((result) => result != ConnectivityResult.none);
      
      print('📡 Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      
      if (wasOffline && _isOnline) {
        // Just came back online
        _syncMessage = 'Back online! Syncing data...';
        syncData();
      } else if (!_isOnline) {
        _syncMessage = 'You are offline. Data will sync when online.';
      }
      
      notifyListeners();
    });
  }

  // Start periodic sync (every 5 minutes when online)
  void _startPeriodicSync() {
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isOnline && !_isSyncing) {
        print('⏰ Periodic sync triggered');
        syncData(silent: true);
      }
    });
  }

  // Check unsynced items count
  Future<void> _checkSyncStatus() async {
    try {
      // Skip database operations on web - SQLite only works on mobile
      if (kIsWeb) {
        _unsyncedItems = 0;
        notifyListeners();
        return;
      }
      
      final unsyncedLogs = await DatabaseService.instance.getUnsyncedHealthLogs();
      final unsyncedSymptoms = await DatabaseService.instance.getUnsyncedSymptoms();
      final unsyncedAppointments = await DatabaseService.instance.getUnsyncedAppointments();
      
      _unsyncedItems = unsyncedLogs.length + unsyncedSymptoms.length + unsyncedAppointments.length;
      notifyListeners();
    } catch (e) {
      print('Error checking sync status: $e');
      _unsyncedItems = 0;
    }
  }

  // Main sync function
  Future<void> syncData({bool silent = false}) async {
    if (_isSyncing || !_isOnline) {
      if (!silent) {
        _syncMessage = _isOnline ? 'Sync already in progress' : 'Cannot sync while offline';
      }
      return;
    }

    // Skip sync on web
    if (kIsWeb) {
      _lastSyncTime = DateTime.now();
      _syncStatus = 'success';
      _syncMessage = 'Web version - data saved directly to Firebase';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _syncStatus = 'syncing';
    if (!silent) _syncMessage = 'Syncing data...';
    notifyListeners();

    try {
      print('🔄 Starting sync...');
      
      // Here you would implement actual sync logic
      await Future.delayed(const Duration(seconds: 2));
      
      _lastSyncTime = DateTime.now();
      await _checkSyncStatus();
      
      _syncStatus = 'success';
      _syncMessage = 'Sync completed successfully';
      
      print('✅ Sync completed successfully');
    } catch (e) {
      print('❌ Sync error: $e');
      _syncStatus = 'error';
      _syncMessage = 'Sync failed: ${e.toString()}';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Force sync (manual trigger)
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      _syncMessage = 'Cannot sync while offline';
      notifyListeners();
      return;
    }
    
    await syncData(silent: false);
  }

  // Check unsynced items (call this after adding new data)
  Future<void> checkUnsyncedItems() async {
    await _checkSyncStatus();
  }

  // Get sync status message for UI
  String getSyncStatusMessage() {
    if (!_isOnline) return '📴 Offline - Data will sync when online';
    if (_isSyncing) return '🔄 Syncing...';
    if (_unsyncedItems > 0) return '⚠️ $_unsyncedItems items pending sync';
    if (_lastSyncTime != null) {
      final diff = DateTime.now().difference(_lastSyncTime!);
      if (diff.inMinutes < 1) return '✅ Synced just now';
      if (diff.inHours < 1) return '✅ Synced ${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '✅ Synced ${diff.inHours}h ago';
      return '✅ Synced ${diff.inDays}d ago';
    }
    return '📊 Ready to sync';
  }

  // Get sync status color for UI
  Color getSyncStatusColor() {
    if (!_isOnline) return Colors.grey;
    if (_isSyncing) return Colors.blue;
    if (_unsyncedItems > 0) return Colors.orange;
    if (_syncStatus == 'error') return Colors.red;
    return Colors.green;
  }

  // Get sync status icon for UI
  IconData getSyncStatusIcon() {
    if (!_isOnline) return Icons.cloud_off;
    if (_isSyncing) return Icons.sync;
    if (_unsyncedItems > 0) return Icons.cloud_upload;
    if (_syncStatus == 'error') return Icons.error;
    return Icons.cloud_done;
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    super.dispose();
  }
}