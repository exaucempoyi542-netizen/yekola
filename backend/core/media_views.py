"""Serve media files with HTTP Range support (required for mobile video seeking)."""
from __future__ import annotations

import mimetypes
import re
from pathlib import Path

from django.conf import settings
from django.http import FileResponse, Http404, HttpResponse, HttpResponseNotModified
from django.utils.http import http_date
from django.views.static import was_modified_since

_RANGE_RE = re.compile(r"bytes\s*=\s*(\d*)\s*-\s*(\d*)", re.I)


class RangeFileWrapper:
    def __init__(self, fileobj, offset: int, length: int, chunk_size: int = 8192):
        self.fileobj = fileobj
        self.remaining = length
        self.chunk_size = chunk_size
        self.fileobj.seek(offset)

    def __iter__(self):
        return self

    def __next__(self):
        if self.remaining <= 0:
            self.close()
            raise StopIteration
        data = self.fileobj.read(min(self.chunk_size, self.remaining))
        if not data:
            self.close()
            raise StopIteration
        self.remaining -= len(data)
        return data

    def close(self):
        try:
            self.fileobj.close()
        except Exception:
            pass


def media_serve(request, path: str):
    root = Path(settings.MEDIA_ROOT).resolve()
    full = (root / path).resolve()
    try:
        full.relative_to(root)
    except ValueError as exc:
        raise Http404("Invalid path") from exc

    if not full.is_file():
        raise Http404("File not found")

    stat = full.stat()
    content_type, encoding = mimetypes.guess_type(str(full))
    content_type = content_type or "application/octet-stream"
    size = stat.st_size

    if not was_modified_since(
        request.META.get("HTTP_IF_MODIFIED_SINCE"),
        stat.st_mtime,
        size,
    ):
        return HttpResponseNotModified()

    range_header = (request.META.get("HTTP_RANGE") or "").strip()
    if range_header:
        match = _RANGE_RE.match(range_header)
        if not match:
            return HttpResponse(status=400)
        start_s, end_s = match.groups()
        start = int(start_s) if start_s else 0
        end = int(end_s) if end_s else size - 1
        if start >= size or start < 0 or end < start:
            resp = HttpResponse(status=416)
            resp["Content-Range"] = f"bytes */{size}"
            return resp
        end = min(end, size - 1)
        length = end - start + 1
        fh = open(full, "rb")
        wrapper = RangeFileWrapper(fh, start, length)
        resp = FileResponse(wrapper, status=206, content_type=content_type)
        resp["Content-Length"] = str(length)
        resp["Content-Range"] = f"bytes {start}-{end}/{size}"
        resp["Accept-Ranges"] = "bytes"
        resp["Last-Modified"] = http_date(stat.st_mtime)
        if encoding:
            resp["Content-Encoding"] = encoding
        return resp

    fh = open(full, "rb")
    resp = FileResponse(fh, content_type=content_type)
    resp["Content-Length"] = str(size)
    resp["Accept-Ranges"] = "bytes"
    resp["Last-Modified"] = http_date(stat.st_mtime)
    if encoding:
        resp["Content-Encoding"] = encoding
    return resp
