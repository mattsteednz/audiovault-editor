import 'package:flutter/material.dart';

/// A sidebar widget with a draggable resize handle at the right edge.
/// Width is constrained between [minWidth] and [maxWidth].
/// Calls [onWidthChanged] when the user finishes dragging.
class ResizableSidebar extends StatefulWidget {
  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onWidthChanged;

  const ResizableSidebar({
    super.key,
    required this.child,
    this.initialWidth = 300,
    this.minWidth = 250,
    this.maxWidth = 500,
    required this.onWidthChanged,
  });

  @override
  State<ResizableSidebar> createState() => _ResizableSidebarState();
}

class _ResizableSidebarState extends State<ResizableSidebar> {
  late double _currentWidth;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.initialWidth.clamp(widget.minWidth, widget.maxWidth);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentWidth =
          (_currentWidth + details.delta.dx).clamp(widget.minWidth, widget.maxWidth);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _isDragging = false);
    widget.onWidthChanged(_currentWidth);
  }

  void _onPanStart(DragStartDetails _) {
    setState(() => _isDragging = true);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _currentWidth,
          child: widget.child,
        ),
        // Resize handle — a thin vertical strip on the right edge
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 5,
              color: _isDragging
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
