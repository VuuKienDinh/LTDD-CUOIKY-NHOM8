import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../theme/shadcn_theme.dart';

class AdminAndReportsView extends StatefulWidget {
  const AdminAndReportsView({super.key});

  @override
  State<AdminAndReportsView> createState() => _AdminAndReportsViewState();
}

class _AdminAndReportsViewState extends State<AdminAndReportsView> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _refunds = [];
  List<Map<String, dynamic>> _auditLogs = [];
  int? _filterCompanyId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final q = _filterCompanyId != null ? {'companyId': _filterCompanyId.toString()} : null;
      final rep = await ApiClient.instance.get('/api/reports/summary', query: q);
      final comps = await ApiClient.instance.get('/api/admin/companies');
      final usrs = await ApiClient.instance.get('/api/admin/users');
      final refs = await ApiClient.instance.get('/api/admin/refunds');
      final logs = await ApiClient.instance.get('/api/admin/audit-logs');

      if (mounted) {
        setState(() {
          _report = Map<String, dynamic>.from(rep as Map);
          _companies = (comps as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _users = (usrs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _refunds = (refs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _auditLogs = (logs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
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

  Future<void> _updateCompanyStatus(int companyId, String status) async {
    try {
      final res = await ApiClient.instance.post('/api/admin/companies/$companyId/status', body: {
        'status': status,
        'reason': 'Quản trị viên nền tảng xét duyệt hồ sơ pháp lý',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã cập nhật').toString())),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleUserActive(int userId) async {
    try {
      final res = await ApiClient.instance.post('/api/admin/users/$userId/toggle-active');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã cập nhật').toString())),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resetUserNoShow(int userId) async {
    try {
      final res = await ApiClient.instance.post('/api/admin/users/$userId/reset-noshow');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã đặt lại No-show').toString())),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAddProvinceDialog() async {
    final nameCtrl = TextEditingController(text: 'Quy Nhơn (Bình Định)');
    final codeCtrl = TextEditingController(text: 'QNH');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Tỉnh / Thành phố mới (Bảng Provinces)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên Tỉnh / Thành phố', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Mã viết tắt (VD: QNH, HUE)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/admin/provinces', body: {
                  'name': nameCtrl.text.trim(),
                  'code': codeCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã thêm tỉnh/thành').toString())),
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
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _broadcastNotificationDialog() async {
    final titleCtrl = TextEditingController(text: 'Ưu đãi đặt vé dịp Lễ / Cuối tuần');
    final contentCtrl = TextEditingController(text: 'Đặt vé trực tuyến trên BusTicketBooking để giữ chỗ 10 phút và nhận vé QR nhanh chóng!');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gửi thông báo toàn hệ thống (UC29, FR21)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Tiêu đề thông báo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Nội dung thông báo', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/admin/notifications/broadcast', body: {
                  'title': titleCtrl.text.trim(),
                  'content': contentCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã gửi thông báo').toString())),
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
            child: const Text('Phát thông báo'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeRefund(int refundId) async {
    try {
      final res = await ApiClient.instance.post('/api/admin/refunds/$refundId/complete');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã hoàn tiền').toString())),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAcceptanceChecklistDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/admin/acceptance-criteria');
      if (!mounted) return;
      final list = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Bảng Nghiệm Thu AT01 – AT12 (Mục 18)')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final item = list[i];
                final code = (item['code'] ?? item['Code']).toString();
                final title = (item['title'] ?? item['Title']).toString();
                final ev = (item['evidence'] ?? item['Evidence']).toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.green.shade50,
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      child: Text(code, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(ev, style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              },
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

  // Mở rộng nâng cao: Quản lý chiến dịch Khuyến mãi / Voucher động (Promotions)
  Future<void> _showPromotionsDialog() async {
    try {
      var res = await ApiClient.instance.get('/api/admin/promotions');
      if (!mounted) return;
      var promos = res as List? ?? [];

      final codeCtrl = TextEditingController(text: 'TET2026');
      final titleCtrl = TextEditingController(text: 'Lì xì đầu xuân giảm 40,000đ');
      final valCtrl = TextEditingController(text: '40000');
      String discountType = 'Fixed';

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.local_offer, color: Colors.deepOrange),
                SizedBox(width: 8),
                Expanded(child: Text('Quản lý Chiến dịch Voucher (Promotions)', style: TextStyle(fontSize: 15))),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...promos.map((p) {
                      final pm = Map<String, dynamic>.from(p as Map);
                      final code = (pm['code'] ?? pm['Code']).toString();
                      final title = (pm['title'] ?? pm['Title']).toString();
                      final used = pm['usedCount'] ?? pm['UsedCount'] ?? 0;
                      final limit = pm['usageLimit'] ?? pm['UsageLimit'] ?? 100;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: Colors.orange.shade50,
                        child: ListTile(
                          dense: true,
                          leading: Chip(
                            label: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            backgroundColor: Colors.orange.shade200,
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                          subtitle: Text('Đã dùng: $used/$limit lượt • ĐH tối thiểu: ${((pm['minOrderAmount'] ?? pm['MinOrderAmount'] ?? 0) as num).toStringAsFixed(0)}đ'),
                        ),
                      );
                    }),
                    const Divider(height: 20),
                    const Text('Tạo mã Voucher khuyến mãi mới:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(labelText: 'Mã Code', isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: discountType,
                            decoration: const InputDecoration(labelText: 'Loại giảm', isDense: true, border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Fixed', child: Text('Giảm tiền (đ)')),
                              DropdownMenuItem(value: 'Percent', child: Text('Giảm %')),
                            ],
                            onChanged: (v) => setDialogState(() => discountType = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Tên chương trình ưu đãi', isDense: true, border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: valCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Giá trị giảm (VNĐ hoặc %)', isDense: true, border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
              FilledButton.icon(
                onPressed: () async {
                  await ApiClient.instance.post('/api/admin/promotions', body: {
                    'code': codeCtrl.text.trim().toUpperCase(),
                    'title': titleCtrl.text.trim(),
                    'discountType': discountType,
                    'discountValue': double.tryParse(valCtrl.text) ?? 40000,
                    'minOrderAmount': 150000,
                    'usageLimit': 200,
                  });
                  final refreshed = await ApiClient.instance.get('/api/admin/promotions');
                  setDialogState(() => promos = refreshed as List? ?? []);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Phát hành Voucher'),
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

  // Mở rộng nâng cao: Xuất báo cáo đối soát tài chính định dạng CSV (Export CSV)
  Future<void> _exportCsvDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/admin/reports/export-csv');
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final fileName = (data['fileName'] ?? data['FileName'] ?? 'DoiSoat.csv').toString();
      final csvContent = (data['csvContent'] ?? data['CsvContent'] ?? '').toString();
      final totalRows = data['totalRows'] ?? data['TotalRows'] ?? 0;

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Xuất File CSV Đối Soát ($fileName)', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tổng số dòng bản ghi đối soát: $totalRows đơn đặt vé', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  height: 220,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csvContent,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csvContent));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã sao chép nội dung CSV ($fileName) vào bộ nhớ tạm!')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Sao chép CSV'),
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

  // Đợt 2 - Tính năng #8: Quản lý Hoa hồng sàn (6%) & Quyết toán công nợ Nhà xe (Platform Commission & Payout Settlement)
  Future<void> _showPlatformSettlementsDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/admin/settlements');
      if (!mounted) return;
      final list = res as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.account_balance, color: Color(0xFF0D47A1)),
              SizedBox(width: 8),
              Expanded(child: Text('Quyết toán Hoa hồng Sàn (6%) & Công nợ Nhà xe', style: TextStyle(fontSize: 14.5))),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: list.map((item) {
                  final m = Map<String, dynamic>.from(item as Map);
                  final cid = (m['companyId'] ?? m['CompanyId']) as int;
                  final name = (m['name'] ?? m['Name']).toString();
                  final vnpay = ((m['vnPayOnlineGross'] ?? m['VnPayOnlineGross'] ?? 0) as num).toDouble();
                  final cod = ((m['codCollectedByCompany'] ?? m['CodCollectedByCompany'] ?? 0) as num).toDouble();
                  final cargo = ((m['cargoRevenue'] ?? m['CargoRevenue'] ?? 0) as num).toDouble();
                  final comm = ((m['platformCommissionFee'] ?? m['PlatformCommissionFee'] ?? 0) as num).toDouble();
                  final payout = ((m['netPayoutToCompany'] ?? m['NetPayoutToCompany'] ?? 0) as num).toDouble();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0D47A1))),
                          const SizedBox(height: 4),
                          Text('• Sàn thu hộ Online (VNPay): ${vnpay.toStringAsFixed(0)} đ', style: const TextStyle(fontSize: 12)),
                          Text('• Nhà xe tự thu tiền mặt (COD + POS): ${cod.toStringAsFixed(0)} đ', style: const TextStyle(fontSize: 12)),
                          Text('• Cước hàng hóa ký gửi: ${cargo.toStringAsFixed(0)} đ', style: const TextStyle(fontSize: 12)),
                          Text('• Phí hoa hồng nền tảng (6%): -${comm.toStringAsFixed(0)} đ', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                          const Divider(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Thực chuyển trả Nhà xe: ${payout.toStringAsFixed(0)} đ',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.green),
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final pRes = await ApiClient.instance.post('/api/admin/settlements/$cid/payout');
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _loadAll();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text((pRes['message'] ?? 'Đã quyết toán!').toString())),
                                    );
                                  }
                                },
                                child: const Text('Tất toán', style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
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
                color: Color(0x0A0369A1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorWeight: 3,
                indicatorColor: ShadcnTheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: ShadcnTheme.primaryDark,
                unselectedLabelColor: ShadcnTheme.mutedForeground,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: -0.2),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, letterSpacing: -0.2),
                tabs: [
                  const Tab(icon: Icon(LucideIcons.barChart3, size: 17), text: 'Báo cáo & Tài chính'),
                  Tab(icon: const Icon(LucideIcons.building2, size: 17), text: 'Duyệt Nhà xe (${_companies.length})'),
                  Tab(icon: const Icon(LucideIcons.users, size: 17), text: 'Tài khoản (${_users.length})'),
                  Tab(icon: const Icon(LucideIcons.receipt, size: 17), text: 'Hoàn tiền & Audit (${_refunds.length})'),
                ],
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildReportTab(),
              _buildCompaniesTab(),
              _buildUsersTab(),
              _buildRefundsAndAuditTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportTab() {
    final fin = Map<String, dynamic>.from((_report?['financials'] ?? _report?['Financials'] ?? {}) as Map);
    final bm = Map<String, dynamic>.from((_report?['bookingMetrics'] ?? _report?['BookingMetrics'] ?? {}) as Map);
    final tm = Map<String, dynamic>.from((_report?['tripMetrics'] ?? _report?['TripMetrics'] ?? {}) as Map);
    final isAdmin = ApiClient.instance.roles.contains('Admin');

    double val(Map<String, dynamic> m, String k1, String k2) => ((m[k1] ?? m[k2] ?? 0) as num).toDouble();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Báo cáo Tài chính – Tách bạch Đã thu, COD & Hoàn tiền (AT12)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              FilledButton.tonalIcon(
                onPressed: _broadcastNotificationDialog,
                icon: const Icon(Icons.campaign, size: 18),
                label: const Text('Gửi thông báo (UC29)'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D47A1)),
                onPressed: _showAcceptanceChecklistDialog,
                icon: const Icon(Icons.fact_check, size: 18),
                label: const Text('AT01-AT12'),
              ),
            ],
          ),
          if (isAdmin && _companies.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: _filterCompanyId,
              decoration: const InputDecoration(
                labelText: 'Lọc phạm vi báo cáo theo Nhà xe (Mục 15.1)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Toàn hệ thống (Tất cả nhà xe)')),
                ..._companies.map((c) => DropdownMenuItem<int?>(
                      value: (c['companyId'] ?? c['CompanyId']) as int,
                      child: Text((c['name'] ?? c['Name']).toString()),
                    )),
              ],
              onChanged: (v) {
                setState(() => _filterCompanyId = v);
                _loadAll();
              },
            ),
          ],
          const SizedBox(height: 10),
          _metricCard(
            title: 'DOANH THU THỰC THU RÒNG (= Đã thu - Đã hoàn)',
            value: '${val(fin, 'netCollectedRevenue', 'NetCollectedRevenue').toStringAsFixed(0)} đ',
            color: Colors.green,
            icon: Icons.account_balance_wallet,
          ),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Tổng tiền đã thu (Gross)',
                  value: '${val(fin, 'totalCollectedGross', 'TotalCollectedGross').toStringAsFixed(0)} đ',
                  color: Colors.blue,
                  icon: Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  title: 'COD chưa thu (Unpaid)',
                  value: '${val(fin, 'uncollectedCodAmount', 'UncollectedCodAmount').toStringAsFixed(0)} đ',
                  color: Colors.orange,
                  icon: Icons.pending_actions,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Tiền đã hoàn (Completed)',
                  value: '${val(fin, 'completedRefundAmount', 'CompletedRefundAmount').toStringAsFixed(0)} đ',
                  color: Colors.purple,
                  icon: Icons.replay_circle_filled_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  title: 'Đang chờ hoàn (Pending)',
                  value: '${val(fin, 'pendingRefundAmount', 'PendingRefundAmount').toStringAsFixed(0)} đ',
                  color: Colors.red,
                  icon: Icons.hourglass_top,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ShadcnCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chỉ số Đơn đặt vé & Hiệu suất lấp đầy ghế', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2)),
                const Divider(height: 20),
                Text('• Tổng số Booking: ${bm['totalBookings'] ?? bm['TotalBookings'] ?? 0} đơn'),
                Text('• Đơn hiệu lực / Hoàn tất: ${bm['confirmedBookings'] ?? bm['ConfirmedBookings'] ?? 0} đơn'),
                Text('• Đơn đã hủy / Hoàn: ${bm['cancelledBookings'] ?? bm['CancelledBookings'] ?? 0} đơn'),
                Text('• Đơn khách vắng mặt (No-show): ${bm['noShowBookings'] ?? bm['NoShowBookings'] ?? 0} đơn'),
                Text('• Tổng số vé đã bán: ${bm['totalTicketsSold'] ?? bm['TotalTicketsSold'] ?? 0} vé'),
                const SizedBox(height: 8),
                Text(
                  '• Tỷ lệ lấp đầy ghế: ${tm['occupancyRatePercent'] ?? tm['OccupancyRatePercent'] ?? 0}% (${tm['bookedSeats'] ?? tm['BookedSeats'] ?? 0}/${tm['totalSeats'] ?? tm['TotalSeats'] ?? 0} ghế)',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: ShadcnTheme.primaryDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ShadcnCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Đối soát doanh thu & Hoa hồng sàn (UC28):', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: -0.2)),
                    TextButton.icon(
                      onPressed: _showPlatformSettlementsDialog,
                      icon: const Icon(LucideIcons.landmark, size: 14, color: ShadcnTheme.success),
                      label: const Text('Quyết toán 6%', style: TextStyle(color: ShadcnTheme.success, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: _showPromotionsDialog,
                      icon: const Icon(LucideIcons.tag, size: 14, color: ShadcnTheme.accentOrange),
                      label: const Text('Voucher', style: TextStyle(color: ShadcnTheme.accentOrange, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: _exportCsvDialog,
                      icon: const Icon(LucideIcons.download, size: 14, color: ShadcnTheme.primaryDark),
                      label: const Text('Xuất CSV', style: TextStyle(color: ShadcnTheme.primaryDark, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: _showAddProvinceDialog,
                      icon: const Icon(LucideIcons.plus, size: 14, color: ShadcnTheme.primaryDark),
                      label: const Text('+ Tỉnh', style: TextStyle(color: ShadcnTheme.primaryDark, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                  const Divider(),
                  ...(((_report?['companyBreakdown'] ?? _report?['CompanyBreakdown']) as List?) ?? []).map((cb) {
                    final cm = Map<String, dynamic>.from(cb as Map);
                    final net = ((cm['netRevenue'] ?? cm['NetRevenue'] ?? 0) as num).toDouble();
                    final cod = ((cm['uncollectedCod'] ?? cm['UncollectedCod'] ?? 0) as num).toDouble();
                    final totalGross = val(fin, 'totalCollectedGross', 'TotalCollectedGross');
                    final ratio = totalGross > 0 ? (net / totalGross).clamp(0.0, 1.0) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${cm['name'] ?? cm['Name']} (${cm['status'] ?? cm['Status']})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              Text(
                                'Net: ${net.toStringAsFixed(0)}đ | COD: ${cod.toStringAsFixed(0)}đ',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0D47A1), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 7,
                              backgroundColor: Colors.blue.shade50,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCompaniesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _companies.length,
      itemBuilder: (ctx, i) {
        final c = _companies[i];
        final id = (c['companyId'] ?? c['CompanyId']) as int;
        final name = (c['name'] ?? c['Name']).toString();
        final status = (c['status'] ?? c['Status']).toString();
        final tax = (c['taxCode'] ?? c['TaxCode']).toString();
        final phone = (c['phone'] ?? c['Phone']).toString();

        return ShadcnCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2)),
                  ),
                  status == 'Active'
                      ? ShadcnBadge.success(status)
                      : (status == 'Pending' ? ShadcnBadge.warning(status) : ShadcnBadge.destructive(status)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Mã số thuế: $tax • Hotline: $phone', style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground)),
              Text('Địa chỉ: ${c['address'] ?? c['Address']}', style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (status != 'Active')
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: ShadcnTheme.success, visualDensity: VisualDensity.compact),
                      onPressed: () => _updateCompanyStatus(id, 'Active'),
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: const Text('Duyệt Active'),
                    ),
                  if (status != 'Suspended')
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _updateCompanyStatus(id, 'Suspended'),
                      child: const Text('Đình chỉ (Suspended)'),
                    ),
                  if (status != 'Rejected')
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: ShadcnTheme.destructive,
                        side: const BorderSide(color: Color(0xFFFECACA)),
                      ),
                      onPressed: () => _updateCompanyStatus(id, 'Rejected'),
                      child: const Text('Từ chối (Rejected)'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _users.length,
      itemBuilder: (ctx, i) {
        final u = _users[i];
        final uid = (u['userId'] ?? u['UserId']) as int;
        final isActive = (u['isActive'] ?? u['IsActive'] ?? true) == true;
        final roles = ((u['roles'] ?? u['Roles']) as List? ?? []).join(', ');

        return ShadcnCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isActive ? ShadcnTheme.secondary : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                      border: Border.all(color: isActive ? ShadcnTheme.border : const Color(0xFFFECACA)),
                    ),
                    child: Icon(
                      isActive ? Icons.person_rounded : Icons.person_off_rounded,
                      color: isActive ? ShadcnTheme.foreground : ShadcnTheme.destructive,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${u['fullName'] ?? u['FullName']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        Text(
                          '${u['email'] ?? u['Email']} • SĐT: ${u['phone'] ?? u['Phone']}',
                          style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  ShadcnBadge.secondary(roles),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (((u['noShowCount'] ?? u['NoShowCount'] ?? 0) as int) > 0)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _resetUserNoShow(uid),
                      child: Text('Xóa No-show (${u['noShowCount']})', style: const TextStyle(fontSize: 11.5)),
                    ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isActive ? ShadcnTheme.destructive : ShadcnTheme.success,
                      side: BorderSide(color: isActive ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                    ),
                    onPressed: () => _toggleUserActive(uid),
                    child: Text(isActive ? 'Khóa tài khoản' : 'Mở khóa', style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRefundsAndAuditTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Yêu cầu hoàn tiền (Refunds - UC27, BR21)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
        ),
        const SizedBox(height: 8),
        if (_refunds.isEmpty)
          const ShadcnCard(
            child: Center(
              child: Text('Chưa có yêu cầu hoàn tiền nào.', style: TextStyle(color: ShadcnTheme.mutedForeground, fontSize: 13)),
            ),
          )
        else
          ..._refunds.map((r) {
            final id = (r['refundId'] ?? r['RefundId']) as int;
            final code = (r['bookingCode'] ?? r['BookingCode']).toString();
            final amount = ((r['amount'] ?? r['Amount'] ?? 0) as num).toDouble();
            final status = (r['status'] ?? r['Status']).toString();
            final reason = (r['reason'] ?? r['Reason'] ?? '').toString();

            return ShadcnCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: ShadcnTheme.secondary,
                      borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                      border: Border.all(color: ShadcnTheme.border),
                    ),
                    child: const Icon(Icons.currency_exchange_rounded, size: 16, color: ShadcnTheme.foreground),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Đơn $code • Hoàn: ${amount.toStringAsFixed(0)} đ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text('Lý do: $reason', style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  status == 'Pending'
                      ? FilledButton(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                          onPressed: () => _completeRefund(id),
                          child: const Text('Xác nhận hoàn', style: TextStyle(fontSize: 11.5)),
                        )
                      : ShadcnBadge.success('Đã hoàn'),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        const Text(
          'Nhật ký kiểm toán & bảo mật (AuditLogs - UC30)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
        ),
        const SizedBox(height: 8),
        ..._auditLogs.map((a) {
          return ShadcnCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: ShadcnTheme.secondary,
                    borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 15, color: ShadcnTheme.foreground),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a['action'] ?? a['Action']} (${a['entityName'] ?? a['EntityName']} #${a['entityId'] ?? a['EntityId']})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      Text(
                        '${a['details'] ?? a['Details']} • User #${a['userId'] ?? a['UserId']}',
                        style: const TextStyle(fontSize: 11, color: ShadcnTheme.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ShadcnStatCard(
        title: title,
        value: value,
        icon: icon,
        iconColor: color,
      ),
    );
  }
}
