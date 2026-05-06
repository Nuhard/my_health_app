import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import 'dart:async';

class SyncService {
  static final SyncService instance = SyncService._init();
  final DatabaseService _localDb = DatabaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isSyncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  SyncService._init();

  // Initialize connectivity listener
  void initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // Check if any result is not 'none'
      final isConnected = results.any((result) => result != ConnectivityResult.none);
      if (isConnected && !_isSyncing) {
        syncAll();
      }
    });
  }

  // Check if device is online
  Future<bool> isOnline() async {
    final List<ConnectivityResult> connectivityResults = await Connectivity().checkConnectivity();
    return connectivityResults.any((result) => result != ConnectivityResult.none);
  }

  // Main sync function - syncs all unsynced data
  Future<void> syncAll() async {
    if (_isSyncing) return;
    
    final online = await isOnline();
    if (!online) return;

    _isSyncing = true;

    try {
      print('🔄 Starting sync...');
      
      // Sync health logs
      await _syncHealthLogs();
      
      // Sync symptoms
      await _syncSymptoms();
      
      // Sync appointments
      await _syncAppointments();
      
      // Sync user profile
      await _syncUserProfile();
      
      // Process sync queue
      await _processSyncQueue();
      
      print('✅ Sync completed successfully');
    } catch (e) {
      print('❌ Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ========== SYNC HEALTH LOGS ==========
  
  Future<void> _syncHealthLogs() async {
    final unsyncedLogs = await _localDb.getUnsyncedHealthLogs();
    
    for (var log in unsyncedLogs) {
      try {
        // Upload to Firestore
        await _firestore.collection('health_logs').doc(log['id']).set({
          'userId': log['userId'],
          'date': Timestamp.fromDate(DateTime.parse(log['date'])),
          'meal': log['meal'],
          'physicalActivity': log['physicalActivity'],
          'weight': log['weight'],
          'mood': log['mood'],
          'notes': log['notes'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        // Mark as synced locally
        await _localDb.markAsSynced('health_logs', log['id']);
        print('✅ Synced health log: ${log['id']}');
      } catch (e) {
        print('❌ Failed to sync health log ${log['id']}: $e');
      }
    }
  }

  // ========== SYNC SYMPTOMS ==========
  
  Future<void> _syncSymptoms() async {
    final unsyncedSymptoms = await _localDb.getUnsyncedSymptoms();
    
    for (var symptom in unsyncedSymptoms) {
      try {
        await _firestore.collection('symptoms').doc(symptom['id']).set({
          'userId': symptom['userId'],
          'symptomName': symptom['symptomName'],
          'severity': symptom['severity'],
          'onsetDate': Timestamp.fromDate(DateTime.parse(symptom['onsetDate'])),
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        await _localDb.markAsSynced('symptoms', symptom['id']);
        print('✅ Synced symptom: ${symptom['id']}');
      } catch (e) {
        print('❌ Failed to sync symptom ${symptom['id']}: $e');
      }
    }
  }

  // ========== SYNC APPOINTMENTS ==========
  
  Future<void> _syncAppointments() async {
    final unsyncedAppointments = await _localDb.getUnsyncedAppointments();
    
    for (var appointment in unsyncedAppointments) {
      try {
        await _firestore.collection('appointments').doc(appointment['id']).set({
          'userId': appointment['userId'],
          'doctorId': appointment['doctorId'],
          'doctorName': appointment['doctorName'],
          'specialization': appointment['specialization'],
          'appointmentDate': Timestamp.fromDate(DateTime.parse(appointment['appointmentDate'])),
          'timeSlot': appointment['timeSlot'],
          'status': appointment['status'],
          'reason': appointment['reason'],
          'notes': appointment['notes'],
          'rejectionReason': appointment['rejectionReason'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        await _localDb.markAsSynced('appointments', appointment['id']);
        print('✅ Synced appointment: ${appointment['id']}');
      } catch (e) {
        print('❌ Failed to sync appointment ${appointment['id']}: $e');
      }
    }
  }

  // ========== SYNC USER PROFILE ==========
  
  Future<void> _syncUserProfile() async {
    // This would sync profile changes if needed
    // Implementation depends on how you track profile sync status
  }

  // ========== PROCESS SYNC QUEUE ==========
  
  Future<void> _processSyncQueue() async {
    final queue = await _localDb.getSyncQueue();
    
    for (var item in queue) {
      try {
        final entityType = item['entityType'];
        final entityId = item['entityId'];
        final operation = item['operation'];
        final data = jsonDecode(item['data']);
        
        switch (operation) {
          case 'CREATE':
            await _firestore.collection(entityType).doc(entityId).set(data);
            break;
          case 'UPDATE':
            await _firestore.collection(entityType).doc(entityId).update(data);
            break;
          case 'DELETE':
            await _firestore.collection(entityType).doc(entityId).delete();
            break;
        }
        
        await _localDb.clearSyncQueue(item['id']);
        print('✅ Processed sync queue item: ${item['id']}');
      } catch (e) {
        print('❌ Failed to process sync queue item ${item['id']}: $e');
      }
    }
  }

  // ========== DOWNLOAD FROM FIRESTORE TO LOCAL DB ==========
  
  // Download health logs from Firestore to local DB
  Future<void> downloadHealthLogs(String userId) async {
    final online = await isOnline();
    if (!online) return;

    try {
      final snapshot = await _firestore
          .collection('health_logs')
          .where('userId', isEqualTo: userId)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        await _localDb.createHealthLog({
          'id': doc.id,
          'userId': data['userId'],
          'date': (data['date'] as Timestamp).toDate().toIso8601String(),
          'meal': data['meal'],
          'physicalActivity': data['physicalActivity'],
          'weight': data['weight'],
          'mood': data['mood'],
          'notes': data['notes'] ?? '',
          'isSynced': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      print('✅ Downloaded health logs');
    } catch (e) {
      print('❌ Failed to download health logs: $e');
    }
  }

  // Download appointments from Firestore
  Future<void> downloadAppointments(String userId) async {
    final online = await isOnline();
    if (!online) return;

    try {
      final snapshot = await _firestore
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        await _localDb.createAppointment({
          'id': doc.id,
          'userId': data['userId'],
          'doctorId': data['doctorId'],
          'doctorName': data['doctorName'],
          'specialization': data['specialization'],
          'appointmentDate': (data['appointmentDate'] as Timestamp).toDate().toIso8601String(),
          'timeSlot': data['timeSlot'],
          'status': data['status'],
          'reason': data['reason'] ?? '',
          'notes': data['notes'] ?? '',
          'rejectionReason': data['rejectionReason'] ?? '',
          'isSynced': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      print('✅ Downloaded appointments');
    } catch (e) {
      print('❌ Failed to download appointments: $e');
    }
  }

  // Initial sync on login - download all data
  Future<void> initialSync(String userId) async {
    final online = await isOnline();
    if (!online) {
      print('⚠️ Offline - skipping initial sync');
      return;
    }

    print('🔄 Starting initial sync...');
    await downloadHealthLogs(userId);
    await downloadAppointments(userId);
    print('✅ Initial sync completed');
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}