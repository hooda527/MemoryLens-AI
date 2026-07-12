import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FreeTierService {
  final FirebaseFirestore _firestore;
  static const int kFreeDailyLimit = 5;

  FreeTierService(this._firestore);

  Future<bool> canUseFreeScans(String userId) async {
    final docRef = _firestore.collection('users').doc(userId).collection('usage').doc('quota');
    final snap = await docRef.get();

    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";

    if (!snap.exists) {
      await docRef.set({
        'freeScansUsed': 0,
        'freeScansLimit': kFreeDailyLimit,
        'lastResetDate': todayStr,
      });
      return true;
    }

    final data = snap.data()!;
    final lastResetDate = data['lastResetDate'] as String?;

    if (lastResetDate != todayStr) {
      // It's a new day, reset usage
      await docRef.update({
        'freeScansUsed': 0,
        'lastResetDate': todayStr,
      });
      return true;
    }

    final used = data['freeScansUsed'] as int? ?? 0;
    final limit = data['freeScansLimit'] as int? ?? kFreeDailyLimit;
    return used < limit;
  }

  Future<void> incrementScanCount(String userId) async {
    final docRef = _firestore.collection('users').doc(userId).collection('usage').doc('quota');
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (snap.exists) {
        final used = snap.data()!['freeScansUsed'] as int? ?? 0;
        transaction.update(docRef, {'freeScansUsed': used + 1});
      }
    });
  }

  Future<Map<String, dynamic>> getQuotaInfo(String userId) async {
    final docRef = _firestore.collection('users').doc(userId).collection('usage').doc('quota');
    final snap = await docRef.get();
    if (!snap.exists) {
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month}-${now.day}";
      final defaultQuota = {
        'freeScansUsed': 0,
        'freeScansLimit': kFreeDailyLimit,
        'lastResetDate': todayStr,
      };
      await docRef.set(defaultQuota);
      return defaultQuota;
    }
    return snap.data()!;
  }
}

final freeTierServiceProvider = Provider<FreeTierService>((ref) {
  return FreeTierService(FirebaseFirestore.instance);
});
