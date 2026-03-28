import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String version;
  final String releaseUrl;
  final String notes;
  final String? assetDownloadUrl;

  UpdateInfo({
    required this.version,
    required this.releaseUrl,
    required this.notes,
    this.assetDownloadUrl,
  });
}

class UpdateService {
  static const String _repoUrl = 'https://api.github.com/repos/DevOpenMindset/audio_router_releases/releases/latest';
  static const String _prefSkipVersion = 'update_skip_version';
  static const String _prefCheckAuto = 'update_check_auto';

  final SharedPreferences _prefs;
  
  UpdateService(this._prefs);

  bool get checkAutoUpdates => _prefs.getBool(_prefCheckAuto) ?? true;
  
  Future<void> setCheckAutoUpdates(bool value) async {
    await _prefs.setBool(_prefCheckAuto, value);
  }

  Future<void> skipVersion(String version) async {
    await _prefs.setString(_prefSkipVersion, version);
  }

  String? get skippedVersion => _prefs.getString(_prefSkipVersion);

  /// Checks GitHub API for a newer version than what we have installed.
  /// Ignores any versions the user has explicitly skipped.
  Future<UpdateInfo?> checkForUpdates() async {
    if (!checkAutoUpdates) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_repoUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String latestVersion = data['tag_name']?.toString().replaceAll('v', '') ?? '';
        final String releaseUrl = data['html_url']?.toString() ?? '';
        final String notes = data['body']?.toString() ?? '';

        String? assetDownloadUrl;
        final assets = data['assets'] as List?;
        if (assets != null) {
          for (var asset in assets) {
            final name = asset['name']?.toString().toLowerCase() ?? '';
            final url = asset['browser_download_url']?.toString() ?? '';
            if (Platform.isWindows && name.endsWith('.exe')) {
              assetDownloadUrl = url;
              break;
            } else if (Platform.isMacOS && name.endsWith('.dmg')) {
              assetDownloadUrl = url;
              break;
            }
          }
        }

        if (latestVersion.isEmpty || releaseUrl.isEmpty) {
          return null;
        }

        if (_isNewer(currentVersion, latestVersion)) {
          if (latestVersion != skippedVersion) {
             return UpdateInfo(
               version: latestVersion,
               releaseUrl: releaseUrl,
               notes: notes,
               assetDownloadUrl: assetDownloadUrl,
             );
          }
        }
      }
    } catch (e) {
      // Silently fail if no internet or github API blocked
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  bool _isNewer(String current, String latest) {
    List<int> cParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    List<int> lParts = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to 3 parts
    while (cParts.length < 3) {
      cParts.add(0);
    }
    while (lParts.length < 3) {
      lParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
       if (lParts[i] > cParts[i]) return true;
       if (lParts[i] < cParts[i]) return false;
    }
    return false; // They are equal
  }

  /// Downloads the update installer to a temporary directory, executes it, and exits the app.
  Future<void> downloadAndInstallUpdate(
    UpdateInfo info,
    void Function(double) onProgress,
  ) async {
    if (info.assetDownloadUrl == null) return;

    try {
      final request = http.Request('GET', Uri.parse(info.assetDownloadUrl!));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 1;
        int downloaded = 0;

        final ext = Platform.isWindows ? '.exe' : '.dmg';
        final file = File('${Directory.systemTemp.path}/audiorouter_update$ext');

        final sink = file.openWrite();
        await for (var chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress(downloaded / contentLength);
        }
        await sink.flush();
        await sink.close();

        // Give file system a moment to sync
        await Future.delayed(const Duration(milliseconds: 500));

        // Launch installer
        if (Platform.isWindows) {
          // Pass /SILENT so the user just sees it install, but it will need admin rights if installed system-wide.
          Process.start(file.path, ['/SILENT'], mode: ProcessStartMode.detached);
        } else if (Platform.isMacOS) {
          Process.start('open', [file.path], mode: ProcessStartMode.detached);
        }
        
        // Exit the current app instance so Windows can replace the exe
        exit(0);
      } else {
        debugPrint('Download failed with status ${response.statusCode}');
        onProgress(-1); // Signal error
      }
    } catch (e) {
      debugPrint('Download error: $e');
      onProgress(-1);
    }
  }
}
