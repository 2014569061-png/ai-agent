// 附件准入策略的边界：选择阶段与发送阶段共用同一组限额，这里锁住它们。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/attachment_policy.dart';

void main() {
  group('限额常量', () {
    test('单一来源：8MB 单文件、24MB 总量、10 个数量', () {
      expect(maxAttachmentBytes, 8 * 1024 * 1024);
      expect(maxAttachmentTotalBytes, 24 * 1024 * 1024);
      expect(maxAttachmentCount, 10);
    });

    test('MB 文案由字节数推导，不会与上限漂移', () {
      expect(maxAttachmentMegabytes, 8);
      expect(maxAttachmentTotalMegabytes, 24);
    });

    test('总预算大于单文件上限，否则多附件预算形同虚设', () {
      expect(maxAttachmentTotalBytes, greaterThan(maxAttachmentBytes));
    });
  });

  group('remainingAttachmentSlots', () {
    test('空列表时可添加满额', () {
      expect(remainingAttachmentSlots(0), maxAttachmentCount);
    });

    test('部分占用时递减', () {
      expect(remainingAttachmentSlots(3), maxAttachmentCount - 3);
    });

    test('已达上限时为 0', () {
      expect(remainingAttachmentSlots(maxAttachmentCount), 0);
    });

    test('超出上限（数据异常）时钳到 0，不返回负数', () {
      expect(remainingAttachmentSlots(maxAttachmentCount + 5), 0);
    });
  });

  group('fitsIntoBudget', () {
    test('常规文件可接受', () {
      expect(fitsIntoBudget(size: 1024, usedBytes: 0), isTrue);
    });

    test('恰好等于单文件上限可接受（闭区间）', () {
      expect(
        fitsIntoBudget(size: maxAttachmentBytes, usedBytes: 0),
        isTrue,
      );
    });

    test('超过单文件上限一个字节即拒绝', () {
      expect(
        fitsIntoBudget(size: maxAttachmentBytes + 1, usedBytes: 0),
        isFalse,
      );
    });

    test('空文件与负大小拒绝', () {
      expect(fitsIntoBudget(size: 0, usedBytes: 0), isFalse);
      expect(fitsIntoBudget(size: -1, usedBytes: 0), isFalse);
    });

    test('恰好用满总预算可接受', () {
      expect(
        fitsIntoBudget(
          size: maxAttachmentBytes,
          usedBytes: maxAttachmentTotalBytes - maxAttachmentBytes,
        ),
        isTrue,
      );
    });

    test('再超一个字节就越过总预算', () {
      expect(
        fitsIntoBudget(
          size: maxAttachmentBytes,
          usedBytes: maxAttachmentTotalBytes - maxAttachmentBytes + 1,
        ),
        isFalse,
      );
    });

    test('单个文件合规但已被前面的附件吃掉预算时拒绝', () {
      expect(
        fitsIntoBudget(size: 1024, usedBytes: maxAttachmentTotalBytes),
        isFalse,
      );
    });
  });

  group('扩展名单（选择器与发送端的单一来源）', () {
    test('名单与发送端真实能力一致：5 种图片 + 4 种文本', () {
      expect(
        acceptedAttachmentExtensions,
        ['csv', 'gif', 'jpeg', 'jpg', 'json', 'md', 'png', 'txt', 'webp'],
      );
    });

    test('名单已排序且不可变，避免渲染顺序随机', () {
      final list = acceptedAttachmentExtensions;
      final sorted = [...list]..sort();
      expect(list, sorted);
      expect(() => list.add('x'), throwsUnsupportedError);
    });

    test('音视频不在名单内：Provider 支持尚不可靠，宁可不让选', () {
      for (final ext in ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'mp4', 'mov']) {
        expect(acceptedAttachmentExtensions, isNot(contains(ext)),
            reason: '$ext 目前发出后会被丢弃');
      }
    });

    test('图片 MIME 映射正确', () {
      expect(imageMimeForExtension('png'), 'image/png');
      expect(imageMimeForExtension('jpg'), 'image/jpeg');
      expect(imageMimeForExtension('jpeg'), 'image/jpeg');
      expect(imageMimeForExtension('webp'), 'image/webp');
      expect(imageMimeForExtension('gif'), 'image/gif');
    });

    test('图片 MIME 大小写不敏感', () {
      expect(imageMimeForExtension('PNG'), 'image/png');
      expect(imageMimeForExtension('JpEg'), 'image/jpeg');
      expect(imageMimeForExtension('WEBP'), 'image/webp');
    });

    test('非图片/未知/空扩展名没有 MIME', () {
      expect(imageMimeForExtension('mp3'), isNull);
      expect(imageMimeForExtension('mp4'), isNull);
      expect(imageMimeForExtension(''), isNull);
      expect(imageMimeForExtension(null), isNull);
    });

    test('文本扩展名判定，大小写不敏感', () {
      for (final ext in ['txt', 'md', 'csv', 'json', 'TXT', 'Md']) {
        expect(isTextAttachmentExtension(ext), isTrue, reason: ext);
      }
      expect(isTextAttachmentExtension('png'), isFalse);
      expect(isTextAttachmentExtension('mp3'), isFalse);
      expect(isTextAttachmentExtension(null), isFalse);
    });

    test('名单里的每个扩展名都能被发送端归类，不会「能选不能发」', () {
      for (final ext in acceptedAttachmentExtensions) {
        final handled = imageMimeForExtension(ext) != null ||
            isTextAttachmentExtension(ext);
        expect(handled, isTrue, reason: '$ext 在选择器里却发不出去');
      }
    });
  });

  group('文件名级图片判定（缩略图用）', () {
    test('gif 必须被认成图片：此前硬编码名单漏了它', () {
      expect(isImageAttachmentFileName('anim.gif'), isTrue);
    });

    test('常见图片后缀都认', () {
      for (final name in ['a.png', 'b.jpg', 'c.jpeg', 'd.webp', 'e.GIF']) {
        expect(isImageAttachmentFileName(name), isTrue, reason: name);
      }
    });

    test('音频/视频/文本不算图片', () {
      for (final name in ['a.mp3', 'b.mp4', 'c.txt', 'd.md', 'e.json']) {
        expect(isImageAttachmentFileName(name), isFalse, reason: name);
      }
    });

    test('无扩展名或点结尾不算图片', () {
      expect(isImageAttachmentFileName('noext'), isFalse);
      expect(isImageAttachmentFileName('trailing.'), isFalse);
    });

    test('只取最后一个点之后的扩展名', () {
      expect(isImageAttachmentFileName('my.photo.png'), isTrue);
      expect(isImageAttachmentFileName('archive.png.zip'), isFalse);
    });

    test('路径分隔符不会被误当成扩展名（调用方传文件名）', () {
      // 含目录时最后一段没有合法扩展名，则应返回 false 而不是碰巧匹配。
      expect(isImageAttachmentFileName('dir.png/file'), isFalse);
    });

    test('文件名 MIME 与扩展名映射一致', () {
      expect(imageMimeForFileName('a.png'), 'image/png');
      expect(imageMimeForFileName('a.gif'), 'image/gif');
      expect(imageMimeForFileName('a.txt'), isNull);
    });
  });
}