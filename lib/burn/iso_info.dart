import 'dart:convert';
import 'dart:io';

/// What the Burn Image page shows about a picked file.
class DiscImageInfo {
  final int bytes;

  /// Volume id from the ISO 9660 primary volume descriptor, or null when the
  /// file is not an ISO 9660 image (still burnable — it is copied verbatim).
  final String? volumeId;

  const DiscImageInfo(this.bytes, this.volumeId);

  bool get isIso => volumeId != null;
}

/// Reads the primary volume descriptor at sector 16: type byte 1, then the
/// "CD001" magic; the 32-byte volume id sits at offset 40.
Future<DiscImageInfo> readImageInfo(String path) async {
  final f = await File(path).open();
  try {
    final length = await f.length();
    if (length < 32768 + 2048) return DiscImageInfo(length, null);
    await f.setPosition(32768);
    final pvd = await f.read(2048);
    final magic = ascii.decode(pvd.sublist(1, 6), allowInvalid: true);
    if (pvd[0] != 1 || magic != 'CD001') return DiscImageInfo(length, null);
    final id = ascii.decode(pvd.sublist(40, 72), allowInvalid: true).trim();
    return DiscImageInfo(length, id);
  } finally {
    await f.close();
  }
}
