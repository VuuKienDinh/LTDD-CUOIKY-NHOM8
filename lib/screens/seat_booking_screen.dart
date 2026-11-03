import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../theme/shadcn_theme.dart';
import 'vnpay_payment_screen.dart';

class SeatBookingScreen extends StatefulWidget {
  final Map<String, dynamic> tripSummary;
  final int? linkedBookingId;

  const SeatBookingScreen({super.key, required this.tripSummary, this.linkedBookingId});

  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends State<SeatBookingScreen> {
  Map<String, dynamic>? _tripDetail;
  List<Map<String, dynamic>> _seats = [];
  final Set<int> _selectedSeatIds = {};

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  // Hold state
  String? _holdToken;
  DateTime? _holdExpiresAt;
  Timer? _countdownTimer;
  Duration _remainingHold = Duration.zero;

  // Booking form controllers
  late TextEditingController _contactNameCtrl;
  late TextEditingController _contactPhoneCtrl;
  late TextEditingController _contactEmailCtrl;
  final Map<int, TextEditingController> _paxNameCtrls = {};
  final Map<int, TextEditingController> _paxPhoneCtrls = {};
  final Map<int, int?> _pickupStopIds = {};
  final Map<int, int?> _dropoffStopIds = {};
  final _promoCodeCtrl = TextEditingController();

  String _paymentMethod = 'VNPay';

  @override
  void initState() {
    super.initState();
    final user = ApiClient.instance.currentUser ?? {};
    _contactNameCtrl = TextEditingController(text: (user['fullName'] ?? user['FullName'] ?? '').toString());
    _contactPhoneCtrl = TextEditingController(text: (user['phone'] ?? user['Phone'] ?? '').toString());
    _contactEmailCtrl = TextEditingController(text: (user['email'] ?? user['Email'] ?? '').toString());
    _loadData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _contactEmailCtrl.dispose();
    _promoCodeCtrl.dispose();
    for (final c in _paxNameCtrls.values) {
      c.dispose();
    }
    for (final c in _paxPhoneCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _tripId => (widget.tripSummary['tripId'] ?? widget.tripSummary['TripId']) as int;

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApiClient.instance.get('/api/trips/$_tripId');
      final seats = await ApiClient.instance.get('/api/trips/$_tripId/seats');
      setState(() {
        _tripDetail = Map<String, dynamic>.from(detail as Map);
        _seats = (seats as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _pickupStops {
    final stops = (_tripDetail?['stops'] ?? _tripDetail?['Stops']) as List? ?? [];
    return stops
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) {
          final t = (s['stopType'] ?? s['StopType']).toString();
          return t == 'Pickup' || t == 'Both';
        })
        .toList();
  }

  List<Map<String, dynamic>> get _dropoffStops {
    final stops = (_tripDetail?['stops'] ?? _tripDetail?['Stops']) as List? ?? [];
    return stops
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) {
          final t = (s['stopType'] ?? s['StopType']).toString();
          return t == 'Dropoff' || t == 'Both';
        })
        .toList();
  }

  void _toggleSeat(Map<String, dynamic> seat) {
    if (_holdToken != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn đang giữ ghế. Hãy hủy giữ ghế nếu muốn đổi vị trí ghế.')),
      );
      return;
    }
    final status = (seat['seatStatus'] ?? seat['SeatStatus']).toString();
    if (status != 'Available') return;

    final seatId = (seat['tripSeatId'] ?? seat['TripSeatId']) as int;
    setState(() {
      if (_selectedSeatIds.contains(seatId)) {
        _selectedSeatIds.remove(seatId);
      } else {
        _selectedSeatIds.add(seatId);
        _paxNameCtrls.putIfAbsent(
          seatId,
          () => TextEditingController(text: _contactNameCtrl.text),
        );
        _paxPhoneCtrls.putIfAbsent(
          seatId,
          () => TextEditingController(text: _contactPhoneCtrl.text),
        );
        if (_pickupStops.isNotEmpty) {
          _pickupStopIds.putIfAbsent(
            seatId,
            () => (_pickupStops.first['routeStopId'] ?? _pickupStops.first['RouteStopId']) as int,
          );
        }
        if (_dropoffStops.isNotEmpty) {
          _dropoffStopIds.putIfAbsent(
            seatId,
            () => (_dropoffStops.first['routeStopId'] ?? _dropoffStops.first['RouteStopId']) as int,
          );
        }
      }
    });
  }

  Future<void> _holdSelectedSeats() async {
    if (_selectedSeatIds.isEmpty) return;
    if (!ApiClient.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập tài khoản Customer để giữ ghế và đặt vé (UC06)!'),
        ),
      );
      Navigator.pop(context);
      ApiClient.instance.logout();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.post('/api/seat-holds', body: {
        'tripId': _tripId,
        'tripSeatIds': _selectedSeatIds.toList(),
      });
      final token = (res['holdToken'] ?? res['HoldToken']).toString();
      final expStr = (res['holdExpiresAt'] ?? res['HoldExpiresAt']).toString();
      final exp = DateTime.parse(expStr).toUtc();

      setState(() {
        _holdToken = token;
        _holdExpiresAt = exp;
      });
      _startCountdown();
      await _loadData();
    } catch (e) {
      setState(() => _error = e.toString());
      await _loadData();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateRemaining();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (_holdExpiresAt == null) return;
    final diff = _holdExpiresAt!.difference(DateTime.now().toUtc());
    if (diff.isNegative) {
      _countdownTimer?.cancel();
      setState(() {
        _holdToken = null;
        _holdExpiresAt = null;
        _remainingHold = Duration.zero;
        _error = 'Phiên giữ ghế đã hết hạn trên máy chủ (AT05). Ghế đã được giải phóng.';
      });
      _loadData();
    } else {
      setState(() => _remainingHold = diff);
    }
  }

  Future<void> _releaseHold() async {
    if (_holdToken == null) return;
    final token = _holdToken!;
    _countdownTimer?.cancel();
    setState(() {
      _holdToken = null;
      _holdExpiresAt = null;
    });
    try {
      await ApiClient.instance.delete('/api/seat-holds/$token');
    } catch (_) {}
    await _loadData();
  }

  // AT04: Mô phỏng người thứ 2 cố tình giữ trùng ghế đang được giữ -> Server trả về 409 Conflict
  Future<void> _testConcurrentHoldConflict() async {
    if (_selectedSeatIds.isEmpty) return;
    try {
      await ApiClient.instance.post('/api/seat-holds', body: {
        'tripId': _tripId,
        'tripSeatIds': _selectedSeatIds.toList(),
      });
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Kiểm thử Chống Giữ Trùng Ghế (AT04)')),
            ],
          ),
          content: Text(
            'Khi có yêu cầu thứ 2 cố tình giữ cùng ghế đang được giữ/đặt, Transaction Serializable trên SQL Server lập tức từ chối với mã 409 Conflict:\n\n"$e"',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
          ],
        ),
      );
    }
  }

  double get _calculatedTotal {
    double sum = 0;
    for (final seatId in _selectedSeatIds) {
      final seat = _seats.firstWhere(
        (s) => (s['tripSeatId'] ?? s['TripSeatId']) == seatId,
        orElse: () => {},
      );
      if (seat.isNotEmpty) {
        sum += ((seat['currentPrice'] ?? seat['CurrentPrice'] ?? 0) as num).toDouble();
      }
      final pStopId = _pickupStopIds[seatId];
      final dStopId = _dropoffStopIds[seatId];
      for (final s in _pickupStops) {
        if ((s['routeStopId'] ?? s['RouteStopId']) == pStopId) {
          sum += ((s['surcharge'] ?? s['Surcharge'] ?? 0) as num).toDouble();
        }
      }
      for (final s in _dropoffStops) {
        if ((s['routeStopId'] ?? s['RouteStopId']) == dStopId) {
          sum += ((s['surcharge'] ?? s['Surcharge'] ?? 0) as num).toDouble();
        }
      }
    }
    final promo = _promoCodeCtrl.text.trim().toUpperCase();
    double discount = 0;
    if (promo == 'FUTA50K') {
      discount = 50000;
    } else if (promo == 'SINHVIEN30K') {
      discount = 30000;
    } else if (promo == 'GIAM10') {
      discount = (sum * 0.10).clamp(0, 60000);
    }
    return (sum - discount).clamp(0, double.infinity);
  }

  Future<void> _createBooking() async {
    if (_holdToken == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final passengers = _selectedSeatIds.map((seatId) {
        return {
          'tripSeatId': seatId,
          'passengerName': _paxNameCtrls[seatId]?.text.trim() ?? _contactNameCtrl.text.trim(),
          'passengerPhone': _paxPhoneCtrls[seatId]?.text.trim() ?? _contactPhoneCtrl.text.trim(),
          'pickupStopId': _pickupStopIds[seatId],
          'dropoffStopId': _dropoffStopIds[seatId],
        };
      }).toList();

      final res = await ApiClient.instance.post('/api/bookings', body: {
        'holdToken': _holdToken,
        'contactName': _contactNameCtrl.text.trim(),
        'contactPhone': _contactPhoneCtrl.text.trim(),
        'contactEmail': _contactEmailCtrl.text.trim(),
        'paymentMethod': _paymentMethod,
        'promoCode': _promoCodeCtrl.text.trim(),
        'linkedBookingId': widget.linkedBookingId,
        'passengers': passengers,
      });

      _countdownTimer?.cancel();
      if (!mounted) return;

      final method = (res['paymentMethod'] ?? res['PaymentMethod']).toString();
      if (method == 'VNPay') {
        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VnPayPaymentScreen(bookingRes: Map<String, dynamic>.from(res as Map)),
          ),
        );
        if (success == true && mounted) {
          Navigator.pop(context, true);
        }
      } else {
        await _showBookingSuccessDialog(
          title: 'Đặt vé COD thành công (AT08)!',
          subtitle:
              'Mã đơn: ${res['bookingCode'] ?? res['BookingCode']}\nTrạng thái Booking: Confirmed\nTrạng thái Payment: Unpaid (Thanh toán khi lên xe)\nVé điện tử QR đã được phát hành.',
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showBookingSuccessDialog({required String title, required String subtitle}) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(subtitle),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Xem vé điện tử QR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeName = (widget.tripSummary['routeName'] ?? widget.tripSummary['RouteName'] ?? '').toString();
    final companyName = (widget.tripSummary['companyName'] ?? widget.tripSummary['CompanyName'] ?? '').toString();

    return Scaffold(
      appBar: ShadcnAppBar(
        title: routeName,
        subtitle: companyName,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw, size: 18, color: ShadcnTheme.foreground),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (_error != null)
                  ShadcnAlert.destructive(title: 'Lỗi', message: _error!),
                if (_holdToken != null) _buildHoldBanner(),
                if (widget.linkedBookingId != null)
                  ShadcnAlert.info(
                    title: 'Vé chiều về khứ hồi (Mục 2.3)',
                    message: 'Liên kết với Booking #${widget.linkedBookingId}',
                  ),
                _buildLegend(),
                const SizedBox(height: 14),
                _buildTwoDeckSeatMap(),
                const SizedBox(height: 16),
                if (_selectedSeatIds.isNotEmpty && _holdToken == null)
                  Container(
                    height: 48,
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
                      ),
                      onPressed: _submitting ? null : _holdSelectedSeats,
                      icon: const Icon(LucideIcons.lock, size: 16),
                      label: Text(
                        'GIỮ ${_selectedSeatIds.length} GHẾ TRONG 10 PHÚT (AT04)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  ),
                if (_holdToken != null) _buildPassengerAndPaymentForm(),
              ],
            ),
    );
  }

  Widget _buildHoldBanner() {
    final mins = _remainingHold.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = _remainingHold.inSeconds.remainder(60).toString().padLeft(2, '0');
    return ShadcnCard(
      color: const Color(0xFFFFFBEB),
      borderColor: const Color(0xFFFDE68A),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.timer, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đang giữ ${_selectedSeatIds.length} ghế • Còn lại: $mins:$secs',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF92400E)),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  foregroundColor: ShadcnTheme.destructive,
                  side: const BorderSide(color: Color(0xFFFECACA)),
                ),
                onPressed: _releaseHold,
                child: const Text('Đổi ghế', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Mã giữ chỗ: $_holdToken (AT05)',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: _testConcurrentHoldConflict,
            child: const Text('Kiểm thử tranh chấp giữ chỗ (AT04)', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return ShadcnCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: ShadcnTheme.surface,
                  border: Border.all(color: ShadcnTheme.border, width: 1.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              const Text('Trống', style: TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: ShadcnTheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              const Text('Đang chọn', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              const Text('Đang giữ', style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E))),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: ShadcnTheme.muted,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              const Text('Đã đặt', style: TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTwoDeckSeatMap() {
    final deck1 = _seats.where((s) => (s['deck'] ?? s['Deck']) == 1).toList();
    final deck2 = _seats.where((s) => (s['deck'] ?? s['Deck']) == 2).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildDeckCard('TẦNG 1 (DÃY A)', deck1)),
        const SizedBox(width: 10),
        Expanded(child: _buildDeckCard('TẦNG 2 (DÃY B)', deck2)),
      ],
    );
  }

  Widget _buildDeckCard(String title, List<Map<String, dynamic>> deckSeats) {
    return ShadcnCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ShadcnTheme.muted,
              borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.airline_seat_recline_extra_rounded, size: 14, color: ShadcnTheme.foreground),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: ShadcnTheme.foreground, letterSpacing: -0.2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Bus Steering Wheel / Windshield Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(LucideIcons.compass, size: 16, color: ShadcnTheme.mutedForeground),
              Container(
                height: 1,
                width: 32,
                color: ShadcnTheme.border,
              ),
              const Icon(LucideIcons.doorOpen, size: 15, color: ShadcnTheme.mutedForeground),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.78,
            ),
            itemCount: deckSeats.length,
            itemBuilder: (ctx, i) {
              final s = deckSeats[i];
              final seatId = (s['tripSeatId'] ?? s['TripSeatId']) as int;
              final code = (s['seatCode'] ?? s['SeatCode']).toString();
              final status = (s['seatStatus'] ?? s['SeatStatus']).toString();
              final price = ((s['currentPrice'] ?? s['CurrentPrice'] ?? 0) as num).toDouble();
              final isSelected = _selectedSeatIds.contains(seatId);

              Color bg = ShadcnTheme.surface;
              Color fg = ShadcnTheme.foreground;
              Color border = ShadcnTheme.border;

              if (isSelected) {
                bg = ShadcnTheme.primary;
                fg = ShadcnTheme.primaryForeground;
                border = ShadcnTheme.primary;
              } else if (status == 'Booked') {
                bg = ShadcnTheme.muted;
                fg = const Color(0xFFA1A1AA);
                border = ShadcnTheme.border;
              } else if (status == 'Held') {
                bg = const Color(0xFFFEF3C7);
                fg = const Color(0xFF92400E);
                border = const Color(0xFFF59E0B);
              }

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _toggleSeat(s),
                  borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
                      borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                      boxShadow: isSelected ? ShadcnTheme.shadowSm : null,
                    ),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSelected ? LucideIcons.check : LucideIcons.armchair,
                              size: 15,
                              color: fg,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              code,
                              style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
                              maxLines: 1,
                            ),
                            Text(
                              '${(price / 1000).toStringAsFixed(0)}k',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.85)),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerAndPaymentForm() {
    final allowCod = (_tripDetail?['allowCod'] ?? _tripDetail?['AllowCod'] ?? true) == true;

    return ShadcnCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1. Thông tin người liên hệ đặt vé',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contactNameCtrl,
            decoration: const InputDecoration(labelText: 'Họ tên người đặt'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _contactPhoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _contactEmailCtrl,
                  decoration: const InputDecoration(labelText: 'Email nhận vé'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '2. Hành khách & Điểm đón/trả theo từng ghế (AT06, BR13)',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          ..._selectedSeatIds.map((seatId) {
            final seat = _seats.firstWhere((s) => (s['tripSeatId'] ?? s['TripSeatId']) == seatId);
            final seatCode = (seat['seatCode'] ?? seat['SeatCode']).toString();
            final seatPrice = ((seat['currentPrice'] ?? seat['CurrentPrice'] ?? 0) as num).toDouble();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ShadcnTheme.primary,
                          borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                        ),
                        child: Text(
                          seatCode,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: ShadcnTheme.primaryForeground, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${seatPrice.toStringAsFixed(0)} đ',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        onPressed: () async {
                          try {
                            final res = await ApiClient.instance.get('/api/auth/companions');
                            if (!mounted) return;
                            final comps = res as List? ?? [];
                            if (comps.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Danh bạ hành khách thường đi đang trống.')),
                              );
                              return;
                            }
                            await showModalBottomSheet(
                              context: context,
                              builder: (ctx) => ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(16),
                                children: [
                                  const Text('Chọn nhanh từ Danh bạ:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  const Divider(height: 16),
                                  ...comps.map((c) {
                                    final cm = Map<String, dynamic>.from(c as Map);
                                    final fn = (cm['fullName'] ?? cm['FullName']).toString();
                                    final ph = (cm['phone'] ?? cm['Phone']).toString();
                                    return ListTile(
                                      leading: const Icon(LucideIcons.user, color: ShadcnTheme.primary),
                                      title: Text(fn, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text('$ph (${cm['relationship'] ?? cm['Relationship']})'),
                                      onTap: () {
                                        setState(() {
                                          _paxNameCtrls[seatId]?.text = fn;
                                          _paxPhoneCtrls[seatId]?.text = ph;
                                        });
                                        Navigator.pop(ctx);
                                      },
                                    );
                                  }),
                                ],
                              ),
                            );
                          } catch (_) {}
                        },
                        icon: const Icon(LucideIcons.contact, size: 14),
                        label: const Text('Danh bạ', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _paxNameCtrls[seatId],
                          decoration: const InputDecoration(labelText: 'Tên hành khách', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _paxPhoneCtrls[seatId],
                          decoration: const InputDecoration(labelText: 'SĐT hành khách', isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_pickupStops.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: _pickupStopIds[seatId],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Điểm đón', isDense: true),
                      items: _pickupStops.map((s) {
                        final id = (s['routeStopId'] ?? s['RouteStopId']) as int;
                        final name = (s['stopName'] ?? s['StopName']).toString();
                        final sur = ((s['surcharge'] ?? s['Surcharge'] ?? 0) as num).toDouble();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            sur > 0 ? '$name (+${sur.toStringAsFixed(0)}đ)' : name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _pickupStopIds[seatId] = v),
                    ),
                  const SizedBox(height: 8),
                  if (_dropoffStops.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: _dropoffStopIds[seatId],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Điểm trả', isDense: true),
                      items: _dropoffStops.map((s) {
                        final id = (s['routeStopId'] ?? s['RouteStopId']) as int;
                        final name = (s['stopName'] ?? s['StopName']).toString();
                        final sur = ((s['surcharge'] ?? s['Surcharge'] ?? 0) as num).toDouble();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            sur > 0 ? '$name (+${sur.toStringAsFixed(0)}đ)' : name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _dropoffStopIds[seatId] = v),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          TextField(
            controller: _promoCodeCtrl,
            decoration: InputDecoration(
              labelText: 'Mã khuyến mãi (VD: FUTA50K, SINHVIEN30K, GIAM10)',
              isDense: true,
              suffixIcon: PopupMenuButton<String>(
                icon: const Icon(LucideIcons.tag, size: 16),
                onSelected: (v) => setState(() => _promoCodeCtrl.text = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'FUTA50K', child: Text('FUTA50K - Giảm 50.000đ')),
                  PopupMenuItem(value: 'SINHVIEN30K', child: Text('SINHVIEN30K - Giảm 30.000đ')),
                  PopupMenuItem(value: 'GIAM10', child: Text('GIAM10 - Giảm 10% (Tối đa 60k)')),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text(
            '3. Phương thức thanh toán (FR15)',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            value: 'VNPay',
            groupValue: _paymentMethod,
            onChanged: (v) => setState(() => _paymentMethod = v!),
            title: const Text('Thanh toán trực tuyến VNPay Sandbox', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            subtitle: const Text('Xác thực chữ ký HMAC-SHA512 & IPN Idempotent (AT07)', style: TextStyle(fontSize: 11.5)),
          ),
          RadioListTile<String>(
            value: 'COD',
            groupValue: _paymentMethod,
            onChanged: allowCod ? (v) => setState(() => _paymentMethod = v!) : null,
            title: const Text('Thanh toán khi lên xe (COD)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            subtitle: Text(
              allowCod
                  ? 'Booking Confirmed nhưng Payment giữ trạng thái Unpaid (AT08)'
                  : 'Nhà xe này không hỗ trợ COD',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng thanh toán:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              Text(
                '${_calculatedTotal.toStringAsFixed(0)} đ',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ShadcnTheme.accentOrange, letterSpacing: -0.4),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 48,
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
              ),
              onPressed: _submitting ? null : _createBooking,
              icon: const Icon(LucideIcons.check, size: 18),
              label: Text(
                _paymentMethod == 'VNPay'
                    ? 'XÁC NHẬN & THANH TOÁN VNPAY'
                    : 'XÁC NHẬN ĐẶT VÉ COD',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

