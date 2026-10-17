import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import 'logo_crop_dialog.dart';
import 'orion_logo.dart';

class LogoControl extends StatefulWidget {
  const LogoControl({
    super.key,
    this.image,
    required this.onChanged,
    this.pickImage,
    this.controller,
  });
  final Uint8List? image;
  final OrionController? controller;
  final ValueChanged<Uint8List?> onChanged;
  final Future<files.XFile?> Function()? pickImage;
  @override
  State<LogoControl> createState() => _LogoControlState();
}

class _LogoControlState extends State<LogoControl> {
  bool _opening = false;
  String? _error;
  Future<void> _choose() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final file = widget.pickImage != null
          ? await widget.pickImage!()
          : await files.openFile(
              confirmButtonText: 'Choose image',
              acceptedTypeGroups: const [
                files.XTypeGroup(
                  label: 'Logo images',
                  extensions: ['png', 'jpg', 'jpeg', 'webp'],
                  mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
                ),
              ],
            );
      if (file == null) return;
      if (await file.length() > maximumLogoInputBytes) {
        throw const FormatException('Choose an image smaller than 20 MB.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final part in file.openRead()) {
        if (builder.length + part.length > maximumLogoInputBytes) {
          throw const FormatException('Choose an image smaller than 20 MB.');
        }
        builder.add(part);
      }
      if (!mounted) return;
      final result = await showLogoCropDialog(
        context,
        builder.takeBytes(),
        controller: widget.controller,
      );
      if (result != null && mounted) widget.onChanged(result);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = 'This image could not be opened. Choose another image.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LogoCheckerboard(
          child: SizedBox(
            height: 76,
            child: Center(
              child: OrionWordmark(height: 32, customImage: widget.image),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.icon(
            key: const ValueKey('logo-choose-image'),
            onPressed: _opening ? null : _choose,
            icon: const Icon(Icons.image_outlined),
            label: Text(_opening ? 'Opening…' : 'Choose image'),
          ),
          TextButton(
            key: const ValueKey('logo-restore'),
            onPressed: _opening || widget.image == null
                ? null
                : () {
                    setState(() => _error = null);
                    widget.onChanged(null);
                  },
            child: const Text('Restore Orion logo'),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
    ],
  );
}
