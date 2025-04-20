import 'package:draggable_carousel_slider/enums/drag_direction.dart';
import 'package:draggable_carousel_slider/draggable_carousel_slider_item_settings.dart';
import 'package:draggable_carousel_slider/widgets/measure_size.dart';
import 'package:flutter/material.dart';

import 'package:vector_math/vector_math.dart' show Vector3;

class DraggableSliderItem extends StatefulWidget {
  final Widget child;
  final DraggableSliderItemSettings settings;
  final DraggableSliderItemSettings? initialSettings;
  final Function(Key?, DragDirection)? onRelease;
  final Function(Key?)? onReleased;

  const DraggableSliderItem({
    super.key,
    required this.child,
    required this.settings,
    this.initialSettings,
    this.onRelease,
    this.onReleased,
  });

  @override
  DraggableSliderItemState createState() => DraggableSliderItemState();
}

class DraggableSliderItemState extends State<DraggableSliderItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late CurvedAnimation _animation;
  late Animation<Offset> _positionTween;
  late Animation<Matrix4> _tranformTween;
  late Size _screenSize;

  final key = GlobalKey();

  var _isPositionAnimating = false;
  var _itemPosition = Offset.zero;
  Offset? _itemGlobalPosition;
  var _widgetSize = Size.zero;

  @override
  void initState() {
    super.initState();

    const duration = Duration(seconds: 1);
    _animationController = AnimationController(vsync: this, duration: duration);
    _animationController.addStatusListener(onAnimationControllerStatusChanged);

    const curve = Curves.easeOut;
    _animation = CurvedAnimation(parent: _animationController, curve: curve);

    _animateItem(widget.initialSettings ?? widget.settings, widget.settings);
  }

  @override
  void didChangeDependencies() {
    _screenSize = MediaQuery
        .of(context)
        .size;

    super.didChangeDependencies();
  }

  TickerFuture? _animateItem(DraggableSliderItemSettings from,
      DraggableSliderItemSettings to,) {
    final initialState = _computeTransformMatrix(from);
    final finalState = _computeTransformMatrix(to);
    _tranformTween = Tween<Matrix4>(
      begin: initialState,
      end: finalState,
    ).animate(_animation);

    if (to.position != null) {
      _positionTween = Tween<Offset>(
        begin: _itemPosition,
        end: to.position!,
      ).animate(_animation);
      _itemPosition = to.position!;
    }

    if (from != to) {
      if (to.position != null) _isPositionAnimating = true;

      return _animationController.forward(from: 0);
    }

    return null;
  }

  @override
  void didUpdateWidget(covariant DraggableSliderItem oldWidget) {
    if (oldWidget.settings != widget.settings) {
      _animateItem(oldWidget.settings, widget.settings);
    }

    super.didUpdateWidget(oldWidget);
  }
  Offset? _startPosition;
  double _dragThreshold = 30.0;

  bool get draggable =>
      widget.settings.draggable && !_animationController.isAnimating;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _positionTween,
      builder: (context, child) =>
          Transform.translate(
            offset: Offset(
              (_isPositionAnimating ? _positionTween.value : _itemPosition).dx,
              (_isPositionAnimating ? _positionTween.value : _itemPosition).dy,
            ),
            child: child!,
          ),
      child: GestureDetector(
        onPanStart: (details) {
          _startPosition = details.localPosition;
        },
        onPanUpdate: (details) {
          if (_startPosition != null) {
            final distance = (_startPosition! - details.localPosition).distance;
            onDragging.call(details);
          }
        },
        onPanEnd: (details) {
          if (_startPosition != null) {
            final distance = (_startPosition! - details.localPosition).distance;
            if (distance < _dragThreshold) {
            } else {
              onDropped.call(details);
            }
          }
        },
        child: AnimatedBuilder(
          animation: _tranformTween,
          child: widget.child,
          builder: (context, child) => Transform(
            transform: (_tranformTween.value != null) ? _tranformTween.value : Matrix4.identity(),
            alignment: FractionalOffset.center,
            child: AnimatedContainer(
              key: key,
              duration: const Duration(seconds: 1),
              decoration: BoxDecoration(
                boxShadow: widget.settings.shadow
                    ? [
                  const BoxShadow(
                    color: Colors.black54,
                    offset: Offset(0, 32),
                    blurRadius: 32,
                  )
                ]
                    : null,
              ),
              child: MeasureSize(
                onChange: onChildSizeChanged,
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onDropped(details) {
    try {
      if (!draggable) return;
      _itemGlobalPosition = null;

      final slope = (_itemPosition.dx / _itemPosition.dy).abs();
      var targetPosition = Offset(
        _itemPosition.dx.sign * _screenSize.width * slope,
        _itemPosition.dy.sign * _screenSize.height * slope,
      );

      final magnitude = targetPosition.distance;
      final scaleFactor = magnitude / _screenSize.longestSide;

      targetPosition = Offset(
        targetPosition.dx / scaleFactor,
        targetPosition.dy / scaleFactor,
      );

      final direction = _itemPosition.dx < 0 ? DragDirection.left : DragDirection.right;

      _animateItem(
        widget.settings,
        DraggableSliderItemSettings(
          angle: direction == DragDirection.right
              ? Vector3(0, 0, 0.6)
              : Vector3(0, 0, -0.6),
          position: targetPosition,
        ),
      )?.whenComplete(() => widget.onReleased!(widget.key));

      if (widget.onRelease != null) {
        widget.onRelease!(widget.key, direction);
      }
    }
    catch (e) {}
  }

  void onDragging(DragUpdateDetails details) {
    try {
      if (!draggable) return;
      if (_itemGlobalPosition == null) {
        final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
        _itemGlobalPosition = renderBox?.localToGlobal(Offset.zero);
        _itemGlobalPosition ??= Offset.zero;
      }

      _itemPosition += details.delta;

      _itemPosition = Offset(
        _itemPosition.dx.clamp(
          -_itemGlobalPosition!.dx,
          _screenSize.width - _itemGlobalPosition!.dx - _widgetSize.width,
        ),
        _itemPosition.dy.clamp(
          -_itemGlobalPosition!.dy,
          _screenSize.height - _itemGlobalPosition!.dy - _widgetSize.height,
        ),
      );

      setState(() {});
    }
    catch (e) {}
  }

  Matrix4 _computeTransformMatrix(DraggableSliderItemSettings settings) {
    final matrix = Matrix4.identity();

    if (settings.scale != null) {
      matrix.scale(settings.scale!);
    }

    if (settings.angle != null) {
      matrix
        ..rotateX(settings.angle!.x)
        ..rotateY(settings.angle!.y)
        ..rotateZ(settings.angle!.z);
    }

    return matrix;
  }

  void onChildSizeChanged(Size size) {
    _widgetSize = size;
  }

  void onAnimationControllerStatusChanged(AnimationStatus status) {
    if (_isPositionAnimating && status == AnimationStatus.completed) {
      _isPositionAnimating = false;
    }
  }

  @override
  void dispose() {
    _animationController
        .removeStatusListener(onAnimationControllerStatusChanged);
    _animationController.dispose();
    super.dispose();
  }
}
