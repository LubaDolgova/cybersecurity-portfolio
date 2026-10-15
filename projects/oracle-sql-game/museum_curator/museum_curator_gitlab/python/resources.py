"""Ищем файлы и из исходников, и из собранного exe.

Когда игра собрана в exe, файлы распаковываются во временную папку,
и путь к ней лежит в sys._MEIPASS. Поэтому sql надо искать там,
а не рядом с кодом.

А файл настроек наоборот должен лежать рядом с exe и никуда не
деваться после перезапуска.
"""
from __future__ import annotations

import sys
from pathlib import Path


def is_frozen() -> bool:
    """Мы сейчас внутри exe или запущены как обычный скрипт?"""
    return getattr(sys, "frozen", False)


def resource_dir() -> Path:
    """Где лежат вложенные файлы.

    В exe это временная папка, в исходниках — корень проекта.
    """
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return Path(base)
    return Path(__file__).resolve().parent.parent


def sql_dir() -> Path:
    """Папка с sql-скриптами."""
    return resource_dir() / "sql"


def sql_file(name: str) -> Path:
    """Путь к одному скрипту. Если его нет, скажем об этом понятно."""
    path = sql_dir() / name
    if not path.is_file():
        raise FileNotFoundError(
            f"Не найден скрипт установки {name}.\n"
            f"Искали в папке: {sql_dir()}\n"
            "Если это собранный exe — скрипты не попали в сборку, "
            "пересоберите его через build_exe.ps1."
        )
    return path


def app_dir() -> Path:
    """Рядом с чем хранить настройки: с exe или с проектом."""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def settings_file() -> Path:
    """Файл, куда пишем адрес базы и логин."""
    return app_dir() / "museum_connection.json"
