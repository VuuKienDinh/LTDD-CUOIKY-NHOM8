import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../theme/shadcn_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginEmailCtrl = TextEditingController(text: 'customer@gmail.vn');
  final _loginPassCtrl = TextEditingController(text: '123456');

  final _regNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _obscureLoginPass = true;
  bool _obscureRegPass = true;

  final List<Map<String, dynamic>> _demoAccounts = const [
    {
      'role': 'Hành khách',
      'badge': 'Customer',
      'email': 'customer@gmail.vn',
      'pass': '123456',
      'desc': 'Đặt vé, chọn ghế 2 tầng, QR Code, VNPay/COD, GPS trực tiếp',
      'icon': LucideIcons.user,
      'badgeColor': Color(0xFF2563EB),
    },
    {
      'role': 'Nhà xe Phương Trang',
      'badge': 'FUTA Bus',
      'email': 'operator@phuongtrang.vn',
      'pass': '123456',
      'desc': 'Quản lý xe, lập lịch chạy, bán vé POS, ký gửi hàng, sổ chi phí',
      'icon': LucideIcons.bus,
      'badgeColor': Color(0xFFEA580C),
    },
    {
      'role': 'Tài xế FUTA',
      'badge': 'Driver',
      'email': 'driver@phuongtrang.vn',
      'pass': '123456',
      'desc': 'Quét QR Check-in, phát GPS 10s, kiểm tra an toàn xuất bến',
      'icon': LucideIcons.armchair,
      'badgeColor': Color(0xFF0D9488),
    },
    {
      'role': 'Nhân viên Bến xe',
      'badge': 'Staff',
      'email': 'staff@phuongtrang.vn',
      'pass': '123456',
      'desc': 'Thu tiền mặt COD, xuất vé nhanh POS, điều phối xe trung chuyển',
      'icon': LucideIcons.contact,
      'badgeColor': Color(0xFF7C3AED),
    },
    {
      'role': 'Nhà xe Thành Bưởi',
      'badge': 'Multi-Tenant',
      'email': 'operator@thanhbuoi.vn',
      'pass': '123456',
      'desc': 'Kiểm thử cách ly dữ liệu độc lập giữa các nhà xe (AT02)',
      'icon': LucideIcons.building2,
      'badgeColor': Color(0xFF4338CA),
    },
    {
      'role': 'Quản trị Hệ thống',
      'badge': 'Admin',
      'email': 'admin@busticket.vn',
      'pass': '123456',
      'desc': 'Duyệt nhà xe, Voucher, hoàn tiền, quyết toán hoa hồng 6%, CSV',
      'icon': LucideIcons.shieldCheck,
      'badgeColor': Color(0xFFE11D48),
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin([String? email, String? password]) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.post('/api/auth/login', body: {
        'email': email ?? _loginEmailCtrl.text.trim(),
        'password': password ?? _loginPassCtrl.text,
      });
      final token = (res['accessToken'] ?? res['AccessToken']).toString();
      final user = Map<String, dynamic>.from(res['user'] ?? res['User']);
      ApiClient.instance.setSession(token, user);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doRegister() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.post('/api/auth/register', body: {
        'fullName': _regNameCtrl.text.trim(),
        'email': _regEmailCtrl.text.trim(),
        'phone': _regPhoneCtrl.text.trim(),
        'password': _regPassCtrl.text,
      });
      final token = (res['accessToken'] ?? res['AccessToken']).toString();
      final user = Map<String, dynamic>.from(res['user'] ?? res['User']);
      ApiClient.instance.setSession(token, user);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showServerUrlDialog() {
    final ctrl = TextEditingController(text: ApiClient.instance.baseUrl);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        decoration: const BoxDecoration(
          color: ShadcnTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(ShadcnTheme.radiusXl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.server, color: ShadcnTheme.foreground, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cấu hình kết nối API Server',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ShadcnTheme.foreground, letterSpacing: -0.3),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(LucideIcons.x, size: 18, color: ShadcnTheme.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://172.16.2.207:5284',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Chọn nhanh IP mạng:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(LucideIcons.usb, size: 14),
                  label: const Text('Cáp USB (127.0.0.1)'),
                  onPressed: () => ctrl.text = 'http://127.0.0.1:5284',
                ),
                ActionChip(
                  avatar: const Icon(LucideIcons.wifi, size: 14),
                  label: const Text('Wi-Fi LAN (172.16.2.207)'),
                  onPressed: () => ctrl.text = 'http://172.16.2.207:5284',
                ),
                ActionChip(
                  avatar: const Icon(LucideIcons.smartphone, size: 14),
                  label: const Text('Máy ảo Android (10.0.2.2)'),
                  onPressed: () => ctrl.text = 'http://10.0.2.2:5284',
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                ApiClient.instance.setBaseUrl(ctrl.text);
                Navigator.pop(ctx);
                setState(() => _error = null);
              },
              child: const Text('Lưu cấu hình'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: ShadcnTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Frosted Glass Ocean App Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: const BoxDecoration(
                color: ShadcnTheme.surfaceGlass,
                border: Border(bottom: BorderSide(color: ShadcnTheme.glassBorder, width: 1.2)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A0369A1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: ShadcnTheme.oceanGradient,
                          borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x330284C7),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.bus,
                          color: ShadcnTheme.primaryForeground,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BusTicketBooking',
                              style: TextStyle(
                                fontSize: 17.5,
                                fontWeight: FontWeight.w800,
                                color: ShadcnTheme.foreground,
                                letterSpacing: -0.4,
                              ),
                            ),
                            Text(
                              'Hệ thống Đặt vé & Điều hành Xe khách Liên tỉnh',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: ShadcnTheme.primaryDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF0F9FF),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                        ),
                        onPressed: _showServerUrlDialog,
                        icon: const Icon(LucideIcons.slidersHorizontal, size: 14, color: ShadcnTheme.primaryDark),
                        label: Text(
                          ApiClient.instance.baseUrl.replaceFirst('http://', ''),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // shadcn Segmented Tabs
                  ShadcnTabs(
                    controller: _tabController,
                    tabs: const ['Vai trò mẫu', 'Đăng nhập', 'Đăng ký'],
                    icons: const [LucideIcons.zap, LucideIcons.logIn, LucideIcons.userPlus],
                  ),
                ],
              ),
            ),

            // Tab View
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDemoRolesTab(),
                  _buildManualLoginTab(bottomInset),
                  _buildRegisterTab(bottomInset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: 1-Tap Role Showcase Cards (shadcn style)
  Widget _buildDemoRolesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_error != null) _buildErrorBanner(),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tài khoản trải nghiệm nhanh (1 chạm)',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ShadcnTheme.foreground, letterSpacing: -0.2),
            ),
            ShadcnBadge.secondary('6 vai trò'),
          ],
        ),
        const SizedBox(height: 10),

        // Grid of 6 role cards in shadcn style
        ..._demoAccounts.map((acc) {
          final badgeColor = acc['badgeColor'] as Color;

          return ShadcnCard(
            padding: const EdgeInsets.all(14),
            onTap: _loading
                ? null
                : () {
                    _loginEmailCtrl.text = acc['email'] as String;
                    _loginPassCtrl.text = acc['pass'] as String;
                    _doLogin(acc['email'] as String, acc['pass'] as String);
                  },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ShadcnTheme.secondary,
                    borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                    border: Border.all(color: ShadcnTheme.border),
                  ),
                  child: Icon(acc['icon'] as IconData, color: ShadcnTheme.foreground, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            acc['role'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ShadcnTheme.foreground, letterSpacing: -0.2),
                          ),
                          const SizedBox(width: 6),
                          ShadcnBadge.outline(acc['badge'] as String, color: badgeColor),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        acc['desc'] as String,
                        style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground, height: 1.25),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronRight, size: 14, color: ShadcnTheme.mutedForeground),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => ApiClient.instance.enterGuestMode(),
            icon: const Icon(LucideIcons.compass, size: 16, color: ShadcnTheme.mutedForeground),
            label: const Text(
              'Xem chuyến xe & tra cứu dưới danh nghĩa Khách vãng lai',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground),
            ),
          ),
        ),
      ],
    );
  }

  // TAB 2: Manual Login (shadcn style)
  Widget _buildManualLoginTab(double bottomInset) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 32),
      children: [
        if (_error != null) _buildErrorBanner(),

        ShadcnCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Đăng nhập tài khoản',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ShadcnTheme.foreground, letterSpacing: -0.3),
              ),
              const SizedBox(height: 4),
              const Text(
                'Nhập email và mật khẩu của bạn để truy cập hệ thống',
                style: TextStyle(fontSize: 12.5, color: ShadcnTheme.mutedForeground),
              ),
              const SizedBox(height: 18),

              TextField(
                controller: _loginEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  labelText: 'Email tài khoản',
                  hintText: 'name@example.com',
                  prefixIcon: Icon(LucideIcons.mail, size: 16, color: ShadcnTheme.mutedForeground),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _loginPassCtrl,
                obscureText: _obscureLoginPass,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(LucideIcons.lock, size: 16, color: ShadcnTheme.mutedForeground),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureLoginPass ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                      color: ShadcnTheme.mutedForeground,
                    ),
                    onPressed: () => setState(() => _obscureLoginPass = !_obscureLoginPass),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              FilledButton(
                onPressed: _loading ? null : () => _doLogin(),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ShadcnTheme.primaryForeground),
                      )
                    : const Text('Đăng nhập'),
              ),
              const SizedBox(height: 10),

              OutlinedButton(
                onPressed: () => ApiClient.instance.enterGuestMode(),
                child: const Text('Tiếp tục với tư cách Khách vãng lai'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // TAB 3: Register (shadcn style)
  Widget _buildRegisterTab(double bottomInset) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 32),
      children: [
        if (_error != null) _buildErrorBanner(),

        ShadcnCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tạo tài khoản mới',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ShadcnTheme.foreground, letterSpacing: -0.3),
              ),
              const SizedBox(height: 4),
              const Text(
                'Đăng ký tài khoản Hành khách để đặt vé và nhận ưu đãi thành viên',
                style: TextStyle(fontSize: 12.5, color: ShadcnTheme.mutedForeground),
              ),
              const SizedBox(height: 18),

              TextField(
                controller: _regNameCtrl,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  prefixIcon: Icon(LucideIcons.user, size: 16, color: ShadcnTheme.mutedForeground),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _regEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(LucideIcons.mail, size: 16, color: ShadcnTheme.mutedForeground),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _regPhoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  prefixIcon: Icon(LucideIcons.phone, size: 16, color: ShadcnTheme.mutedForeground),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _regPassCtrl,
                obscureText: _obscureRegPass,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu (>= 6 ký tự)',
                  prefixIcon: const Icon(LucideIcons.lock, size: 16, color: ShadcnTheme.mutedForeground),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureRegPass ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                      color: ShadcnTheme.mutedForeground,
                    ),
                    onPressed: () => setState(() => _obscureRegPass = !_obscureRegPass),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              FilledButton(
                onPressed: _loading ? null : _doRegister,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ShadcnTheme.primaryForeground),
                      )
                    : const Text('Tạo tài khoản'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShadcnTheme.destructiveBg,
        borderRadius: BorderRadius.circular(ShadcnTheme.radius),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.alertTriangle, color: ShadcnTheme.destructive, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lỗi kết nối API Server',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF991B1B), fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C), height: 1.25),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _showServerUrlDialog,
            icon: const Icon(LucideIcons.wrench, color: ShadcnTheme.destructive, size: 17),
            tooltip: 'Đổi IP máy chủ',
          ),
        ],
      ),
    );
  }
}
