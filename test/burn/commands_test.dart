import 'package:cd_writer/burn/commands.dart';
import 'package:cd_writer/burn/models.dart';
import 'package:cd_writer/project/disc_project.dart';
import 'package:flutter_test/flutter_test.dart';

const _drive = Drive(address: '/dev/sr0');
const _blankCd = MediaInfo(profile: 'CD-R', present: true, blank: true, writableBlocks: 359844);
const _appendableDvd = MediaInfo(
    profile: 'DVD+RW', present: true, appendable: true, sessions: 1, dataBlocks: 100);

final _project = const DiscProject(label: 'MY DISC').withAdded(const [
  DiscEntry(sourcePath: '/home/u/Photos', name: 'Photos', isDirectory: true),
  DiscEntry(sourcePath: '/home/u/a=b.txt', name: 'a=b.txt', isDirectory: false),
]);

void main() {
  group('burnProjectArgs', () {
    test('blank write-once disc: fresh session, closed, max speed', () {
      final args = burnProjectArgs(_project, _drive, _blankCd, const BurnOptions());
      expect(args.sublist(0, 2), ['-md5', 'on']);
      expect(args, containsAllInOrder(['-outdev', '/dev/sr0']));
      expect(args, isNot(contains('-dev')));
      expect(args, isNot(contains('-blank')));
      expect(args, containsAllInOrder(['-speed', 'max', '-dummy', 'off', '-close', 'on']));
      expect(args, containsAllInOrder(['-volid', 'MY DISC']));
      expect(args, containsAllInOrder(['-map', '/home/u/Photos', '/Photos']));
      expect(args, containsAllInOrder(['-map', '/home/u/a=b.txt', '/a=b.txt']));
      // Verify follows, so the write itself must not eject.
      expect(args.sublist(args.length - 2), ['-commit_eject', 'none']);
    });

    test('appendable disc loads the existing session with -dev', () {
      final args = burnProjectArgs(_project, _drive, _appendableDvd, const BurnOptions());
      expect(args, containsAllInOrder(['-dev', '/dev/sr0']));
      expect(args, isNot(contains('-outdev')));
    });

    test('erase first on rewritable replaces instead of appending', () {
      final args = burnProjectArgs(
          _project, _drive, _appendableDvd, const BurnOptions(eraseFirst: true));
      expect(args, containsAllInOrder(['-outdev', '/dev/sr0', '-blank', 'as_needed']));
    });

    test('speed carries the media unit suffix', () {
      String speedFor(MediaInfo m) {
        final a = burnProjectArgs(_project, _drive, m, const BurnOptions(speed: 8));
        return a[a.indexOf('-speed') + 1];
      }

      expect(speedFor(_blankCd), '8c');
      expect(speedFor(_appendableDvd), '8d');
      expect(speedFor(const MediaInfo(profile: 'BD-R sequential recording', present: true, blank: true)), '8b');
    });

    test('simulation: dummy on, no verify so eject happens with the write', () {
      final args = burnProjectArgs(_project, _drive, _blankCd, const BurnOptions(simulate: true));
      expect(args, containsAllInOrder(['-dummy', 'on']));
      expect(args.sublist(args.length - 2), ['-commit_eject', 'all']);
    });

    test('leave open', () {
      final args = burnProjectArgs(_project, _drive, _blankCd, const BurnOptions(closeDisc: false));
      expect(args, containsAllInOrder(['-close', 'off']));
    });
  });

  test('buildIsoArgs escapes graft points', () {
    final args = buildIsoArgs(_project, '/tmp/out.iso');
    expect(args.sublist(0, 2), ['-md5', 'on']);
    expect(args, containsAllInOrder(['-as', 'mkisofs', '-V', 'MY DISC']));
    expect(args, containsAllInOrder(['-o', '/tmp/out.iso', '-graft-points']));
    expect(args, contains('/Photos=/home/u/Photos'));
    expect(args, contains(r'/a\=b.txt=/home/u/a\=b.txt'));
  });

  test('printSizeArgs never commits', () {
    final args = printSizeArgs(_project);
    expect(args, containsAllInOrder(['-outdev', 'stdio:/dev/null']));
    expect(args.sublist(args.length - 2), ['-print_size', '-rollback_end']);
  });

  group('burnImageArgs', () {
    test('defaults', () {
      final args = burnImageArgs('/x.iso', _drive, _blankCd, const BurnOptions());
      expect(args, containsAllInOrder(['-as', 'cdrecord', '-v', 'dev=/dev/sr0']));
      expect(args.last, '/x.iso');
      expect(args, isNot(contains('-eject')));
      expect(args, isNot(contains('-dummy')));
      expect(args, isNot(contains('-multi')));
    });
    test('all switches', () {
      final args = burnImageArgs('/x.iso', _drive, _appendableDvd, const BurnOptions(
        speed: 4, simulate: true, closeDisc: false, eraseFirst: true, verify: false));
      expect(args, containsAll(['speed=4', '-dummy', 'blank=as_needed', '-multi', '-eject']));
      expect(args.last, '/x.iso');
    });
  });

  test('blankArgs', () {
    expect(blankArgs(_drive, BlankMode.fast), containsAllInOrder(['-outdev', '/dev/sr0', '-blank', 'as_needed']));
    expect(blankArgs(_drive, BlankMode.full), containsAllInOrder(['-blank', 'all']));
    expect(blankArgs(_drive, BlankMode.full, simulate: true), containsAllInOrder(['-dummy', 'on']));
  });

  test('verifyArgs loads MD5s before the drive', () {
    final args = verifyArgs(_drive, eject: true);
    expect(args.indexOf('-md5'), lessThan(args.indexOf('-indev')));
    expect(args, containsAllInOrder(['-check_md5', 'FAILURE', '--', '-eject', 'all']));
  });
}
