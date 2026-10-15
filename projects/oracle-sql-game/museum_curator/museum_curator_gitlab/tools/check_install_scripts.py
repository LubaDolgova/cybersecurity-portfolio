"""Проверяет, что скрипты установки правильно режутся на операторы.

На стендах нет sqlplus, поэтому установщик режет .sql сам, своим
разборщиком. И если он потеряет один оператор, установка отчитается
«успешно», а схема будет неполной. Такое потом ищешь очень долго.
Поэтому тут три проверки:

  1. операторов получилось столько, сколько должно быть;
  2. ничего не потерялось: если склеить операторы обратно, все CREATE
     и INSERT останутся на месте;
  3. в операторы не попали команды sqlplus (SET, PROMPT, SHOW) и
     слэши в конце — Oracle такое не примет.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "python"))

import installer  # noqa: E402
import resources  # noqa: E402

# Сколько операторов должно получиться. Числа взяты из схемы:
# 22 таблицы + 22 последовательности + 12 индексов = 56 и так далее.
EXPECTED = {
    "00_drop_all.sql": 2,
    "01_tables.sql": 56,
    "02_reference_data.sql": 40,
    "03_catalog_data.sql": 2,
    "04_package_spec.sql": 1,
    "05_package_body.sql": 1,
}

# Ключевые слова, начинающие оператор. Считаем их до и после разбора.
STARTERS = ("CREATE TABLE", "CREATE SEQUENCE", "CREATE INDEX",
            "CREATE OR REPLACE PACKAGE", "INSERT INTO", "COMMIT")

FAILS: list[str] = []

def ok(title: str, good: bool, note: str = "") -> None:
    print(("  OK     " if good else "  ПРОВАЛ ") + title + (f"   [{note}]" if note else ""))
    if not good:
        FAILS.append(f"{title} — {note}" if note else title)

def count_starters(text: str) -> dict[str, int]:
    clean = installer._mask(text)
    return {word: len(re.findall(word, clean, re.I)) for word in STARTERS}

def main() -> int:
    total = 0
    for name, _title in installer.INSTALL_SCRIPTS:
        source = resources.sql_file(name).read_text(encoding="utf-8-sig")
        statements = installer.split_script(source)
        total += len(statements)

        expected = EXPECTED.get(name)
        ok(f"{name}: операторов {len(statements)}",
           expected is None or len(statements) == expected,
           f"ожидалось {expected}" if expected and len(statements) != expected else "")

        # Ничего не потеряно: ключевые слова сохранились в том же числе.
        before = count_starters(source)
        after = count_starters("\n;\n".join(statements))
        lost = {w: (before[w], after[w]) for w in STARTERS if before[w] != after[w]}
        ok(f"{name}: ни один оператор не потерян", not lost, str(lost) if lost else "")

        # Команд sqlplus и слэшей в операторах быть не должно.
        junk = []
        for number, statement in enumerate(statements, 1):
            head = statement.strip().split("\n")[0]
            if installer._SQLPLUS.match(head) or head.strip() == "/":
                junk.append(f"№{number}: {head[:40]}")
            if re.search(r"^\s*/\s*$", statement, re.M):
                junk.append(f"№{number}: строка со слэшем внутри оператора")
            if statement.rstrip().endswith(";") and not re.search(
                    r"\bEND\b[^;]*;\s*$", statement, re.I):
                junk.append(f"№{number}: лишняя точка с запятой на конце")
        ok(f"{name}: в операторах нет команд sqlplus и слэшей", not junk,
           "; ".join(junk[:3]))

    print(f"\n  всего операторов установки: {total}")

    print()
    if FAILS:
        print(f"ИТОГ: ПРОВАЛОВ {len(FAILS)}")
        return 1
    print("ИТОГ: скрипты установки разбираются без потерь")
    return 0

if __name__ == "__main__":
    sys.exit(main())
