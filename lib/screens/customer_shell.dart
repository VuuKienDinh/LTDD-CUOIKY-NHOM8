import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../theme/shadcn_theme.dart';
import 'seat_booking_screen.dart';
import 'trip_chat_screen.dart';
import 'in_app_call_screen.dart';

class CustomerPortalView extends StatefulWidget {
  const CustomerPortalView({super.key});

  @override
  State<CustomerPortalView> createState() => _CustomerPortalViewState();
}

class _CustomerPortalViewState extends State<CustomerPortalView> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<Map<String, dynamic>> _provinces = [];
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _supportRequests = [];

  int? _originId;
  int? _destId;
  DateTime? _selectedDate;
  int _passengers = 1;
  String? _busTypeFilter;
  String _sortBy = 'time'; // time, priceAsc, priceDesc
  int? _linkedOutboundBookingId;
  String? _linkedOutboundBookingCode;
  bool _loading = false;
  String? _error;

  Timer? _notificationPollTimer;
  final Set<int> _notifiedIds = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadInitial();
    // Poller kiểm tra thông báo đẩy & cuộc gọi đến từ hệ thống/tài xế
    _notificationPollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      _checkNewPushNotifications();
      _checkIncomingCallDirectly();
    });
  }

  bool _isIncomingCallOpen = false;

  Future<void> _checkIncomingCallDirectly() async {
    if (_isIncomingCallOpen) return;
    try {
      int checkTripId = 1;
      if (_bookings.isNotEmpty) {
        final b = _bookings.first;
        checkTripId = (b['tripId'] ?? b['TripId'] ?? 1) as int;
      }
      final res = await ApiClient.instance.get('/api/trips/$checkTripId/calls/active');
      if (res is Map && mounted && !_isIncomingCallOpen) {
        final status = (res['status'] ?? res['Status'])?.toString();
        final role = (res['callerRole'] ?? res['CallerRole'])?.toString();
        final callId = (res['callId'] ?? res['CallId'])?.toString();
        final caller = (res['callerName'] ?? res['CallerName'] ?? 'Đối phương').toString();

        final isUserDriver = ApiClient.instance.isDriver;
        final isIncomingForMe = (isUserDriver && role == 'Customer') || (!isUserDriver && role == 'Driver');

        if (status == 'Ringing' && isIncomingForMe && callId != null) {
          _isIncomingCallOpen = true;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InAppCallScreen(
                tripId: checkTripId,
                partnerName: caller.isNotEmpty ? caller : (isUserDriver ? 'Hành khách' : 'Bác tài Nguyễn Văn Tài'),
                partnerPhone: isUserDriver ? 'Hành khách trên xe' : '0901000004',
                partnerRole: isUserDriver ? 'Customer' : 'Driver',
                isIncoming: true,
                initialCallId: callId,
              ),
            ),
          );
          _isIncomingCallOpen = false;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkNewPushNotifications() async {
    if (!ApiClient.instance.isLoggedIn) return;
    try {
      final res = await ApiClient.instance.get('/api/notifications/my');
      if (res is List && mounted) {
        for (final item in res) {
          final n = Map<String, dynamic>.from(item as Map);
          final id = (n['notificationId'] ?? n['NotificationId']) as int;
          final isRead = (n['isRead'] ?? n['IsRead']) == true;
          final type = (n['type'] ?? n['Type'] ?? '').toString();
          final title = (n['title'] ?? n['Title'] ?? '').toString();
          final content = (n['content'] ?? n['Content'] ?? '').toString();
          final refId = (n['referenceId'] ?? n['ReferenceId'] ?? 1) as int;

          if (!_notifiedIds.contains(id) && !isRead) {
            _notifiedIds.add(id);
            if (type == 'BusApproaching') {
              NotificationService.instance.showBusApproachingNotification(
                routeName: 'Tuyến Sài Gòn - Đà Lạt',
                plateNumber: '51B-288.99',
                driverName: 'Nguyễn Văn Tài',
                etaMinutes: 10,
                note: content,
              );
            } else if (type == 'ChatMessage') {
              NotificationService.instance.showNewChatMessageNotification(
                senderName: title.replaceAll('💬 Tin nhắn từ ', ''),
                messageContent: content,
                tripId: refId,
              );
            } else if (type == 'IncomingCall' && !_isIncomingCallOpen) {
              _isIncomingCallOpen = true;
              final callerTitle = title.replaceAll('📞 Cuộc gọi thoại qua App từ ', '').trim();
              final isUserDriver = ApiClient.instance.isDriver;
              NotificationService.instance.showNewChatMessageNotification(
                senderName: title,
                messageContent: content,
                tripId: refId,
              );
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InAppCallScreen(
                    tripId: refId,
                    partnerName: callerTitle.isNotEmpty
                        ? callerTitle
                        : (isUserDriver ? 'Hành khách' : 'Bác tài Nguyễn Văn Tài'),
                    partnerPhone: isUserDriver ? 'Hành khách trên xe' : '0901000004',
                    partnerRole: isUserDriver ? 'Customer' : 'Driver',
                    isIncoming: true,
                  ),
                ),
              );
              _isIncomingCallOpen = false;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provs = await ApiClient.instance.get('/api/provinces');
      _provinces = (provs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _searchTrips();
      if (ApiClient.instance.isLoggedIn) {
        await _loadMyBookingsAndNotifications();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchTrips() async {
    setState(() => _loading = true);
    try {
      final q = <String, String>{
        'passengers': _passengers.toString(),
      };
      if (_originId != null) q['originProvinceId'] = _originId.toString();
      if (_destId != null) q['destinationProvinceId'] = _destId.toString();
      if (_selectedDate != null) {
        q['date'] = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      }
      if (_busTypeFilter != null && _busTypeFilter!.isNotEmpty) {
        q['busType'] = _busTypeFilter!;
      }

      final res = await ApiClient.instance.get('/api/trips/search', query: q);
      var list = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (_sortBy == 'priceAsc') {
        list.sort((a, b) => ((a['basePrice'] ?? a['BasePrice'] ?? 0) as num)
            .compareTo((b['basePrice'] ?? b['BasePrice'] ?? 0) as num));
      } else if (_sortBy == 'priceDesc') {
        list.sort((a, b) => ((b['basePrice'] ?? b['BasePrice'] ?? 0) as num)
            .compareTo((a['basePrice'] ?? a['BasePrice'] ?? 0) as num));
      }

      setState(() {
        _trips = list;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMyBookingsAndNotifications() async {
    if (!ApiClient.instance.isLoggedIn) return;
    try {
      final b = await ApiClient.instance.get('/api/bookings/my');
      final n = await ApiClient.instance.get('/api/notifications/my');
      final s = await ApiClient.instance.get('/api/support-requests/my');
      if (mounted) {
        setState(() {
          _bookings = (b as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _notifications = (n as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _supportRequests = (s as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
  }

  String _fmtDateTime(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtTimeOnly(dynamic raw) {
    if (raw == null) return '--:--';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDateOnly(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtMoney(num amount) {
    final s = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} đ';
  }

  // UC04: Xem chi tiết chuyến xe (Lộ trình điểm dừng, chính sách, tài xế, đánh giá)
  Future<void> _showTripDetailSheet(int tripId) async {
    try {
      final res = await ApiClient.instance.get('/api/trips/$tripId');
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res as Map);
      final stops = (d['stops'] ?? d['Stops']) as List? ?? [];
      final reviews = (d['reviews'] ?? d['Reviews']) as List? ?? [];
      final drivers = (d['drivers'] ?? d['Drivers']) as List? ?? [];

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF0D47A1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chi tiết chuyến xe #$tripId (UC04)',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              Text(
                (d['routeName'] ?? d['RouteName']).toString(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
              ),
              Text('Nhà xe: ${d['companyName'] ?? d['CompanyName']} • Hotline: ${d['companyPhone'] ?? d['CompanyPhone']}'),
              Text('Phương tiện: ${d['busType'] ?? d['BusType']} (${d['plateNumber'] ?? d['PlateNumber']})'),
              Text('Cự ly: ${d['distanceKm'] ?? d['DistanceKm']} km • Thời gian giữ ghế: ${d['seatHoldMinutes'] ?? d['SeatHoldMinutes']} phút'),
              if (drivers.isNotEmpty)
                Text(
                  'Tài xế phụ trách: ${drivers.map((x) => x['fullName'] ?? x['FullName']).join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 12),
              const Text('Lộ trình các điểm đón / trả (RouteStops):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...stops.map((s) {
                final sm = Map<String, dynamic>.from(s as Map);
                final sur = ((sm['surcharge'] ?? sm['Surcharge'] ?? 0) as num).toDouble();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    (sm['stopType'] ?? sm['StopType']) == 'Pickup' ? Icons.trip_origin : Icons.place,
                    color: (sm['stopType'] ?? sm['StopType']) == 'Pickup' ? Colors.blue : Colors.deepOrange,
                    size: 20,
                  ),
                  title: Text('${sm['stopName'] ?? sm['StopName']} (${sm['stopType'] ?? sm['StopType']})'),
                  subtitle: Text('${sm['address'] ?? sm['Address']} • +${sm['offsetMinutes'] ?? sm['OffsetMinutes']} phút'),
                  trailing: sur > 0
                      ? Text('+${sur.toStringAsFixed(0)}đ', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))
                      : const Text('Miễn phí', style: TextStyle(color: Colors.green, fontSize: 12)),
                );
              }),
              const Divider(),
              Text('Đánh giá của hành khách (${reviews.length}):', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (reviews.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Chưa có đánh giá nào cho nhà xe này.', style: TextStyle(color: Colors.black54)),
                )
              else
                ...reviews.map((r) {
                  final rm = Map<String, dynamic>.from(r as Map);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.shade100,
                      child: Text('${rm['rating'] ?? rm['Rating']}★', style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text((rm['userName'] ?? rm['UserName'] ?? 'Hành khách').toString()),
                    subtitle: Text((rm['comment'] ?? rm['Comment'] ?? '').toString()),
                  );
                }),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showQrDialog(Map<String, dynamic> ticket, String seatCode, String paxName, String routeName) async {
    final code = (ticket['ticketCode'] ?? ticket['TicketCode']).toString();
    final qrPayload = (ticket['qrDisplayPayload'] ?? ticket['QRDisplayPayload']).toString();
    final status = (ticket['status'] ?? ticket['Status']).toString();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: Color(0xFF0D47A1), size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('Vé Điện Tử QR • Ghế $seatCode')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(routeName, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Hành khách: $paxName'),
            const SizedBox(height: 12),
            Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF0284C7), width: 2.5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Center(
                child: QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  size: 184.0,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Chip(
              label: Text('Trạng thái vé: $status'),
              backgroundColor: status == 'Active'
                  ? Colors.green.shade100
                  : status == 'Used'
                      ? Colors.blue.shade100
                      : Colors.red.shade100,
            ),
            const SizedBox(height: 6),
            SelectableText(
              'Mã vé: $code\nChuỗi ký số QR:\n$qrPayload',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            // Khối liên hệ Bác tài & Gọi điện / Nhắn tin
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 17,
                    backgroundColor: Color(0xFF0284C7),
                    child: Icon(LucideIcons.bus, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tài xế: Nguyễn Văn Tài', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        Text('SĐT: 0901 000 004', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: () {
                      final tripId = (ticket['tripId'] ?? ticket['TripId'] ?? 1) as int;
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InAppCallScreen(
                            tripId: tripId,
                            partnerName: 'Bác tài Nguyễn Văn Tài',
                            partnerPhone: '0901000004',
                            partnerRole: 'Driver',
                            routeName: routeName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.phoneCall, size: 15, color: Colors.white),
                    tooltip: 'Gọi điện qua App luôn',
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: () {
                      final tripId = (ticket['tripId'] ?? ticket['TripId'] ?? 1) as int;
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TripChatScreen(
                            tripId: tripId,
                            routeName: routeName,
                            partnerName: 'Bác tài Nguyễn Văn Tài',
                            partnerPhone: '0901000004',
                            partnerRole: 'Driver',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.messagesSquare, size: 15, color: Colors.white),
                    tooltip: 'Nhắn tin với bác tài',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: qrPayload));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép chuỗi QR để dán vào máy quét Check-in!')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy chuỗi QR'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  Future<void> _showTrackingDialog(int tripId) async {
    try {
      var res = await ApiClient.instance.get('/api/trips/$tripId/tracking');
      if (!mounted) return;
      var data = Map<String, dynamic>.from(res as Map);

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final live = data['liveLocation'] ?? data['LiveLocation'];
            final history = (data['statusHistory'] ?? data['StatusHistory']) as List? ?? [];
            final stops = (data['stops'] ?? data['Stops']) as List? ?? [];

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.gps_fixed, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Bản đồ GPS Chuyến #$tripId (AT10)', style: const TextStyle(fontSize: 16))),
                  IconButton(
                    tooltip: 'Làm mới tọa độ GPS',
                    onPressed: () async {
                      final refreshed = await ApiClient.instance.get('/api/trips/$tripId/tracking');
                      setDialogState(() {
                        data = Map<String, dynamic>.from(refreshed as Map);
                      });
                    },
                    icon: const Icon(Icons.refresh, color: Color(0xFF0D47A1)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tuyến: ${data['routeName'] ?? data['RouteName']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Biển số: ${data['plateNumber'] ?? data['PlateNumber']} • Trạng thái: ${data['status'] ?? data['Status']}'),
                    if ((data['delayReason'] ?? data['DelayReason']) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Lý do trễ: ${data['delayReason'] ?? data['DelayReason']} (Dự kiến mới: ${_fmtDateTime(data['delayedArrivalEstimate'] ?? data['DelayedArrivalEstimate'])})',
                          style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Container(
                      height: 135,
                      width: double.maxFinite,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade400, width: 1.5),
                      ),
                      child: CustomPaint(
                        painter: _LiveRouteMapPainter(
                          stops: stops,
                          liveLat: live != null ? ((live['latitude'] ?? live['Latitude'] ?? 0) as num).toDouble() : null,
                          liveLng: live != null ? ((live['longitude'] ?? live['Longitude'] ?? 0) as num).toDouble() : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (live != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TỌA ĐỘ GPS TRỰC TIẾP (TripLiveLocations):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('• Vĩ độ (Lat): ${live['latitude'] ?? live['Latitude']}'),
                            Text('• Kinh độ (Lng): ${live['longitude'] ?? live['Longitude']}'),
                            Text('• Tốc độ: ${live['speedKmh'] ?? live['SpeedKmh']} km/h'),
                            Text('• Cập nhật lúc: ${_fmtDateTime(live['updatedAt'] ?? live['UpdatedAt'])}'),
                          ],
                        ),
                      ),
                    ] else
                      const Text('Chưa có tọa độ GPS trực tiếp cho chuyến này.'),
                    const SizedBox(height: 12),
                    const Text('Lịch sử trạng thái chuyến:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...history.map((h) {
                      final m = Map<String, dynamic>.from(h as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text('${m['oldStatus'] ?? m['OldStatus']} → ${m['newStatus'] ?? m['NewStatus']}'),
                        subtitle: Text('${m['reason'] ?? m['Reason'] ?? ''} • ${_fmtDateTime(m['changedAt'] ?? m['ChangedAt'])}'),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    final shareText = '🚌 Hành trình BusTicketBooking: Chuyến #$tripId (${data['routeName'] ?? data['RouteName']}) • Xe ${data['plateNumber'] ?? data['PlateNumber']} • GPS: Lat ${live?['latitude'] ?? live?['Latitude'] ?? 'N/A'}, Lng ${live?['longitude'] ?? live?['Longitude'] ?? 'N/A'}';
                    Clipboard.setData(ClipboardData(text: shareText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép thông tin chia sẻ hành trình cho người thân!')),
                    );
                  },
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Chia sẻ hành trình'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: () async {
                    try {
                      final sosRes = await ApiClient.instance.post('/api/trips/$tripId/sos', body: {
                        'message': 'Cần hỗ trợ khẩn cấp trên xe ${data['plateNumber'] ?? data['PlateNumber']}!',
                      });
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text((sosRes['message'] ?? 'Đã phát tín hiệu SOS!').toString()),
                            backgroundColor: Colors.red.shade800,
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.sos, size: 18),
                  label: const Text('BÁO SOS KHẨN CẤP'),
                ),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cancelBooking(int bookingId, String code) async {
    final reasonCtrl = TextEditingController(text: 'Thay đổi kế hoạch di chuyển');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hủy đơn đặt vé $code'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Lý do hủy vé',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Đóng')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận hủy'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await ApiClient.instance.post('/api/bookings/$bookingId/cancel', body: {
        'reason': reasonCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã hủy đơn vé').toString())),
      );
      await _loadMyBookingsAndNotifications();
      await _searchTrips();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reviewBooking(int bookingId, String routeName) async {
    int rating = 5;
    final commentCtrl = TextEditingController(text: 'Xe sạch sẽ, chạy đúng giờ, tài xế thân thiện!');
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Đánh giá chuyến đi\n$routeName', style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    onPressed: () => setDialogState(() => rating = i + 1),
                    icon: Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                  );
                }),
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nhận xét của bạn',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/reviews', body: {
                    'bookingId': bookingId,
                    'rating': rating,
                    'comment': commentCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã gửi đánh giá').toString())),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Gửi đánh giá'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: ShadcnTheme.surfaceGlass,
            border: Border(bottom: BorderSide(color: ShadcnTheme.glassBorder, width: 1.2)),
            boxShadow: [
              BoxShadow(
                color: Color(0x060369A1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorWeight: 2.5,
            indicatorColor: ShadcnTheme.primary,
            labelColor: ShadcnTheme.primaryDark,
            unselectedLabelColor: ShadcnTheme.mutedForeground,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: -0.2),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: -0.2),
            tabs: [
              const Tab(icon: Icon(LucideIcons.search, size: 16), text: 'Tìm chuyến'),
              Tab(
                icon: const Icon(LucideIcons.ticket, size: 16),
                text: 'Vé của tôi (${_bookings.length})',
              ),
              Tab(
                icon: const Icon(LucideIcons.bell, size: 16),
                text: 'Thông báo (${_notifications.length})',
              ),
              const Tab(
                icon: Icon(LucideIcons.user, size: 16),
                text: 'Tài khoản & Tiện ích',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildSearchTab(),
              _buildMyBookingsTab(),
              _buildNotificationsTab(),
              _buildProfileAndSupportTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTripSkeletonCard() {
    return ShadcnCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              ShadcnSkeleton(width: 28, height: 28, borderRadius: 6),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShadcnSkeleton(width: 150, height: 14),
                    SizedBox(height: 4),
                    ShadcnSkeleton(width: 100, height: 11),
                  ],
                ),
              ),
              ShadcnSkeleton(width: 70, height: 16),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ShadcnTheme.secondary,
              borderRadius: BorderRadius.circular(ShadcnTheme.radius),
              border: Border.all(color: ShadcnTheme.border),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShadcnSkeleton(width: 50, height: 26),
                ShadcnSkeleton(width: 90, height: 12),
                ShadcnSkeleton(width: 50, height: 26),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              ShadcnSkeleton(width: 85, height: 22, borderRadius: 12),
              SizedBox(width: 8),
              ShadcnSkeleton(width: 65, height: 22, borderRadius: 12),
              Spacer(),
              ShadcnSkeleton(width: 75, height: 20),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: ShadcnSkeleton(height: 38, borderRadius: 8)),
              SizedBox(width: 8),
              Expanded(child: ShadcnSkeleton(height: 38, borderRadius: 8)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // shadcn Search Box Card
        ShadcnCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tìm chuyến xe liên tỉnh',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: ShadcnTheme.foreground,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Giữ chỗ 10p • Vé QR • GPS trực tiếp',
                          style: TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: Color(0xFFBAE6FD)),
                      backgroundColor: const Color(0xFFF0F9FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                    ),
                    onPressed: _showPublicLookupDialog,
                    icon: const Icon(LucideIcons.qrCode, size: 14, color: ShadcnTheme.primaryDark),
                    label: const Text('Tra cứu vé', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Origin & Destination Row with Swap Button
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _originId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Điểm khởi hành',
                        prefixIcon: Icon(LucideIcons.circleDot, color: ShadcnTheme.foreground, size: 15),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Tất cả tỉnh/thành')),
                        ..._provinces.map((p) => DropdownMenuItem<int?>(
                              value: (p['provinceId'] ?? p['ProvinceId']) as int,
                              child: Text((p['name'] ?? p['Name']).toString(), overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _originId = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: IconButton.outlined(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: ShadcnTheme.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                      ),
                      tooltip: 'Đảo chiều đi / về',
                      onPressed: () {
                        setState(() {
                          final tmp = _originId;
                          _originId = _destId;
                          _destId = tmp;
                        });
                        _searchTrips();
                      },
                      icon: const Icon(LucideIcons.arrowLeftRight, size: 16, color: ShadcnTheme.foreground),
                    ),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _destId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Điểm đến',
                        prefixIcon: Icon(LucideIcons.mapPin, color: ShadcnTheme.foreground, size: 15),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Tất cả tỉnh/thành')),
                        ..._provinces.map((p) => DropdownMenuItem<int?>(
                              value: (p['provinceId'] ?? p['ProvinceId']) as int,
                              child: Text((p['name'] ?? p['Name']).toString(), overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _destId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Date & Passenger Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                          _searchTrips();
                        }
                      },
                      borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: ShadcnTheme.surface,
                          borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                          border: Border.all(color: ShadcnTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar, size: 15, color: ShadcnTheme.mutedForeground),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDate == null
                                    ? 'Mọi ngày sắp tới'
                                    : 'Ngày ${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadcnTheme.foreground),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_selectedDate != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _selectedDate = null);
                                  _searchTrips();
                                },
                                child: const Icon(LucideIcons.x, size: 15, color: ShadcnTheme.destructive),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _passengers,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Hành khách',
                        prefixIcon: Icon(LucideIcons.users, size: 15, color: ShadcnTheme.mutedForeground),
                      ),
                      items: [1, 2, 3, 4, 5]
                          .map((n) => DropdownMenuItem(value: n, child: Text('$n khách')))
                          .toList(),
                      onChanged: (v) => setState(() => _passengers = v ?? 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Bus Type & Sort Row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _busTypeFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Dòng xe',
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tất cả xe')),
                        DropdownMenuItem(value: 'Limousine', child: Text('Limousine VIP')),
                        DropdownMenuItem(value: 'Giường nằm', child: Text('Giường nằm')),
                        DropdownMenuItem(value: 'Cabin', child: Text('Cabin Cung Điện')),
                      ],
                      onChanged: (v) => setState(() => _busTypeFilter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _sortBy,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sắp xếp',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'time', child: Text('Giờ chạy')),
                        DropdownMenuItem(value: 'priceAsc', child: Text('Giá thấp → cao')),
                        DropdownMenuItem(value: 'priceDesc', child: Text('Giá cao → thấp')),
                      ],
                      onChanged: (v) => setState(() => _sortBy = v ?? 'time'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Ocean Blue Gradient Search Button
              Container(
                decoration: BoxDecoration(
                  gradient: ShadcnTheme.oceanGradient,
                  borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330284C7),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: ShadcnTheme.primaryForeground,
                    padding: const EdgeInsets.symmetric(vertical: 13.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radius)),
                  ),
                  onPressed: _searchTrips,
                  icon: const Icon(LucideIcons.search, size: 17),
                  label: const Text(
                    'Tìm kiếm chuyến xe',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -0.1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_linkedOutboundBookingId != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ShadcnTheme.secondary,
              borderRadius: BorderRadius.circular(ShadcnTheme.radius),
              border: Border.all(color: ShadcnTheme.border),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.arrowLeftRight, color: ShadcnTheme.foreground, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang chọn chuyến chiều về Khứ hồi liên kết với đơn $_linkedOutboundBookingCode',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: ShadcnTheme.foreground),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 15),
                  onPressed: () => setState(() {
                    _linkedOutboundBookingId = null;
                    _linkedOutboundBookingCode = null;
                  }),
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: ShadcnTheme.destructive)),
          ),
        // Section Header: Results count
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lịch trình khả dụng (${_trips.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ShadcnTheme.foreground, letterSpacing: -0.2),
              ),
              ShadcnBadge.secondary('Giá niêm yết'),
            ],
          ),
        ),
        if (_loading)
          Column(
            children: [
              _buildTripSkeletonCard(),
              const SizedBox(height: 12),
              _buildTripSkeletonCard(),
              const SizedBox(height: 12),
              _buildTripSkeletonCard(),
            ],
          )
        else if (_trips.isEmpty)
          ShadcnCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Icon(LucideIcons.bus, size: 36, color: ShadcnTheme.mutedForeground),
                const SizedBox(height: 8),
                const Text(
                  'Không tìm thấy chuyến xe phù hợp điều kiện lọc.',
                  style: TextStyle(fontWeight: FontWeight.w500, color: ShadcnTheme.mutedForeground, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ..._trips.asMap().entries.map((entry) {
            final i = entry.key;
            final t = entry.value;
            final tripId = (t['tripId'] ?? t['TripId']) as int;
            final routeName = (t['routeName'] ?? t['RouteName']).toString();
            final companyName = (t['companyName'] ?? t['CompanyName']).toString();
            final busType = (t['busType'] ?? t['BusType']).toString();
            final plate = (t['plateNumber'] ?? t['PlateNumber']).toString();
            final price = ((t['basePrice'] ?? t['BasePrice'] ?? 0) as num).toDouble();
            final avail = (t['availableSeats'] ?? t['AvailableSeats']) as int;
            final status = (t['status'] ?? t['Status']).toString();
            final depRaw = t['departureAt'] ?? t['DepartureAt'];
            final arrRaw = t['arrivalEstimate'] ?? t['ArrivalEstimate'];

            return ShadcnCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Row: Company Name + Badges + Price
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 1),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: const Icon(LucideIcons.bus, size: 16, color: ShadcnTheme.primaryDark),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              companyName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: ShadcnTheme.foreground, letterSpacing: -0.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$busType • $plate',
                              style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _fmtMoney(price),
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0369A1),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Timeline: Departure ── 🚌 ── Arrival
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                      border: Border.all(color: const Color(0xFFBAE6FD), width: 0.9),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fmtTimeOnly(depRaw),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: ShadcnTheme.primaryDark),
                            ),
                            Text(
                              _fmtDateOnly(depRaw),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ShadcnTheme.mutedForeground),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.circle, size: 6, color: ShadcnTheme.primary),
                                    Expanded(
                                      child: Container(
                                        height: 1.5,
                                        color: const Color(0xFFBAE6FD),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(LucideIcons.arrowRight, size: 14, color: ShadcnTheme.primary),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 1.5,
                                        color: const Color(0xFFBAE6FD),
                                      ),
                                    ),
                                    const Icon(Icons.circle_outlined, size: 6, color: ShadcnTheme.primary),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  routeName,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ShadcnTheme.mutedForeground),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _fmtTimeOnly(arrRaw),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: ShadcnTheme.primaryDark),
                            ),
                            Text(
                              _fmtDateOnly(arrRaw),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ShadcnTheme.mutedForeground),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Badges: Seats left + Amenities
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      avail > 5
                          ? ShadcnBadge.success('Còn $avail chỗ')
                          : ShadcnBadge.destructive('Còn $avail chỗ'),
                      ShadcnBadge.secondary(status),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: () => _showWaitlistDialog(tripId, routeName),
                        icon: const Icon(LucideIcons.bell, size: 13, color: ShadcnTheme.mutedForeground),
                        label: const Text('Săn vé chờ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Bottom Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0F9FF),
                            side: const BorderSide(color: Color(0xFFBAE6FD)),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                          ),
                          onPressed: () => _showTripDetailSheet(tripId),
                          icon: const Icon(LucideIcons.mapPin, size: 14, color: ShadcnTheme.primaryDark),
                          label: const Text('Lộ trình', style: TextStyle(fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: ShadcnTheme.oceanGradient,
                            borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x330284C7),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final booked = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SeatBookingScreen(
                                    tripSummary: t,
                                    linkedBookingId: _linkedOutboundBookingId,
                                  ),
                                ),
                              );
                              await _searchTrips();
                              await _loadMyBookingsAndNotifications();
                              if (booked == true && mounted) {
                                setState(() {
                                  _linkedOutboundBookingId = null;
                                  _linkedOutboundBookingCode = null;
                                });
                                _tabCtrl.animateTo(1);
                              }
                            },
                            child: const Text('Chọn ghế', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 250.ms, delay: (i * 40).ms, curve: Curves.easeOut).slideY(begin: 0.05, end: 0, duration: 250.ms, delay: (i * 40).ms, curve: Curves.easeOut);
          }),
      ],
    );
  }

  Widget _buildMyBookingsTab() {
    if (!ApiClient.instance.isLoggedIn) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => ApiClient.instance.logout(),
          icon: const Icon(LucideIcons.logIn),
          label: const Text('Đăng nhập để xem đơn đặt vé và vé QR'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyBookingsAndNotifications,
      child: _bookings.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Icon(LucideIcons.ticket, size: 54, color: ShadcnTheme.mutedForeground),
                SizedBox(height: 10),
                Center(
                  child: Text(
                    'Bạn chưa có đơn đặt vé nào.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              itemCount: _bookings.length,
              itemBuilder: (ctx, i) {
                final b = _bookings[i];
                final bookingId = (b['bookingId'] ?? b['BookingId']) as int;
                final tripId = (b['tripId'] ?? b['TripId']) as int;
                final code = (b['bookingCode'] ?? b['BookingCode']).toString();
                final routeName = (b['routeName'] ?? b['RouteName']).toString();
                final companyName = (b['companyName'] ?? b['CompanyName']).toString();
                final status = (b['status'] ?? b['Status']).toString();
                final payMethod = (b['paymentMethod'] ?? b['PaymentMethod']).toString();
                final payStatus = (b['paymentStatus'] ?? b['PaymentStatus']).toString();
                final total = ((b['totalAmount'] ?? b['TotalAmount'] ?? 0) as num).toDouble();
                final details = (b['details'] ?? b['Details']) as List? ?? [];

                return ShadcnCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Minimalist Ticket Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: ShadcnTheme.muted,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(ShadcnTheme.radiusLg - 1)),
                          border: Border(bottom: BorderSide(color: ShadcnTheme.border)),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.ticket, size: 16, color: ShadcnTheme.foreground),
                                const SizedBox(width: 6),
                                Text(
                                  code,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: ShadcnTheme.foreground,
                                    fontSize: 13,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                status == 'Confirmed' || status == 'Completed'
                                    ? ShadcnBadge.success(status)
                                    : ShadcnBadge.warning(status),
                                ShadcnBadge.secondary('$payMethod • $payStatus'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        routeName,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$companyName • Khởi hành: ${_fmtDateTime(b['departureAt'] ?? b['DepartureAt'])}',
                                        style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _fmtMoney(total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: ShadcnTheme.accentOrange,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(),
                            ),
                            const Text(
                              'DANH SÁCH GHẾ & VÉ ĐIỆN TỬ QR',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: ShadcnTheme.mutedForeground,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...details.map((d) {
                              final dm = Map<String, dynamic>.from(d as Map);
                              final seatCode = (dm['seatCode'] ?? dm['SeatCode']).toString();
                              final paxName = (dm['passengerName'] ?? dm['PassengerName']).toString();
                              final pickup = (dm['pickupStopName'] ?? dm['PickupStopName']).toString();
                              final dropoff = (dm['dropoffStopName'] ?? dm['DropoffStopName']).toString();
                              final ticketRaw = dm['ticket'] ?? dm['Ticket'];
                              final ticket = ticketRaw != null ? Map<String, dynamic>.from(ticketRaw as Map) : null;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ShadcnTheme.secondary,
                                  borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                                  border: Border.all(color: ShadcnTheme.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: ShadcnTheme.primary,
                                        borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                                      ),
                                      child: Text(
                                        seatCode,
                                        style: const TextStyle(
                                          color: ShadcnTheme.primaryForeground,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(paxName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Đón: $pickup\nTrả: $dropoff',
                                            style: const TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (ticket != null)
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _showQrDialog(ticket, seatCode, paxName, routeName),
                                        icon: const Icon(LucideIcons.qrCode, size: 15),
                                        label: const Text(
                                          'Vé QR',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            // Clean Action Outline Grid
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    backgroundColor: const Color(0xFFF0F9FF),
                                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                                  ),
                                  icon: const Icon(LucideIcons.messagesSquare, size: 14, color: Color(0xFF0284C7)),
                                  label: const Text('Nhắn tin bác tài', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TripChatScreen(
                                          tripId: tripId,
                                          bookingId: bookingId,
                                          routeName: routeName,
                                          partnerName: 'Bác tài Nguyễn Văn Tài',
                                          partnerPhone: '0901000004',
                                          partnerRole: 'Driver',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    backgroundColor: const Color(0xFFF0FDF4),
                                    side: const BorderSide(color: Color(0xFFBBF7D0)),
                                  ),
                                  icon: const Icon(LucideIcons.phoneCall, size: 14, color: Color(0xFF16A34A)),
                                  label: const Text('Gọi qua App', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => InAppCallScreen(
                                          tripId: tripId,
                                          partnerName: 'Bác tài Nguyễn Văn Tài',
                                          partnerPhone: '0901000004',
                                          partnerRole: 'Driver',
                                          routeName: routeName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.navigation, size: 14),
                                  label: const Text('Theo dõi GPS', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _showTrackingDialog(tripId),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.bus, size: 14),
                                  label: const Text('Xe trung chuyển', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _showShuttleBookingDialog(bookingId, code),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.fileText, size: 14),
                                  label: const Text('Hóa đơn VAT', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _showVatInvoiceDialog(bookingId, code, total),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.arrowLeftRight, size: 14),
                                  label: const Text('Đặt khứ hồi', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _bookReturnTripFor(b),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.receipt, size: 14),
                                  label: const Text('Biên lai GD', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _showBookingTransactionsDialog(bookingId, code),
                                ),
                                if (status == 'Confirmed' || status == 'PendingPayment') ...[
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                    icon: const Icon(LucideIcons.armchair, size: 14),
                                    label: const Text('Đổi ghế nhanh', style: TextStyle(fontSize: 11.5)),
                                    onPressed: () => _showChangeSeatDialog(bookingId, tripId, code),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      foregroundColor: ShadcnTheme.destructive,
                                      side: const BorderSide(color: Color(0xFFFECACA)),
                                    ),
                                    icon: const Icon(LucideIcons.ban, size: 14),
                                    label: const Text('Hủy vé / Hoàn tiền', style: TextStyle(fontSize: 11.5)),
                                    onPressed: () => _cancelBooking(bookingId, code),
                                  ),
                                ],
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  icon: const Icon(LucideIcons.star, size: 14, color: Colors.amber),
                                  label: const Text('Đánh giá', style: TextStyle(fontSize: 11.5)),
                                  onPressed: () => _reviewBooking(bookingId, routeName),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildNotificationsTab() {
    if (!ApiClient.instance.isLoggedIn) {
      return const Center(child: Text('Đăng nhập để nhận thông báo chuyến xe & vé.'));
    }
    final unreadCount = _notifications.where((n) => (n['isRead'] ?? n['IsRead'] ?? false) == false).length;

    return RefreshIndicator(
      onRefresh: _loadMyBookingsAndNotifications,
      child: _notifications.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Text(
                    'Chưa có thông báo nào.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Bạn có $unreadCount thông báo mới',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ShadcnTheme.foreground),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await ApiClient.instance.post('/api/notifications/read-all');
                            await _loadMyBookingsAndNotifications();
                          },
                          icon: const Icon(LucideIcons.checkCheck, size: 16),
                          label: const Text('Đã đọc tất cả', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ..._notifications.map((n) {
                  final isRead = (n['isRead'] ?? n['IsRead'] ?? false) == true;
                  final type = (n['type'] ?? n['Type'] ?? '').toString();
                  final title = (n['title'] ?? n['Title'] ?? '').toString();
                  final refId = (n['referenceId'] ?? n['ReferenceId'] ?? 1) as int;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                      onTap: () {
                        if (type == 'IncomingCall') {
                          final isUserDriver = ApiClient.instance.isDriver;
                          final callerTitle = title.replaceAll('📞 Cuộc gọi thoại qua App từ ', '').trim();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppCallScreen(
                                tripId: refId,
                                partnerName: callerTitle.isNotEmpty
                                    ? callerTitle
                                    : (isUserDriver ? 'Hành khách' : 'Bác tài Nguyễn Văn Tài'),
                                partnerPhone: isUserDriver ? 'Hành khách trên xe' : '0901000004',
                                partnerRole: isUserDriver ? 'Customer' : 'Driver',
                              ),
                            ),
                          );
                        } else if (type == 'ChatMessage') {
                          final isUserDriver = ApiClient.instance.isDriver;
                          final sender = title.replaceAll('💬 Tin nhắn từ ', '').trim();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TripChatScreen(
                                tripId: refId,
                                partnerName: sender.isNotEmpty ? sender : 'Đối phương',
                                partnerPhone: isUserDriver ? 'Hành khách trên xe' : '0901000004',
                                partnerRole: isUserDriver ? 'Customer' : 'Driver',
                              ),
                            ),
                          );
                        }
                      },
                      child: ShadcnCard(
                        padding: const EdgeInsets.all(14),
                        borderColor: isRead ? ShadcnTheme.border : const Color(0xFFBFDBFE),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isRead
                                    ? ShadcnTheme.secondary
                                    : (type == 'IncomingCall' ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4)),
                                borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                                border: Border.all(
                                  color: isRead
                                      ? ShadcnTheme.border
                                      : (type == 'IncomingCall' ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0)),
                                ),
                              ),
                              child: Icon(
                                type == 'IncomingCall'
                                    ? LucideIcons.phoneCall
                                    : (type == 'ChatMessage' ? LucideIcons.messageSquare : (isRead ? LucideIcons.bell : LucideIcons.bellRing)),
                                size: 18,
                                color: type == 'IncomingCall'
                                    ? const Color(0xFF0284C7)
                                    : (type == 'ChatMessage' ? const Color(0xFF16A34A) : (isRead ? ShadcnTheme.mutedForeground : const Color(0xFF1D4ED8))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (n['title'] ?? n['Title'] ?? '').toString(),
                                          style: TextStyle(
                                            fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                            fontSize: 13.5,
                                            color: ShadcnTheme.foreground,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      if (!isRead)
                                        Container(
                                          width: 7,
                                          height: 7,
                                          margin: const EdgeInsets.only(left: 6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF2563EB),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (n['content'] ?? n['Content'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 12.5, color: ShadcnTheme.mutedForeground, height: 1.35),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmtDateTime(n['createdAt'] ?? n['CreatedAt']),
                                        style: const TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                                      ),
                                      if (type == 'IncomingCall')
                                        const Row(
                                          children: [
                                            Icon(LucideIcons.phoneCall, size: 11, color: Color(0xFF0284C7)),
                                            SizedBox(width: 4),
                                            Text('Bấm để gọi lại', style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                                          ],
                                        )
                                      else if (type == 'ChatMessage')
                                        const Row(
                                          children: [
                                            Icon(LucideIcons.messageSquare, size: 11, color: Color(0xFF16A34A)),
                                            SizedBox(width: 4),
                                            Text('Bấm để nhắn lại', style: TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  // Tab 4: Hồ sơ cá nhân (FR02), Đổi mật khẩu (FR01), Yêu cầu hỗ trợ (UC31), Đăng ký mở Nhà xe (UC14)
  Widget _buildProfileAndSupportTab() {
    if (!ApiClient.instance.isLoggedIn) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => ApiClient.instance.logout(),
          icon: const Icon(LucideIcons.logIn),
          label: const Text('Đăng nhập tài khoản'),
        ),
      );
    }

    final user = ApiClient.instance.currentUser ?? {};
    final nameCtrl = TextEditingController(text: (user['fullName'] ?? user['FullName'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (user['phone'] ?? user['Phone'] ?? '').toString());

    Widget buildFeatureItem({
      required IconData icon,
      required String title,
      required String subtitle,
      required String buttonLabel,
      required VoidCallback onTap,
    }) {
      return ShadcnCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ShadcnTheme.secondary,
                borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                border: Border.all(color: ShadcnTheme.border),
              ),
              child: Icon(icon, color: ShadcnTheme.foreground, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: onTap,
              child: Text(buttonLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        ShadcnCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ShadcnTheme.secondary,
                      borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                      border: Border.all(color: ShadcnTheme.border),
                    ),
                    child: const Icon(LucideIcons.user, size: 16, color: ShadcnTheme.foreground),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Thông tin cá nhân & Tài khoản',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  prefixIcon: Icon(LucideIcons.user, size: 16),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  prefixIcon: Icon(LucideIcons.phone, size: 16),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        try {
                          final res = await ApiClient.instance.put('/api/auth/profile', body: {
                            'fullName': nameCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                          });
                          ApiClient.instance.updateCurrentUserFields(
                            nameCtrl.text.trim(),
                            phoneCtrl.text.trim(),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text((res['message'] ?? 'Đã lưu').toString())),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: const Text('Lưu hồ sơ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showChangePasswordDialog,
                      icon: const Icon(LucideIcons.keyRound, size: 16),
                      label: const Text('Đổi mật khẩu'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        buildFeatureItem(
          icon: LucideIcons.award,
          title: 'Hạng Thành Viên & Điểm Thưởng',
          subtitle: 'Tích điểm tự động mỗi chuyến đi & đổi Voucher ưu đãi',
          buttonLabel: 'Xem điểm',
          onTap: _showLoyaltyDialog,
        ),

        buildFeatureItem(
          icon: LucideIcons.users,
          title: 'Danh bạ Hành khách thường đi',
          subtitle: 'Lưu thông tin đi kèm để tự động điền nhanh 1 chạm',
          buttonLabel: 'Danh bạ',
          onTap: _showSavedCompanionsDialog,
        ),

        buildFeatureItem(
          icon: LucideIcons.smartphone,
          title: 'Thiết bị nhận thông báo đẩy',
          subtitle: 'Nhận thông báo giờ khởi hành & săn vé khi có chỗ',
          buttonLabel: 'Thiết bị',
          onTap: _showManageDevicesDialog,
        ),

        buildFeatureItem(
          icon: LucideIcons.store,
          title: 'Đăng ký mở Đối tác Nhà xe (UC14)',
          subtitle: 'Gửi hồ sơ đăng ký tham gia mạng lưới vận tải',
          buttonLabel: 'Đăng ký',
          onTap: _showRegisterCompanyDialog,
        ),

        // UC31: Gửi & Theo dõi yêu cầu hỗ trợ
        ShadcnCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Trung tâm Hỗ trợ (UC31)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _showCreateSupportDialog,
                    icon: const Icon(LucideIcons.plus, size: 14),
                    label: const Text('Gửi yêu cầu', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_supportRequests.isEmpty)
                const Text('Bạn chưa gửi yêu cầu hỗ trợ nào.', style: TextStyle(color: ShadcnTheme.mutedForeground, fontSize: 13))
              else
                ..._supportRequests.map((s) {
                  final status = (s['status'] ?? s['Status']).toString();
                  final reply = s['replyContent'] ?? s['ReplyContent'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ShadcnTheme.secondary,
                      borderRadius: BorderRadius.circular(ShadcnTheme.radius),
                      border: Border.all(color: ShadcnTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (s['subject'] ?? s['Subject']).toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            status == 'Resolved'
                                ? ShadcnBadge.success(status)
                                : ShadcnBadge.warning(status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (s['content'] ?? s['Content']).toString(),
                          style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                        ),
                        if (reply != null && reply.toString().isNotEmpty) ...[
                          const Divider(height: 14),
                          Text(
                            'Phản hồi CSKH: $reply',
                            style: const TextStyle(color: ShadcnTheme.foreground, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  void _bookReturnTripFor(Map<String, dynamic> outboundBooking) {
    final orig = outboundBooking['originProvinceId'] ?? outboundBooking['OriginProvinceId'];
    final dest = outboundBooking['destinationProvinceId'] ?? outboundBooking['DestinationProvinceId'];
    final bId = (outboundBooking['bookingId'] ?? outboundBooking['BookingId']) as int?;
    final bCode = (outboundBooking['bookingCode'] ?? outboundBooking['BookingCode'] ?? '').toString();
    setState(() {
      if (dest is int && orig is int) {
        _originId = dest;
        _destId = orig;
      }
      _selectedDate = null;
      _linkedOutboundBookingId = bId;
      _linkedOutboundBookingCode = bCode;
    });
    _tabCtrl.animateTo(0);
    _searchTrips();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã đảo chiều tìm chuyến khứ hồi liên kết với đơn $bCode (Mục 2.3).',
        ),
      ),
    );
  }

  Future<void> _showBookingTransactionsDialog(int bookingId, String code) async {
    try {
      final res = await ApiClient.instance.get('/api/bookings/$bookingId/transactions');
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final payments = (data['payments'] ?? data['Payments']) as List? ?? [];
      final subTotal = ((data['subTotal'] ?? data['SubTotal'] ?? 0) as num).toDouble();
      final surcharge = ((data['surchargeTotal'] ?? data['SurchargeTotal'] ?? 0) as num).toDouble();
      final discount = ((data['discountAmount'] ?? data['DiscountAmount'] ?? 0) as num).toDouble();
      final total = ((data['totalAmount'] ?? data['TotalAmount'] ?? 0) as num).toDouble();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Biên lai & Lịch sử giao dịch\nĐơn $code', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('• Tiền ghế (Snapshot BR13): ${subTotal.toStringAsFixed(0)} đ'),
                  Text('• Phụ thu điểm đón/trả: +${surcharge.toStringAsFixed(0)} đ'),
                  Text('• Khuyến mãi giảm giá: -${discount.toStringAsFixed(0)} đ'),
                  Text('• TỔNG THANH TOÁN: ${total.toStringAsFixed(0)} đ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                  const Divider(),
                  ...payments.map((p) {
                    final pm = Map<String, dynamic>.from(p as Map);
                    final txs = (pm['transactions'] ?? pm['Transactions']) as List? ?? [];
                    final refunds = (pm['refunds'] ?? pm['Refunds']) as List? ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phương thức: ${pm['method'] ?? pm['Method']} • Trạng thái: ${pm['status'] ?? pm['Status']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text('Nhật ký cổng thanh toán (PaymentTransactions):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if (txs.isEmpty)
                          const Text('• Chưa phát sinh giao dịch cổng thanh toán.', style: TextStyle(fontSize: 12))
                        else
                          ...txs.map((t) {
                            final tm = Map<String, dynamic>.from(t as Map);
                            return Text(
                              '• Mã GD: ${tm['providerRef'] ?? tm['ProviderRef']} | RspCode: ${tm['responseCode'] ?? tm['ResponseCode']} | Chữ ký HMAC: ${(tm['signatureValid'] ?? tm['SignatureValid']) == true ? "Hợp lệ" : "Sai"}',
                              style: const TextStyle(fontSize: 11.5),
                            );
                          }),
                        if (refunds.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text('Lịch sử hoàn tiền (Refunds - UC11, BR20):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
                          ...refunds.map((r) {
                            final rm = Map<String, dynamic>.from(r as Map);
                            return Text(
                              '• Hoàn ${((rm['amount'] ?? rm['Amount'] ?? 0) as num).toStringAsFixed(0)} đ (${rm['status'] ?? rm['Status']}) — ${rm['reason'] ?? rm['Reason']}',
                              style: const TextStyle(fontSize: 11.5),
                            );
                          }),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showPublicLookupDialog() async {
    final codeCtrl = TextEditingController(text: 'BTB-20261103-001');
    final phoneCtrl = TextEditingController(text: '0901234567');
    Map<String, dynamic>? result;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tra cứu vé nhanh (Mã đơn + SĐT)', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Không cần đăng nhập: Nhập Mã đơn đặt vé và Số điện thoại để kiểm tra vé QR.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Mã đơn (VD: BTB-20261103-001)', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Số điện thoại đặt vé', isDense: true, border: OutlineInputBorder()),
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  if (result != null) ...[
                    const Divider(height: 20),
                    Text('Tuyến: ${result!['routeName'] ?? result!['RouteName']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Nhà xe: ${result!['companyName'] ?? result!['CompanyName']} • Xe: ${result!['plateNumber'] ?? result!['PlateNumber']}'),
                    Text('Trạng thái đơn: ${result!['status'] ?? result!['Status']} • Thanh toán: ${result!['paymentMethod'] ?? result!['PaymentMethod']} (${result!['paymentStatus'] ?? result!['PaymentStatus']})'),
                    const SizedBox(height: 6),
                    ...(((result!['seats'] ?? result!['Seats']) as List?) ?? []).map((s) {
                      final sm = Map<String, dynamic>.from(s as Map);
                      return Text('• Ghế ${sm['seatCode'] ?? sm['SeatCode']}: ${sm['passengerName'] ?? sm['PassengerName']} — Mã vé: ${sm['ticketCode'] ?? sm['TicketCode'] ?? "Chưa xuất"}');
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.get('/api/bookings/public-lookup', query: {
                    'bookingCode': codeCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                  });
                  setDialogState(() {
                    result = Map<String, dynamic>.from(res as Map);
                    err = null;
                  });
                } catch (e) {
                  setDialogState(() {
                    err = e.toString();
                    result = null;
                  });
                }
              },
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Tra cứu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangeSeatDialog(int bookingId, int tripId, String code) async {
    try {
      final seatsRes = await ApiClient.instance.get('/api/trips/$tripId/seats');
      if (!mounted) return;
      final availSeats = (seatsRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((s) => (s['seatStatus'] ?? s['SeatStatus']) == 'Available')
          .toList();

      if (availSeats.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chuyến xe hiện không còn ghế trống để đổi.')),
        );
        return;
      }

      int selectedNewSeatId = (availSeats.first['tripSeatId'] ?? availSeats.first['TripSeatId']) as int;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Đổi ghế nhanh cho đơn $code', style: const TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chọn ghế trống mới trên cùng chuyến xe (tự động cấp lại mã vé QR mới):', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: selectedNewSeatId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ghế trống khả dụng', border: OutlineInputBorder()),
                  items: availSeats.map((s) {
                    final id = (s['tripSeatId'] ?? s['TripSeatId']) as int;
                    final sc = (s['seatCode'] ?? s['SeatCode']).toString();
                    final deck = (s['deck'] ?? s['Deck']).toString();
                    final pr = ((s['currentPrice'] ?? s['CurrentPrice'] ?? 0) as num).toStringAsFixed(0);
                    return DropdownMenuItem(value: id, child: Text('Ghế $sc (Tầng $deck - $pr đ)'));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => selectedNewSeatId = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                onPressed: () async {
                  try {
                    final res = await ApiClient.instance.post('/api/bookings/$bookingId/change-seat', body: {
                      'newTripSeatId': selectedNewSeatId,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadMyBookingsAndNotifications();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text((res['message'] ?? 'Đã đổi ghế thành công!').toString())),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: const Text('Xác nhận đổi ghế'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showLoyaltyDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/auth/loyalty');
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final promos = (data['availablePromotions'] ?? data['AvailablePromotions']) as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.workspace_premium, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(child: Text('Hồ sơ Thành viên & Điểm thưởng Loyalty', style: TextStyle(fontSize: 15))),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hạng hiện tại: ${data['tierName'] ?? data['TierName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepOrange)),
                        const SizedBox(height: 4),
                        Text('• Điểm thưởng tích lũy: ${data['loyaltyPoints'] ?? data['LoyaltyPoints']} điểm (Mốc tiếp theo: ${data['nextTierPoints'] ?? data['NextTierPoints']} điểm)'),
                        Text('• Tổng chi tiêu: ${((data['totalSpent'] ?? data['TotalSpent'] ?? 0) as num).toStringAsFixed(0)} đ (${data['totalTickets'] ?? data['TotalTickets']} vé)'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Kho Voucher / Khuyến mãi đang mở:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...promos.map((p) {
                    final pm = Map<String, dynamic>.from(p as Map);
                    final code = (pm['code'] ?? pm['Code']).toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.local_offer, color: Colors.deepOrange),
                        title: Text(code, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${pm['description'] ?? pm['Description']}\nĐã dùng: ${pm['usedCount'] ?? pm['UsedCount']}/${pm['usageLimit'] ?? pm['UsageLimit']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã sao chép mã $code!')),
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showManageDevicesDialog() async {
    try {
      var res = await ApiClient.instance.get('/api/auth/devices');
      if (!mounted) return;
      var devices = res as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Thiết bị nhận thông báo (UserDevices - Mục 10.1)', style: TextStyle(fontSize: 15)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (devices.isEmpty)
                    const Text('Chưa có thiết bị nào được đăng ký.')
                  else
                    ...devices.map((d) {
                      final dm = Map<String, dynamic>.from(d as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.phone_android, color: Color(0xFF0D47A1)),
                        title: Text('Nền tảng: ${dm['devicePlatform'] ?? dm['DevicePlatform']}'),
                        subtitle: Text('FCM: ${dm['fcmToken'] ?? dm['FcmToken']}'),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
              FilledButton.icon(
                onPressed: () async {
                  await ApiClient.instance.post('/api/auth/devices', body: {
                    'devicePlatform': 'Android Physical Device',
                    'fcmToken': 'FCM-ANDROID-${DateTime.now().millisecondsSinceEpoch}',
                  });
                  final refreshed = await ApiClient.instance.get('/api/auth/devices');
                  setDialogState(() {
                    devices = refreshed as List? ?? [];
                  });
                },
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Đồng bộ thiết bị này'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi mật khẩu (FR01)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: curCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu mới (>= 6 ký tự)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/auth/change-password', body: {
                  'currentPassword': curCtrl.text,
                  'newPassword': newCtrl.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã đổi mật khẩu').toString())),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRegisterCompanyDialog() async {
    final nameCtrl = TextEditingController(text: 'Nhà xe Hoàng Long Express');
    final taxCtrl = TextEditingController(text: '0200123999');
    final phoneCtrl = TextEditingController(text: '19009889');
    final addrCtrl = TextEditingController(text: 'Số 5 Phạm Ngũ Lão, Hải Phòng');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng ký hồ sơ Nhà xe mới (UC14)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Tên nhà xe', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: taxCtrl,
                decoration: const InputDecoration(labelText: 'Mã số thuế doanh nghiệp', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Hotline liên hệ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Địa chỉ trụ sở', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/operator/register-company', body: {
                  'name': nameCtrl.text.trim(),
                  'taxCode': taxCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'address': addrCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã gửi hồ sơ').toString())),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Gửi hồ sơ chờ duyệt'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateSupportDialog() async {
    final subjCtrl = TextEditingController(text: 'Hỗ trợ đổi điểm đón khách');
    final contentCtrl = TextEditingController(text: 'Tôi muốn đổi điểm đón sang VP Hàng Xanh cho chuyến tối nay.');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gửi yêu cầu hỗ trợ (UC31)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjCtrl,
              decoration: const InputDecoration(labelText: 'Tiêu đề', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Nội dung chi tiết', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/support-requests', body: {
                  'subject': subjCtrl.text.trim(),
                  'content': contentCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadMyBookingsAndNotifications();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã gửi yêu cầu').toString())),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
  }

  // Đợt 2 - Tính năng #1: Đăng ký chờ săn ghế trống (Trip Waitlist & Auto-Alert)
  Future<void> _showWaitlistDialog(int tripId, String routeName) async {
    final user = ApiClient.instance.currentUser ?? {};
    final nameCtrl = TextEditingController(text: (user['fullName'] ?? user['FullName'] ?? 'Nguyễn Văn Khách').toString());
    final phoneCtrl = TextEditingController(text: (user['phone'] ?? user['Phone'] ?? '0901234567').toString());
    int seats = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Đăng ký Săn ghế trống / Danh sách chờ\nChuyến #$tripId ($routeName)', style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Khi có hành khách hủy vé hoặc hết hạn giữ chỗ 10 phút, hệ thống sẽ tự động đẩy thông báo ưu tiên cho bạn ngay lập tức:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Họ tên người nhận thông báo', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Số điện thoại liên hệ', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: seats,
                decoration: const InputDecoration(labelText: 'Số ghế cần chờ', isDense: true, border: OutlineInputBorder()),
                items: [1, 2, 3, 4].map((n) => DropdownMenuItem(value: n, child: Text('$n ghế'))).toList(),
                onChanged: (v) => setDialogState(() => seats = v ?? 1),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/trips/$tripId/waitlist', body: {
                    'customerName': nameCtrl.text.trim(),
                    'customerPhone': phoneCtrl.text.trim(),
                    'seatCountRequested': seats,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã đăng ký danh sách chờ!').toString())),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              icon: const Icon(Icons.notifications_active, size: 16),
              label: const Text('Đăng ký nhận báo ghế trống'),
            ),
          ],
        ),
      ),
    );
  }

  // Đợt 2 - Tính năng #2: Đặt xe trung chuyển đón/trả tận nơi (Shuttle / Door-to-Door Transfer)
  Future<void> _showShuttleBookingDialog(int bookingId, String bookingCode) async {
    try {
      final res = await ApiClient.instance.get('/api/bookings/$bookingId/shuttle');
      if (!mounted) return;
      final existing = (res as Map)['shuttle'] ?? res['Shuttle'];
      final pickupCtrl = TextEditingController(
        text: existing != null
            ? (existing['pickupAddress'] ?? existing['PickupAddress'] ?? '').toString()
            : '268 Lý Thường Kiệt, Phường 14, Quận 10, TP.HCM',
      );
      final dropoffCtrl = TextEditingController(
        text: existing != null
            ? (existing['dropoffAddress'] ?? existing['DropoffAddress'] ?? '').toString()
            : 'Khách sạn TTC Ngọc Lan, 42 Nguyễn Chí Thanh, Đà Lạt',
      );
      final areaCtrl = TextEditingController(
        text: existing != null
            ? (existing['pickupArea'] ?? existing['PickupArea'] ?? 'Quận 10 / Nội thành').toString()
            : 'Quận 10 / Nội thành',
      );

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Xe trung chuyển đón/trả tận nơi\nĐơn $bookingCode', style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      'Trạng thái điều phối: ${existing['status'] ?? existing['Status']}\nXe trung chuyển: ${existing['shuttlePlate'] ?? existing['ShuttlePlate'] ?? "Đang điều phối"}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                  ),
                ],
                TextField(
                  controller: areaCtrl,
                  decoration: const InputDecoration(labelText: 'Khu vực / Quận đón', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pickupCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Địa chỉ đón tận nơi (Nhà riêng / Khách sạn)', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dropoffCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Địa chỉ trả tận nơi tại điểm đến', isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () async {
                final postRes = await ApiClient.instance.post('/api/bookings/$bookingId/shuttle', body: {
                  'pickupAddress': pickupCtrl.text.trim(),
                  'dropoffAddress': dropoffCtrl.text.trim(),
                  'pickupArea': areaCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((postRes['message'] ?? 'Đã đăng ký xe trung chuyển!').toString())),
                  );
                }
              },
              icon: const Icon(Icons.airport_shuttle, size: 16),
              label: const Text('Lưu đăng ký trung chuyển'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // Đợt 2 - Tính năng #3: Quản lý Danh bạ Hành khách thường đi (Saved Companions)
  Future<void> _showSavedCompanionsDialog() async {
    try {
      var res = await ApiClient.instance.get('/api/auth/companions');
      if (!mounted) return;
      var list = res as List? ?? [];

      final nameCtrl = TextEditingController(text: 'Trần Quốc Bảo');
      final phoneCtrl = TextEditingController(text: '0918222333');
      String relation = 'Gia đình';

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Danh bạ Hành khách thường đi (Quick-Fill)', style: TextStyle(fontSize: 15)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (list.isEmpty)
                      const Text('Chưa có người đi cùng nào trong danh bạ.')
                    else
                      ...list.map((c) {
                        final cm = Map<String, dynamic>.from(c as Map);
                        final id = (cm['companionId'] ?? cm['CompanionId']) as int;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_pin, color: Color(0xFF0D47A1)),
                            title: Text((cm['fullName'] ?? cm['FullName']).toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('SĐT: ${cm['phone'] ?? cm['Phone']} • ${cm['relationship'] ?? cm['Relationship']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                              onPressed: () async {
                                await ApiClient.instance.delete('/api/auth/companions/$id');
                                final refreshed = await ApiClient.instance.get('/api/auth/companions');
                                setDialogState(() => list = refreshed as List? ?? []);
                              },
                            ),
                          ),
                        );
                      }),
                    const Divider(height: 20),
                    const Text('Thêm người thân / đồng nghiệp mới:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên', isDense: true, border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            decoration: const InputDecoration(labelText: 'Số điện thoại', isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: relation,
                            decoration: const InputDecoration(labelText: 'Mối quan hệ', isDense: true, border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Gia đình', child: Text('Gia đình')),
                              DropdownMenuItem(value: 'Đồng nghiệp', child: Text('Đồng nghiệp')),
                              DropdownMenuItem(value: 'Bạn bè', child: Text('Bạn bè')),
                            ],
                            onChanged: (v) => setDialogState(() => relation = v ?? 'Gia đình'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
              FilledButton.icon(
                onPressed: () async {
                  await ApiClient.instance.post('/api/auth/companions', body: {
                    'fullName': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'relationship': relation,
                  });
                  final refreshed = await ApiClient.instance.get('/api/auth/companions');
                  setDialogState(() => list = refreshed as List? ?? []);
                },
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Thêm vào danh bạ'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // Đợt 2 - Tính năng #4: Xuất Hóa đơn điện tử GTGT VAT (E-Invoice Request)
  Future<void> _showVatInvoiceDialog(int bookingId, String bookingCode, double totalAmount) async {
    try {
      final res = await ApiClient.instance.get('/api/bookings/$bookingId/invoice');
      if (!mounted) return;
      final existing = (res as Map)['invoice'] ?? res['Invoice'];

      final taxCtrl = TextEditingController(
        text: existing != null ? (existing['taxCode'] ?? existing['TaxCode']).toString() : '0312345678',
      );
      final compCtrl = TextEditingController(
        text: existing != null ? (existing['companyName'] ?? existing['CompanyName']).toString() : 'CÔNG TY TNHH CÔNG NGHỆ & VẬN TẢI VIỆT NAM',
      );
      final addrCtrl = TextEditingController(
        text: existing != null ? (existing['companyAddress'] ?? existing['CompanyAddress']).toString() : 'Tòa nhà Bitexco, Số 2 Hải Triều, Quận 1, TP.HCM',
      );
      final emailCtrl = TextEditingController(
        text: existing != null ? (existing['buyerEmail'] ?? existing['BuyerEmail']).toString() : 'ketoan@congtyvietnam.vn',
      );

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Hóa đơn điện tử GTGT (VAT 8%)\nĐơn $bookingCode', style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      'ĐÃ PHÁT HÀNH HÓA ĐƠN SỐ: ${existing['invoiceNumber'] ?? existing['InvoiceNumber']}\nTổng thanh toán: ${totalAmount.toStringAsFixed(0)}đ (Thuế VAT 8%: ${((existing['vatAmount'] ?? existing['VatAmount'] ?? 0) as num).toStringAsFixed(0)}đ)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0D47A1)),
                    ),
                  ),
                TextField(
                  controller: taxCtrl,
                  decoration: const InputDecoration(labelText: 'Mã số thuế doanh nghiệp', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: compCtrl,
                  decoration: const InputDecoration(labelText: 'Tên đơn vị / Công ty', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: 'Địa chỉ đăng ký thuế', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email nhận bản thể hiện hóa đơn điện tử PDF/XML', isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () async {
                final postRes = await ApiClient.instance.post('/api/bookings/$bookingId/invoice', body: {
                  'taxCode': taxCtrl.text.trim(),
                  'companyName': compCtrl.text.trim(),
                  'companyAddress': addrCtrl.text.trim(),
                  'buyerEmail': emailCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((postRes['message'] ?? 'Đã phát hành hóa đơn VAT!').toString())),
                  );
                }
              },
              icon: const Icon(Icons.receipt, size: 16),
              label: const Text('Phát hành Hóa đơn VAT'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }
}


class _LiveRouteMapPainter extends CustomPainter {
  final List<dynamic> stops;
  final double? liveLat;
  final double? liveLng;

  _LiveRouteMapPainter({
    required this.stops,
    this.liveLat,
    this.liveLng,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.green.shade700
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final startX = 24.0;
    final endX = size.width - 24.0;
    final midY = size.height * 0.55;

    final path = Path()
      ..moveTo(startX, midY + 15)
      ..quadraticBezierTo(size.width * 0.5, midY - 35, endX, midY - 10);
    canvas.drawPath(path, roadPaint);

    final count = stops.isEmpty ? 2 : stops.length;
    for (int i = 0; i < count; i++) {
      final t = count == 1 ? 0.5 : i / (count - 1);
      final x = startX + (endX - startX) * t;
      final y = (1 - t) * (1 - t) * (midY + 15) +
          2 * (1 - t) * t * (midY - 35) +
          t * t * (midY - 10);

      canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()
          ..color = const Color(0xFF0D47A1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      if (stops.isNotEmpty) {
        final s = Map<String, dynamic>.from(stops[i] as Map);
        final name = (s['stopName'] ?? s['StopName'] ?? '').toString();
        final shortName = name.length > 12 ? '${name.substring(0, 12)}…' : name;
        final tp = TextPainter(
          text: TextSpan(
            text: shortName,
            style: const TextStyle(fontSize: 9.5, color: Colors.black87, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, i.isEven ? y + 10 : y - 22));
      }
    }

    if (liveLat != null && liveLng != null) {
      // Map latitude (10.8 -> 11.95) to progress t (0.0 -> 1.0)
      final t = ((liveLat! - 10.80) / (11.93 - 10.80)).clamp(0.05, 0.95);
      final bx = startX + (endX - startX) * t;
      final by = (1 - t) * (1 - t) * (midY + 15) +
          2 * (1 - t) * t * (midY - 35) +
          t * t * (midY - 10);

      canvas.drawCircle(Offset(bx, by), 12, Paint()..color = Colors.deepOrange);
      final tp = TextPainter(
        text: const TextSpan(
          text: '🚌 XE',
          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(bx - tp.width / 2, by - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
