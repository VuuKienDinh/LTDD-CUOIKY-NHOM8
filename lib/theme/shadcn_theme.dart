import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ShadcnTheme {
  // Ocean Blue & Crisp White Palette
  static const Color background = Color(0xFFF0F7FF); // Crystal-clear ice blue mist
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceGlass = Color(0xF5FFFFFF); // 96% opacity pure white frosted glass
  static const Color foreground = Color(0xFF0F172A); // Slate 900 - ultra crisp text
  static const Color muted = Color(0xFFF1F5F9); // Slate 100
  static const Color mutedForeground = Color(0xFF64748B); // Slate 500
  static const Color border = Color(0xFFE2E8F0); // Crisp light border
  static const Color glassBorder = Color(0x66BAE6FD); // Sky glass translucent border
  static const Color input = Color(0xFFF8FAFC);
  static const Color ring = Color(0xFF38BDF8);

  // Ocean Blue Primary Action
  static const Color primary = Color(0xFF0284C7); // Sky/Ocean Blue 600
  static const Color primaryDark = Color(0xFF0369A1); // Deep Ocean 700
  static const Color primaryLight = Color(0xFF38BDF8); // Ocean Sky 400
  static const Color primaryForeground = Color(0xFFFFFFFF);

  // Ocean Secondary (Soft Ice Sky Tint)
  static const Color secondary = Color(0xFFE0F2FE); // Sky 100
  static const Color secondaryForeground = Color(0xFF0369A1); // Deep Ocean

  // Semantic
  static const Color accentBlue = Color(0xFF0284C7);
  static const Color accentOrange = Color(0xFFEA580C);
  static const Color destructive = Color(0xFFDC2626);
  static const Color destructiveBg = Color(0xFFFEF2F2);
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFF0FDF4);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFFFBEB);

  // Ocean Gradients
  static const LinearGradient oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0369A1), Color(0xFF0284C7), Color(0xFF0EA5E9)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF5FFFFFF), Color(0xEBEEF7FE)],
  );

  // Radii
  static const double radiusSm = 6.0;
  static const double radius = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 18.0;

  // Box Shadows (Glassmorphism & Crisp Floating)
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x080284C7),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static String formatMoney(num amount) {
    final s = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} đ';
  }

  static const List<BoxShadow> shadowGlass = [
    BoxShadow(
      color: Color(0x0D0369A1),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x120369A1),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  // ThemeData configuration with Be Vietnam Pro font
  static ThemeData get themeData {
    final baseTextTheme = ThemeData.light().textTheme;
    final beVietnamTheme = GoogleFonts.beVietnamProTextTheme(baseTextTheme).apply(
      bodyColor: foreground,
      displayColor: foreground,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      textTheme: beVietnamTheme,
      colorScheme: const ColorScheme.light(
        surface: surface,
        primary: primary,
        secondary: secondary,
        error: destructive,
        onPrimary: primaryForeground,
        onSurface: foreground,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: glassBorder, width: 1.2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: mutedForeground, fontSize: 13.5),
        labelStyle: const TextStyle(color: mutedForeground, fontSize: 13.5, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: destructive, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: primaryDark,
          elevation: 0,
          side: const BorderSide(color: border, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondary,
        disabledColor: muted,
        selectedColor: primary,
        secondarySelectedColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: const BorderSide(color: border, width: 0.8),
        ),
        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: secondaryForeground),
        secondaryLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: primaryForeground),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: -0.3,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

// Shadcn Badge helper (Ocean Blue styled)
class ShadcnBadge extends StatelessWidget {
  final String text;
  final Widget? icon;
  final Color? bg;
  final Color? fg;
  final Color? border;
  final bool outline;

  const ShadcnBadge({
    super.key,
    required this.text,
    this.icon,
    this.bg,
    this.fg,
    this.border,
    this.outline = false,
  });

  factory ShadcnBadge.outline(String text, {Widget? icon, Color? color}) {
    return ShadcnBadge(
      text: text,
      icon: icon,
      bg: Colors.transparent,
      fg: color ?? ShadcnTheme.primaryDark,
      border: color?.withValues(alpha: 0.35) ?? ShadcnTheme.border,
      outline: true,
    );
  }

  factory ShadcnBadge.secondary(String text, {Widget? icon}) {
    return ShadcnBadge(
      text: text,
      icon: icon,
      bg: ShadcnTheme.secondary,
      fg: ShadcnTheme.secondaryForeground,
      border: const Color(0xFFBAE6FD),
    );
  }

  factory ShadcnBadge.success(String text, {Widget? icon}) {
    return ShadcnBadge(
      text: text,
      icon: icon,
      bg: ShadcnTheme.successBg,
      fg: ShadcnTheme.success,
      border: const Color(0xFFBBF7D0),
    );
  }

  factory ShadcnBadge.destructive(String text, {Widget? icon}) {
    return ShadcnBadge(
      text: text,
      icon: icon,
      bg: ShadcnTheme.destructiveBg,
      fg: ShadcnTheme.destructive,
      border: const Color(0xFFFECACA),
    );
  }

  factory ShadcnBadge.warning(String text, {Widget? icon}) {
    return ShadcnBadge(
      text: text,
      icon: icon,
      bg: ShadcnTheme.warningBg,
      fg: ShadcnTheme.warning,
      border: const Color(0xFFFDE68A),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? ShadcnTheme.secondary,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border ?? ShadcnTheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg ?? ShadcnTheme.secondaryForeground,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// Shadcn Card container with Frosted Glass (Glassmorphism)
class ShadcnCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final bool isGlass;

  const ShadcnCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.isGlass = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? (isGlass ? const Color(0xF5FFFFFF) : ShadcnTheme.surface);
    final effectiveBorder = borderColor ?? (isGlass ? ShadcnTheme.glassBorder : ShadcnTheme.border);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(ShadcnTheme.radiusLg),
        border: Border.all(color: effectiveBorder, width: 1.2),
        boxShadow: isGlass ? ShadcnTheme.shadowGlass : ShadcnTheme.shadowSm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShadcnTheme.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(ShadcnTheme.radiusLg),
              onTap: onTap,
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Shadcn Segmented Tab bar
class ShadcnTabs extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  final List<IconData>? icons;

  const ShadcnTabs({
    super.key,
    required this.controller,
    required this.tabs,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ShadcnTheme.muted,
        borderRadius: BorderRadius.circular(ShadcnTheme.radius),
        border: Border.all(color: ShadcnTheme.border.withValues(alpha: 0.6), width: 1),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: ShadcnTheme.surface,
          borderRadius: BorderRadius.circular(ShadcnTheme.radius - 2),
          border: Border.all(color: ShadcnTheme.border, width: 0.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: ShadcnTheme.foreground,
        unselectedLabelColor: ShadcnTheme.mutedForeground,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: -0.2),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, letterSpacing: -0.2),
        tabs: List.generate(tabs.length, (i) {
          return Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icons != null && i < icons!.length) ...[
                  Icon(icons![i], size: 14),
                  const SizedBox(width: 5),
                ],
                Flexible(child: Text(tabs[i], overflow: TextOverflow.ellipsis)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// Shadcn Alert / Callout
class ShadcnAlert extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? trailing;
  final Color? bg;
  final Color? fg;
  final Color? borderColor;

  const ShadcnAlert({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.trailing,
    this.bg,
    this.fg,
    this.borderColor,
  });

  factory ShadcnAlert.destructive({required String title, String? message, Widget? trailing}) {
    return ShadcnAlert(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      trailing: trailing,
      bg: ShadcnTheme.destructiveBg,
      fg: ShadcnTheme.destructive,
      borderColor: const Color(0xFFFECACA),
    );
  }

  factory ShadcnAlert.warning({required String title, String? message, Widget? trailing}) {
    return ShadcnAlert(
      icon: Icons.warning_amber_rounded,
      title: title,
      message: message,
      trailing: trailing,
      bg: ShadcnTheme.warningBg,
      fg: ShadcnTheme.warning,
      borderColor: const Color(0xFFFDE68A),
    );
  }

  factory ShadcnAlert.info({required String title, String? message, Widget? trailing}) {
    return ShadcnAlert(
      icon: Icons.info_outline_rounded,
      title: title,
      message: message,
      trailing: trailing,
      bg: const Color(0xFFEFF6FF),
      fg: const Color(0xFF1D4ED8),
      borderColor: const Color(0xFFBFDBFE),
    );
  }

  factory ShadcnAlert.success({required String title, String? message, Widget? trailing}) {
    return ShadcnAlert(
      icon: Icons.check_circle_outline_rounded,
      title: title,
      message: message,
      trailing: trailing,
      bg: ShadcnTheme.successBg,
      fg: ShadcnTheme.success,
      borderColor: const Color(0xFFBBF7D0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg ?? ShadcnTheme.muted,
        borderRadius: BorderRadius.circular(ShadcnTheme.radius),
        border: Border.all(color: borderColor ?? ShadcnTheme.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg ?? ShadcnTheme.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg ?? ShadcnTheme.foreground,
                    letterSpacing: -0.2,
                  ),
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: (fg ?? ShadcnTheme.foreground).withValues(alpha: 0.85),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// Shadcn Stat / KPI Card
class ShadcnStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;

  const ShadcnStatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShadcnTheme.surface,
        borderRadius: BorderRadius.circular(ShadcnTheme.radiusLg),
        border: Border.all(color: ShadcnTheme.border, width: 1),
        boxShadow: ShadcnTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShadcnTheme.mutedForeground,
                    letterSpacing: -0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Icon(icon, size: 16, color: iconColor ?? ShadcnTheme.mutedForeground),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ShadcnTheme.foreground,
              letterSpacing: -0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: ShadcnTheme.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// Shadcn Top Header App Bar with Frosted Glass
class ShadcnAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;

  const ShadcnAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (leading != null) leading!,
                  if (leading == null && Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 20, color: ShadcnTheme.primaryDark),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Quay lại',
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ShadcnTheme.foreground,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: ShadcnTheme.primaryDark,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shadcn Skeleton Loading component with smooth shimmer
class ShadcnSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const ShadcnSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = ShadcnTheme.radiusSm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE4E4E7),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1200.ms, color: const Color(0xFFFAFAFA));
  }
}
