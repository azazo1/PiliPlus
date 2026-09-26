#!/usr/bin/env python3
"""todo remove 小窗 spike: 给 media_kit AndroidVideoController 加上 overlay wid 接管."""

from __future__ import annotations

import os
from pathlib import Path


def find_controller() -> Path:
    roots: list[Path] = []
    pub = os.environ.get("PUB_CACHE")
    if pub:
        roots.append(Path(pub))
    roots.append(Path.home() / ".pub-cache")
    for root in roots:
        matches = list(
            root.glob(
                "git/**/media_kit_video/lib/src/video_controller/android_video_controller/real.dart"
            )
        )
        if matches:
            return matches[0]
    raise SystemExit("android_video_controller/real.dart not found in pub-cache")


INSERT = """  int? _overlayWid;

  static AndroidVideoController? of(Player player) =>
      _controllers[player.handle];

  void attachOverlayWid(int wid) {
    _overlayWid = wid;
  }

  Future<void> detachOverlayWid() async {
    _overlayWid = null;
    final data = await _channel.invokeMethod(
      'VideoOutputManager.CreateSurface',
      {'handle': player.handle.toString()},
    );
    _wid = data['wid'];
    player.setOption('vo', 'null');
    player.setOption('wid', '0');
    player.setOption('wid', _wid.toString());
    player.setOption('vo', vo);
  }

"""


def main() -> None:
    path = find_controller()
    text = path.read_text()
    if "_overlayWid" in text:
        print("already patched", path)
        return
    old_wid = "player.setOption('wid', _wid.toString());"
    new_wid = "player.setOption('wid', (_overlayWid ?? _wid).toString());"
    if old_wid not in text:
        raise SystemExit("wid setOption pattern not found")
    text = text.replace(old_wid, new_wid)
    marker = "  /// Disposes the instance."
    if marker not in text:
        raise SystemExit("dispose marker not found")
    text = text.replace(marker, INSERT + marker, 1)
    path.write_text(text)
    print("patched", path)


if __name__ == "__main__":
    main()
