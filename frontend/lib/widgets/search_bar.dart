import 'dart:async';
import 'package:flutter/material.dart';

class DebouncedSearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final String initialValue;

  const DebouncedSearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Search...',
    this.initialValue = '',
  });

  @override
  State<DebouncedSearchBar> createState() => _DebouncedSearchBarState();
}

class _DebouncedSearchBarState extends State<DebouncedSearchBar> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant DebouncedSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      widget.onChanged(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Color(0xFF64748B)),
                onPressed: () {
                  _controller.clear();
                  _onTextChanged('');
                  setState(() {});
                },
              )
            : null,
      ),
    );
  }
}
