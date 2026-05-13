/// E-26-10c: File drop zone for desktop.
///
/// Uses desktop_drop package. Drop files on:
/// - Chat pane: adds as attachments to the current message
/// - Sidebar: drops to a topic become memories
import 'package:flutter/material.dart';

/// Wraps a child widget to accept file drops on desktop.
///
/// On mobile, this is a no-op passthrough.
class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Called when files are dropped. Paths are absolute file system paths.
  final void Function(List<String> filePaths) onFilesDropped;

  /// Visual feedback text shown during hover.
  final String hintText;

  const FileDropZone({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.hintText = 'Drop files here',
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // desktop_drop integration:
    // return DropTarget(
    //   onDragEntered: (_) => setState(() => _hovering = true),
    //   onDragExited: (_) => setState(() => _hovering = false),
    //   onDragDone: (details) {
    //     setState(() => _hovering = false);
    //     final paths = details.files.map((f) => f.path).toList();
    //     widget.onFilesDropped(paths);
    //   },
    //   child: _buildChild(context),
    // );

    // Passthrough until desktop_drop is added to pubspec.
    return widget.child;
  }

  Widget _buildChild(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        widget.child,
        if (_hovering)
          Positioned.fill(
            child: Container(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_download,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.hintText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
