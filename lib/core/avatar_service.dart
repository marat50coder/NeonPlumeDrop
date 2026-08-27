import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'profile_service.dart';

class AvatarService {
  AvatarService._();

  static final _picker = ImagePicker();

  static Future<String?> pickAndSave(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 720,
      imageQuality: 85,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/player_avatar.jpg');
    await File(picked.path).copy(dest.path);
    await ProfileService.instance.setAvatarPath(dest.path);
    return dest.path;
  }

  static Future<void> clear() async {
    final path = ProfileService.instance.avatarPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await ProfileService.instance.setAvatarPath(null);
  }
}
