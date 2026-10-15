"""Ищет русские имена таблиц, оставшиеся в SQL-строках внутри Python.

Схему я перевёл на английский, но в коде остались служебные запросы:
посчитать строки, посмотреть что установилось. Если там забылось
старое имя таблицы, ошибка вылезет только когда до этой ветки дойдёт
дело, и будет ORA-00942.

Скрипт ищет строки, похожие на запрос, и смотрит, нет ли в них
кириллицы. Обычный русский текст — сообщения и подписи в игре — не
трогает, он на запрос не похож.
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Признак того, что строка — это запрос, а не человеческий текст.
LOOKS_LIKE_SQL = re.compile(
    r"\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE|CREATE|DROP|ALTER"
    r"|TRUNCATE|CALL|BEGIN)\b",
    re.I,
)
CYRILLIC = re.compile(r"[А-Яа-яЁё]")

def sql_literals(path: Path):
    """Строковые литералы, похожие на SQL, с номерами строк."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            # Литерал должен НАЧИНАТЬСЯ с ключевого слова: так
            # отсеиваются строки документации и сообщения, где слово
            # SELECT или BEGIN просто упомянуто в тексте.
            if LOOKS_LIKE_SQL.match(node.value.strip()):
                yield node.lineno, node.value

def main() -> int:
    problems = []
    scanned = 0

    for folder in ("python", "tools"):
        for path in sorted((ROOT / folder).glob("*.py")):
            for lineno, text in sql_literals(path):
                scanned += 1
                if CYRILLIC.search(text):
                    snippet = " ".join(text.split())[:80]
                    problems.append(f"{folder}/{path.name}:{lineno}: {snippet}")

    print(f"проверено SQL-литералов: {scanned}")
    if problems:
        print("\n  ПРОВАЛ  кириллица внутри запроса:")
        for line in problems:
            print("      " + line)
        print(f"\nИТОГ: запросов со старыми именами {len(problems)}")
        return 1
    print("  OK      ни в одном запросе нет кириллических имён")
    print("\nИТОГ: SQL в клиенте обращается только к английским именам")
    return 0

if __name__ == "__main__":
    sys.exit(main())
