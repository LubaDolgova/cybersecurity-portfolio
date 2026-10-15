"""Достаёт из пакета список столбцов, которые отдаёт каждый курсор.

Каждая функция пакета с SYS_REFCURSOR открывает один запрос. Имена
столбцов этого запроса — это ровно те ключи, по которым клиент потом
будет читать словарь. Разбираю их прямо из текста пакета, база для
этого не нужна.

Как определяю имя: если есть «AS псевдоним» — беру псевдоним, иначе
то, что после точки (z.hall_name -> hall_name).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "python"))

from installer import _mask  # noqa: E402

def _split_top_level(text: str) -> list[str]:
    """Разбить список выборки по запятым верхнего уровня."""
    parts, depth, current = [], 0, []
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if current:
        parts.append("".join(current))
    return [p.strip() for p in parts if p.strip()]

def _select_list(query: str) -> str | None:
    """Вернуть текст между SELECT и его собственным FROM.

    Учитывается вложенность: подзапросы в списке выборки имеют свои
    SELECT и FROM, их пропускаем. Для запроса с WITH берём последний
    SELECT нулевого уровня — это и есть итоговая выборка.
    """
    depth = 0
    select_at = None
    for match in re.finditer(r"\(|\)|\bSELECT\b|\bFROM\b", query, re.I):
        token = match.group(0).upper()
        if token == "(":
            depth += 1
        elif token == ")":
            depth -= 1
        elif depth == 0 and token == "SELECT":
            select_at = match.end()
        elif depth == 0 and token == "FROM" and select_at is not None:
            return query[select_at:match.start()]
    return None

def _column_name(item: str) -> str | None:
    """Имя столбца для одного элемента списка выборки."""
    alias = re.search(r"\bAS\s+([A-Za-z_]\w*)\s*$", item, re.I | re.S)
    if alias:
        return alias.group(1).lower()
    bare = item.strip()
    # Простой столбец, возможно с префиксом таблицы.
    simple = re.fullmatch(r"([A-Za-z_]\w*\.)?([A-Za-z_]\w*)", bare)
    if simple:
        return simple.group(2).lower()
    return None

def _subquery_after_from(query: str) -> str | None:
    """Текст первого подзапроса в скобках после FROM нулевого уровня."""
    depth = 0
    from_at = None
    for match in re.finditer(r"\(|\)|\bFROM\b", query, re.I):
        token = match.group(0).upper()
        if token == "(":
            if from_at is not None:
                start = match.end()
                level = 1
                for inner in re.finditer(r"\(|\)", query[start:]):
                    level += 1 if inner.group(0) == "(" else -1
                    if level == 0:
                        return query[start:start + inner.start()]
                return None
            depth += 1
        elif token == ")":
            depth -= 1
        elif depth == 0 and token == "FROM":
            from_at = match.end()
    return None

def cursor_columns() -> dict[str, list[str]]:
    """{имя функции пакета: список имён столбцов её курсора}."""
    body = _mask((ROOT / "sql" / "05_package_body.sql").read_text(encoding="utf-8"))
    out: dict[str, list[str]] = {}

    pattern = re.compile(
        r"\bFUNCTION\s+([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s*RETURN\s+SYS_REFCURSOR\s+IS"
        r"(.*?)\bEND\s+\1\s*;",
        re.I | re.S,
    )
    for match in pattern.finditer(body):
        name, code = match.group(1).lower(), match.group(2)
        open_for = re.search(r"\bOPEN\s+\w+\s+FOR\b(.*)$", code, re.I | re.S)
        if not open_for:
            out[name] = []
            continue
        query = open_for.group(1)
        # Обрезаем всё после запроса: RETURN c; и остальное.
        query = re.split(r";\s*RETURN\b", query, maxsplit=1)[0]
        select_list = _select_list(query)
        # SELECT * FROM (подзапрос) — приём для ROWNUM: имена столбцов
        # задаёт внутренний запрос, в него и заглядываем.
        hops = 0
        while select_list is not None and hops < 3 and \
                re.fullmatch(r"(\w+\.)?\*", select_list.strip()):
            inner = _subquery_after_from(query)
            if inner is None:
                break
            query = inner
            select_list = _select_list(query)
            hops += 1
        if select_list is None:
            out[name] = []
            continue
        columns = []
        for item in _split_top_level(select_list):
            column = _column_name(item)
            if column:
                columns.append(column)
        out[name] = columns
    return out

if __name__ == "__main__":
    data = cursor_columns()
    print(f"геттеров с курсором: {len(data)}\n")
    for name in sorted(data):
        columns = data[name]
        mark = "  " if columns else "!!"
        print(f"{mark} {name:26} {len(columns):2}  {', '.join(columns)}")
    empty = [n for n, c in data.items() if not c]
    if empty:
        print(f"\nне разобрались: {empty}")
