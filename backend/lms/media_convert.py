# -*- coding: utf-8 -*-
"""Conversion Office (PPT/PPTX) → PDF pour lecture native dans l'app mobile."""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from django.core.files import File

logger = logging.getLogger(__name__)

_PPT_EXTENSIONS = {".ppt", ".pptx", ".odp", ".pps", ".ppsx"}


def _find_libreoffice() -> str | None:
    for name in ("soffice", "libreoffice"):
        path = shutil.which(name)
        if path:
            return path
    # Chemins courants Debian/Ubuntu
    for candidate in (
        "/usr/bin/soffice",
        "/usr/bin/libreoffice",
        "/usr/lib/libreoffice/program/soffice",
    ):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def libreoffice_available() -> bool:
    return _find_libreoffice() is not None


def convert_file_to_pdf(source_path: str | Path, dest_pdf: str | Path) -> bool:
    """Convertit un fichier Office en PDF via LibreOffice headless."""
    source = Path(source_path)
    dest = Path(dest_pdf)
    if not source.is_file():
        logger.error("Source introuvable pour conversion: %s", source)
        return False

    soffice = _find_libreoffice()
    if not soffice:
        logger.error("LibreOffice introuvable — impossible de convertir %s", source.name)
        return False

    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="yekola_ppt_") as tmp:
        tmp_dir = Path(tmp)
        cmd = [
            soffice,
            "--headless",
            "--nologo",
            "--nolockcheck",
            "--norestore",
            "--convert-to",
            "pdf",
            "--outdir",
            str(tmp_dir),
            str(source.resolve()),
        ]
        try:
            result = subprocess.run(
                cmd,
                check=False,
                capture_output=True,
                text=True,
                timeout=180,
                env={**os.environ, "HOME": tmp},
            )
        except subprocess.TimeoutExpired:
            logger.error("Timeout conversion LibreOffice: %s", source.name)
            return False
        except OSError as exc:
            logger.error("Erreur lancement LibreOffice: %s", exc)
            return False

        produced = tmp_dir / f"{source.stem}.pdf"
        if not produced.is_file():
            # Parfois LibreOffice renomme légèrement
            pdfs = list(tmp_dir.glob("*.pdf"))
            if not pdfs:
                logger.error(
                    "Conversion PDF échouée (%s): %s %s",
                    result.returncode,
                    result.stdout,
                    result.stderr,
                )
                return False
            produced = pdfs[0]

        shutil.copy2(produced, dest)
    return dest.is_file() and dest.stat().st_size > 0


def ensure_lesson_preview(lesson) -> bool:
    """
    Génère lesson.preview_file (PDF) pour les leçons PowerPoint.
    Pour PDF : pas de conversion (view_file = content_file côté API).
    Retourne True si un aperçu PDF est disponible.
    """
    from lms.models import Lesson

    if not isinstance(lesson, Lesson):
        return False

    if lesson.content_type == "PDF" and lesson.content_file:
        return True

    if lesson.content_type != "PPT" or not lesson.content_file:
        return False

    try:
        if not lesson.content_file.storage.exists(lesson.content_file.name):
            logger.warning("Fichier PPT manquant: %s", lesson.content_file.name)
            return False
    except Exception as exc:
        logger.warning("Vérification fichier PPT: %s", exc)
        return False

    src_name = lesson.content_file.name
    ext = Path(src_name).suffix.lower()
    if ext not in _PPT_EXTENSIONS:
        logger.warning("Extension non PPT ignorée: %s", ext)
        return False

    # Déjà converti pour ce même fichier source ?
    if lesson.preview_file:
        try:
            if lesson.preview_file.storage.exists(lesson.preview_file.name):
                # Si le nom source est stocké en meta via le nom du preview
                return True
        except Exception:
            pass

    try:
        with tempfile.TemporaryDirectory(prefix="yekola_src_") as tmp:
            tmp_path = Path(tmp)
            local_src = tmp_path / Path(src_name).name
            with lesson.content_file.open("rb") as src_fh:
                local_src.write_bytes(src_fh.read())

            local_pdf = tmp_path / f"lesson_{lesson.pk}_preview.pdf"
            if not convert_file_to_pdf(local_src, local_pdf):
                return False

            # Évite de re-déclencher une conversion en boucle
            preview_name = f"lesson_{lesson.pk}_{Path(src_name).stem}.pdf"
            with local_pdf.open("rb") as pdf_fh:
                lesson.preview_file.save(preview_name, File(pdf_fh), save=False)
            Lesson.objects.filter(pk=lesson.pk).update(preview_file=lesson.preview_file.name)
            lesson.refresh_from_db(fields=["preview_file"])
            logger.info("Aperçu PDF généré pour leçon #%s", lesson.pk)
            return True
    except Exception as exc:
        logger.exception("ensure_lesson_preview leçon #%s: %s", lesson.pk, exc)
        return False
