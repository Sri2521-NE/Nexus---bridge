import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class DownloadItem {
  final String id;
  final String filename;
  final String filePath;
  double progress;
  String status;

  DownloadItem({
    required this.id,
    required this.filename,
    required this.filePath,
    this.progress = 0.0,
    this.status = 'Ready',
  });
}

class DownloadService extends ChangeNotifier {
  final List<DownloadItem> downloads = [];
  String _downloadPath = '';
  Future<void>? _downloadPathFuture;

  DownloadService() {
    _downloadPathFuture = _initializeDownloadPath();
  }

  String getDownloadFilePath(String filename) {
    return '$_downloadPath/$filename';
  }

  Future<void> _ensureDownloadPath() async {
    if (_downloadPathFuture != null) {
      await _downloadPathFuture;
      _downloadPathFuture = null;
    }

    if (_downloadPath.isEmpty) {
      await _initializeDownloadPath();
    }
  }

  Future<void> _initializeDownloadPath() async {
    final directory = await getApplicationDocumentsDirectory();
    _downloadPath = '${directory.path}/NexusBridgeDownloads';

    final dir = Directory(_downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> registerLocalFile(String filename) async {
    await _ensureDownloadPath();
    final filePath = getDownloadFilePath(filename);
    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filename: filename,
      filePath: filePath,
      status: 'Available',
      progress: 1.0,
    );
    downloads.add(item);
    notifyListeners();
  }

  void removeDownload(String id) {
    downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void clearCompleted() {
    downloads.removeWhere((d) => d.status == 'Available');
    notifyListeners();
  }
}
