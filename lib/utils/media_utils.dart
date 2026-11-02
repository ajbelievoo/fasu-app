import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/const.dart';
import '../services/api_client.dart';
import '../utils/log.dart';

/// Global guard for image picker — prevents the `already_active`
/// PlatformException when the user taps the pick button multiple times
/// before the picker dialog appears.
class ImagePickerGuard {
  static bool _isActive = false;

  /// Returns true if a pick operation is safe to start.
  static bool get canPick => !_isActive;

  /// Wraps a pick operation with a global guard. Call this instead of
  /// `picker.pickImage(...)` directly.
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
    int? imageQuality,
    double? maxWidth,
    double? maxHeight,
  }) async {
    if (_isActive) return null;
    _isActive = true;
    try {
      return await ImagePicker().pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    } catch (e) {
      Log.e('ImagePickerGuard', 'pickImage failed', e);
      return null;
    } finally {
      _isActive = false;
    }
  }
}

class ImageUploadUtil {
  static const String _tag = 'ImageUploadUtil';

  static Future<String?> uploadImage({
    required File file,
    required String userId,
    String fieldName = 'image',
    String endpoint = '/chat/uploadImage',
  }) async {
    try {
      final dio = ApiClient.createUpload();
      final form = FormData.fromMap({
        'userId': userId,
        fieldName: MultipartFile.fromFileSync(file.path),
      });
      final r = await dio.post(endpoint, data: form);
      final data = r.data as Map<String, dynamic>;
      if (data['status'] == true) {
        return data['message'] as String?;
      }
    } catch (e, s) {
      Log.e(_tag, 'uploadImage failed', e, s);
    }
    return null;
  }
}

class VideoUtil {
  // Backend default placeholder URLs that don't actually exist on the CDN
  // (return 404). These are sent when a user hasn't uploaded a real image,
  // so we treat them as empty to trigger graceful fallbacks.
  static final RegExp _brokenDefaultPattern = RegExp(
    r'/storage/(coverImage|bannerImage)\.(jpg|png)$',
    caseSensitive: false,
  );

  /// File extensions that Android's ImageDecoder cannot decode. Loading
  /// these via CachedNetworkImage causes "Failed to decode image" errors.
  static final RegExp _unsupportedImagePattern = RegExp(
    r'\.(svg|heic|heif|tiff?|bmp|psd|ai|raw)(\?|$)',
    caseSensitive: false,
  );

  static String getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    // Filter out broken backend default placeholders (e.g. /storage/coverImage.jpg)
    if (_brokenDefaultPattern.hasMatch(path)) return '';
    // SVGA URLs must NOT be loaded via CachedNetworkImage — Android's
    // ImageDecoder cannot decode them and throws "Failed to decode image".
    // SVGA callers must use getFullSvgaUrl() instead.
    if (SvgaHelper.isSvgaUrl(path)) return '';
    // Filter out unsupported image formats that cause decode errors.
    if (_unsupportedImagePattern.hasMatch(path)) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/uploads'))
      return '${Const.baseUrl.replaceAll(RegExp(r'/$'), '')}$path';
    return '${Const.cdnUrl}$path';
  }

  /// Returns the full URL for SVGA animation files. Use this instead of
  /// [getFullImageUrl] when the caller will route the URL to [SvgaPlayer]
  /// (avatar frames, VIP badges, entry effects, voice waves, gift animations).
  static String getFullSvgaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (_brokenDefaultPattern.hasMatch(path)) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/uploads'))
      return '${Const.baseUrl.replaceAll(RegExp(r'/$'), '')}$path';
    return '${Const.cdnUrl}$path';
  }

  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String getThumbnailUrl(String videoUrl) {
    if (videoUrl.isEmpty) return '';
    final parts = videoUrl.split('.');
    if (parts.length > 1) {
      return '${parts.sublist(0, parts.length - 1).join('.')}_thumb.jpg';
    }
    return '${videoUrl}_thumb.jpg';
  }
}

class SvgaHelper {
  static String? getCacheKey(String url) {
    if (url.isEmpty) return null;
    return url.hashCode.toString();
  }

  static bool isSvgaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.trim().toLowerCase().split('?').first;
    if (RegExp(r'\.(png|jpe?g|gif|webp|bmp|svg|mp4|mov|webm|mkv|3gp)$')
        .hasMatch(lower)) {
      return false;
    }
    return lower.endsWith('.svga') || lower.contains('/svga/');
  }
}

/// Safely returns an ImageProvider. If the URL is empty or null, returns
/// a fallback placeholder asset image to avoid crashes in CircleAvatar
/// or DecorationImage.
///
/// Use this everywhere an ImageProvider is required for network images
/// to ensure graceful error handling.
final CacheManager _safeImageCacheManager = CacheManager(
  Config(
    'beliveImageCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 500,
  ),
);

// ignore: non_constant_identifier_names
ImageProvider SafeImageProvider(String? url, {String? fallbackAsset}) {
  if (url == null || url.trim().isEmpty) {
    return AssetImage(fallbackAsset ?? 'assets/images/safu_logo.png');
  }
  return CachedNetworkImageProvider(url, cacheManager: _safeImageCacheManager);
}
