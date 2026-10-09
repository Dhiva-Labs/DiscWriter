import 'package:cd_writer/burn/models.dart';
import 'package:cd_writer/burn/parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripPacket', () {
    test('splits channel and text', () {
      expect(stripPacket('R:1: Image size   : 12s'), ('R', 'Image size   : 12s'));
      expect(stripPacket('I:1: '), ('I', ''));
    });
    test('passes non-packet lines through as info', () {
      expect(stripPacket('xorriso 1.5.6 : RockRidge'), ('I', 'xorriso 1.5.6 : RockRidge'));
    });
  });

  group('parseDevices', () {
    test('reads vendor, model and permissions', () {
      final drives = parseDevices([
        'I:1: Beginning to scan for devices ...',
        "R:1: 0  -dev '/dev/sr0' rwrw-- :  'HL-DT-ST' 'DVDRAM GH24NSD1' ",
        "R:1: 1  -dev '/dev/sr1' rwrw-- :  'ASUS    ' 'BW-16D1HT       ' ",
        'I:1: Full drive scan done.',
      ]);
      expect(drives.map((d) => d.address), ['/dev/sr0', '/dev/sr1']);
      expect(drives[0].vendor, 'HL-DT-ST');
      expect(drives[0].model, 'DVDRAM GH24NSD1');
      expect(drives[1].vendor, 'ASUS');
      expect(drives[1].model, 'BW-16D1HT');
      expect(drives[0].permissions, 'rwrw--');
    });
    test('no drives is an empty list', () {
      expect(parseDevices(['I:1: xorriso : SORRY : No drives found']), isEmpty);
    });
  });

  group('parseToc', () {
    test('blank CD-R in a real drive', () {
      final m = parseToc([
        "R:1: Drive current: -outdev '/dev/sr0'",
        "R:1: Drive type   : vendor 'HL-DT-ST' product 'DVDRAM GH24NSD1' revision 'LG00'",
        'R:1: Media current: CD-R',
        'R:1: Media product: 97m26s66f , Ritek Corp',
        'R:1: Media status : is blank',
        'R:1: Media blocks : 0 readable , 359844 writable , 359844 overall',
        'R:1: Media summary: 0 sessions, 0 data blocks, 0 data,  703m free',
      ]);
      expect(m.present, isTrue);
      expect(m.blank, isTrue);
      expect(m.family, DiscFamily.cd);
      expect(m.erasable, isFalse);
      expect(m.writableBlocks, 359844);
      expect(m.vendor, 'HL-DT-ST');
      expect(m.summary, 'CD-R · blank');
    });
    test('appendable DVD+RW with a session', () {
      final m = parseToc([
        'R:1: Media current: DVD+RW',
        'R:1: Media status : is written , is appendable',
        'R:1: Media blocks : 195644 readable , 2099460 writable , 2295104 overall',
        'R:1: TOC layout   : Idx ,  sbsector ,       Size , Volume Id',
        'R:1: ISO session  :   1 ,         0 ,    195644s , BACKUP 2026',
        'R:1: Media summary: 1 session, 195644 data blocks,  382m data, 4100m free',
      ]);
      expect(m.appendable, isTrue);
      expect(m.blank, isFalse);
      expect(m.erasable, isTrue);
      expect(m.family, DiscFamily.dvd);
      expect(m.sessions, 1);
      expect(m.dataBlocks, 195644);
      expect(m.volumeId, 'BACKUP 2026');
      expect(m.summary, 'DVD+RW · appendable, 1 session');
    });
    test('closed BD-R strips the recording-mode suffix', () {
      final m = parseToc([
        'R:1: Media current: BD-R sequential recording',
        'R:1: Media status : is written , is closed',
        'R:1: Media summary: 1 session, 1000 data blocks, 2000k data, 0 free',
      ]);
      expect(m.closed, isTrue);
      expect(m.writable, isFalse);
      expect(m.family, DiscFamily.bd);
      expect(m.summary, 'BD-R · closed');
    });
    test('empty tray', () {
      final m = parseToc([
        'I:1: Media current: is not present',
        'I:1: Media status : is not present',
      ]);
      expect(m.present, isFalse);
      expect(m.summary, 'No disc');
    });
    test('stdio pseudo drive', () {
      final m = parseToc([
        'R:1: Media current: stdio file, overwriteable',
        'R:1: Media status : is blank',
        'R:1: Media blocks : 0 readable , 6252454 writable , 6252454 overall',
      ]);
      expect(m.family, DiscFamily.file);
      expect(m.erasable, isTrue);
      expect(m.summary, 'Image file · blank');
    });
  });

  test('parseImageSize', () {
    expect(parseImageSize(['I:1: x', 'R:1: Image size   : 2621624s']), 2621624);
    expect(parseImageSize(['I:1: nothing']), isNull);
  });

  group('parseMessage', () {
    test('severity and text', () {
      final m = parseMessage("I:1: xorriso : FAILURE : Cannot open '/dev/sr0'")!;
      expect(m.severity, Severity.failure);
      expect(m.text, "Cannot open '/dev/sr0'");
      expect(m.isProblem, isTrue);
    });
    test('libburn messages count too', () {
      expect(parseMessage('I:1: libburn : SORRY : Drive is busy')!.severity, Severity.sorry);
    });
    test('notes are not problems', () {
      expect(parseMessage('I:1: xorriso : NOTE : -blank as_needed: no need')!.isProblem, isFalse);
    });
    test('non-messages', () {
      expect(parseMessage('R:1: Media current: CD-R'), isNull);
    });
  });

  group('parseProgress', () {
    test('mkisofs percent', () {
      final p = parseProgress('I:1: xorriso : UPDATE :  32.00% done')!;
      expect(p.fraction, closeTo(0.32, 1e-9));
      expect(p.phase, JobPhase.writing);
    });
    test('native commit with speed', () {
      final p = parseProgress(
          'I:1: xorriso : UPDATE : Writing:     117529s   80.1%   fifo   0%  buf  50%  173.9xD ')!;
      expect(p.fraction, closeTo(0.801, 1e-9));
      expect(p.speed, closeTo(173.9, 1e-9));
      expect(p.detail, '230 MB written');
    });
    test('native commit before speed is known', () {
      final p = parseProgress('I:1: xorriso : UPDATE : Writing:      11616s    7.9%   fifo   0%  buf  50%')!;
      expect(p.fraction, closeTo(0.079, 1e-9));
      expect(p.speed, isNull);
    });
    test('cdrecord MB written', () {
      final p = parseProgress(
          'I:1: xorriso : UPDATE :   91 of  382 MB written (fifo 99%) [buf  50%]  60.0x.')!;
      expect(p.fraction, closeTo(91 / 382, 1e-9));
      expect(p.speed, 60.0);
      expect(p.detail, '91 of 382 MB written');
    });
    test('blanking', () {
      final p = parseProgress('I:1: xorriso : UPDATE : Blanking  ( 23.4% done in 12 seconds )')!;
      expect(p.phase, JobPhase.blanking);
      expect(p.fraction, closeTo(0.234, 1e-9));
    });
    test('md5 check with and without a known total', () {
      const line = 'I:1: xorriso : UPDATE :    51200 blocks read in 3 seconds , 12.3xD';
      final p = parseProgress(line, checkTotalBlocks: 102400)!;
      expect(p.phase, JobPhase.verifying);
      expect(p.fraction, closeTo(0.5, 1e-9));
      expect(parseProgress(line)!.fraction, isNull);
    });
    test('files added is indeterminate preparation', () {
      final p = parseProgress('I:1: xorriso : UPDATE :       4 files added in 1 seconds')!;
      expect(p.phase, JobPhase.preparing);
      expect(p.fraction, isNull);
      expect(p.detail, '4 files added');
    });
    test('ignores non-update lines', () {
      expect(parseProgress('I:1: xorriso : NOTE : 32.00% done'), isNull);
      expect(parseProgress('R:1: 32.00% done'), isNull);
    });
  });
}
