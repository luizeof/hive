import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/frame_helper.dart';
import 'package:hive/src/box/keystore.dart';
import 'package:hive/src/crypto_helper.dart';
import 'package:hive/src/io/buffered_file_reader.dart';
import 'package:meta/meta.dart';

class FrameIoHelper extends FrameHelper {
  @visibleForTesting
  Future<RandomAccessFile> openFile(String path) {
    return File(path).open();
  }

  @visibleForTesting
  Future<List<int>> readFile(String path) {
    return File(path).readAsBytes();
  }

  Future<int> keysFromFile(
      String path, Keystore keystore, CryptoHelper crypto) async {
    var raf = await openFile(path);
    var fileReader = BufferedFileReader(raf);
    try {
      return await _KeyReader(fileReader).readKeys(keystore, crypto);
    } finally {
      await raf.close();
    }
  }

  Future<int> framesFromFile(String path, Keystore keystore,
      TypeRegistry registry, CryptoHelper crypto) async {
    var bytes = await readFile(path);
    return framesFromBytes(bytes as Uint8List, keystore, registry, crypto);
  }
}

class _KeyReader {
  final BufferedFileReader fileReader;

  BinaryReaderImpl _reader;

  _KeyReader(this.fileReader);

  Future<int> readKeys(Keystore keystore, CryptoHelper crypto) async {
    await _load(4);
    while (true) {
      var frameOffset = fileReader.offset;

      if (_reader.availableBytes < 4) {
        var available = await _load(4);
        if (available == 0) {
          break;
        } else if (available < 4) {
          return frameOffset;
        }
      }

      var frameLength = _reader.peekUint32();
      if (_reader.availableBytes < frameLength) {
        var available = await _load(frameLength);
        if (available < frameLength) return frameOffset;
      }

      var frame = _reader.readFrame(
        crypto: crypto,
        lazy: true,
        frameOffset: frameOffset,
      );
      if (frame == null) return frameOffset;

      keystore.insert(frame, notify: false);

      fileReader.skip(frameLength);
    }

    return -1;
  }

  Future<int> _load(int bytes) async {
    var loadedBytes = await fileReader.loadBytes(bytes);
    var buffer = fileReader.peekBytes(loadedBytes);
    _reader = BinaryReaderImpl(buffer, null);

    return loadedBytes;
  }
}
