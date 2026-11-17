import 'package:flutter/material.dart';

import '../app_version.dart';
import '../update_service.dart';

/// Checks for a newer build and, if there is one, shows the "Update
/// available" dialog. With [manual] it also says when you are up to date.
Future<void> checkAndPromptForUpdate(
  BuildContext context,
  UpdateService service, {
  bool manual = false,
}) async {
  if (!service.isSupported) return;
  final info = await service.checkForUpdate(manual: manual);
  if (!context.mounted) return;
  if (info == null) {
    if (manual) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Powwot is up to date.')));
    }
    return;
  }
  final required = info.isRequiredFor(await service.installedBuild());
  if (!context.mounted) return;
  await showUpdateDialog(context, service, info, required: required);
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateService service,
  AppVersionInfo info, {
  bool required = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !required,
    builder: (_) =>
        _UpdateDialog(service: service, info: info, required: required),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateService service;
  final AppVersionInfo info;
  final bool required;

  const _UpdateDialog({
    required this.service,
    required this.info,
    required this.required,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final file = await widget.service.downloadAndVerify(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await widget.service.install(file);
      if (mounted) Navigator.pop(context);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong with the update. Try again.';
      });
    }
  }

  Future<void> _later() async {
    await widget.service.postpone(widget.info);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return PopScope(
      canPop: !widget.required && !_busy,
      child: AlertDialog(
        title: const Text('Update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Powwot ${info.versionName} is ready to install.'),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  "What's new",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(info.notes),
              ],
              if (widget.required) ...[
                const SizedBox(height: 12),
                const Text(
                  'This update is required to keep using Powwot.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const Key('update_progress'),
                  value: _progress,
                ),
                const SizedBox(height: 4),
                Text(
                  _progress == null
                      ? 'Starting download...'
                      : 'Downloading ${(_progress! * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('update_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.required)
            TextButton(
              key: const Key('update_later'),
              onPressed: _busy ? null : _later,
              child: const Text('Later'),
            ),
          ElevatedButton(
            key: const Key('update_now'),
            onPressed: _busy ? null : _update,
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
