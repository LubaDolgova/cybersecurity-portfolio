"""Сверяет ключи словарей в клиенте с именами столбцов в SQL.

Зачем. Клиент получает строки из базы словарями, ключ — это имя
столбца или псевдоним из запроса. Опечатку в таком ключе не видно
ничем: она превращается в KeyError прямо во время игры. Смоук-тесты
её тоже не ловят, потому что в заглушке стоит тот же самый
неправильный ключ, и обе стороны ошибаются одинаково.

Поэтому правду тут берём из SQL: имена столбцов из CREATE TABLE и
псевдонимы AS из тела пакета. Всё, чем клиент лезет в словари, должно
быть либо оттуда, либо из короткого списка своих питоновских ключей.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "python"))

from installer import _mask  # noqa: E402

# Ключи, которые клиент придумывает сам: разделы снимка состояния
# в Worker.snapshot и служебные поля.
OWN_KEYS = {
    "state", "halls", "exhibits", "clock", "visitors", "storage",
    "employees", "improvements", "events", "actions", "mix", "days",
    "host", "port", "kind", "database", "user", "password",
}

def sql_names() -> set[str]:
    """Имена столбцов и псевдонимы, которые может вернуть база."""
    names: set[str] = set()

    ddl = (ROOT / "sql" / "01_tables.sql").read_text(encoding="utf-8")
    for body in re.findall(r"CREATE TABLE \w+ \(\n(.*?)\n\);", ddl, re.S):
        for line in body.split("\n"):
            line = line.strip()
            if not line or line.startswith("--"):
                continue
            if line.upper().startswith("CONSTRAINT"):
                continue
            match = re.match(r"([A-Za-z_]\w*)\s", line)
            if match:
                names.add(match.group(1).lower())

    # Псевдонимы столбцов в геттерах: SELECT ... AS visitors_count
    body = _mask((ROOT / "sql" / "05_package_body.sql").read_text(encoding="utf-8"))
    for alias in re.findall(r"\bAS\s+([A-Za-z_]\w*)", body, re.I):
        names.add(alias.lower())

    return names

def python_keys() -> dict[str, set[str]]:
    """Ключи, которыми клиент индексирует словари, по файлам."""
    out: dict[str, set[str]] = {}
    # Индексация словаря, а не литерал списка: перед скобкой должно
    # стоять имя, закрывающая скобка или закрывающий индекс —
    # row["x"], f(...)["x"], items[0]["x"]. Строка ["x", "y"] не подходит.
    # Кириллица в шаблон входит намеренно: оставшийся русский ключ —
    # это недоделанное переименование, и он должен быть виден проверке,
    # а не тихо выпасть из выборки.
    pattern = re.compile(
        r"""(?:(?<=[\w)\]])\[\s*|\.get\(\s*)(['"])"""
        r"""([A-Za-zА-Яа-яЁё_][A-Za-zА-Яа-яЁё0-9_]*)\1"""
    )
    for path in sorted((ROOT / "python").glob("*.py")):
        if path.name in ("installer.py", "check_install.py", "resources.py"):
            continue
        keys = {m.group(2) for m in pattern.finditer(path.read_text(encoding="utf-8"))}
        if keys:
            out[path.name] = keys
    return out

def main() -> int:
    known = sql_names() | OWN_KEYS
    print(f"имён из SQL: {len(sql_names())}, своих ключей клиента: {len(OWN_KEYS)}")

    problems = 0
    for name, keys in python_keys().items():
        unknown = sorted(keys - known)
        if unknown:
            problems += len(unknown)
            print(f"\n  ПРОВАЛ {name}: ключи, которых нет в схеме:")
            for key in unknown:
                print(f"      {key}")
        else:
            print(f"  OK     {name}: все {len(keys)} ключей есть в схеме")

    print()
    if problems:
        print(f"ИТОГ: неизвестных ключей {problems}")
        return 1
    print("ИТОГ: все ключи словарей соответствуют схеме базы")
    return 0

if __name__ == "__main__":
    sys.exit(main())
