import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/services/navigation_history_service.dart';

class DesktopTitleBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final VoidCallback? onRefresh;
  final bool isUploadInProgress;

  const DesktopTitleBar({
    super.key,
    this.onRefresh,
    this.isUploadInProgress = false,
  });

  @override
  ConsumerState<DesktopTitleBar> createState() => _DesktopTitleBarState();

  @override
  Size get preferredSize => const Size.fromHeight(48);
}

class _DesktopTitleBarState extends ConsumerState<DesktopTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final max = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = max;
        });
      }
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _handleClose(BuildContext context) async {
    if (widget.isUploadInProgress) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Cancel Upload?"),
          content: const Text("A document analysis is in progress. Closing the app now will cancel it. Proceed?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Keep Uploading"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kError),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Close App"),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return const SizedBox.shrink();
    }

    final navService = ref.watch(navigationHistoryProvider);

    return DragToMoveArea(
      child: GestureDetector(
        onDoubleTap: _toggleMaximize,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: kSurface,
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.08),
                width: 1.0,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Left side - App Branding
              const Icon(Icons.camera_enhance, color: kPrimary, size: 20),
              const SizedBox(width: 8),
              const Text(
                "MemoryLens AI",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 24),

              // Navigation Buttons
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: navService.canGoBack ? () => navService.goBack(context) : null,
                tooltip: "Back",
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: navService.canGoForward ? () => navService.goForward(context) : null,
                tooltip: "Forward",
              ),
              _isRefreshing
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Padding(
                        padding: EdgeInsets.all(10.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: widget.onRefresh == null
                          ? null
                          : () async {
                              setState(() => _isRefreshing = true);
                              widget.onRefresh!();
                              await Future.delayed(const Duration(seconds: 1));
                              if (mounted) setState(() => _isRefreshing = false);
                            },
                      tooltip: "Refresh Page",
                    ),
              const SizedBox(width: 16),

              // Address Bar / Breadcrumbs
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: kCardColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: navService.breadcrumbs.length,
                    separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 14, color: Colors.white30),
                    itemBuilder: (context, idx) {
                      final segment = navService.breadcrumbs[idx];
                      return TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          // Clickable Breadcrumbs Navigation
                          if (segment.toLowerCase() == 'dashboard') {
                            navService.navigateTo('/dashboard', context);
                          } else if (segment.toLowerCase() == 'capture') {
                            navService.navigateTo('/capture', context);
                          } else if (segment.toLowerCase() == 'settings') {
                            navService.navigateTo('/settings', context);
                          } else if (segment.toLowerCase() == 'search') {
                            navService.navigateTo('/search', context);
                          }
                        },
                        child: Text(
                          segment,
                          style: TextStyle(
                            fontSize: 12,
                            color: idx == navService.breadcrumbs.length - 1 ? kPrimary : Colors.white70,
                            fontWeight: idx == navService.breadcrumbs.length - 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Window minimize/maximize/close Controls
              IconButton(
                icon: const Icon(Icons.minimize, size: 18),
                onPressed: () => windowManager.minimize(),
                tooltip: "Minimize",
              ),
              IconButton(
                icon: Icon(
                  _isMaximized ? Icons.fullscreen_exit : Icons.crop_square,
                  size: 18,
                ),
                onPressed: _toggleMaximize,
                tooltip: _isMaximized ? "Restore" : "Maximize",
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                hoverColor: kError.withOpacity(0.2),
                onPressed: () => _handleClose(context),
                tooltip: "Close",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
