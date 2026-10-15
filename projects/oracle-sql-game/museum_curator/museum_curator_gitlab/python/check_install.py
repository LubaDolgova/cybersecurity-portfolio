"""Ставит схему без запуска игры и печатает каждый шаг.

Делает то же самое, что кнопка «Установить схему заново» в игре.
Писал его, чтобы видеть, на каком именно операторе всё падает, а не
гадать по одному сообщению об ошибке.

Запуск:

    .\\.venv\\Scripts\\python.exe python\\check_install.py ^
        10.22.10.41 1521 sid orcl KS2318_11 пароль

Аргументы по порядку: адрес, порт, service или sid, имя сервиса
(или SID), пользователь, пароль.
"""
from __future__ import annotations

import sys
import time

import oracledb

import installer
import settings


def main(argv: list[str]) -> int:
    if len(argv) != 6:
        print(__doc__)
        return 2

    host, port, kind, database, user, password = argv
    if kind not in (settings.KIND_SID, settings.KIND_SERVICE):
        print(f"Третий аргумент должен быть service или sid, а не {kind!r}")
        return 2

    conn_settings = settings.Connection(
        host=host, port=int(port), kind=kind,
        database=database, user=user, password=password,
    )
    print(f"Подключение: {conn_settings.short_dsn()}")

    try:
        conn = oracledb.connect(
            user=conn_settings.user,
            password=conn_settings.password,
            dsn=conn_settings.dsn(),
        )
    except oracledb.DatabaseError as err:
        print(f"ПРОВАЛ: не удалось подключиться — {err}")
        return 1

    info = installer.server_info(conn)
    print(f"Сервер Oracle {info.version}, кодировка {info.charset}, схема {info.schema}")
    print(f"  версия подходит: {info.version_ok()}, кодировка подходит: {info.charset_ok()}")

    print("\n--- Разбор скриптов на операторы ---")
    total_statements = 0
    import resources
    for name, title in installer.INSTALL_SCRIPTS:
        text = resources.sql_file(name).read_text(encoding="utf-8-sig")
        count = len(installer.split_script(text))
        total_statements += count
        print(f"  {name:24} {count:4} операторов   ({title})")
    print(f"  всего {total_statements}")

    print("\n--- Установка ---")
    started = time.time()
    try:
        installer.install(conn, lambda s, t, title: print(f"  [{s}/{t}] {title}"))
    except installer.InstallError as err:
        print(f"\nПРОВАЛ установки:\n{err}")
        return 1
    print(f"  заняло {time.time() - started:.1f} с")

    print("\n--- Проверка результата ---")
    ready, note = installer.schema_state(conn)
    print(f"  {note}")
    errors = installer.compile_errors(conn)
    if errors:
        print("  ОШИБКИ КОМПИЛЯЦИИ:")
        for line in errors:
            print("    " + line)
        return 1

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM user_tables")
        tables = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM user_sequences")
        seqs = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM exhibit_catalog")
        catalog = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM statuses")
        statuses = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM preferences")
        prefs = cur.fetchone()[0]
        cur.execute(
            "SELECT COUNT(*) FROM user_procedures WHERE object_name = :n",
            n=installer.PACKAGE_NAME,
        )
        routines = cur.fetchone()[0]

    print(f"  таблиц {tables}, последовательностей {seqs}")
    print(f"  экспонатов в каталоге {catalog}, статусов {statuses}, предпочтений {prefs}")
    print(f"  подпрограмм в пакете {routines}")

    problems = []
    if tables != 22:
        problems.append(f"таблиц {tables}, ожидалось 22")
    if catalog != 20:
        problems.append(f"экспонатов {catalog}, ожидалось 20")
    if prefs == 0:
        problems.append("таблица предпочтений пуста")
    if not ready:
        problems.append("пакет не валиден")

    print()
    if problems:
        print("ПРОВАЛ: " + "; ".join(problems))
        return 1
    print(">>> УСТАНОВКА ИЗ PYTHON ПРОШЛА ПОЛНОСТЬЮ")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
