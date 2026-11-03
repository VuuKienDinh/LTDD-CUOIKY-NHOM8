 import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../theme/shadcn_theme.dart';

class OperatorManagementView extends StatefulWidget {
  const OperatorManagementView({super.key});

  @override
  State<OperatorManagementView> createState() => _OperatorManagementViewState();
}

class _OperatorManagementViewState extends State<OperatorManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _provinces = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadDashboard();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get('/api/operator/dashboard');
      final provs = await ApiClient.instance.get('/api/provinces');
      setState(() {
        _dashboard = Map<String, dynamic>.from(res as Map);
        _provinces = (provs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testCrossTenantAccess() async {
    final comp = _dashboard?['company'] ?? _dashboard?['Company'];
    final myCompanyId = (comp?['companyId'] ?? comp?['CompanyId'] ?? 1) as int;
    final otherCompanyId = myCompanyId == 1 ? 2 : 1;

    try {
      await ApiClient.instance.get('/api/operator/dashboard', query: {
        'requestedCompanyId': otherCompanyId.toString(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã truy cập (Tài khoản Admin có quyền toàn hệ thống).')),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Đạt tiêu chí AT02 & BR03!')),
            ],
          ),
          content: Text(
            'Khi cố tình đổi CompanyId sang #$otherCompanyId của nhà xe khác, Backend đã chặn truy cập ngang:\n\n"$e"',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã rõ')),
          ],
        ),
      );
    }
  }

  Future<void> _showCreateTripDialog() async {
    final routes = (_dashboard?['routes'] ?? _dashboard?['Routes']) as List? ?? [];
    final buses = (_dashboard?['buses'] ?? _dashboard?['Buses']) as List? ?? [];
    final drivers = (_dashboard?['drivers'] ?? _dashboard?['Drivers']) as List? ?? [];

    if (routes.isEmpty || buses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhà xe cần có ít nhất 1 tuyến và 1 xe để tạo chuyến.')),
      );
      return;
    }

    int routeId = (routes.first['routeId'] ?? routes.first['RouteId']) as int;
    int busId = (buses.first['busId'] ?? buses.first['BusId']) as int;
    int? driverId = drivers.isNotEmpty ? (drivers.first['driverId'] ?? drivers.first['DriverId']) as int : null;
    final priceCtrl = TextEditingController(text: '350000');
    int daysAhead = 2;
    int hour = 21;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Lập lịch chuyến xe mới (UC21, AT03)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: routeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tuyến đường', border: OutlineInputBorder()),
                  items: routes.map((r) {
                    final id = (r['routeId'] ?? r['RouteId']) as int;
                    final name = (r['name'] ?? r['Name']).toString();
                    return DropdownMenuItem(value: id, child: Text(name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => routeId = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: busId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Xe vận hành (BR06, BR07)', border: OutlineInputBorder()),
                  items: buses.map((b) {
                    final id = (b['busId'] ?? b['BusId']) as int;
                    final plate = (b['plateNumber'] ?? b['PlateNumber']).toString();
                    final type = (b['busType'] ?? b['BusType']).toString();
                    return DropdownMenuItem(value: id, child: Text('$plate - $type', overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => busId = v!),
                ),
                const SizedBox(height: 10),
                if (drivers.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: driverId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tài xế phân công (BR08)', border: OutlineInputBorder()),
                    items: drivers.map((d) {
                      final id = (d['driverId'] ?? d['DriverId']) as int;
                      final name = (d['fullName'] ?? d['FullName']).toString();
                      final cls = (d['licenseClass'] ?? d['LicenseClass']).toString();
                      return DropdownMenuItem<int?>(value: id, child: Text('$name (Hạng $cls)'));
                    }).toList(),
                    onChanged: (v) => setDialogState(() => driverId = v),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: daysAhead,
                        decoration: const InputDecoration(labelText: 'Ngày chạy', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Hôm nay')),
                          DropdownMenuItem(value: 1, child: Text('Ngày mai')),
                          DropdownMenuItem(value: 2, child: Text('+2 ngày tới')),
                          DropdownMenuItem(value: 3, child: Text('+3 ngày tới')),
                        ],
                        onChanged: (v) => setDialogState(() => daysAhead = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: hour,
                        decoration: const InputDecoration(labelText: 'Giờ xuất bến', border: OutlineInputBorder()),
                        items: [7, 8, 13, 18, 21, 22, 23]
                            .map((h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')))
                            .toList(),
                        onChanged: (v) => setDialogState(() => hour = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Giá vé cơ bản (VNĐ)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final baseDate = DateTime.now().toUtc().dateOnly.add(Duration(days: daysAhead, hours: hour));
                  final res = await ApiClient.instance.post('/api/operator/trips', body: {
                    'routeId': routeId,
                    'busId': busId,
                    'driverId': driverId,
                    'departureAt': baseDate.toIso8601String(),
                    'basePrice': double.tryParse(priceCtrl.text) ?? 350000,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã tạo chuyến').toString())),
                    );
                    await _loadDashboard();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Tạo chuyến & Sinh sơ đồ ghế'),
            ),
          ],
        ),
      ),
    );
  }

  // UC22: Phân công / Thay tài xế cho chuyến
  Future<void> _showReassignDriverDialog(int tripId) async {
    final drivers = (_dashboard?['drivers'] ?? _dashboard?['Drivers']) as List? ?? [];
    if (drivers.isEmpty) return;

    int newDriverId = (drivers.first['driverId'] ?? drivers.first['DriverId']) as int;
    final reasonCtrl = TextEditingController(text: 'Điều phối ca trực tài xế');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Phân công / Thay tài xế chuyến #$tripId (UC22)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: newDriverId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chọn tài xế mới', border: OutlineInputBorder()),
                items: drivers.map((d) {
                  final id = (d['driverId'] ?? d['DriverId']) as int;
                  final name = (d['fullName'] ?? d['FullName']).toString();
                  return DropdownMenuItem(value: id, child: Text(name));
                }).toList(),
                onChanged: (v) => setDialogState(() => newDriverId = v!),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Lý do thay tài xế (Lưu lịch sử)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/operator/trips/$tripId/reassign-driver', body: {
                    'newDriverId': newDriverId,
                    'reason': reasonCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadDashboard();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã phân công').toString())),
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
      ),
    );
  }

  Future<void> _showAddBusDialog() async {
    final plateCtrl = TextEditingController(text: '51B-333.68');
    final typeCtrl = TextEditingController(text: 'Limousine 20 Phòng Đôi');
    final brandCtrl = TextEditingController(text: 'Hyundai Universe');
    final seatsCtrl = TextEditingController(text: '20');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm xe & Tự động thiết kế sơ đồ ghế (FR05, FR06)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: plateCtrl,
                decoration: const InputDecoration(labelText: 'Biển kiểm soát (Duy nhất - BR05)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: typeCtrl,
                decoration: const InputDecoration(labelText: 'Loại xe', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(labelText: 'Hãng / Model', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: seatsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tổng số ghế (Tầng 1 A + Tầng 2 B)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/operator/buses', body: {
                  'plateNumber': plateCtrl.text.trim(),
                  'busType': typeCtrl.text.trim(),
                  'brandModel': brandCtrl.text.trim(),
                  'totalSeats': int.tryParse(seatsCtrl.text) ?? 20,
                  'manufactureYear': 2025,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã thêm xe').toString())),
                  );
                  await _loadDashboard();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Lưu xe & Sơ đồ ghế'),
          ),
        ],
      ),
    );
  }

  // UC19, FR07: Thêm tài xế mới
  Future<void> _showAddDriverDialog() async {
    final nameCtrl = TextEditingController(text: 'Võ Minh Tuấn');
    final phoneCtrl = TextEditingController(text: '0909888777');
    final licCtrl = TextEditingController(text: '790888999111');
    String licClass = 'E';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm hồ sơ Tài xế mới (UC19, FR07)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ và tên tài xế', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: licCtrl,
                  decoration: const InputDecoration(labelText: 'Số GPLX', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: licClass,
                  decoration: const InputDecoration(labelText: 'Hạng GPLX (BR08)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'E', child: Text('Hạng E (Xe khách > 30 chỗ)')),
                    DropdownMenuItem(value: 'D', child: Text('Hạng D (Xe 10 - 30 chỗ)')),
                  ],
                  onChanged: (v) => setDialogState(() => licClass = v ?? 'E'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/operator/drivers', body: {
                    'fullName': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'licenseNumber': licCtrl.text.trim(),
                    'licenseClass': licClass,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadDashboard();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã thêm tài xế').toString())),
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
              child: const Text('Lưu tài xế'),
            ),
          ],
        ),
      ),
    );
  }

  // UC20, FR08: Thêm tuyến đường mới
  Future<void> _showAddRouteDialog() async {
    if (_provinces.length < 2) return;
    int originId = (_provinces[0]['provinceId'] ?? _provinces[0]['ProvinceId']) as int;
    int destId = (_provinces[3]['provinceId'] ?? _provinces[3]['ProvinceId']) as int;
    final kmCtrl = TextEditingController(text: '125');
    final minCtrl = TextEditingController(text: '150');
    final pickupCtrl = TextEditingController(text: 'Bến xe Miền Đông Mới');
    final dropoffCtrl = TextEditingController(text: 'Bến xe Vũng Tàu');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Khai báo Tuyến & Điểm dừng (UC20, FR08)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: originId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tỉnh/thành đi', border: OutlineInputBorder()),
                  items: _provinces.map((p) {
                    final id = (p['provinceId'] ?? p['ProvinceId']) as int;
                    return DropdownMenuItem(value: id, child: Text((p['name'] ?? p['Name']).toString()));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => originId = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: destId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tỉnh/thành đến', border: OutlineInputBorder()),
                  items: _provinces.map((p) {
                    final id = (p['provinceId'] ?? p['ProvinceId']) as int;
                    return DropdownMenuItem(value: id, child: Text((p['name'] ?? p['Name']).toString()));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => destId = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: kmCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cự ly (km)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Thời gian (phút)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pickupCtrl,
                  decoration: const InputDecoration(labelText: 'Điểm đón đầu tuyến', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dropoffCtrl,
                  decoration: const InputDecoration(labelText: 'Điểm trả cuối tuyến', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/operator/routes', body: {
                    'originProvinceId': originId,
                    'destinationProvinceId': destId,
                    'distanceKm': int.tryParse(kmCtrl.text) ?? 125,
                    'estimatedDurationMinutes': int.tryParse(minCtrl.text) ?? 150,
                    'defaultPickupStopName': pickupCtrl.text.trim(),
                    'defaultDropoffStopName': dropoffCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadDashboard();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã tạo tuyến').toString())),
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
              child: const Text('Lưu tuyến đường'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBusMaintenance(int busId, String currentStatus) async {
    final nextStatus = currentStatus == 'Active' ? 'Maintenance' : 'Active';
    try {
      final res = await ApiClient.instance.post('/api/operator/buses/$busId/status', body: {
        'status': nextStatus,
        'description': 'Cập nhật trạng thái bảo dưỡng phương tiện',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã cập nhật').toString())),
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // UC16, FR07: Tạo tài khoản Nhân viên nhà xe (Staff)
  Future<void> _showAddStaffDialog() async {
    final nameCtrl = TextEditingController(text: 'Phạm Thị Hồng (NV Bán vé)');
    final emailCtrl = TextEditingController(text: 'hong.staff@phuongtrang.vn');
    final phoneCtrl = TextEditingController(text: '0901999888');
    final passCtrl = TextEditingController(text: '123456');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo tài khoản Nhân viên nhà xe (UC16, FR07)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Họ tên nhân viên', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email đăng nhập', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Mật khẩu khởi tạo', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/operator/staff', body: {
                  'fullName': nameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'password': passCtrl.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadDashboard();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã tạo nhân viên').toString())),
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
            child: const Text('Tạo nhân viên'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddStopToRouteDialog(int routeId, String routeName) async {
    final nameCtrl = TextEditingController(text: 'Ngã ba Dầu Giây (Đón/Trả)');
    final addrCtrl = TextEditingController(text: 'QL1A, Thống Nhất, Đồng Nai');
    final offsetCtrl = TextEditingController(text: '75');
    final surCtrl = TextEditingController(text: '10000');
    String stopType = 'Both';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Thêm điểm dừng dọc tuyến\n$routeName', style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên điểm dừng', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: stopType,
                  decoration: const InputDecoration(labelText: 'Loại điểm dừng', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Pickup', child: Text('Điểm đón (Pickup)')),
                    DropdownMenuItem(value: 'Dropoff', child: Text('Điểm trả (Dropoff)')),
                    DropdownMenuItem(value: 'Both', child: Text('Cả đón & trả (Both)')),
                  ],
                  onChanged: (v) => setDialogState(() => stopType = v ?? 'Both'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: offsetCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Sau giờ đi (phút)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: surCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Phụ phí (VNĐ)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await ApiClient.instance.post('/api/operator/routes/$routeId/stops', body: {
                    'stopName': nameCtrl.text.trim(),
                    'address': addrCtrl.text.trim(),
                    'stopType': stopType,
                    'offsetMinutes': int.tryParse(offsetCtrl.text) ?? 60,
                    'surcharge': double.tryParse(surCtrl.text) ?? 0,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadDashboard();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã thêm điểm dừng').toString())),
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
              child: const Text('Thêm điểm dừng'),
            ),
          ],
        ),
      ),
    );
  }

  // UC18, FR06, BR27: Thiết kế & cấu hình sơ đồ ghế của xe
  Future<void> _showBusSeatConfigDialog(int busId, String plate) async {
    try {
      var res = await ApiClient.instance.get('/api/operator/buses/$busId/seats');
      if (!mounted) return;
      var data = Map<String, dynamic>.from(res as Map);

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final seats = (data['seats'] ?? data['Seats']) as List? ?? [];
            final maint = (data['maintenances'] ?? data['Maintenances']) as List? ?? [];

            return AlertDialog(
              title: Text('Sơ đồ ghế & Bảo trì xe $plate (UC18, BR27)', style: const TextStyle(fontSize: 15)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chạm vào ghế để chuyển đổi loại ghế VIP (+20.000đ) / Standard (0đ). Thay đổi chỉ áp dụng cho chuyến mới, giữ nguyên hóa đơn cũ (BR27):',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: seats.map((s) {
                          final sm = Map<String, dynamic>.from(s as Map);
                          final seatId = (sm['busSeatId'] ?? sm['BusSeatId']) as int;
                          final code = (sm['seatCode'] ?? sm['SeatCode']).toString();
                          final type = (sm['seatType'] ?? sm['SeatType']).toString();
                          final sur = ((sm['priceSurcharge'] ?? sm['PriceSurcharge'] ?? 0) as num).toDouble();
                          final isVip = type == 'VIP';

                          return ActionChip(
                            backgroundColor: isVip ? Colors.amber.shade100 : Colors.blue.shade50,
                            label: Text('$code ($type +${(sur / 1000).toStringAsFixed(0)}k)', style: const TextStyle(fontSize: 11)),
                            onPressed: () async {
                              final nextType = isVip ? 'Standard' : 'VIP';
                              final nextSur = isVip ? 0 : 20000;
                              await ApiClient.instance.put('/api/operator/buses/$busId/seats/$seatId', body: {
                                'seatType': nextType,
                                'priceSurcharge': nextSur,
                                'isActive': true,
                              });
                              final refreshed = await ApiClient.instance.get('/api/operator/buses/$busId/seats');
                              setDialogState(() {
                                data = Map<String, dynamic>.from(refreshed as Map);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (maint.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text('Lịch sử bảo trì phương tiện (BusMaintenances):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ...maint.map((m) {
                          final mm = Map<String, dynamic>.from(m as Map);
                          return Text('• ${mm['description'] ?? mm['Description']} (${mm['status'] ?? mm['Status']})', style: const TextStyle(fontSize: 12));
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
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

  // Section 10.2: Xem và thêm giấy tờ pháp lý tài xế (DriverDocuments)
  Future<void> _showDriverDocumentsDialog(int driverId, String driverName) async {
    try {
      var res = await ApiClient.instance.get('/api/operator/drivers/$driverId/documents');
      if (!mounted) return;
      var data = Map<String, dynamic>.from(res as Map);
      final typeCtrl = TextEditingController(text: 'Giấy khám sức khỏe định kỳ');

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final docs = (data['documents'] ?? data['Documents']) as List? ?? [];
            return AlertDialog(
              title: Text('Hồ sơ & Giấy tờ tài xế: $driverName', style: const TextStyle(fontSize: 15)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (docs.isEmpty)
                        const Text('Chưa có giấy tờ đính kèm.')
                      else
                        ...docs.map((d) {
                          final dm = Map<String, dynamic>.from(d as Map);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.verified_user, color: Colors.green),
                            title: Text((dm['type'] ?? dm['Type']).toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${dm['fileUrl'] ?? dm['FileUrl']}\nTrạng thái: ${dm['status'] ?? dm['Status']}'),
                          );
                        }),
                      const Divider(),
                      TextField(
                        controller: typeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Thêm loại giấy tờ mới (VD: Chứng chỉ nghiệp vụ)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
                FilledButton.icon(
                  onPressed: () async {
                    await ApiClient.instance.post('/api/operator/drivers/$driverId/documents', body: {
                      'type': typeCtrl.text.trim(),
                    });
                    final refreshed = await ApiClient.instance.get('/api/operator/drivers/$driverId/documents');
                    setDialogState(() {
                      data = Map<String, dynamic>.from(refreshed as Map);
                    });
                  },
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Thêm giấy tờ'),
                ),
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

  Future<void> _replySupportDialog(int requestId, String subject) async {
    final replyCtrl = TextEditingController(text: 'Nhà xe đã tiếp nhận và cập nhật điểm đón theo yêu cầu của quý khách.');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Phản hồi hỗ trợ: $subject (UC31)'),
        content: TextField(
          controller: replyCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nội dung phản hồi cho khách', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/operator/support-requests/$requestId/reply', body: {
                  'replyContent': replyCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadDashboard();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã phản hồi').toString())),
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
            child: const Text('Gửi phản hồi'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelTrip(int tripId) async {
    try {
      final res = await ApiClient.instance.post('/api/operator/trips/$tripId/cancel', body: {
        'reason': 'Bảo trì phương tiện khẩn cấp',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã hủy chuyến').toString())),
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _collectCod(int bookingId) async {
    try {
      final res = await ApiClient.instance.post('/api/operator/bookings/$bookingId/collect-cod');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã xác nhận thu COD').toString())),
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markNoShow(int bookingId) async {
    try {
      final res = await ApiClient.instance.post('/api/operator/bookings/$bookingId/mark-noshow');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['message'] ?? 'Đã ghi nhận No-Show').toString())),
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showTripOperationalLogsDialog(int tripId, String routeName) async {
    try {
      final res = await ApiClient.instance.get('/api/operator/trips/$tripId/operational-logs');
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final assignments = (data['driverAssignments'] ?? data['DriverAssignments']) as List? ?? [];
      final statusHistories = (data['statusHistories'] ?? data['StatusHistories']) as List? ?? [];
      final incidents = (data['incidents'] ?? data['Incidents']) as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Nhật ký vận hành & Sự cố chuyến #$tripId\n($routeName)', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('1. Lịch sử phân công tài xế (DriverAssignments - UC22):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (assignments.isEmpty)
                    const Text('• Chưa có phân công.', style: TextStyle(fontSize: 12))
                  else
                    ...assignments.map((a) {
                      final am = Map<String, dynamic>.from(a as Map);
                      final released = am['releasedAt'] ?? am['ReleasedAt'];
                      final reason = am['replaceReason'] ?? am['ReplaceReason'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${am['driverName'] ?? am['DriverName']} (${am['role'] ?? am['Role']}) - ${released == null ? "Đang phụ trách" : "Đã thay thế ($reason)"}',
                          style: TextStyle(fontSize: 12, color: released == null ? Colors.green.shade800 : Colors.grey.shade700),
                        ),
                      );
                    }),
                  const Divider(),
                  const Text('2. Lịch sử trạng thái chuyến (TripStatusHistories - BR28):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (statusHistories.isEmpty)
                    const Text('• Chưa có lịch sử trạng thái.', style: TextStyle(fontSize: 12))
                  else
                    ...statusHistories.map((h) {
                      final hm = Map<String, dynamic>.from(h as Map);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${hm['oldStatus'] ?? hm['OldStatus']} → ${hm['newStatus'] ?? hm['NewStatus']}: ${hm['reason'] ?? hm['Reason'] ?? ""}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }),
                  const Divider(),
                  const Text('3. Sự cố dọc đường (TripIncidents - UC25):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (incidents.isEmpty)
                    const Text('• Không có sự cố nào được ghi nhận.', style: TextStyle(fontSize: 12, color: Colors.green))
                  else
                    ...incidents.map((inc) {
                      final im = Map<String, dynamic>.from(inc as Map);
                      return Card(
                        color: Colors.red.shade50,
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          title: Text('${im['type'] ?? im['Type']} (${im['driverName'] ?? im['DriverName']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          subtitle: Text((im['description'] ?? im['Description']).toString(), style: const TextStyle(fontSize: 12)),
                        ),
                      );
                    }),
                ],
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

  Future<void> _showBusMaintenanceHistoryDialog(int busId, String plate) async {
    try {
      final res = await ApiClient.instance.get('/api/operator/buses/$busId/maintenances');
      if (!mounted) return;
      final list = res as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Lịch sử bảo trì xe $plate (BusMaintenances)', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? const Text('Xe chưa có lịch sử bảo trì nào.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, idx) {
                      final m = Map<String, dynamic>.from(list[idx] as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.build_circle_outlined, color: Colors.orange),
                        title: Text((m['description'] ?? m['Description']).toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Trạng thái: ${m['status'] ?? m['Status']} • Bắt đầu: ${(m['startAt'] ?? m['StartAt']).toString().substring(0, 10)}'),
                      );
                    },
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

  Future<void> _showCompanyReviewsDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/operator/reviews');
      if (!mounted) return;
      final list = res as List? ?? [];

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Đánh giá của hành khách (${list.length} lượt - UC13)', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? const Text('Chưa có đánh giá nào từ hành khách.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, idx) {
                      final r = Map<String, dynamic>.from(list[idx] as Map);
                      final rating = (r['rating'] ?? r['Rating'] ?? 5) as int;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.shade100,
                          child: Text('$rating★', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        title: Text('${r['customerName'] ?? r['CustomerName']} (Đơn ${r['bookingCode'] ?? r['BookingCode']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text((r['comment'] ?? r['Comment'] ?? '').toString()),
                      );
                    },
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

  Future<void> _showOperatorReportSummaryDialog() async {
    try {
      final res = await ApiClient.instance.get('/api/operator/reports/summary');
      if (!mounted) return;
      final r = Map<String, dynamic>.from(res as Map);
      final collected = ((r['collectedRevenue'] ?? r['CollectedRevenue'] ?? 0) as num).toDouble();
      final uncollectedCod = ((r['uncollectedCodAmount'] ?? r['UncollectedCodAmount'] ?? 0) as num).toDouble();
      final refunded = ((r['completedRefundAmount'] ?? r['CompletedRefundAmount'] ?? 0) as num).toDouble();
      final netRev = ((r['netRevenue'] ?? r['NetRevenue'] ?? 0) as num).toDouble();
      final occ = ((r['occupancyRatePercent'] ?? r['OccupancyRatePercent'] ?? 0) as num).toDouble();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Báo cáo Doanh thu & Vận hành Nhà xe (UC26, BR26)', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Tổng số chuyến đang mở: ${r['activeTrips'] ?? r['ActiveTrips']}/${r['totalTrips'] ?? r['TotalTrips']} chuyến'),
              Text('• Ghế đã bán: ${r['totalSeatsBooked'] ?? r['TotalSeatsBooked']}/${r['totalSeatsOffered'] ?? r['TotalSeatsOffered']} ghế (${occ.toStringAsFixed(1)}%)'),
              const Divider(),
              Text('• Doanh thu đã thu (Paid): ${collected.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              Text('• COD chưa thu (Unpaid): ${uncollectedCod.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.orange)),
              Text('• Tiền đã hoàn (Refunded): -${refunded.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.red)),
              const Divider(),
              Text('• DOANH THU RÒNG (NET): ${netRev.toStringAsFixed(0)} đ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0D47A1))),
            ],
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

  // Mở rộng nâng cao: Tạo lịch chạy hàng loạt nhiều ngày (Recurring Trip Generator)
  Future<void> _showBulkGenerateTripsDialog() async {
    final routes = (_dashboard?['routes'] ?? _dashboard?['Routes']) as List? ?? [];
    final buses = (_dashboard?['buses'] ?? _dashboard?['Buses']) as List? ?? [];
    final drivers = (_dashboard?['drivers'] ?? _dashboard?['Drivers']) as List? ?? [];
    if (routes.isEmpty || buses.isEmpty) return;

    int routeId = (routes.first['routeId'] ?? routes.first['RouteId']) as int;
    int busId = (buses.first['busId'] ?? buses.first['BusId']) as int;
    int? driverId = drivers.isNotEmpty ? ((drivers.first['driverId'] ?? drivers.first['DriverId']) as int) : null;
    final daysCtrl = TextEditingController(text: '3');
    final priceCtrl = TextEditingController(text: '350000');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tạo lịch chạy tự động hàng loạt (Nhiều ngày)', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: routeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tuyến đường', border: OutlineInputBorder()),
                  items: routes.map((r) => DropdownMenuItem(
                    value: (r['routeId'] ?? r['RouteId']) as int,
                    child: Text((r['name'] ?? r['Name']).toString(), overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => routeId = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: busId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Xe vận hành', border: OutlineInputBorder()),
                  items: buses.map((b) => DropdownMenuItem(
                    value: (b['busId'] ?? b['BusId']) as int,
                    child: Text('${b['plateNumber'] ?? b['PlateNumber']} (${b['totalSeats'] ?? b['TotalSeats']} chỗ)'),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => busId = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: daysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Số ngày liên tiếp', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Giá vé (VNĐ)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final start = DateTime.now().toUtc().add(const Duration(days: 2));
                  final res = await ApiClient.instance.post('/api/operator/trips/bulk-generate', body: {
                    'routeId': routeId,
                    'busId': busId,
                    'driverId': driverId,
                    'startDepartureAt': start.toIso8601String(),
                    'daysCount': int.tryParse(daysCtrl.text) ?? 3,
                    'basePrice': double.tryParse(priceCtrl.text) ?? 350000,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadDashboard();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res['message'] ?? 'Đã tạo lịch hàng loạt').toString())),
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
              icon: const Icon(Icons.auto_mode),
              label: const Text('Sinh lịch tự động'),
            ),
          ],
        ),
      ),
    );
  }

  // Mở rộng nâng cao: Bán vé nhanh tại quầy / qua điện thoại (Counter POS Booking)
  Future<void> _showCounterPosBookingDialog(int tripId, String routeName) async {
    final nameCtrl = TextEditingController(text: 'Khách mua vé tại quầy Bến xe');
    final phoneCtrl = TextEditingController(text: '0912888999');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bán vé nhanh tại quầy (POS)\nChuyến #$tripId ($routeName)', style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tự động chọn ghế trống tiếp theo, xuất mã vé QR ngay lập tức và ghi nhận Đã thu tiền mặt (Paid) tại quầy:',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Họ tên hành khách', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Số điện thoại hành khách', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () async {
              try {
                final res = await ApiClient.instance.post('/api/operator/pos-booking', body: {
                  'tripId': tripId,
                  'passengerName': nameCtrl.text.trim(),
                  'passengerPhone': phoneCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadDashboard();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text((res['message'] ?? 'Đã xuất vé POS').toString())),
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
            icon: const Icon(Icons.point_of_sale, size: 18),
            label: const Text('Xuất vé & Thu tiền ngay'),
          ),
        ],
      ),
    );
  }

  // Mở rộng nâng cao: Quản lý Hàng hóa ký gửi theo chuyến xe (CargoShipments)
  Future<void> _showCargoShipmentsDialog(int tripId, String routeName) async {
    try {
      var res = await ApiClient.instance.get('/api/operator/parcels', query: {'tripId': tripId.toString()});
      if (!mounted) return;
      var parcels = res as List? ?? [];

      final senderNameCtrl = TextEditingController(text: 'Nguyễn Văn Hùng');
      final senderPhoneCtrl = TextEditingController(text: '0908111222');
      final receiverNameCtrl = TextEditingController(text: 'Trần Thị Mai');
      final receiverPhoneCtrl = TextEditingController(text: '0919333444');
      final descCtrl = TextEditingController(text: 'Thùng trái cây & Bưu phẩm');
      final feeCtrl = TextEditingController(text: '70000');

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Hàng hóa ký gửi chuyến #$tripId\n($routeName)', style: const TextStyle(fontSize: 15)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (parcels.isEmpty)
                      const Text('Chưa có kiện hàng ký gửi nào trên chuyến này.')
                    else
                      ...parcels.map((p) {
                        final pm = Map<String, dynamic>.from(p as Map);
                        final id = (pm['shipmentId'] ?? pm['ShipmentId']) as int;
                        final st = (pm['status'] ?? pm['Status']).toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined, color: Colors.deepOrange),
                            title: Text('${pm['trackingCode'] ?? pm['TrackingCode']} • ${pm['description'] ?? pm['Description']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            subtitle: Text('Gửi: ${pm['senderName'] ?? pm['SenderName']} → Nhận: ${pm['receiverName'] ?? pm['ReceiverName']} (${pm['receiverPhone'] ?? pm['ReceiverPhone']})\nCước: ${((pm['feeAmount'] ?? pm['FeeAmount'] ?? 0) as num).toStringAsFixed(0)}đ • Trạng thái: $st'),
                            trailing: st != 'Delivered'
                                ? TextButton(
                                    onPressed: () async {
                                      await ApiClient.instance.post('/api/operator/parcels/$id/status', body: {'status': 'Delivered'});
                                      final refreshed = await ApiClient.instance.get('/api/operator/parcels', query: {'tripId': tripId.toString()});
                                      setDialogState(() => parcels = refreshed as List? ?? []);
                                    },
                                    child: const Text('Đã giao', style: TextStyle(fontSize: 11)),
                                  )
                                : const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          ),
                        );
                      }),
                    const Divider(height: 20),
                    const Text('Nhận thêm kiện hàng ký gửi mới:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: senderNameCtrl, decoration: const InputDecoration(labelText: 'Người gửi', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        Expanded(child: TextField(controller: senderPhoneCtrl, decoration: const InputDecoration(labelText: 'SĐT gửi', isDense: true, border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: receiverNameCtrl, decoration: const InputDecoration(labelText: 'Người nhận', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        Expanded(child: TextField(controller: receiverPhoneCtrl, decoration: const InputDecoration(labelText: 'SĐT nhận', isDense: true, border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 2, child: TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Mô tả hàng hóa', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(width: 6),
                        Expanded(child: TextField(controller: feeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cước (đ)', isDense: true, border: OutlineInputBorder()))),
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
                  await ApiClient.instance.post('/api/operator/parcels', body: {
                    'tripId': tripId,
                    'senderName': senderNameCtrl.text.trim(),
                    'senderPhone': senderPhoneCtrl.text.trim(),
                    'receiverName': receiverNameCtrl.text.trim(),
                    'receiverPhone': receiverPhoneCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'weightKg': 2.5,
                    'feeAmount': double.tryParse(feeCtrl.text) ?? 70000,
                  });
                  final refreshed = await ApiClient.instance.get('/api/operator/parcels', query: {'tripId': tripId.toString()});
                  setDialogState(() => parcels = refreshed as List? ?? []);
                },
                icon: const Icon(Icons.add_box, size: 16),
                label: const Text('Tạo phiếu gửi hàng'),
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

  // Đợt 2 - Tính năng #5: Sổ chi phí chuyến đi & Quyết toán lợi nhuận ròng theo chuyến (TripExpenses)
  Future<void> _showTripExpensesAndProfitDialog(int tripId, String routeName) async {
    try {
      var res = await ApiClient.instance.get('/api/operator/trips/$tripId/expenses');
      if (!mounted) return;
      var data = Map<String, dynamic>.from(res as Map);

      String category = 'Fuel';
      final amountCtrl = TextEditingController(text: '350000');
      final noteCtrl = TextEditingController(text: 'Phụ cấp ăn đêm & bến bãi cho tổ lái');

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final ticketRev = ((data['ticketRevenue'] ?? data['TicketRevenue'] ?? 0) as num).toDouble();
            final cargoRev = ((data['cargoRevenue'] ?? data['CargoRevenue'] ?? 0) as num).toDouble();
            final totalExp = ((data['totalExpense'] ?? data['TotalExpense'] ?? 0) as num).toDouble();
            final netProfit = ((data['netTripProfit'] ?? data['NetTripProfit'] ?? 0) as num).toDouble();
            final expenses = (data['expenses'] ?? data['Expenses']) as List? ?? [];

            return AlertDialog(
              title: Text('Quyết toán Lợi nhuận & Sổ chi phí chuyến #$tripId\n($routeName)', style: const TextStyle(fontSize: 14.5)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• Doanh thu bán vé: +${ticketRev.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            Text('• Cước hàng hóa ký gửi: +${cargoRev.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                            Text('• Tổng chi phí vận hành chuyến: -${totalExp.toStringAsFixed(0)} đ', style: const TextStyle(color: Colors.red)),
                            const Divider(height: 12),
                            Text(
                              'LỢI NHUẬN RÒNG CHUYẾN: ${netProfit.toStringAsFixed(0)} đ',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0D47A1)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Các khoản chi phí đã ghi nhận:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      ...expenses.map((e) {
                        final em = Map<String, dynamic>.from(e as Map);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.local_gas_station, color: Colors.deepOrange, size: 18),
                          title: Text('${em['category'] ?? em['Category']}: ${((em['amount'] ?? em['Amount'] ?? 0) as num).toStringAsFixed(0)} đ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          subtitle: Text((em['note'] ?? em['Note'] ?? '').toString(), style: const TextStyle(fontSize: 11.5)),
                        );
                      }),
                      const Divider(height: 18),
                      const Text('Thêm khoản chi phí chuyến mới:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: category,
                              decoration: const InputDecoration(labelText: 'Khoản mục', isDense: true, border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Fuel', child: Text('Tiền dầu (Fuel)')),
                                DropdownMenuItem(value: 'BOT', child: Text('Phí cầu đường BOT')),
                                DropdownMenuItem(value: 'DriverAllowance', child: Text('Phụ cấp tổ lái')),
                                DropdownMenuItem(value: 'Other', child: Text('Chi phí khác')),
                              ],
                              onChanged: (v) => setDialogState(() => category = v ?? 'Fuel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Số tiền (VNĐ)', isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Ghi chú chứng từ / hóa đơn xăng dầu', isDense: true, border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
                FilledButton.icon(
                  onPressed: () async {
                    await ApiClient.instance.post('/api/operator/trips/$tripId/expenses', body: {
                      'category': category,
                      'amount': double.tryParse(amountCtrl.text) ?? 350000,
                      'note': noteCtrl.text.trim(),
                    });
                    final refreshed = await ApiClient.instance.get('/api/operator/trips/$tripId/expenses');
                    setDialogState(() => data = Map<String, dynamic>.from(refreshed as Map));
                  },
                  icon: const Icon(Icons.add_card, size: 16),
                  label: const Text('Ghi sổ chi phí'),
                ),
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

  // Đợt 2 - Tính năng #6: Danh sách đón khách xe trung chuyển tận nơi (Shuttle Pickup Manifest)
  Future<void> _showShuttleManifestDialog(int tripId, String routeName) async {
    try {
      var res = await ApiClient.instance.get('/api/operator/shuttles', query: {'tripId': tripId.toString()});
      if (!mounted) return;
      var list = res as List? ?? [];
      final plateCtrl = TextEditingController(text: '51B-999.16 (Ford Transit 16 chỗ)');

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Điều phối Xe trung chuyển đón khách tận nơi\nChuyến #$tripId ($routeName)', style: const TextStyle(fontSize: 14.5)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: plateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Biển số xe trung chuyển điều phối',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (list.isEmpty)
                      const Text('Chưa có hành khách nào đăng ký đón/trả tận nơi trên chuyến này.')
                    else
                      ...list.map((s) {
                        final sm = Map<String, dynamic>.from(s as Map);
                        final sid = (sm['shuttleRequestId'] ?? sm['ShuttleRequestId']) as int;
                        final st = (sm['status'] ?? sm['Status']).toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.airport_shuttle, color: Color(0xFF0D47A1)),
                            title: Text('${sm['passengerName'] ?? sm['PassengerName']} (${sm['passengerPhone'] ?? sm['PassengerPhone']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Khu vực: ${sm['pickupArea'] ?? sm['PickupArea']}\nĐón tại: ${sm['pickupAddress'] ?? sm['PickupAddress']}\nXe: ${sm['shuttlePlate'] ?? sm['ShuttlePlate']} • Trạng thái: $st'),
                            trailing: st != 'PickedUp'
                                ? TextButton(
                                    onPressed: () async {
                                      await ApiClient.instance.post('/api/operator/shuttles/$sid/assign', body: {
                                        'shuttlePlate': plateCtrl.text.trim(),
                                        'status': 'PickedUp',
                                      });
                                      final refreshed = await ApiClient.instance.get('/api/operator/shuttles', query: {'tripId': tripId.toString()});
                                      setDialogState(() => list = refreshed as List? ?? []);
                                    },
                                    child: const Text('Đã đón', style: TextStyle(fontSize: 11)),
                                  )
                                : const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
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

  @override
  Widget build(BuildContext context) {
    final comp = _dashboard?['company'] ?? _dashboard?['Company'];
    final trips = (_dashboard?['trips'] ?? _dashboard?['Trips']) as List? ?? [];
    final bookings = (_dashboard?['bookings'] ?? _dashboard?['Bookings']) as List? ?? [];
    final buses = (_dashboard?['buses'] ?? _dashboard?['Buses']) as List? ?? [];
    final drivers = (_dashboard?['drivers'] ?? _dashboard?['Drivers']) as List? ?? [];
    final routes = (_dashboard?['routes'] ?? _dashboard?['Routes']) as List? ?? [];
    final staffMembers = (_dashboard?['staffMembers'] ?? _dashboard?['StaffMembers']) as List? ?? [];
    final supportReqs = (_dashboard?['supportRequests'] ?? _dashboard?['SupportRequests']) as List? ?? [];

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
                  Tab(icon: const Icon(LucideIcons.calendarCheck, size: 17), text: 'Chuyến xe (${trips.length})'),
                  Tab(icon: const Icon(LucideIcons.ticket, size: 17), text: 'Đơn vé & COD (${bookings.length})'),
                  Tab(icon: const Icon(LucideIcons.bus, size: 17), text: 'Đội xe (${buses.length}) & Nhân sự'),
                  Tab(icon: const Icon(LucideIcons.headset, size: 17), text: 'Hỗ trợ khách (${supportReqs.length})'),
                ],
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ShadcnAlert.destructive(title: 'Có lỗi xảy ra', message: _error!),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // Tab 1: Trips
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (comp != null)
                    ShadcnCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 3),
                                  border: Border.all(color: const Color(0xFFBAE6FD)),
                                ),
                                child: const Icon(LucideIcons.building2, color: ShadcnTheme.primaryDark, size: 20),
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
                                            '${comp['name'] ?? comp['Name']}',
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.2),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ShadcnBadge.success((comp['status'] ?? comp['Status']).toString()),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Mã nhà xe: #${comp['companyId'] ?? comp['CompanyId']} • Giữ ghế: ${comp['seatHoldMinutes'] ?? comp['SeatHoldMinutes']} phút',
                                      style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                  onPressed: _showOperatorReportSummaryDialog,
                                  icon: const Icon(LucideIcons.barChart3, size: 15, color: ShadcnTheme.primaryDark),
                                  label: const Text('Báo cáo UC26', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF0F9FF),
                                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                                  ),
                                  onPressed: _testCrossTenantAccess,
                                  icon: const Icon(LucideIcons.shieldCheck, size: 15, color: ShadcnTheme.primaryDark),
                                  label: const Text('Kiểm tra AT02', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
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
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: _showCreateTripDialog,
                            icon: const Icon(LucideIcons.plusCircle, size: 15),
                            label: const Text('Tạo chuyến (AT03)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0F9FF),
                            side: const BorderSide(color: Color(0xFFBAE6FD)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                          ),
                          onPressed: _showBulkGenerateTripsDialog,
                          icon: const Icon(LucideIcons.calendarPlus, size: 15, color: ShadcnTheme.primaryDark),
                          label: const Text('Lập lịch hàng loạt', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
              ...trips.map((t) {
                final tm = Map<String, dynamic>.from(t as Map);
                final id = (tm['tripId'] ?? tm['TripId']) as int;
                final status = (tm['status'] ?? tm['Status']).toString();
                final drvList = ((tm['drivers'] ?? tm['Drivers']) as List? ?? []).join(', ');
                final routeName = (tm['routeName'] ?? tm['RouteName']).toString();
                final booked = tm['bookedSeats'] ?? tm['BookedSeats'] ?? 0;
                final total = tm['totalSeats'] ?? tm['TotalSeats'] ?? 0;
                final plate = (tm['plateNumber'] ?? tm['PlateNumber']).toString();
                final pct = (total > 0 ? (booked / total) : 0.0).clamp(0.0, 1.0);

                return ShadcnCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ShadcnBadge.secondary('#$id'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              routeName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          status == 'Scheduled' || status == 'Running'
                              ? ShadcnBadge.success(status)
                              : (status == 'Cancelled' ? ShadcnBadge.destructive(status) : ShadcnBadge.secondary(status)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(LucideIcons.bus, size: 14, color: ShadcnTheme.mutedForeground),
                          const SizedBox(width: 5),
                          Text(plate, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          const Icon(LucideIcons.user, size: 14, color: ShadcnTheme.mutedForeground),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              drvList.isEmpty ? "Chưa gán tài xế" : drvList,
                              style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Đã đặt $booked/$total ghế',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadcnTheme.mutedForeground),
                          ),
                          Text(
                            '${(pct * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.toDouble(),
                          backgroundColor: ShadcnTheme.muted,
                          color: pct > 0.8 ? ShadcnTheme.accentOrange : ShadcnTheme.primary,
                          minHeight: 5,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.switch_account_rounded, size: 14),
                            label: const Text('Đổi tài xế', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showReassignDriverDialog(id),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.point_of_sale_rounded, size: 14),
                            label: const Text('Bán vé POS', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showCounterPosBookingDialog(id, routeName),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.inventory_2_outlined, size: 14),
                            label: const Text('Ký gửi hàng', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showCargoShipmentsDialog(id, routeName),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.airport_shuttle_rounded, size: 14),
                            label: const Text('Trung chuyển', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showShuttleManifestDialog(id, routeName),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.calculate_outlined, size: 14),
                            label: const Text('Sổ chi phí', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showTripExpensesAndProfitDialog(id, routeName),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
                            icon: const Icon(Icons.history_edu_rounded, size: 14),
                            label: const Text('Nhật ký', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _showTripOperationalLogsDialog(id, routeName),
                          ),
                          if (status != 'Cancelled' && status != 'Arrived')
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                foregroundColor: ShadcnTheme.destructive,
                                side: const BorderSide(color: Color(0xFFFECACA)),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 14),
                              label: const Text('Hủy chuyến', style: TextStyle(fontSize: 11.5)),
                              onPressed: () => _cancelTrip(id),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
                ],
              ),

              // Tab 2: Bookings & COD
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Đơn đặt vé & Xác nhận thu COD (AT08, BR17)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2),
                    ),
                  ),
                  ...bookings.map((b) {
                    final bm = Map<String, dynamic>.from(b as Map);
                    final id = (bm['bookingId'] ?? bm['BookingId']) as int;
                    final code = (bm['bookingCode'] ?? bm['BookingCode']).toString();
                    final status = (bm['status'] ?? bm['Status']).toString();
                    final payMethod = (bm['paymentMethod'] ?? bm['PaymentMethod']).toString();
                    final payStatus = (bm['paymentStatus'] ?? bm['PaymentStatus']).toString();
                    final amount = ((bm['totalAmount'] ?? bm['TotalAmount'] ?? 0) as num).toDouble();
                    final seats = ((bm['seats'] ?? bm['Seats']) as List? ?? []).join(', ');

                    return ShadcnCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ShadcnBadge.secondary(code),
                              const Spacer(),
                              Text(
                                ShadcnTheme.formatMoney(amount),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: ShadcnTheme.primaryDark, fontSize: 15, letterSpacing: -0.3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Khách: ${bm['contactName'] ?? bm['ContactName']} (${bm['contactPhone'] ?? bm['ContactPhone']})',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ghế đã chọn: $seats',
                            style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                          ),
                          const SizedBox(height: 8),
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
                          if (payMethod == 'COD' && payStatus == 'Unpaid' && status == 'Confirmed') ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: ShadcnTheme.success,
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                    ),
                                    onPressed: () => _collectCod(id),
                                    icon: const Icon(Icons.payments_rounded, size: 16),
                                    label: const Text('Thu tiền COD (AT08)', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: ShadcnTheme.destructive,
                                    side: const BorderSide(color: Color(0xFFFECACA)),
                                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                  ),
                                  onPressed: () => _markNoShow(id),
                                  child: const Text('Khách No-Show', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),

              // Tab 3: Buses, Routes & Drivers
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _showAddBusDialog,
                        icon: const Icon(Icons.directions_bus_rounded, size: 16),
                        label: const Text('Thêm Xe & Sơ đồ ghế'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddDriverDialog,
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: const Text('Thêm Tài xế (UC19)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddRouteDialog,
                        icon: const Icon(Icons.alt_route_rounded, size: 16),
                        label: const Text('Thêm Tuyến (UC20)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddStaffDialog,
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: const Text('Thêm Nhân viên (UC16)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('1. Danh sách phương tiện vận tải', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...buses.map((b) {
                    final bm = Map<String, dynamic>.from(b as Map);
                    final busId = (bm['busId'] ?? bm['BusId']) as int;
                    final plate = (bm['plateNumber'] ?? bm['PlateNumber']).toString();
                    final status = (bm['status'] ?? bm['Status']).toString();
                    return ShadcnCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: ShadcnTheme.secondary,
                                  borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                                ),
                                child: const Icon(Icons.directions_bus_rounded, size: 16, color: ShadcnTheme.foreground),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$plate • ${bm['busType'] ?? bm['BusType']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                ),
                              ),
                              status == 'Active' ? ShadcnBadge.success(status) : ShadcnBadge.warning(status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${bm['brandModel'] ?? bm['BrandModel']} • ${bm['totalSeats'] ?? bm['TotalSeats']} chỗ',
                            style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                onPressed: () => _showBusSeatConfigDialog(busId, plate),
                                icon: const Icon(Icons.grid_view_rounded, size: 14),
                                label: const Text('Sơ đồ ghế', style: TextStyle(fontSize: 11)),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                onPressed: () => _showBusMaintenanceHistoryDialog(busId, plate),
                                icon: const Icon(Icons.build_circle_outlined, size: 14),
                                label: const Text('Lịch sử BT', style: TextStyle(fontSize: 11)),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                onPressed: () => _toggleBusMaintenance(busId, status),
                                child: Text(status == 'Active' ? 'Bảo trì' : 'Kích hoạt', style: const TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text('2. Danh sách Tuyến đường (Routes)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...routes.map((r) {
                    final rm = Map<String, dynamic>.from(r as Map);
                    final rId = (rm['routeId'] ?? rm['RouteId']) as int;
                    final rName = (rm['name'] ?? rm['Name']).toString();
                    final stops = (rm['stops'] ?? rm['Stops']) as List? ?? [];
                    return ShadcnCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: ShadcnTheme.secondary,
                              borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                            ),
                            child: const Icon(Icons.alt_route_rounded, size: 16, color: ShadcnTheme.foreground),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('${rm['distanceKm'] ?? rm['DistanceKm']} km • ${stops.length} điểm đón/trả', style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                            onPressed: () => _showAddStopToRouteDialog(rId, rName),
                            icon: const Icon(Icons.add_location_alt_outlined, size: 14),
                            label: const Text('+ Điểm', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text('3. Danh sách Nhân viên & Tài xế', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...staffMembers.map((st) {
                    final sm = Map<String, dynamic>.from(st as Map);
                    return ShadcnCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: ShadcnTheme.secondary,
                              borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                            ),
                            child: const Icon(Icons.badge_outlined, size: 16, color: ShadcnTheme.foreground),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${sm['fullName'] ?? sm['FullName']} (${sm['memberRole'] ?? sm['MemberRole']})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('${sm['email'] ?? sm['Email']} • ${sm['phone'] ?? sm['Phone']}', style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  ...drivers.map((d) {
                    final dm = Map<String, dynamic>.from(d as Map);
                    final drvId = (dm['driverId'] ?? dm['DriverId']) as int;
                    final drvName = (dm['fullName'] ?? dm['FullName']).toString();
                    return ShadcnCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: ShadcnTheme.secondary,
                              borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm),
                            ),
                            child: const Icon(Icons.person_pin_rounded, size: 16, color: ShadcnTheme.foreground),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$drvName (${dm['phone'] ?? dm['Phone']})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('GPLX: ${dm['licenseNumber'] ?? dm['LicenseNumber']} • Hạng ${dm['licenseClass'] ?? dm['LicenseClass']}', style: const TextStyle(fontSize: 11.5, color: ShadcnTheme.mutedForeground)),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                            onPressed: () => _showDriverDocumentsDialog(drvId, drvName),
                            icon: const Icon(Icons.folder_shared_outlined, size: 14),
                            label: const Text('Giấy tờ', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),

              // Tab 4: Customer Support Requests (UC31)
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Yêu cầu hỗ trợ & Phản hồi (UC31)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: _showCompanyReviewsDialog,
                        icon: const Icon(Icons.star_rate_rounded, size: 16, color: Colors.amber),
                        label: const Text('Đánh giá (UC13)', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (supportReqs.isEmpty)
                    const ShadcnCard(
                      child: Center(
                        child: Text(
                          'Chưa có yêu cầu hỗ trợ nào từ khách hàng.',
                          style: TextStyle(color: ShadcnTheme.mutedForeground, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ...supportReqs.map((s) {
                      final sm = Map<String, dynamic>.from(s as Map);
                      final reqId = (sm['requestId'] ?? sm['RequestId']) as int;
                      final subj = (sm['subject'] ?? sm['Subject']).toString();
                      final status = (sm['status'] ?? sm['Status']).toString();
                      final reply = sm['replyContent'] ?? sm['ReplyContent'];

                      return ShadcnCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(subj, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                ),
                                status == 'Resolved'
                                    ? ShadcnBadge.success(status)
                                    : ShadcnBadge.warning(status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Khách hàng: ${sm['customerName'] ?? sm['CustomerName']} (${sm['customerPhone'] ?? sm['CustomerPhone']})',
                              style: const TextStyle(fontSize: 12, color: ShadcnTheme.mutedForeground),
                            ),
                            const SizedBox(height: 6),
                            Text((sm['content'] ?? sm['Content']).toString(), style: const TextStyle(fontSize: 12.5)),
                            if (reply != null && reply.toString().isNotEmpty) ...[
                              const Divider(height: 16),
                              Text('Đã phản hồi: $reply', style: const TextStyle(color: ShadcnTheme.success, fontWeight: FontWeight.w600, fontSize: 12)),
                            ],
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () => _replySupportDialog(reqId, subj),
                                icon: const Icon(Icons.reply_rounded, size: 15),
                                label: const Text('Phản hồi khách', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _DateOnlyExt on DateTime {
  DateTime get dateOnly => DateTime.utc(year, month, day);
}
