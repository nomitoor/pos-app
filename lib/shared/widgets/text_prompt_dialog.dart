import 'package:material_ui/material_ui.dart';

/// Asks for one line of text. Returns the text, or null if cancelled.
/// The dialog owns its controller, so it is only disposed after the
/// closing animation (disposing it earlier crashes with a red screen).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String okLabel = 'OK',
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(title: title, hint: hint, okLabel: okLabel),
);

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String okLabel;
  const _TextPromptDialog({
    required this.title,
    this.hint,
    required this.okLabel,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
