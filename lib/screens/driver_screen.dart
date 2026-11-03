import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../theme/shadcn_theme.dart';
import 'trip_chat_screen.dart';
import 'in_app_call_screen.dart';

class DriverOperationsView extends StatefulWidget {
  const DriverOperationsView({super.key});

  @override
  State<DriverOperationsView> createState() => _DriverOperationsViewState();
}

class _DriverOperationsViewState extends State<DriverOperationsView> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _trips = [];
  int? _selectedTripId;
  bool _loading = false;
  int _activeSubTab = 0; // 0: Soát vé QR, 1: Danh sách hành khách & COD, 2: Điều hành & GPS

  // Camera & MobileScanner
  MobileScannerController? _scannerController;
  bool _cameraActive = false;
  bool _torchOn = false;
  DateTime? _lastScanTime;
  String? _lastScannedCode;

  // Quét vé & Kiểm tra (Inspect & Check-in)
  final _qrInputCtrl = TextEditingController();
  bool _inspecting = false;
  Map<String, dynamic>? _inspectedTicket;
  String? _inspectionError;
  String? _checkInSuccessMessage;

  // GPS & Hành trình
  Timer? _autoGpsTimer;
  bool _autoGpsActive = false;
  int _waypointIndex = 0;
  String _passengerFilter = 'ALL'; // ALL, ACTIVE, USED, COD_UNPAID

  final List<Map<String, dynamic>> _gpsWaypoints = const [
    {'name': 'Bến xe Miền Đông Mới (TP.HCM)', 'lat': 10.8794, 'lng': 106.8142, 'speed': 35.0},
    {'name': 'Cao tốc Long Thành - Dầu Giây', 'lat': 10.8211, 'lng': 107.0189, 'speed': 82.5},
    {'name': 'Trạm dừng Bảo Lộc (Lâm Đồng)', 'lat': 11.5479, 'lng': 107.8077, 'speed': 54.0},
    {'name': 'Đèo Prenn - Cửa ngõ Đà Lạt', 'lat': 11.9012, 'lng': 108.4395, 'speed': 42.0},
    {'name': 'Bến xe Liên tỉnh Đà Lạt', 'lat': 11.9267, 'lng': 108.4451, 'speed': 0.0},
  ];

  // Poller kiểm tra cuộc gọi đến từ hành khách
  Timer? _callCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _callCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkForIncomingCall());
  }

  @override
  void dispose() {
    _callCheckTimer?.cancel();
    _autoGpsTimer?.cancel();
    _qrInputCtrl.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _checkForIncomingCall() async {
    final checkTripId = _selectedTripId ?? 1;
    try {
      final res = await ApiClient.instance.get('/api/trips/$checkTripId/calls/active');
      if (res is Map && mounted) {
        final status = (res['status'] ?? res['Status'])?.toString();
        final role = (res['callerRole'] ?? res['CallerRole'])?.toString();
        final callId = (res['callId'] ?? res['CallId'])?.toString();
        final caller = (res['callerName'] ?? res['CallerName'] ?? 'Hành khách').toString();

        if (status == 'Ringing' && role == 'Customer' && callId != null) {
          _callCheckTimer?.cancel();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InAppCallScreen(
                tripId: checkTripId,
                partnerName: caller,
                partnerPhone: 'Hành khách trên xe',
                partnerRole: 'Customer',
                isIncoming: true,
                initialCallId: callId,
              ),
            ),
          );
          _callCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkForIncomingCall());
        }
      }
    } catch (_) {}
  }

  void _toggleCamera() {
    setState(() {
      _cameraActive = !_cameraActive;
      if (_cameraActive) {
        _scannerController = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          detectionTimeoutMs: 1200,
          facing: CameraFacing.back,
          torchEnabled: false,
          formats: const [BarcodeFormat.qrCode],
        );
      } else {
        _scannerController?.dispose();
        _scannerController = null;
        _torchOn = false;
      }
    });
  }

  void _toggleTorch() {
    if (_scannerController != null) {
      _scannerController!.toggleTorch();
      setState(() => _torchOn = !_torchOn);
    }
  }

  String _formatVND(dynamic amount) {
    if (amount == null) return '0 đ';
    final n = (amount is num) ? amount.toInt() : int.tryParse(amount.toString()) ?? 0;
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return '${buffer.toString()} đ';
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '--';
    try {
      final d = DateTime.parse(iso).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      final mo = d.month.toString().padLeft(2, '0');
      return '$hh:$mm $dd/$mo';
    } catch (_) {
      return iso;
    }
  }

  void _toggleAutoGps(bool enable) {
    _autoGpsTimer?.cancel();
    setState(() => _autoGpsActive = enable);
    if (enable) {
      _sendGps(_gpsWaypoints[_waypointIndex % _gpsWaypoints.length]);
      _autoGpsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted || !_autoGpsActive) return;
        _waypointIndex = (_waypointIndex + 1) % _gpsWaypoints.length;
        _sendGps(_gpsWaypoints[_waypointIndex]);
      });
    }
  }

  Future<void> _sendGps(Map<String, dynamic> wp) async {
    final trip = _currentTrip;
    if (trip == null) return;
    final tripId = (trip['tripId'] ?? trip['TripId']) as int;
    try {
      await ApiClient.instance.post('/api/driver/trips/$tripId/location', body: {
        'latitude': wp['lat'],
        'longitude': wp['lng'],
        'speedKmh': wp['speed'],
      });
    } catch (_) {}
  }

  Future<void> _loadTrips() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get('/api/driver/trips');
      final list = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _trips = list;
        if (_selectedTripId == null && list.isNotEmpty) {
          final tripWithPax = list.firstWhere(
            (t) => ((t['passengers'] ?? t['Passengers']) as List? ?? []).isNotEmpty,
            orElse: () => list.first,
          );
          _selectedTripId = (tripWithPax['tripId'] ?? tripWithPax['TripId']) as int;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _currentTrip {
    if (_trips.isEmpty) return null;
    return _trips.firstWhere(
      (t) => (t['tripId'] ?? t['TripId']) == _selectedTripId,
      orElse: () => _trips.first,
    );
  }

  // Tra cứu thông tin vé & trạng thái thu tiền/lên xe
  Future<void> _inspectTicket([String? codeOverride]) async {
    final code = (codeOverride ?? _qrInputCtrl.text).trim();
    if (code.isEmpty) return;
    _qrInputCtrl.text = code;

    setState(() {
      _inspecting = true;
      _inspectionError = null;
      _checkInSuccessMessage = null;
    });

    try {
      final res = await ApiClient.instance.post('/api/tickets/inspect', body: {
        'qrOrTicketCode': code,
        'tripId': _selectedTripId,
      });

      setState(() {
        _inspectedTicket = Map<String, dynamic>.from(res as Map);
        _activeSubTab = 0; // Quay về tab quét vé để hiển thị
      });
    } catch (e) {
      setState(() {
        _inspectedTicket = null;
        _inspectionError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  // Thực hiện Check-in lên xe (có hoặc không thu tiền COD)
  Future<void> _confirmCheckIn({required bool collectCod}) async {
    final ticket = _inspectedTicket;
    if (ticket == null) return;
    final code = (ticket['ticketCode'] ?? ticket['TicketCode'] ?? _qrInputCtrl.text).toString();

    setState(() => _inspecting = true);
    try {
      final res = await ApiClient.instance.post('/api/tickets/check-in', body: {
        'qrOrTicketCode': code,
        'tripId': _selectedTripId,
        'collectCodNow': collectCod,
        'deviceInfo': 'Máy Soát Vé Cầm Tay (Staff Handheld)',
      });

      setState(() {
        _checkInSuccessMessage = (res['message'] ?? 'Xác nhận lên xe thành công!').toString();
        // Cập nhật trạng thái inspected ticket tức thì
        if (_inspectedTicket != null) {
          _inspectedTicket!['isBoarded'] = true;
          _inspectedTicket!['ticketStatus'] = 'Used';
          if (collectCod) {
            _inspectedTicket!['isPaid'] = true;
            _inspectedTicket!['isCodUnpaid'] = false;
            _inspectedTicket!['paymentStatus'] = 'Paid';
          }
        }
      });

      await _loadTrips();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  void _resetScanner() {
    setState(() {
      _qrInputCtrl.clear();
      _inspectedTicket = null;
      _inspectionError = null;
      _checkInSuccessMessage = null;
    });
  }

  Future<void> _updateTripStatus(String newStatus) async {
    final trip = _currentTrip;
    if (trip == null) return;
    final tripId = (trip['tripId'] ?? trip['TripId']) as int;

    String? reason;
    if (newStatus == 'Delayed') {
      final ctrl = TextEditingController(text: 'Kẹt xe khu vực đèo Bảo Lộc (+45 phút)');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Báo trễ chuyến (BR28)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Lý do trễ chuyến', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cập nhật')),
          ],
        ),
      );
      if (ok != true) return;
      reason = ctrl.text.trim();
    }

    try {
      final res = await ApiClient.instance.post('/api/driver/trips/$tripId/status', body: {
        'newStatus': newStatus,
        'reason': reason,
      });
      if (!mounted) return;
      await _loadTrips();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã cập nhật trạng thái').toString())),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _currentTrip;
    final passengers = (trip?['passengers'] ?? trip?['Passengers']) as List? ?? [];
    final totalTickets = (trip?['totalTickets'] ?? trip?['TotalTickets'] ?? 0) as int;
    final checkedInTickets = (trip?['checkedInTickets'] ?? trip?['CheckedInTickets'] ?? 0) as int;
    final isStaff = ApiClient.instance.roles.contains('Staff');

    return Scaffold(
      backgroundColor: ShadcnTheme.background,
      body: _loading && _trips.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Top Header: Trip Selector & Conductor Title
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: ShadcnTheme.primary.withOpacity(0.15))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [ShadcnTheme.primary, ShadcnTheme.accentBlue],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: ShadcnTheme.primary.withOpacity(0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ],
                              ),
                              child: const Icon(LucideIcons.scanLine, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isStaff ? 'CỔNG SOÁT VÉ ĐIỆN TỬ (STAFF)' : 'SOÁT VÉ & ĐIỀU HÀNH CHUYẾN',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      letterSpacing: -0.3,
                                      color: ShadcnTheme.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    'Quét QR kiểm tra thu tiền COD & xác nhận lên xe',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _loadTrips,
                              icon: const Icon(LucideIcons.refreshCw, size: 18, color: ShadcnTheme.primary),
                              tooltip: 'Làm mới',
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Trip Dropdown Selector
                        if (_trips.isEmpty)
                          const Text('Không có chuyến xe nào được phân công.', style: TextStyle(color: Colors.grey))
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: ShadcnTheme.primaryLight.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ShadcnTheme.primary.withOpacity(0.2)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedTripId,
                                isExpanded: true,
                                icon: const Icon(LucideIcons.chevronDown, size: 18, color: ShadcnTheme.primary),
                                items: _trips.map((t) {
                                  final id = (t['tripId'] ?? t['TripId']) as int;
                                  final route = (t['routeName'] ?? t['RouteName']).toString();
                                  final plate = (t['plateNumber'] ?? t['PlateNumber']).toString();
                                  final dep = _formatDate((t['departureAt'] ?? t['DepartureAt'])?.toString());
                                  return DropdownMenuItem<int>(
                                    value: id,
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.bus, size: 15, color: ShadcnTheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$route ($plate) • $dep',
                                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _selectedTripId = v;
                                    _resetScanner();
                                  });
                                },
                              ),
                            ),
                          ),

                        const SizedBox(height: 8),

                        // Quick Statistics Bar
                        Row(
                          children: [
                            _statPill(
                              icon: LucideIcons.userCheck,
                              label: 'Đã lên xe',
                              value: '$checkedInTickets / $totalTickets',
                              color: ShadcnTheme.success,
                            ),
                            const SizedBox(width: 8),
                            _statPill(
                              icon: LucideIcons.badgeDollarSign,
                              label: 'Chưa thu COD',
                              value: passengers.where((p) {
                                final pm = Map<String, dynamic>.from(p as Map);
                                return (pm['paymentMethod'] == 'COD' && pm['paymentStatus'] == 'Unpaid');
                              }).length.toString(),
                              color: Colors.amber.shade700,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Sub-tabs Segmented Bar
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _subTabItem(0, LucideIcons.scanLine, 'Quét QR'),
                        _subTabItem(1, LucideIcons.users, 'Khách ($totalTickets)'),
                        _subTabItem(2, LucideIcons.compass, 'Chuyến & GPS'),
                      ],
                    ),
                  ),
                ),

                // Main Tab Body
                SliverPadding(
                  padding: const EdgeInsets.all(14),
                  sliver: SliverToBoxAdapter(
                    child: _buildActiveTabContent(trip, passengers),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statPill({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subTabItem(int index, IconData icon, String label) {
    final active = _activeSubTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeSubTab = index),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? ShadcnTheme.primary : Colors.grey.shade600),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? ShadcnTheme.primaryDark : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(Map<String, dynamic>? trip, List passengers) {
    if (_activeSubTab == 0) {
      return _buildQrScannerView(passengers);
    } else if (_activeSubTab == 1) {
      return _buildPassengerListView(passengers);
    } else {
      return _buildTripOperationsView(trip);
    }
  }

  // ==========================================
  // TAB 1: QUÉT MÃ QR SOÁT VÉ CHUYÊN NGHIỆP
  // ==========================================
  Widget _buildQrScannerView(List passengers) {
    final ticket = _inspectedTicket;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Máy quét / Khung Scanner (Hỗ trợ Live Camera thực tế & Giả lập)
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Dark slate viewfinder
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: ShadcnTheme.primary.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Live camera stream if active
                if (_cameraActive && _scannerController != null)
                  Positioned.fill(
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) {
                        final barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          final raw = barcode.rawValue?.trim();
                          if (raw != null && raw.isNotEmpty) {
                            final now = DateTime.now();
                            if (_lastScannedCode == raw && _lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 1500) {
                              return;
                            }
                            _lastScannedCode = raw;
                            _lastScanTime = now;
                            _inspectTicket(raw);
                            break;
                          }
                        }
                      },
                    ),
                  )
                else
                  // Simulated dark camera background when camera is idle
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0F172A),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.camera, size: 36, color: Colors.white.withOpacity(0.4)),
                            const SizedBox(height: 8),
                            Text(
                              'Camera đang tắt',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Khung ngắm quét QR (Target Viewfinder)
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                  ),
                  child: Stack(
                    children: [
                      // 4 góc sáng màu Ocean Blue
                      _buildCornerBorder(Alignment.topLeft, top: true, left: true),
                      _buildCornerBorder(Alignment.topRight, top: true, left: false),
                      _buildCornerBorder(Alignment.bottomLeft, top: false, left: true),
                      _buildCornerBorder(Alignment.bottomRight, top: false, left: false),

                      // Laser Scan Beam chuyển động
                      Center(
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.transparent, Color(0xFF38BDF8), Colors.transparent],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF38BDF8).withOpacity(0.8),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                        )
                            .animate(onPlay: (controller) => controller.repeat(reverse: true))
                            .moveY(begin: -70, end: 70, duration: 1600.ms),
                      ),
                    ],
                  ),
                ),

                // Nút Bật/Tắt Camera & Đèn Flash trên góc
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Camera On/Off Toggle Button
                      InkWell(
                        onTap: _toggleCamera,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _cameraActive ? Colors.red.withOpacity(0.85) : Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_cameraActive ? LucideIcons.cameraOff : LucideIcons.camera, size: 14, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                _cameraActive ? 'Tắt Camera' : 'Bật Camera Thực Tế',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Flashlight toggle
                      if (_cameraActive)
                        InkWell(
                          onTap: _toggleTorch,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: _torchOn ? Colors.amber.withOpacity(0.85) : Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.flashlight, size: 14, color: _torchOn ? Colors.black : Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  _torchOn ? 'Tắt Flash' : 'Bật Flash',
                                  style: TextStyle(
                                    color: _torchOn ? Colors.black : Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Trạng thái kiểm tra
                if (_inspecting)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 10),
                        Text('Đang kiểm tra vé...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Input & Test Buttons Bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qrInputCtrl,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Nhập mã vé hoặc dán chuỗi QR...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(LucideIcons.scan, size: 16, color: ShadcnTheme.primary),
                  suffixIcon: _qrInputCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 15),
                          onPressed: _resetScanner,
                        )
                      : null,
                ),
                onSubmitted: (v) => _inspectTicket(v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ShadcnTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _inspectTicket(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.search, size: 15),
                  SizedBox(width: 4),
                  Text('Kiểm tra', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),

        // Quick Pick Sample Tickets Chips from current trip
        if (passengers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(LucideIcons.sparkles, size: 12, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                'Bấm nhanh vé mẫu trên chuyến để kiểm tra:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: passengers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final p = Map<String, dynamic>.from(passengers[i] as Map);
                final seat = (p['seatCode'] ?? p['SeatCode']).toString();
                final name = (p['passengerName'] ?? p['PassengerName']).toString();
                final code = (p['ticketCode'] ?? p['TicketCode']).toString();
                final isUsed = (p['ticketStatus'] ?? p['TicketStatus']) == 'Used';
                final isCod = (p['paymentMethod'] == 'COD' && p['paymentStatus'] == 'Unpaid');

                return InkWell(
                  onTap: () => _inspectTicket(code),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isUsed
                          ? Colors.green.shade50
                          : isCod
                              ? Colors.amber.shade50
                              : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isUsed
                            ? Colors.green.shade300
                            : isCod
                                ? Colors.amber.shade400
                                : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          seat,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: isUsed
                                ? Colors.green.shade800
                                : isCod
                                    ? Colors.amber.shade900
                                    : ShadcnTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          name.split(' ').last,
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Thông báo lỗi nếu có
        if (_inspectionError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertTriangle, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _inspectionError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Thông báo check-in thành công
        if (_checkInSuccessMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _checkInSuccessMessage!,
                    style: TextStyle(color: Colors.green.shade900, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 2. KẾT QUẢ SOÁT VÉ CHI TIẾT (INSPECTION RESULT CARD)
        if (ticket != null) ...[
          const SizedBox(height: 14),
          _buildTicketResultCard(ticket),
        ],
      ],
    );
  }

  Widget _buildCornerBorder(Alignment alignment, {required bool top, required bool left}) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          border: Border(
            top: top ? const BorderSide(color: Color(0xFF38BDF8), width: 3.5) : BorderSide.none,
            bottom: !top ? const BorderSide(color: Color(0xFF38BDF8), width: 3.5) : BorderSide.none,
            left: left ? const BorderSide(color: Color(0xFF38BDF8), width: 3.5) : BorderSide.none,
            right: !left ? const BorderSide(color: Color(0xFF38BDF8), width: 3.5) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  // THẺ BÁO KẾT QUẢ SOÁT VÉ TO RÕ, NỔI BẬT THEO ĐÚNG YÊU CẦU
  Widget _buildTicketResultCard(Map<String, dynamic> t) {
    final bool isBoarded = (t['isBoarded'] ?? (t['ticketStatus'] == 'Used')) == true;
    final bool isPaid = (t['isPaid'] ?? (t['paymentStatus'] == 'Paid')) == true;
    final bool isCodUnpaid = (t['isCodUnpaid'] ?? (t['paymentMethod'] == 'COD' && t['paymentStatus'] == 'Unpaid')) == true;
    final bool isWrongTrip = (t['isWrongTrip'] ?? t['IsWrongTrip']) == true;
    final String boardedAt = _formatDate(t['boardedAt']?.toString());
    final dynamic totalAmount = t['totalAmount'] ?? t['TotalAmount'] ?? 0;
    final dynamic codAmount = t['codAmountToCollect'] ?? totalAmount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isWrongTrip
              ? Colors.orange.shade500
              : isBoarded
                  ? Colors.red.shade300
                  : isCodUnpaid
                      ? Colors.amber.shade400
                      : ShadcnTheme.primary.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isWrongTrip
                    ? Colors.orange
                    : isBoarded
                        ? Colors.red
                        : isCodUnpaid
                            ? Colors.amber
                            : ShadcnTheme.primary)
                .withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 0. CẢNH BÁO LÊN NHẦM CHUYẾN XE (NẾU CÓ)
          if (isWrongTrip)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ CẢNH BÁO: KHÁCH LÊN NHẦM CHUYẾN!',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Vé thuộc: ${t['routeName'] ?? ''} (Chuyến #${t['tripId']}). Bạn đang chọn chuyến #${_selectedTripId}.',
                          style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.orange.shade900,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 30),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            final targetTripId = t['tripId'] as int;
                            setState(() => _selectedTripId = targetTripId);
                            _inspectTicket(t['ticketCode']?.toString() ?? '');
                          },
                          icon: const Icon(LucideIcons.arrowRightLeft, size: 14),
                          label: Text(
                            'Chuyển ngay sang Chuyến #${t['tripId']} để soát vé',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // 1. BANNER TÌNH TRẠNG LÊN XE (BOARDING STATUS)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isBoarded ? Colors.red.shade600 : const Color(0xFF059669),
              borderRadius: isWrongTrip ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  isBoarded ? LucideIcons.alertOctagon : LucideIcons.badgeCheck,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBoarded ? 'CẢNH BÁO: ĐÃ LÊN XE TRƯỚC ĐÓ!' : 'HỢP LỆ: CHƯA LÊN XE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        isBoarded
                            ? 'Vé đã check-in lúc $boardedAt. Từ chối quét lặp lại (AT09)!'
                            : 'Vé sẵn sàng cho hành khách lên xe.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // 2. KHỐI TÌNH TRẠNG THU TIỀN (PAYMENT NOTICE)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCodUnpaid ? Colors.amber.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCodUnpaid ? Colors.amber.shade400 : Colors.green.shade300,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCodUnpaid ? Colors.amber.shade100 : Colors.green.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCodUnpaid ? LucideIcons.banknote : LucideIcons.checkCheck,
                        color: isCodUnpaid ? Colors.amber.shade900 : Colors.green.shade800,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCodUnpaid ? '⚠️ CHƯA THU TIỀN! CẦN THU COD:' : '✅ ĐÃ THANH TOÁN ĐỦ QUA CỔNG VNPAY',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isCodUnpaid ? Colors.amber.shade900 : Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (isCodUnpaid)
                            Text(
                              _formatVND(codAmount),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.red,
                              ),
                            )
                          else
                            Text(
                              'Số tiền đã thu: ${_formatVND(totalAmount)} • KHÔNG THU THÊM TIỀN MẶT CỦA KHÁCH',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 3. THÔNG TIN HÀNH KHÁCH & VỊ TRÍ GHẾ
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ghế to nổi bật
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ShadcnTheme.primaryDark, ShadcnTheme.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: ShadcnTheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('GHẾ', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800)),
                        Text(
                          (t['seatCode'] ?? t['SeatCode'] ?? '--').toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Chi tiết khách hàng
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (t['passengerName'] ?? t['PassengerName'] ?? 'Hành khách').toString(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(LucideIcons.phone, size: 12, color: ShadcnTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              (t['passengerPhone'] ?? t['PassengerPhone'] ?? '--').toString(),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black54),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final tripId = (t['tripId'] ?? t['TripId'] ?? _selectedTripId ?? 1) as int;
                                final paxName = (t['passengerName'] ?? t['PassengerName'] ?? 'Hành khách').toString();
                                final paxPhone = (t['passengerPhone'] ?? t['PassengerPhone'] ?? '').toString();
                                final seatCode = (t['seatCode'] ?? t['SeatCode'] ?? '').toString();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InAppCallScreen(
                                      tripId: tripId,
                                      partnerName: 'Khách $paxName ($seatCode)',
                                      partnerPhone: paxPhone,
                                      partnerRole: 'Customer',
                                      routeName: (t['routeName'] ?? t['RouteName'] ?? '').toString(),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(LucideIcons.phoneCall, size: 16, color: Color(0xFF0284C7)),
                              tooltip: 'Gọi qua App luôn',
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final paxName = (t['passengerName'] ?? t['PassengerName'] ?? 'Hành khách').toString();
                                final paxPhone = (t['passengerPhone'] ?? t['PassengerPhone'] ?? '').toString();
                                final seatCode = (t['seatCode'] ?? t['SeatCode'] ?? '').toString();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TripChatScreen(
                                      tripId: _selectedTripId ?? 1,
                                      partnerName: 'Khách $paxName ($seatCode)',
                                      partnerPhone: paxPhone,
                                      partnerRole: 'Customer',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(LucideIcons.messagesSquare, size: 16, color: Color(0xFF0284C7)),
                              tooltip: 'Nhắn tin với khách',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mã vé: ${(t['ticketCode'] ?? t['TicketCode'] ?? '--')}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Thông tin chuyến & điểm đón trả
              _infoRow(LucideIcons.route, 'Tuyến:', (t['routeName'] ?? t['RouteName'] ?? '--').toString()),
              _infoRow(LucideIcons.mapPin, 'Đón khách:', (t['pickupStop'] ?? t['PickupStop'] ?? 'Tại bến').toString()),
              _infoRow(LucideIcons.flag, 'Trả khách:', (t['dropoffStop'] ?? t['DropoffStop'] ?? 'Tại bến').toString()),
              _infoRow(LucideIcons.bus, 'Phương tiện:', '${t['plateNumber'] ?? t['PlateNumber'] ?? '--'} (${t['busType'] ?? ''})'),

              const SizedBox(height: 16),

              // 4. NÚT HÀNH ĐỘNG DÀNH CHO NHÂN VIÊN
              if (!isBoarded) ...[
                if (isCodUnpaid) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: () => _confirmCheckIn(collectCod: true),
                    icon: const Icon(LucideIcons.banknote, size: 18),
                    label: Text(
                      'ĐÃ THU ${_formatVND(codAmount)} COD & CHO LÊN XE',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: () => _confirmCheckIn(collectCod: false),
                    icon: const Icon(LucideIcons.checkCheck, size: 18),
                    label: const Text(
                      'XÁC NHẬN CHO KHÁCH LÊN XE (CHECK-IN)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ] else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: null,
                  icon: const Icon(LucideIcons.xCircle, size: 16),
                  label: const Text('VÉ ĐÃ SỬ DỤNG - KHÔNG CHO CHECK-IN LẠI'),
                ),
              ],

              const SizedBox(height: 8),

              // Nút xóa để quét vé tiếp theo
              TextButton.icon(
                onPressed: _resetScanner,
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('Quét Vé Tiếp Theo'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: ShadcnTheme.primary),
          const SizedBox(width: 6),
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: DANH SÁCH HÀNH KHÁCH & THU COD
  // ==========================================
  Widget _buildPassengerListView(List passengers) {
    final filtered = passengers.where((p) {
      final pm = Map<String, dynamic>.from(p as Map);
      final st = (pm['ticketStatus'] ?? pm['TicketStatus']).toString();
      final payMethod = (pm['paymentMethod'] ?? pm['PaymentMethod']).toString();
      final payStatus = (pm['paymentStatus'] ?? pm['PaymentStatus']).toString();
      if (_passengerFilter == 'ACTIVE') return st != 'Used';
      if (_passengerFilter == 'USED') return st == 'Used';
      if (_passengerFilter == 'COD_UNPAID') return payMethod == 'COD' && payStatus == 'Unpaid';
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Tất cả (${passengers.length})', 'ALL'),
              const SizedBox(width: 6),
              _filterChip('Chưa lên xe', 'ACTIVE'),
              const SizedBox(width: 6),
              _filterChip('Đã lên xe', 'USED'),
              const SizedBox(width: 6),
              _filterChip('Cần thu COD', 'COD_UNPAID'),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Không có hành khách nào theo bộ lọc.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else
          ...filtered.map((p) {
            final pm = Map<String, dynamic>.from(p as Map);
            final seat = (pm['seatCode'] ?? pm['SeatCode']).toString();
            final name = (pm['passengerName'] ?? pm['PassengerName']).toString();
            final phone = (pm['passengerPhone'] ?? pm['PassengerPhone'] ?? '').toString();
            final ticketCode = (pm['ticketCode'] ?? pm['TicketCode']).toString();
            final isBoarded = (pm['ticketStatus'] ?? pm['TicketStatus']) == 'Used';
            final isCod = (pm['paymentMethod'] == 'COD' && pm['paymentStatus'] == 'Unpaid');
            final dynamic amount = pm['totalAmount'] ?? pm['TotalAmount'] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isBoarded ? Colors.green.shade200 : isCod ? Colors.amber.shade300 : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                children: [
                  // Seat indicator
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isBoarded
                          ? const Color(0xFF059669)
                          : isCod
                              ? Colors.amber.shade700
                              : ShadcnTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      seat,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Passenger Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name ($phone)',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã vé: $ticketCode',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Boarding tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isBoarded ? Colors.green.shade100 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isBoarded ? 'Đã lên xe' : 'Chưa lên xe',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isBoarded ? Colors.green.shade900 : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Payment tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCod ? Colors.red.shade100 : Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isCod ? 'Thu COD ${_formatVND(amount)}' : 'Đã trả',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isCod ? Colors.red.shade900 : Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Action buttons: Call, Chat & Soát vé
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          if (_selectedTripId == null) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppCallScreen(
                                tripId: _selectedTripId!,
                                partnerName: 'Khách $name ($seat)',
                                partnerPhone: phone,
                                partnerRole: 'Customer',
                                routeName: _currentTrip?['routeName']?.toString() ?? '',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.phoneCall, size: 16, color: Color(0xFF0284C7)),
                        tooltip: 'Gọi qua App luôn',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TripChatScreen(
                                tripId: _selectedTripId ?? 1,
                                partnerName: 'Khách $name ($seat)',
                                partnerPhone: phone,
                                partnerRole: 'Customer',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.messagesSquare, size: 16, color: Color(0xFF0284C7)),
                        tooltip: 'Nhắn tin với khách',
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: isBoarded ? Colors.grey.shade300 : ShadcnTheme.primary,
                          foregroundColor: isBoarded ? Colors.grey.shade700 : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _inspectTicket(ticketCode),
                        child: Text(
                          isBoarded ? 'Xem lại' : 'Soát vé',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _passengerFilter == value;
    return InkWell(
      onTap: () => setState(() => _passengerFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ShadcnTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? ShadcnTheme.primary : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: ĐIỀU HÀNH CHUYẾN XE & GPS
  // ==========================================
  Widget _buildTripOperationsView(Map<String, dynamic>? trip) {
    if (trip == null) {
      return const Center(child: Text('Chưa chọn chuyến xe'));
    }

    final status = (trip['status'] ?? trip['Status']).toString();
    final liveLoc = trip['liveLocation'] ?? trip['LiveLocation'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trạng thái chuyến
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cập Nhật Trạng Thái Chuyến Xe (BR04)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tripStatusBtn('Đón khách', 'Boarding', status),
                  _tripStatusBtn('Khởi hành', 'Departed', status),
                  _tripStatusBtn('Báo trễ', 'Delayed', status),
                  _tripStatusBtn('Đến bến', 'Arrived', status),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Khối Phát Thông Báo Đẩy Xe Sắp Đến & Chat
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.bellRing, color: Color(0xFF16A34A), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Thông Báo Đẩy Tới Hành Khách',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF15803D)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Phát thông báo đẩy đến điện thoại của tất cả khách hàng khi xe sắp đến điểm đón (ngay cả khi khách đã tắt hoặc ẩn ứng dụng).',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF166534)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _showNotifyApproachingDialog(trip),
                      icon: const Icon(LucideIcons.send, size: 16),
                      label: const Text('BÁO XE SẮP ĐẾN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF16A34A)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TripChatScreen(
                              tripId: _selectedTripId ?? 1,
                              partnerName: 'Toàn bộ hành khách chuyến',
                              partnerPhone: 'Tổng đài điều hành',
                              partnerRole: 'Driver',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.messagesSquare, size: 16, color: Color(0xFF16A34A)),
                      label: const Text('KÊNH CHAT CHUYẾN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF16A34A))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Phát GPS
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Phát Tọa Độ GPS Chuyến Xe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  if (_autoGpsActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
                      child: Text('Live 10s Hub', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.green.shade900)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (liveLoc != null)
                Text(
                  'Tọa độ: ${liveLoc['latitude']}, ${liveLoc['longitude']} • ${liveLoc['speedKmh']} km/h',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ShadcnTheme.primary),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _autoGpsActive,
                onChanged: _toggleAutoGps,
                title: const Text('Tự động phát GPS mỗi 10 giây (SignalR)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tripStatusBtn(String label, String code, String current) {
    final active = current == code;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? ShadcnTheme.primary : Colors.white,
        foregroundColor: active ? Colors.white : Colors.black87,
        side: BorderSide(color: active ? ShadcnTheme.primary : Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _updateTripStatus(code),
      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _showNotifyApproachingDialog(Map<String, dynamic> trip) async {
    int selectedMins = 10;
    final noteCtrl = TextEditingController(text: 'Xe đang tới gần cổng bến/sảnh đón, quý khách vui lòng chuẩn bị hành lý!');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(LucideIcons.megaphone, color: Color(0xFF16A34A), size: 24),
              SizedBox(width: 8),
              Expanded(child: Text('Báo Xe Đang Tới Gần', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dự kiến xe tới điểm đón trong:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [5, 10, 15, 20].map((m) {
                  final sel = selectedMins == m;
                  return ChoiceChip(
                    label: Text('$m phút'),
                    selected: sel,
                    onSelected: (_) => setDlgState(() => selectedMins = m),
                    selectedColor: const Color(0xFF16A34A),
                    labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Lời nhắn gửi hành khách',
                  hintText: 'Nhập dặn dò (vị trí đỗ, màu xe...)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Phát Thông Báo Đẩy'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final res = await ApiClient.instance.post('/api/trips/$_selectedTripId/notify-approaching', body: {
          'estimatedMinutes': selectedMins,
          'note': noteCtrl.text.trim(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text((res['message'] ?? 'Đã phát thông báo đẩy thành công!').toString()),
              backgroundColor: const Color(0xFF15803D),
            ),
          );
          // Phát luôn local notification trên máy tài xế
          NotificationService.instance.showBusApproachingNotification(
            routeName: (trip['routeName'] ?? trip['RouteName'] ?? 'Tuyến xe').toString(),
            plateNumber: (trip['plateNumber'] ?? trip['PlateNumber'] ?? '51B-288.99').toString(),
            driverName: 'Bác tài (Chính bạn)',
            etaMinutes: selectedMins,
            note: noteCtrl.text.trim(),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi phát thông báo: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
