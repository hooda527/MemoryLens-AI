import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReminderService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initialize() async {
    if (kIsWeb) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(initSettings);

    if (!kIsWeb && Platform.isAndroid) {
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'memorylens_reminders',
          'MemoryLens Reminders',
          description: 'Reminders for bills, tickets, prescriptions, and exams.',
          importance: Importance.max,
        ),
      );
    }
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String documentId,
    required String userId,
  }) async {
    // Persist reminder details in Firestore
    await _firestore.collection('users').doc(userId).collection('reminders').doc(documentId).set({
      'notificationId': id,
      'title': title,
      'body': body,
      'reminderTime': Timestamp.fromDate(scheduledDate),
      'documentId': documentId,
      'status': 'scheduled',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (kIsWeb) return;

    // Schedule local notification
    const androidDetails = AndroidNotificationDetails(
      'memorylens_reminders',
      'MemoryLens Reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final delay = scheduledDate.difference(DateTime.now());
    if (delay.isNegative) return; // Cannot schedule in past

    try {
      await _notifications.show(
        id,
        title,
        body,
        details,
      );
    } catch (_) {
      // Gracefully handle
    }
  }

  Future<void> cancelReminder(int id, String userId, String documentId) async {
    if (!kIsWeb) {
      await _notifications.cancel(id);
    }
    await _firestore.collection('users').doc(userId).collection('reminders').doc(documentId).update({
      'status': 'cancelled',
    });
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService();
  service.initialize();
  return service;
});
