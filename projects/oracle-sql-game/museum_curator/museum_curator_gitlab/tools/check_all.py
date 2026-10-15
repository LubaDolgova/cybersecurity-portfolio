"""Запускает все проверки, которым не нужен сервер Oracle.

Запуск из корня проекта:

    .\\.venv\\Scripts\\python.exe tools\\check_all.py

Если код возврата 0, значит всё хорошо.

Чего тут нет: сам пакет не компилируется и настоящих запросов не
выполняется, для этого нужна живая база. На сервере для этого есть
python\\check_runtime.py.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STEPS = [
    ("Статический контроль SQL и клиента", ["tools/verify.py"], ROOT),
    ("Ключи словарей против схемы", ["tools/check_keys.py"], ROOT),
    ("Ключи против конкретных курсоров", ["tools/check_columns.py"], ROOT),
    ("Коды действий, параметры, аргументы", ["tools/check_calls.py"], ROOT),
    ("Разбор скриптов установки на операторы", ["tools/check_install_scripts.py"], ROOT),
    ("Кириллица в SQL-запросах клиента", ["tools/check_sql_in_python.py"], ROOT),
    ("Интерфейс: все экраны и диалоги", ["smoke_ui.py"], ROOT / "python"),
    ("Границы: пустой музей, банкротство, обрыв связи", ["smoke_edge.py"], ROOT / "python"),
]

def main() -> int:
    failed: list[str] = []
    width = max(len(title) for title, _, _ in STEPS)

    for title, args, cwd in STEPS:
        print("=" * 72)
        print(f" {title}")
        print("=" * 72)
        result = subprocess.run(
            [sys.executable, *args], cwd=cwd,
            env={**_env(), "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
        )
        if result.returncode != 0:
            failed.append(title)
        print()

    print("=" * 72)
    for title, _, _ in STEPS:
        mark = "ПРОВАЛ" if title in failed else "  OK  "
        print(f" {mark}  {title.ljust(width)}")
    print("=" * 72)

    if failed:
        print(f"\nПРОВАЛОВ: {len(failed)}")
        return 1
    print("\nВСЕ ПРОВЕРКИ БЕЗ БАЗЫ ПРОЙДЕНЫ")
    print("Осталось прогнать на живом сервере: python\\check_runtime.py")
    return 0

def _env() -> dict:
    import os
    return dict(os.environ)

if __name__ == "__main__":
    sys.exit(main())
