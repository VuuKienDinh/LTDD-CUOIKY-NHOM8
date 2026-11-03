import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Kênh thông báo chính cho ứng dụng
  static const String channelId = 'bus_approach_channel';
  static const String channelName = 'Thông báo xe đến & Tin nhắn';
  static const String channelDescription =
      'Thông báo đẩy khi chuyến xe gần tới điểm đón hoặc có tin nhắn mới từ tài xế/nhân viên';

  Future<void> initialize() async {
    if (_initialized) return;

    // Cấu hình Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // Cấu hình iOS/macOS
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[NotificationService] User clicked notification: ${response.payload}');
      },
    );

    // Xin quyền Android 13+ (POST_NOTIFICATIONS)
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    _initialized = true;
    debugPrint('[NotificationService] Local notifications initialized successfully.');
  }

  // 1. Phát thông báo đẩy khi chuyến xe sắp tới điểm đón
  Future<void> showBusApproachingNotification({
    required String routeName,
    required String plateNumber,
    required String driverName,
    int etaMinutes = 10,
    String? stopName,
    String? note,
  }) async {
    await initialize();

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final where = stopName?.isNotEmpty == true ? stopName! : 'điểm đón của bạn';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Chuyến xe đang tới gần',
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        'Tài xế $driverName (Xe $plateNumber) đang di chuyển tới $where.\nDự kiến tới trong khoảng $etaMinutes phút nữa. Quý khách vui lòng chuẩn bị hành lý và đứng tại điểm đón!${note != null && note.isNotEmpty ? '\n\nLời nhắn: $note' : ''}',
        contentTitle: '🚌 Chuyến xe của bạn đang tới gần!',
        summaryText: 'Cập nhật chuyến: $routeName',
      ),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: id,
      title: '🚌 Chuyến xe của bạn đang tới gần!',
      body: 'Xe $plateNumber ($driverName) sắp đến $where trong $etaMinutes phút nữa!',
      notificationDetails: notificationDetails,
      payload: 'trip_approaching',
    );
  }

  // 2. Phát thông báo đẩy khi có tin nhắn mới từ tài xế / hành khách
  Future<void> showNewChatMessageNotification({
    required String senderName,
    required String messageContent,
    required int tripId,
  }) async {
    await initialize();

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Tin nhắn mới từ $senderName',
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        messageContent,
        contentTitle: '💬 Tin nhắn từ $senderName',
        summaryText: 'Chuyến xe #$tripId',
      ),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: id,
      title: '💬 Tin nhắn từ $senderName',
      body: messageContent,
      notificationDetails: notificationDetails,
      payload: 'chat_trip_$tripId',
    );
  }

  // 3. Gọi điện thoại trực tiếp qua trình quay số (One-touch call)
  static Future<bool> makePhoneCall(String rawPhoneNumber) async {
    final cleanPhone = rawPhoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) return false;

    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        await launchUrl(uri);
        return true;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error making phone call: $e');
      return false;
    }
  }
}
