import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../theme/shadcn_theme.dart';

class VnPayPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> bookingRes;

  const VnPayPaymentScreen({super.key, required this.bookingRes});

  @override
  State<VnPayPaymentScreen> createState() => _VnPayPaymentScreenState();
}

class _VnPayPaymentScreenState extends State<VnPayPaymentScreen> {
  late String _bookingCode;
  late double _totalAmount;
  late String _vnpUrl;
  late String _sig;

  int _currentStep = 0; // 0: Nhập thẻ NCB, 1: Nhập OTP
  bool _loading = false;
  String? _error;

  // Form controllers
  final _cardNumberCtrl = TextEditingController(text: '9704198526191432198');
  final _cardHolderCtrl = TextEditingController(text: 'NGUYEN VAN A');
  final _issueDateCtrl = TextEditingController(text: '07/15');
  final _otpCtrl = TextEditingController(text: '123456');

  int _countdownSeconds = 120;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _bookingCode = (widget.bookingRes['bookingCode'] ?? widget.bookingRes['BookingCode'] ?? '').toString();
    _totalAmount = ((widget.bookingRes['totalAmount'] ?? widget.bookingRes['TotalAmount'] ?? 0) as num).toDouble();
    _vnpUrl = (widget.bookingRes['vnPayPaymentUrl'] ?? widget.bookingRes['VnPayPaymentUrl'] ?? '').toString();
    _sig = (widget.bookingRes['vnPaySignature'] ?? widget.bookingRes['VnPaySignature'] ?? '').toString();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cardNumberCtrl.dispose();
    _cardHolderCtrl.dispose();
    _issueDateCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownSeconds = 120;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdownSeconds > 0) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _fillNcbTestCard() {
    setState(() {
      _cardNumberCtrl.text = '9704198526191432198';
      _cardHolderCtrl.text = 'NGUYEN VAN A';
      _issueDateCtrl.text = '07/15';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã điền tự động thẻ test NCB Sandbox!'), duration: Duration(seconds: 1)),
    );
  }

  void _goToOtpStep() {
    if (_cardNumberCtrl.text.replaceAll(' ', '').length < 16) {
      setState(() => _error = 'Vui lòng nhập đủ 16 - 19 số thẻ');
      return;
    }
    if (_cardHolderCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập họ tên chủ thẻ');
      return;
    }
    if (_issueDateCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập ngày phát hành (MM/YY)');
      return;
    }

    setState(() {
      _error = null;
      _currentStep = 1;
    });
    _startCountdown();
  }

  Future<void> _submitPayment() async {
    if (_otpCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập mã xác thực OTP');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiClient.instance.post('/api/payments/vnpay/ipn', body: {
        'bookingCode': _bookingCode,
        'amount': _totalAmount,
        'responseCode': '00',
        'transactionNo': 'VNP-${DateTime.now().millisecondsSinceEpoch}',
        'signature': _sig,
      });

      if (!mounted) return;

      // Show Payment Success Dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusLg)),
          title: const Row(
            children: [
              Icon(LucideIcons.checkCircle2, color: Color(0xFF16A34A), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('Thanh Toán Thành Công!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mã đơn: $_bookingCode',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Số tiền đã thanh toán: ${ShadcnTheme.formatMoney(_totalAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0369A1), fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ngân hàng: NCB (Ngân hàng Quốc Dân)\nCổng thanh toán: VNPAY Sandbox',
                style: TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground, height: 1.3),
              ),
              const Divider(height: 20),
              const Text(
                'Vé điện tử QR đã được phát hành và lưu vào mục "Vé của tôi".',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context, true); // Close VNPay screen with success=true
              },
              child: const Text('Xem Vé Điện Tử QR', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Thanh toán thất bại: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelPayment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy thanh toán?'),
        content: const Text('Giao dịch sẽ được ghi nhận là Hủy (ResponseCode 24). Bạn có chắc chắn muốn hủy?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ShadcnTheme.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý hủy'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiClient.instance.post('/api/payments/vnpay/ipn', body: {
          'bookingCode': _bookingCode,
          'amount': _totalAmount,
          'responseCode': '24',
          'transactionNo': 'VNP-CANCEL-$_bookingCode',
          'signature': _sig,
        });
      } catch (_) {}
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF005BAA), // Official VNPay Deep Blue
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'VNPAY',
                style: TextStyle(color: Color(0xFF005BAA), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'CỔNG THANH TOÁN',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _cancelPayment,
            icon: const Icon(LucideIcons.x, size: 20),
            tooltip: 'Hủy giao dịch',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Order summary banner
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Đơn vị chấp nhận thanh toán:',
                          style: TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                        ),
                        const Text(
                          'BUS TICKET BOOKING SYSTEM',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã đơn: $_bookingCode',
                          style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Số tiền thanh toán:',
                        style: TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                      ),
                      Text(
                        ShadcnTheme.formatMoney(_totalAmount),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFE11D48),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            if (_error != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertCircle, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                    ),
                  ],
                ),
              ),

            // Main payment content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (_currentStep == 0) _buildCardInputStep() else _buildOtpStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // BƯỚC 1: Nhập thông tin thẻ ATM NCB
  Widget _buildCardInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bank Selection Badge
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ShadcnTheme.radius),
            border: Border.all(color: const Color(0xFF005BAA), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Center(
                  child: Text(
                    'NCB',
                    style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF005BAA), fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ngân hàng Quốc Dân (NCB)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      'Thẻ ATM nội địa • Môi trường Sandbox',
                      style: TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.checkCircle, color: Color(0xFF005BAA), size: 20),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Quick Fill Card Test Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(ShadcnTheme.radius),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.sparkles, size: 15, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Thẻ Test Mẫu VNPay Sandbox (NCB)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF15803D)),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: _fillNcbTestCard,
                    icon: const Icon(LucideIcons.zap, size: 12, color: Color(0xFF16A34A)),
                    label: const Text('Điền mẫu', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Số thẻ: 9704 1985 2619 1432 198 • Tên: NGUYEN VAN A • Ngày: 07/15 • OTP: 123456',
                style: TextStyle(fontSize: 11, color: Color(0xFF166534), fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Form Fields
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ShadcnTheme.radius),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'THÔNG TIN THẺ NỘI ĐỊA',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF005BAA), letterSpacing: 0.5),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _cardNumberCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 1),
                decoration: const InputDecoration(
                  labelText: 'Số thẻ ngân hàng',
                  hintText: '9704 1985 2619 1432 198',
                  prefixIcon: Icon(LucideIcons.creditCard, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _cardHolderCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Tên in trên thẻ (không dấu)',
                  hintText: 'NGUYEN VAN A',
                  prefixIcon: Icon(LucideIcons.user, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _issueDateCtrl,
                keyboardType: TextInputType.datetime,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Ngày phát hành (MM/YY)',
                  hintText: '07/15',
                  prefixIcon: Icon(LucideIcons.calendar, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAA),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _goToOtpStep,
                child: const Text('TIẾP TỤC XÁC THỰC OTP', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
        if (_vnpUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _vnpUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép link Cổng thanh toán VNPay! Bạn có thể dán vào trình duyệt web.')),
              );
            },
            icon: const Icon(LucideIcons.externalLink, size: 14, color: Color(0xFF005BAA)),
            label: const Text('Sao chép Link Web Cổng VNPay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF005BAA))),
          ),
        ],
      ],
    );
  }

  // BƯỚC 2: Nhập mã OTP xác thực
  Widget _buildOtpStep() {
    final mins = (_countdownSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_countdownSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ShadcnTheme.radius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(LucideIcons.arrowLeft, size: 18, color: Color(0xFF005BAA)),
                tooltip: 'Quay lại sửa thông tin thẻ',
              ),
              const Expanded(
                child: Text(
                  'XÁC THỰC MÃ OTP',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF005BAA), letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 6),

          Text(
            'Mã OTP 6 số đã được gửi đến SĐT đăng ký chủ thẻ NCB.\n(Môi trường Sandbox mã cố định: 123456)',
            style: const TextStyle(fontSize: 12.5, color: ShadcnTheme.mutedForeground, height: 1.35),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 8, color: Color(0xFF005BAA)),
            decoration: const InputDecoration(
              labelText: 'MÃ XÁC THỰC OTP',
              hintText: '123456',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hiệu lực còn lại: $mins:$secs',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _countdownSeconds < 30 ? const Color(0xFFDC2626) : const Color(0xFF005BAA),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _otpCtrl.text = '123456'),
                child: const Text('⚡ Điền OTP 123456', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005BAA),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _loading ? null : _submitPayment,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('XÁC NHẬN THANH TOÁN', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 10),

          OutlinedButton(
            onPressed: _cancelPayment,
            child: const Text('Hủy giao dịch', style: TextStyle(color: ShadcnTheme.destructive)),
          ),
        ],
      ),
    );
  }
}
