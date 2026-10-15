"""Ставит схему в базу прямо из игры.

На учебных компьютерах нет ни sqlplus, ни Docker, поэтому пришлось
делать установку самому. Тут три вещи: разрезать .sql на отдельные
команды, выполнить их по очереди и проверить, что всё получилось.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

import oracledb

import resources

# В таком порядке и ставим. Сначала чистим, чтобы можно было
# устанавливать поверх старого.
INSTALL_SCRIPTS = (
    ("00_drop_all.sql", "Очистка старых объектов"),
    ("01_tables.sql", "Таблицы, последовательности, индексы"),
    ("02_reference_data.sql", "Справочники"),
    ("03_catalog_data.sql", "Каталог экспонатов"),
    ("04_package_spec.sql", "Спецификация пакета"),
    ("05_package_body.sql", "Тело пакета (игровая логика)"),
)

PACKAGE_NAME = "MUSEUM_CURATOR"

# На версиях младше 12.2 схема не встанет.
MIN_VERSION = (12, 2)

# Это команды sqlplus, обычному соединению они не нужны — пропускаем.
_SQLPLUS = re.compile(
    r"^\s*(SET|SHOW|PROMPT|WHENEVER|SPOOL|DEFINE|UNDEFINE|COLUMN|CLEAR"
    r"|REM|REMARK|EXIT|QUIT|CONNECT|DISCONNECT|TTITLE|BTITLE|PAUSE)\b",
    re.I,
)
_SQLPLUS_AT = re.compile(r"^\s*@")

# Если строка начинается с этого, значит дальше PL/SQL-блок,
# и закрывать его будет не точка с запятой, а слэш.
_PLSQL_START = re.compile(
    r"^\s*(DECLARE\b|BEGIN\b"
    r"|CREATE\s+(OR\s+REPLACE\s+)?"
    r"(PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE)\b)",
    re.I,
)

class InstallError(Exception):
    """Что-то пошло не так. Текст сразу можно показать игроку."""

@dataclass
class ServerInfo:
    version: str
    charset: str
    schema: str

    @property
    def version_tuple(self) -> tuple[int, ...]:
        parts = []
        for chunk in self.version.split("."):
            digits = "".join(c for c in chunk if c.isdigit())
            parts.append(int(digits) if digits else 0)
        return tuple(parts)

    def version_ok(self) -> bool:
        return self.version_tuple[:2] >= MIN_VERSION

    def charset_ok(self) -> bool:
        # Кириллица в базе нормально живёт только в юникоде
        return "UTF8" in self.charset.upper()

# Режем .sql на отдельные команды
def _mask(text: str) -> str:
    """Затирает пробелами всё, что внутри кавычек и комментариев.

    Длина текста при этом не меняется. Смотрим на затёртый вариант,
    а режем настоящий. Иначе точка с запятой внутри строки разорвала бы
    команду пополам.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "'":
            start = i
            i += 1
            while i < n:
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            out.append(_blank(text[start:i]))
        elif ch == '"':
            start = i
            i += 1
            while i < n and text[i] != '"':
                i += 1
            i = min(i + 1, n)
            # В двойных кавычках имя объекта, а не текст — не трогаем
            out.append(text[start:i])
        elif ch == "-" and nxt == "-":
            start = i
            while i < n and text[i] != "\n":
                i += 1
            out.append(_blank(text[start:i]))
        elif ch == "/" and nxt == "*":
            start = i
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                i += 1
            i = min(i + 2, n)
            out.append(_blank(text[start:i]))
        else:
            out.append(ch)
            i += 1
    return "".join(out)

def _blank(chunk: str) -> str:
    """Меняем символы на пробелы, но переносы строк оставляем."""
    return "".join("\n" if c == "\n" else " " for c in chunk)

def split_script(text: str) -> list[str]:
    """Разбить содержимое .sql на список операторов для execute()."""
    masked = _mask(text)
    src_lines = text.splitlines()
    msk_lines = masked.splitlines()
    # На всякий случай выравниваем длину: маска не должна терять строки.
    while len(msk_lines) < len(src_lines):
        msk_lines.append("")

    statements: list[str] = []
    buf: list[str] = []
    in_block = False

    for src, msk in zip(src_lines, msk_lines):
        bare = msk.strip()

        # Строка «/» закрывает накопленный блок.
        if bare == "/":
            if buf:
                statements.append("\n".join(buf).strip())
                buf = []
                in_block = False
            continue

        # Команды sqlplus и пустые строки пропускаем, но только пока
        # не начали набирать оператор.
        if not buf:
            if not bare:
                continue
            if _SQLPLUS.match(bare) or _SQLPLUS_AT.match(bare):
                continue

        buf.append(src)

        if not in_block and _PLSQL_START.match("\n".join(buf).lstrip()):
            in_block = True

        if not in_block and bare.rstrip().endswith(";"):
            stmt = "\n".join(buf).strip()
            # oracledb не принимает завершающую точку с запятой
            # в обычном SQL-операторе.
            statements.append(stmt.rstrip().rstrip(";").rstrip())
            buf = []

    leftover = "\n".join(buf).strip()
    if leftover:
        statements.append(leftover.rstrip().rstrip(";").rstrip())

    return [s for s in statements if s]

#  Опрос сервера
def server_info(conn) -> ServerInfo:
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM product_component_version "
                    "WHERE product LIKE 'Oracle%' AND ROWNUM = 1")
        row = cur.fetchone()
        version = row[0] if row else "0"

        cur.execute("SELECT value FROM nls_database_parameters "
                    "WHERE parameter = 'NLS_CHARACTERSET'")
        row = cur.fetchone()
        charset = row[0] if row else "?"

        cur.execute("SELECT USER FROM dual")
        schema = cur.fetchone()[0]
    return ServerInfo(version=str(version), charset=str(charset), schema=str(schema))

def schema_state(conn) -> tuple[bool, str]:
    """Установлена ли игра в текущей схеме.

    Возвращает (готова ли к игре, пояснение для экрана).
    """
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM user_tables")
        tables = cur.fetchone()[0]

        cur.execute(
            "SELECT status FROM user_objects "
            "WHERE object_name = :n AND object_type = 'PACKAGE BODY'",
            n=PACKAGE_NAME,
        )
        row = cur.fetchone()

    if row is None:
        if tables == 0:
            return False, "Схема пуста — нужна установка."
        return False, f"Пакет {PACKAGE_NAME} не найден (таблиц в схеме: {tables})."
    if row[0] != "VALID":
        return False, f"Пакет {PACKAGE_NAME} собран с ошибками — нужна переустановка."
    return True, "Схема установлена, пакет валиден."

def compile_errors(conn, limit: int = 12) -> list[str]:
    """Ошибки компиляции пакета в читаемом виде."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT name, type, line, text FROM user_errors "
            "WHERE attribute = 'ERROR' ORDER BY name, sequence"
        )
        rows = cur.fetchall()
    out = []
    for name, typ, line, textmsg in rows[:limit]:
        out.append(f"{name} ({typ}), строка {line}: {str(textmsg).strip()}")
    if len(rows) > limit:
        out.append(f"… и ещё {len(rows) - limit} сообщений")
    return out

#  Установка
def _run_script(conn, name: str, tolerant: bool) -> None:
    text = resources.sql_file(name).read_text(encoding="utf-8-sig")
    statements = split_script(text)
    if not statements:
        raise InstallError(f"Скрипт {name} оказался пустым — сборка повреждена.")

    with conn.cursor() as cur:
        for number, stmt in enumerate(statements, 1):
            try:
                cur.execute(stmt)
            except oracledb.DatabaseError as err:
                if tolerant:
                    continue
                head = stmt.strip().splitlines()[0][:120]
                message = _first_line(err)
                raise InstallError(
                    f"{name}, оператор №{number}:\n"
                    f"  {head}…\n"
                    f"  {message}{_hint(message)}"
                ) from err
    conn.commit()

def _first_line(err: Exception) -> str:
    return str(err).strip().splitlines()[0]

# Ошибки установки, у которых есть понятная бытовая причина.
_INSTALL_HINTS = (
    ("ORA-02264",
     "В схеме остались объекты прошлой версии игры: имя ограничения занято.\n"
     "  Очистка должна была их убрать — проверьте, что 00_drop_all.sql свежий."),
    ("ORA-00955",
     "В схеме уже есть объект с таким именем. Обычно это остаток прошлой\n"
     "  установки; помогает повторный запуск установки целиком."),
    ("ORA-01031",
     "У этой учётной записи нет права создавать таблицы.\n"
     "  Нужны права CREATE TABLE, CREATE SEQUENCE и CREATE PROCEDURE."),
    ("ORA-01536",
     "Исчерпана квота на табличное пространство — нужен администратор базы."),
    ("ORA-00959",
     "Табличное пространство недоступно — нужен администратор базы."),
)

def _hint(text: str) -> str:
    for code, note in _INSTALL_HINTS:
        if code in text:
            return "\n  " + note
    return ""

def _our_tables() -> list[str]:
    """Имена таблиц игры — читаем из самого DDL, чтобы не разъехалось."""
    ddl = resources.sql_file("01_tables.sql").read_text(encoding="utf-8-sig")
    return [name.upper() for name in re.findall(r"CREATE TABLE (\w+)", ddl)]

def leftovers(conn) -> list[str]:
    """Объекты с нашими именами, пережившие очистку.

    Очистка выполняется в терпимом режиме: её ошибки не должны
    прерывать установку. Но тогда и провал очистки остаётся незаметным,
    а следующий шаг падает на ORA-00955 без объяснений. Поэтому
    результат проверяется явно.
    """
    names = _our_tables()
    if not names:
        return []
    placeholders = ", ".join(f":n{i}" for i in range(len(names)))
    with conn.cursor() as cur:
        cur.execute(
            "SELECT object_name, object_type FROM user_objects "
            f"WHERE object_name IN ({placeholders})",
            {f"n{i}": name for i, name in enumerate(names)},
        )
        return [f"{row[1]} {row[0]}" for row in cur.fetchall()]

def install(conn, progress=None) -> None:
    """Полная установка схемы. progress(шаг, всего, подпись) — для экрана."""
    info = server_info(conn)
    if not info.version_ok():
        raise InstallError(
            f"На сервере Oracle {info.version}, а игре нужна 12.2 или новее.\n"
            "Причина: имена таблиц и полей написаны кириллицей, более старые\n"
            "версии их не принимают. Попросите другую базу или сообщите мне —\n"
            "сделаю вариант схемы на латинице."
        )
    if not info.charset_ok():
        raise InstallError(
            f"Кодировка базы {info.charset}, а нужна AL32UTF8.\n"
            "В этой кодировке кириллические имена объектов не создать."
        )

    total = len(INSTALL_SCRIPTS)
    for index, (name, title) in enumerate(INSTALL_SCRIPTS, 1):
        if progress:
            progress(index, total, title)
        # Ошибки очистки не важны: объектов могло просто не быть.
        _run_script(conn, name, tolerant=(name == "00_drop_all.sql"))

        if name == "00_drop_all.sql":
            stuck = leftovers(conn)
            if stuck:
                raise InstallError(
                    "Очистка не смогла удалить объекты прошлой установки:\n"
                    + "\n".join("  " + line for line in stuck[:10])
                    + "\n\n  Чаще всего их держит открытая сессия: закройте окно\n"
                      "  игры и другие подключения к этой схеме, затем повторите."
                )

    ok, note = schema_state(conn)
    if not ok:
        errors = compile_errors(conn)
        detail = "\n".join(errors) if errors else note
        raise InstallError("Установка прошла, но схема не готова:\n" + detail)
