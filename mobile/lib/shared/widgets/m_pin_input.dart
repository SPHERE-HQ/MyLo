import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';

class MPinInput extends StatefulWidget {
  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool obscure;

  const MPinInput({
    super.key,
    this.length = 6,
    required this.onChanged,
    this.onCompleted,
    this.obscure = true,
  });

  @override
  State<MPinInput> createState() => _MPinInputState();
}

class _MPinInputState extends State<MPinInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // hidden input that drives the dots
      SizedBox(
        height: 1,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            LengthLimitingTextInputFormatter(widget.length),
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(color: Colors.transparent, height: .01),
          decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
          onChanged: (v) {
            setState(() {});
            widget.onChanged(v);
            if (v.length == widget.length && widget.onCompleted != null) {
              widget.onCompleted!(v);
            }
          },
        ),
      ),
      GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(widget.length, (i) {
          final filled = i < _controller.text.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: filled ? MyloColors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: MyloColors.primary, width: 2),
            ),
          );
        })),
      ),
    ]);
  }
}
