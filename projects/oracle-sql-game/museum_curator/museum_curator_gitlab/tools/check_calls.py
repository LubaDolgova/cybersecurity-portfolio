"""Сверяет, как клиент зовёт пакет: коды действий, параметры, аргументы.

Есть три ошибки, которые не видно ни при запуске Python, ни при
компиляции пакета. Вылезают только когда нажмёшь кнопку в игре:

  1. клиент кладёт в очередь код действия, которого пакет не знает —
     действие тихо уходит в «Ошибка»;

  2. клиент шлёт параметр под одним именем, а пакет читает другое —
     действие выполняется с пустым значением;

  3. аргументов в вызове больше или меньше, чем объявлено — Oracle
     отвечает ORA-06550.

Правду берём из пакета: из спецификации и из его диспетчера действий.
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "python"))

from installer import _mask  # noqa: E402

PY = ROOT / "python"
SQL = ROOT / "sql"

FAILS: list[str] = []

def ok(title: str, good: bool, note: str = "") -> None:
    print(("  OK     " if good else "  ПРОВАЛ ") + title + (f"   [{note}]" if note else ""))
    if not good:
        FAILS.append(f"{title} — {note}" if note else title)

#  Что знает пакет
def package_signatures() -> dict[str, tuple[int, int]]:
    """{подпрограмма: (минимум аргументов, максимум)} из спецификации.

    Минимум — без параметров со значением по умолчанию.
    """
    spec = _mask((SQL / "04_package_spec.sql").read_text(encoding="utf-8"))
    out: dict[str, tuple[int, int]] = {}
    pattern = re.compile(
        r"\b(?:PROCEDURE|FUNCTION)\s+([A-Za-z_]\w*)\s*(\(([^;]*?)\))?\s*"
        r"(?:RETURN\s+[A-Za-z_][\w. ]*)?\s*;",
        re.I | re.S,
    )
    for match in pattern.finditer(spec):
        name = match.group(1).lower()
        params_text = match.group(3) or ""
        params = [p.strip() for p in _split_params(params_text) if p.strip()]
        optional = sum(1 for p in params if re.search(r"\bDEFAULT\b", p, re.I))
        out[name] = (len(params) - optional, len(params))
    return out

def _split_params(text: str) -> list[str]:
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
    return parts

def dispatcher_codes() -> set[str]:
    """Коды действий, которые различает диспетчер пакета."""
    body = (SQL / "05_package_body.sql").read_text(encoding="utf-8")
    # Коды сравниваются со строковыми литералами: p_code = 'OPEN_HALL'
    return set(re.findall(r"'([A-Z][A-Z_]{3,})'", body))

def action_params() -> set[str]:
    """Имена параметров действий, которые пакет читает из очереди.

    В теле это f_param(p_params, 'NAME') для строк
    и f_param_num(p_params, 'HALL') для чисел.
    """
    body = (SQL / "05_package_body.sql").read_text(encoding="utf-8")
    # Строковые параметры читает f_param, числовые — f_param_num.
    return set(re.findall(
        r"\bf_param(?:_num)?\s*\(\s*[A-Za-z_]\w*\s*,\s*'([A-Z_]+)'", body))

#  Что делает клиент
def client_enqueues() -> dict[str, set[str]]:
    """{код действия: имена параметров} из main.py."""
    tree = ast.parse((PY / "main.py").read_text(encoding="utf-8"))
    out: dict[str, set[str]] = {}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "enqueue" and node.args):
            continue
        code_node = node.args[0]
        if not (isinstance(code_node, ast.Constant) and isinstance(code_node.value, str)):
            continue
        params: set[str] = set()
        if len(node.args) > 1 and isinstance(node.args[1], ast.Dict):
            for key in node.args[1].keys:
                if isinstance(key, ast.Constant) and isinstance(key.value, str):
                    params.add(key.value)
        out.setdefault(code_node.value, set()).update(params)
    return out

def client_calls() -> list[tuple[str, str, int]]:
    """[(метод db.py, подпрограмма пакета, число переданных аргументов)]."""
    tree = ast.parse((PY / "db.py").read_text(encoding="utf-8"))
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        for call in ast.walk(node):
            if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                    and call.func.attr in ("_rows", "_one", "_call", "_func",
                                           "dbms_output")):
                continue
            if not (call.args and isinstance(call.args[0], ast.Constant)):
                continue
            name = call.args[0].value
            count = 0
            # Второй аргумент — кортеж или список фактических параметров.
            if len(call.args) > 1 and isinstance(call.args[1], (ast.Tuple, ast.List)):
                count = len(call.args[1].elts)
            elif call.func.attr == "_func" and len(call.args) > 2 \
                    and isinstance(call.args[2], (ast.Tuple, ast.List)):
                count = len(call.args[2].elts)
            out.append((node.name, name, count))
            break
    return out

def main() -> int:
    print("=== 1. КОДЫ ДЕЙСТВИЙ ===")
    codes = dispatcher_codes()
    used = client_enqueues()
    unknown = sorted(set(used) - codes)
    ok(f"все {len(used)} кодов действий клиента известны пакету", not unknown,
       ", ".join(unknown))
    print(f"         клиент использует: {', '.join(sorted(used))}")

    print("\n=== 2. ПАРАМЕТРЫ ДЕЙСТВИЙ ===")
    known_params = action_params()
    sent = set()
    for names in used.values():
        sent |= names
    unread = sorted(sent - known_params)
    ok("каждый параметр, который клиент передаёт, пакет читает", not unread,
       ", ".join(unread))
    print(f"         клиент передаёт: {', '.join(sorted(sent))}")
    ignored = sorted(known_params - sent)
    if ignored:
        print(f"         пакет умеет читать ещё: {', '.join(ignored)} (не ошибка)")

    print("\n=== 3. ЧИСЛО АРГУМЕНТОВ В ВЫЗОВАХ ПАКЕТА ===")
    signatures = package_signatures()
    problems = []
    checked = 0
    for method, routine, count in client_calls():
        signature = signatures.get(routine.lower())
        if signature is None:
            problems.append(f"db.{method}: в спецификации нет {routine}")
            continue
        low, high = signature
        checked += 1
        if not (low <= count <= high):
            problems.append(
                f"db.{method} -> {routine}: передано {count}, "
                f"а объявлено от {low} до {high}"
            )
    ok(f"во всех {checked} вызовах число аргументов допустимо", not problems)
    for line in problems:
        print("         " + line)

    print()
    if FAILS:
        print(f"ИТОГ: ПРОВАЛОВ {len(FAILS)}")
        return 1
    print("ИТОГ: вызовы клиента согласованы с пакетом")
    return 0

if __name__ == "__main__":
    sys.exit(main())
