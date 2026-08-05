import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:second/log_inst.dart';
import 'package:xml/xml.dart';

class KeyEvent {
  final String key;
  final DateTime timestamp;

  KeyEvent(this.key) : timestamp = DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyEvent &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          timestamp == other.timestamp;

  @override
  int get hashCode => key.hashCode ^ timestamp.hashCode;
}

// Event bus for virtual keyboard events
class VirtualKeyEventBus {
  static VirtualKeyEventBus? _instance;
  static VirtualKeyEventBus get instance {
    _instance ??= VirtualKeyEventBus._internal();
    return _instance!;
  }

  VirtualKeyEventBus._internal();

  final ValueNotifier<KeyEvent?> _keyEventNotifier = ValueNotifier<KeyEvent?>(
    null,
  );
  ValueNotifier<KeyEvent?> get keyEventNotifier => _keyEventNotifier;

  void emitKeyEvent(String key) {
    _keyEventNotifier.value = KeyEvent(key);
  }

  void dispose() {
    _keyEventNotifier.dispose();
  }
}

// Virtual TextField that responds to virtual keyboard events
class VirtualTextField extends StatefulWidget {
  final String? hintText;
  final bool requireFocus;
  final TextStyle? style;
  final InputDecoration? decoration;
  final int? maxLines;
  final Function(String)? onChanged;
  final TextEditingController? controller;

  const VirtualTextField({
    super.key,
    this.hintText,
    this.requireFocus = true,
    this.style,
    this.decoration,
    this.maxLines = 1,
    this.onChanged,
    this.controller,
  });

  @override
  State<VirtualTextField> createState() => _VirtualTextFieldState();
}

class _VirtualTextFieldState extends State<VirtualTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isInternalController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController();
      _isInternalController = true;
    } else {
      _controller = widget.controller!;
    }
    _focusNode = FocusNode();

    // Listen to virtual key events
    VirtualKeyEventBus.instance.keyEventNotifier.addListener(
      _onVirtualKeyEvent,
    );
  }

  @override
  void didUpdateWidget(covariant VirtualTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_isInternalController) {
        _controller.dispose();
      }
      if (widget.controller == null) {
        _controller = TextEditingController();
        _isInternalController = true;
      } else {
        _controller = widget.controller!;
        _isInternalController = false;
      }
    }
  }

  @override
  void dispose() {
    VirtualKeyEventBus.instance.keyEventNotifier.removeListener(
      _onVirtualKeyEvent,
    );
    if (_isInternalController) {
      _controller.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _onVirtualKeyEvent() {
    final key = VirtualKeyEventBus.instance.keyEventNotifier.value;
    if (key == null) return;
    // if (widget.requireFocus && !_focusNode.hasFocus) return;

    switch (key.key) {
      case 'backspace':
        if (_controller.selection.isCollapsed) {
          // No selection, delete previous character
          if (_controller.text.isEmpty) return;
          final newText = _controller.text.substring(
            0,
            _controller.text.length - 1,
          );
          _controller.value = TextEditingValue(text: newText);
        } else {
          // Has selection, delete selected text
          _controller.text = _controller.text.replaceRange(
            _controller.selection.start,
            _controller.selection.end,
            '',
          );
          _controller.selection = TextSelection.collapsed(
            offset: _controller.selection.start,
          );
        }
        break;
      case 'return':
        if (widget.maxLines != 1) {
          final text = _controller.text;
          final newText = '$text\n'; // Add newline for multi-line text
          _controller.value = TextEditingValue(text: newText);
        }
        break;
      default:
      // Insert the character
        final text = _controller.text;
        final newText = text + key.key;
        _controller.value = TextEditingValue(text: newText);
    }
    widget.onChanged?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: widget.style,
      maxLines: widget.maxLines,
      decoration:
      widget.decoration ??
          InputDecoration(
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
          ),
      // Disable physical keyboard input
      keyboardType: TextInputType.none,
      showCursor: true,
      readOnly: true,
      onChanged: widget.onChanged,
    );
  }
}
// Key data model with caching support
class KeyData {
  final String type;
  final String symbol;
  final String style;
  final String? keystroke;
  final double width;
  final String? layoutLink;

  // Cache key for widget caching
  late final String _cacheKey;

  KeyData({
    required this.type,
    required this.symbol,
    required this.style,
    this.keystroke,
    required this.width,
    this.layoutLink,
  }) {
    _cacheKey = '$type-$symbol-$style-$keystroke-$width-$layoutLink';
  }

  String get cacheKey => _cacheKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyData &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

// Row data model
class RowData {
  final String? type;
  final List<dynamic> elements; // KeyData or SpacerData

  // Cache key for row caching
  late final String _cacheKey;

  RowData({this.type, required this.elements}) {
    _cacheKey =
        '$type-${elements.map((e) => e is KeyData
            ? e.cacheKey
            : e is SpacerData
            ? '${e.type}-${e.width}'
            : '').join('-')}';
  }

  String get cacheKey => _cacheKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RowData &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

// Spacer data model
class SpacerData {
  final String type;
  final double width;

  SpacerData({required this.type, required this.width});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpacerData &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          width == other.width;

  @override
  int get hashCode => type.hashCode ^ width.hashCode;
}

// Layout data model
class LayoutData {
  final String layoutName;
  final List<RowData> rows;

  // Cache key for layout caching
  late final String _cacheKey;

  LayoutData({required this.layoutName, required this.rows}) {
    _cacheKey = '$layoutName-${rows.map((r) => r.cacheKey).join('-')}';
  }

  String get cacheKey => _cacheKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutData &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

// Cached Key Widget
class CachedKeyWidget extends StatelessWidget {
  final KeyData keyData;
  final double keyWidth;
  final double keyHeight;
  final VoidCallback onPressed;

  const CachedKeyWidget({
    super.key,
    required this.keyData,
    required this.keyWidth,
    required this.keyHeight,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    Widget keyContent;
    switch (keyData.symbol) {
      case 'ICON_SHIFT':
      case 'ICON_UNSHIFT':
        keyContent = const Icon(Icons.keyboard_arrow_up);
        break;
      case 'ICON_BKSP':
        keyContent = const Icon(Icons.backspace_outlined);
        break;
      default:
        keyContent = Text(keyData.symbol);
    }

    final theme = Theme.of(context);

    // Helper to wrap the key content so it will scale down on tight space.
    Widget scaledContent(Widget content) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown, // shrink the icon/text if needed
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: content,
          ),
        ),
      );
    }

    // Create the button but allow it to be smaller by setting minimumSize to Size.zero
    // and placing scaled content inside the button.
    Widget child;
    final ButtonStyle baseStyle = ButtonStyle(
      // ensure the button can shrink smaller than default material min sizes
      minimumSize: WidgetStateProperty.all(const Size(0, 0)),
      padding: WidgetStateProperty.all(EdgeInsets.zero),
      elevation: WidgetStateProperty.all(1.0),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
      ),
      textStyle: WidgetStateProperty.all(TextStyle(fontSize: 18)),
      splashFactory: NoSplash.splashFactory,
    );

    if (keyData.style == "Primary") {
      child = FilledButton(
        onPressed: onPressed,
        style: baseStyle.merge(
          FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            textStyle: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        child: scaledContent(keyContent),
      );
    } else if (keyData.style == "Secondary") {
      child = FilledButton(
        onPressed: onPressed,
        style: baseStyle.merge(
          FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: theme.colorScheme.onSecondary,
            textStyle: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSecondary,
            ),
          ),
        ),
        child: scaledContent(keyContent),
      );
    } else if (keyData.style == "Tertiary") {
      child = FilledButton(
        onPressed: onPressed,
        style: baseStyle.merge(
          FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.tertiary,
            foregroundColor: theme.colorScheme.onTertiary,
            textStyle: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onTertiary,
            ),
          ),
        ),
        child: scaledContent(keyContent),
      );
    } else {
      child = ElevatedButton(
        onPressed: onPressed,
        style: baseStyle,
        child: scaledContent(keyContent),
      );
    }

    const double minKeyDim = 28.0;
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minKeyDim,
          maxWidth: keyWidth * keyData.width,
          minHeight: minKeyDim,
          maxHeight: keyHeight,
        ),
        child: child,
      ),
    );
  }
}

// Cached Row Widget
class CachedRowWidget extends StatelessWidget {
  final RowData rowData;
  final double keyWidth;
  final double keyHeight;
  final Function(KeyData) onKeyPressed;

  const CachedRowWidget({
    super.key,
    required this.rowData,
    required this.keyWidth,
    required this.keyHeight,
    required this.onKeyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        ...rowData.elements.map((element) => _buildElementWidget(element)),
        const Spacer(),
      ],
    );
  }

  Widget _buildElementWidget(dynamic element) {
    // Convert a fractional width (e.g. 1, 1.5, 2) into an integer flex.
    int flexFromWidth(double w) {
      final int v = (w * 100).round();
      return v < 1 ? 1 : v;
    }

    if (element is SpacerData) {
      final int flex = flexFromWidth(element.width);
      // A flexible empty box — it will take its proportion of row space but can shrink.
      return Flexible(
        fit: FlexFit.loose,
        flex: flex,
        child: const SizedBox.shrink(),
      );
    } else if (element is KeyData) {
      final int flex = flexFromWidth(element.width);
      return Flexible(
        fit: FlexFit.loose,
        flex: flex,
        child: CachedKeyWidget(
          keyData: element,
          keyWidth: keyWidth,
          keyHeight: keyHeight,
          onPressed: () => onKeyPressed(element),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// Cached Layout Widget
class CachedLayoutWidget extends StatelessWidget {
  final LayoutData layoutData;
  final double keyWidth;
  final double keyHeight;
  final Function(KeyData) onKeyPressed;

  const CachedLayoutWidget({
    super.key,
    required this.layoutData,
    required this.keyWidth,
    required this.keyHeight,
    required this.onKeyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: layoutData.rows
            .map(
              (row) => CachedRowWidget(
                rowData: row,
                keyWidth: keyWidth,
                keyHeight: keyHeight,
                onKeyPressed: onKeyPressed,
              ),
            )
            .toList(),
      ),
    );
  }
}

// Virtual Keyboard Widget with caching
class VirtualKeyboard extends StatefulWidget {
  final String rootLayoutPath;
  final double keyWidth;
  final double keyHeight;

  const VirtualKeyboard({
    super.key,
    required this.rootLayoutPath,
    this.keyWidth = 48.0,
    this.keyHeight = 40.0,
  });

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard>
    with AutomaticKeepAliveClientMixin<VirtualKeyboard> {
  late PageController _pageController;
  final Map<String, int> _layoutNameToIndex = {};
  final Map<String, LayoutData> _parsedLayoutsCache = {};
  final Map<String, Widget> _layoutWidgetCache = {}; // Widget cache
  String? _rootLayoutFilename;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _rootLayoutFilename = widget.rootLayoutPath.split('/').last;
    _buildLayouts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => _parsedLayoutsCache.isNotEmpty;

  Future<LayoutData?> _parseLayoutXml(String path) async {
    if (_parsedLayoutsCache.containsKey(path)) {
      return _parsedLayoutsCache[path];
    }

    try {
      // FIX: Use rootBundle.loadString to load from assets
      final xmlString = await rootBundle.loadString(path);

      final document = XmlDocument.parse(xmlString);
      final root = document.rootElement;

      final layoutName = root.getAttribute('name') ?? 'Unknown Layout';
      final rows = <RowData>[];

      for (final rowElement in root.findElements('Row')) {
        final rowType = rowElement.getAttribute('type');
        final elements = <dynamic>[];

        for (final element in rowElement.children.whereType<XmlElement>()) {
          if (element.name.local == 'Key') {
            final keyData = KeyData(
              type: 'key',
              symbol: element.getAttribute('symbol') ?? '',
              style: element.getAttribute('style') ?? 'Std',
              keystroke: element.getAttribute('keystroke'),
              width:
                  double.tryParse(element.getAttribute('width') ?? '1.0') ??
                  1.0,
              layoutLink: element.getAttribute('layoutLink'),
            );
            elements.add(keyData);
          } else if (element.name.local == 'Spacer') {
            final spacerData = SpacerData(
              type: 'spacer',
              width:
                  double.tryParse(element.getAttribute('width') ?? '1.0') ??
                  1.0,
            );
            elements.add(spacerData);
          }
        }

        rows.add(RowData(type: rowType, elements: elements));
      }

      final layoutData = LayoutData(layoutName: layoutName, rows: rows);
      _parsedLayoutsCache[path] = layoutData;
      return layoutData;
    } catch (e) {
      loggerInstance?.e(
        'Error parsing XML asset $path: $e',
      ); // Changed message for clarity
      return null;
    }
  }

  Future<void> _buildLayouts() async {
    await _buildLayoutsRecursive(widget.rootLayoutPath, _rootLayoutFilename!);
    // Pre-build widget cache after layouts are loaded
    _prebuildWidgetCache();
  }

  Future<void> _buildLayoutsRecursive(
    String currentPath,
    String currentLinkName,
  ) async {
    if (_layoutNameToIndex.containsKey(currentLinkName)) {
      return;
    }

    final layoutData = await _parseLayoutXml(currentPath);
    if (layoutData == null) return;

    final index = _layoutNameToIndex.length;
    _layoutNameToIndex[currentLinkName] = index;

    // Process layout links for recursive loading
    for (final row in layoutData.rows) {
      for (final element in row.elements) {
        if (element is KeyData && element.layoutLink != null) {
          if (element.layoutLink == 'ROOT') continue;

          final directory = currentPath.substring(
            0,
            currentPath.lastIndexOf('/'),
          );
          final nextLayoutPath = '$directory/${element.layoutLink}';
          await _buildLayoutsRecursive(nextLayoutPath, element.layoutLink!);
        }
      }
    }
  }

  // Pre-build widget cache for all layouts
  void _prebuildWidgetCache() {
    for (final entry in _parsedLayoutsCache.entries) {
      final layoutData = entry.value;
      final cacheKey =
          '${layoutData.cacheKey}-${widget.keyWidth}-${widget.keyHeight}';

      if (!_layoutWidgetCache.containsKey(cacheKey)) {
        _layoutWidgetCache[cacheKey] = CachedLayoutWidget(
          layoutData: layoutData,
          keyWidth: widget.keyWidth,
          keyHeight: widget.keyHeight,
          onKeyPressed: _onKeyPressed,
        );
      }
    }

    if (mounted) {
      setState(() {}); // Trigger rebuild to show cached widgets
    }
  }

  void _switchToLayout(String targetLayoutLinkName) {
    if (!_layoutNameToIndex.containsKey(targetLayoutLinkName)) {
      loggerInstance?.e(
        'Attempted to switch to unknown layout: $targetLayoutLinkName',
      );
      return;
    }

    final targetIndex = _layoutNameToIndex[targetLayoutLinkName]!;
    _pageController.jumpToPage(targetIndex);
  }

  Widget _getCachedLayoutWidget(LayoutData layoutData) {
    final cacheKey =
        '${layoutData.cacheKey}-${widget.keyWidth}-${widget.keyHeight}';

    if (_layoutWidgetCache.containsKey(cacheKey)) {
      return _layoutWidgetCache[cacheKey]!;
    }

    // Fallback: build widget if not in cache
    final cachedWidget = CachedLayoutWidget(
      layoutData: layoutData,
      keyWidth: widget.keyWidth,
      keyHeight: widget.keyHeight,
      onKeyPressed: _onKeyPressed,
    );

    _layoutWidgetCache[cacheKey] = cachedWidget;
    return cachedWidget;
  }

  void _onKeyPressed(KeyData keyData) {
    if (keyData.layoutLink != null) {
      String targetLinkName = keyData.layoutLink!;
      if (targetLinkName == 'ROOT') {
        targetLinkName = _rootLayoutFilename!;
      }
      _switchToLayout(targetLinkName);
    } else if (keyData.keystroke != null) {
      VirtualKeyEventBus.instance.emitKeyEvent(keyData.keystroke!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_parsedLayoutsCache.isEmpty || _layoutWidgetCache.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(), // Only switch via buttons
      children: _parsedLayoutsCache.values
          .map((layoutData) => _getCachedLayoutWidget(layoutData))
          .toList(),
    );
  }
}
