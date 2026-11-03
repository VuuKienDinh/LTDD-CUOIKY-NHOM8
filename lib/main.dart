import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'services/api_client.dart';
import 'theme/shadcn_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/customer_shell.dart';
import 'screens/driver_screen.dart';
import 'screens/operator_screen.dart';
import 'screens/admin_screen.dart';

import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }
  runApp(const BusTicketBookingApp());
}

class BusTicketBookingApp extends StatelessWidget {
  const BusTicketBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ApiClient.instance,
      builder: (context, _) {
        final showWorkspace =
            ApiClient.instance.isLoggedIn || ApiClient.instance.isGuestMode;

        return MaterialApp(
          title: 'BusTicketBooking',
          debugShowCheckedModeBanner: false,
          theme: ShadcnTheme.themeData,
          home: showWorkspace ? const RoleWorkspaceShell() : const AuthScreen(),
        );
      },
    );
  }
}

class RoleWorkspaceShell extends StatefulWidget {
  const RoleWorkspaceShell({super.key});

  @override
  State<RoleWorkspaceShell> createState() => _RoleWorkspaceShellState();
}

class _RoleWorkspaceShellState extends State<RoleWorkspaceShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isGuest = ApiClient.instance.isGuestMode && !ApiClient.instance.isLoggedIn;
    final user = ApiClient.instance.currentUser ?? {};
    final fullName = isGuest
        ? 'Khách vãng lai'
        : (user['fullName'] ?? user['FullName'] ?? 'Người dùng').toString();
    final roles = isGuest ? const ['Guest'] : ApiClient.instance.roles;

    final isAdmin = roles.contains('Admin');
    final isOperator = roles.contains('BusOperator') || isAdmin;
    final isStaffOrDriver =
        roles.contains('Driver') || roles.contains('Staff') || isOperator;

    final pages = <Widget>[
      const CustomerPortalView(),
      if (!isGuest && isStaffOrDriver) const DriverOperationsView(),
      if (!isGuest && (isOperator || roles.contains('Staff'))) const OperatorManagementView(),
      if (!isGuest && (isAdmin || isOperator)) const AdminAndReportsView(),
    ];

    final navItems = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(LucideIcons.ticket, size: 18),
        selectedIcon: Icon(LucideIcons.ticket, size: 18),
        label: 'Đặt vé',
      ),
      if (!isGuest && isStaffOrDriver)
        NavigationDestination(
          icon: const Icon(LucideIcons.qrCode, size: 18),
          selectedIcon: const Icon(LucideIcons.qrCode, size: 18),
          label: roles.contains('Staff') ? 'Soát vé QR' : 'Tài xế / Soát vé',
        ),
      if (!isGuest && (isOperator || roles.contains('Staff')))
        const NavigationDestination(
          icon: Icon(LucideIcons.bus, size: 18),
          selectedIcon: Icon(LucideIcons.bus, size: 18),
          label: 'Nhà xe',
        ),
      if (!isGuest && (isAdmin || isOperator))
        const NavigationDestination(
          icon: Icon(LucideIcons.barChart3, size: 18),
          selectedIcon: Icon(LucideIcons.barChart3, size: 18),
          label: 'Quản trị',
        ),
    ];

    final safeIndex = _selectedIndex >= pages.length ? 0 : _selectedIndex;
    final companyText = (user['companyName'] ?? user['CompanyName'])?.toString();

    return Scaffold(
      backgroundColor: ShadcnTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: Container(
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
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Ocean Gradient Logo Mark
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: ShadcnTheme.oceanGradient,
                          borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
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
                      // User identity
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ShadcnTheme.foreground,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ShadcnBadge.secondary(roles.first),
                              ],
                            ),
                            if (companyText != null && companyText.isNotEmpty) ...[
                              Text(
                                companyText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ShadcnTheme.primaryDark),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Switch Role button (ocean glass outline)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF0F9FF),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm)),
                        ),
                        onPressed: () {
                          setState(() => _selectedIndex = 0);
                          ApiClient.instance.logout();
                        },
                        icon: Icon(
                          isGuest ? LucideIcons.logIn : LucideIcons.users,
                          size: 14,
                          color: ShadcnTheme.primaryDark,
                        ),
                        label: Text(
                          isGuest ? 'Đăng nhập' : 'Đổi vai trò',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ShadcnTheme.primaryDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: pages[safeIndex],
      bottomNavigationBar: navItems.length > 1
          ? Container(
              decoration: const BoxDecoration(
                color: ShadcnTheme.surfaceGlass,
                border: Border(top: BorderSide(color: ShadcnTheme.glassBorder, width: 1.2)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A0369A1),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: NavigationBar(
                    height: 60,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: const Color(0xFFE0F2FE),
                    indicatorShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ShadcnTheme.radiusSm + 2),
                      side: const BorderSide(color: Color(0xFFBAE6FD), width: 1),
                    ),
                    selectedIndex: safeIndex,
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
                    destinations: navItems,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
