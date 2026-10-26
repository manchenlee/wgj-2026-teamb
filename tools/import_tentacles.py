"""Import the four pose animation groups from the art delivery ZIP."""

from pathlib import Path, PurePosixPath
import re
import sys
from zipfile import ZipFile


POSE_PHASES = {"坐姿觸手": 2, "躺姿觸手": 3, "趴姿觸手": 4, "站姿觸手": 5}
TAIL_SIDES = {"左邊尾巴觸手": "left", "中間尾巴觸手": "center", "右邊尾巴觸手": "right"}


def main() -> None:
    archive = Path(sys.argv[1])
    output = Path(__file__).resolve().parents[1] / "assets/art/tentacles"
    count = 0
    with ZipFile(archive) as source:
        for item in source.infolist():
            parts = PurePosixPath(item.filename).parts
            if len(parts) != 3 or not item.filename.endswith(".png"):
                continue
            pose, name = parts[1:]
            phase = POSE_PHASES[pose]
            numbers = re.search(r"(\d+)-(\d+)\.png$", name)
            if name.startswith("尾巴") and numbers:
                filename = f"tail_{numbers[1]}_{numbers[2]}.png"
            elif any(name.startswith(prefix) for prefix in TAIL_SIDES):
                side = next(side for prefix, side in TAIL_SIDES.items() if name.startswith(prefix))
                frame = re.search(r"(\d+)\.png$", name)[1]
                filename = f"tail_{side}_{frame}.png"
            elif numbers:
                filename = f"part_{numbers[1]}_{numbers[2]}.png"
            else:
                raise ValueError(name)
            destination = output / f"phase{phase}" / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source.read(item))
            count += 1
    print(f"Imported {count} PNG files")


if __name__ == "__main__":
    main()
