from io import BytesIO
from pathlib import Path
import stat
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile, ZipInfo

from unpack_app import read_archive, write_or_check


def archive_bytes(entries):
    stream = BytesIO()
    with ZipFile(stream, "w") as archive:
        for name, data in entries:
            archive.writestr(name, data)
    return stream.getvalue()


class UnpackTests(unittest.TestCase):
    def test_rejects_unsafe_paths(self):
        for path in ("../escape", "/absolute", "C:/drive", "a\\..\\escape"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                read_archive(archive_bytes([(path, b"data")]))

    def test_rejects_case_collisions_on_windows(self):
        with self.assertRaises(ValueError):
            read_archive(archive_bytes([("A.json", b"1"), ("a.json", b"2")]))

    def test_rejects_symbolic_links(self):
        link = ZipInfo("link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(ValueError):
            read_archive(archive_bytes([(link, b"../outside")]))

    def test_roundtrip_is_idempotent(self):
        files = read_archive(archive_bytes([("data/a.json", b'{"n": 1}')] ))
        with TemporaryDirectory() as directory:
            output = Path(directory)
            write_or_check(output, files)
            write_or_check(output, files)
            write_or_check(output, files, check=True)
            self.assertEqual((output / "data/a.json").read_bytes(), files["data/a.json"])

    def test_refuses_overwrite_before_creating_other_files(self):
        with TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "edited.json").write_bytes(b"user edit")
            with self.assertRaises(ValueError):
                write_or_check(output, {"new.json": b"new", "edited.json": b"original"})
            self.assertFalse((output / "new.json").exists())
            self.assertEqual((output / "edited.json").read_bytes(), b"user edit")

    def test_check_never_creates_output(self):
        with TemporaryDirectory() as directory:
            output = Path(directory) / "missing"
            with self.assertRaises(ValueError):
                write_or_check(output, {"data.json": b"data"}, check=True)
            self.assertFalse(output.exists())

    def test_rejects_output_escape(self):
        with TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                write_or_check(Path(directory) / "output", {"../escape": b"data"})
            self.assertFalse((Path(directory) / "escape").exists())


if __name__ == "__main__":
    unittest.main()
