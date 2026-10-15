"""Сверяет клиента с каждым курсором пакета по отдельности.

check_keys.py проверяет мягче: есть ли такой столбец хоть где-то в
схеме. Тут строже — читает ли клиент у КОНКРЕТНОГО курсора только те
столбцы, которые этот курсор правда отдаёт.

Всю цепочку скрипт находит сам:

    main.py   self.snap("halls")      ->  раздел снимка
    main.py   Worker._refresh         ->  какой метод db его наполняет
    db.py     self._rows("get_halls") ->  какая функция пакета
    05_...    OPEN c FOR SELECT ...   ->  какие столбцы она отдаёт

Так ловится и опечатка, и обращение к столбцу, который в таблице есть,
но именно этот запрос его не возвращает.
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from columns import cursor_columns  # noqa: E402
from taint import Analyzer  # noqa: E402

PY = ROOT / "python"

# Разделы снимка, которые не являются строками из курсора.
NOT_A_ROW = {"visitors"}

def db_method_to_getter() -> dict[str, str]:
    """{метод db.py: функция пакета} — из тела db.py."""
    source = (PY / "db.py").read_text(encoding="utf-8")
    tree = ast.parse(source)
    out: dict[str, str] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        for call in ast.walk(node):
            if not isinstance(call, ast.Call):
                continue
            func = call.func
            if not (isinstance(func, ast.Attribute)
                    and func.attr in ("_rows", "_one", "_call", "_func", "dbms_output")):
                continue
            if call.args and isinstance(call.args[0], ast.Constant) \
                    and isinstance(call.args[0].value, str):
                out[node.name] = call.args[0].value
                break
    return out

def snapshot_to_db_method() -> dict[str, str]:
    """{раздел снимка: метод db.py} — из Worker._refresh в main.py."""
    source = (PY / "main.py").read_text(encoding="utf-8")
    tree = ast.parse(source)
    out: dict[str, str] = {}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.FunctionDef) and node.name == "_refresh"):
            continue
        for assign in ast.walk(node):
            if not isinstance(assign, ast.Assign) or len(assign.targets) != 1:
                continue
            target = assign.targets[0]
            if not (isinstance(target, ast.Subscript)
                    and isinstance(target.value, ast.Name)
                    and target.value.id == "snap"
                    and isinstance(target.slice, ast.Constant)):
                continue
            key = target.slice.value
            call = assign.value
            if isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute):
                out[key] = call.func.attr
    return out

def used_keys_by_section() -> tuple[dict[str, set[str]], int, int]:
    """Какие ключи клиент читает у каждого раздела снимка."""
    analyzer = Analyzer((PY / "main.py").read_text(encoding="utf-8"))
    return analyzer.keys_by_section()

def main() -> int:
    getters = cursor_columns()
    db_map = db_method_to_getter()
    snap_map = snapshot_to_db_method()
    used, linked, total = used_keys_by_section()

    print("=== связи, выведенные автоматически ===")
    for section in sorted(snap_map):
        method = snap_map[section]
        getter = db_map.get(method, "?")
        count = len(getters.get(getter, []))
        print(f"  {section:12} -> db.{method:18} -> {getter:22} столбцов {count}")

    print("\n=== сверка ключей по каждому курсору ===")
    fails = 0
    for section in sorted(used):
        keys = used[section]
        if section in NOT_A_ROW:
            print(f"  --     {section:12} не строка курсора, пропуск")
            continue
        method = snap_map.get(section)
        getter = db_map.get(method or "", "")
        available = set(getters.get(getter, []))
        if not available:
            print(f"  ВНИМ   {section:12} не удалось сопоставить с курсором")
            continue
        unknown = sorted(keys - available)
        if unknown:
            fails += len(unknown)
            print(f"  ПРОВАЛ {section:12} {getter}: нет столбцов {unknown}")
        else:
            print(f"  OK     {section:12} {getter}: все {len(keys)} ключей на месте")

    print(f"\nпривязано к разделам обращений: {linked} из {total} "
          f"({100 * linked // max(total, 1)}%)")
    print("остальные — служебные словари клиента и результаты колбэков,")
    print("их покрывает check_keys.py и сквозная проверка на сервере.")

    print()
    if fails:
        print(f"ИТОГ: неверных ключей {fails}")
        return 1
    print("ИТОГ: клиент читает только те столбцы, которые отдают курсоры")
    return 0

if __name__ == "__main__":
    sys.exit(main())
