library houdai_kit;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';

typedef BleOperation<T> = Future<T> Function();

class BleRequestQueue {
  final Queue<BleOperation> _operationQueue = Queue<BleOperation>();
  bool _isProcessing = false;

  static final BleRequestQueue _instance = BleRequestQueue._internal();

  factory BleRequestQueue() => _instance;

  BleRequestQueue._internal();

  Future<T> addOperation<T>(BleOperation<T> operation, {int retries = 3}) {
    final completer = Completer<T>();
    _operationQueue.add(() async {
      int attempt = 0;
      while (attempt < retries) {
        try {
          final result = await operation();
          completer.complete(result);
          break;
        } catch (e) {
          attempt++;
          if (attempt >= retries) {
            completer.completeError(e);
          } else {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
      _processQueue();
    });
    _processQueue();
    return completer.future;
  }

  void _processQueue() async {
    if (_isProcessing) return;
    if (_operationQueue.isEmpty) return;

    _isProcessing = true;
    final operation = _operationQueue.removeFirst();

    try {
      await operation();
    } catch (e) {
      // print(e);
    } finally {
      _isProcessing = false;
      _processQueue();
    }
  }
}

class BLEManager {
  BLEManager._internal();

  static final BLEManager _instance = BLEManager._internal();

  factory BLEManager() {
    return _instance;
  }

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  BluetoothDevice? _connectedDevice;
  List<BluetoothCharacteristic> _characteristics = [];
  final Map<String, BluetoothCharacteristic> _characteristicMap = {};

  Future<void> init(
      List<BluetoothService> service, BluetoothDevice device) async {
    _characteristicMap.clear();
    _connectedDevice = device;

    // Cancel previous subscription if it exists
    _connectionStateSubscription?.cancel();

    _connectionStateSubscription =
        _connectedDevice!.connectionState.listen((state) async {
      print("Connection state changed: $state");
      _connectionState = state;
    });

    for (var service in service) {
      _characteristics.addAll(service.characteristics);
    }

    for (var characteristic in _characteristics) {
      _characteristicMap[characteristic.uuid.toString()] = characteristic;
    }
  }

  BluetoothCharacteristic? getCharacteristic(String uuid) {
    return _characteristicMap[uuid];
  }

  Future<int> getChunkSize() async {
    return (await _connectedDevice!.mtu.first) - 3;
  }

  Future<void> sendFragment(String uuid, List<int> data) async {
    final characteristic = _characteristicMap[uuid]!;
    int chunkSize = await getChunkSize();

    await BleRequestQueue().addOperation(() async {
      await characteristic.write(utf8.encode('START'));
    });

    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
      final chunk = data.sublist(i, end);
      await BleRequestQueue().addOperation(() async {
        await characteristic.write(chunk);
      });
    }

    await BleRequestQueue().addOperation(() async {
      await characteristic.write(utf8.encode('END'));
    });
  }

  Future<String> receiveFile(String uuid, String fileName) async {
    final characteristic = _characteristicMap[uuid]!;
    final Completer<String> completer = Completer<String>();
    final StringBuffer buffer = StringBuffer();
    StreamSubscription<List<int>>? subscription;

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/$fileName';
    final file = File(filePath);
    await file.create();

    await BleRequestQueue().addOperation(() async {
      await characteristic.setNotifyValue(true);
    });

    subscription = characteristic.onValueReceived.listen((value) async {
      final String data = utf8.decode(value);

      if (data == "START") {
        buffer.clear();
      } else if (data == 'END') {
        completer.complete(filePath);
        subscription?.cancel();
      } else {
        buffer.write(data);
        await file.writeAsString(buffer.toString(), mode: FileMode.append);
        buffer.clear();
      }
    });

    await BleRequestQueue().addOperation(() async {
      await characteristic.read();
    });

    return completer.future;
  }

  Future<String> receiveFragment(String uuid) async {
    final characteristic = _characteristicMap[uuid]!;
    final Completer<String> completer = Completer<String>();
    final StringBuffer buffer = StringBuffer();
    StreamSubscription<List<int>>? subscription;

    await BleRequestQueue().addOperation(() async {
      await characteristic.setNotifyValue(true);
    });

    subscription = characteristic.onValueReceived.listen((value) {
      final String data = utf8.decode(value);

      if (data.startsWith('START')) {
        buffer.clear();
      } else if (data.contains('END')) {
        buffer.write(data.substring(0, data.indexOf('END')));
        completer.complete(buffer.toString());
        subscription?.cancel();
      } else {
        buffer.write(data);
      }
    });

    await BleRequestQueue().addOperation(() async {
      await characteristic.read();
    });

    return completer.future;
  }

  Future<void> setNotifyValueWithRetry(
      BluetoothCharacteristic characteristic, bool notify,
      {int retries = 3}) async {
    int attempt = 0;
    while (attempt < retries) {
      try {
        await characteristic.setNotifyValue(notify);
        return;
      } catch (e) {
        attempt++;
        if (attempt >= retries) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  BluetoothDevice? get connectedDevice => _connectedDevice;
  BluetoothConnectionState get connectionState => _connectionState;
  List<BluetoothCharacteristic> get characteristics => _characteristics;
}
