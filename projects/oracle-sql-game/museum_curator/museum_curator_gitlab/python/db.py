"""Тут лежат все обращения к базе.

Никаких расчётов здесь нет: только вызвать процедуру или функцию
пакета и превратить курсор в список словарей.
"""
from __future__ import annotations

import re
import threading

import oracledb

import config

PKG = "museum_curator"
_ORA_MSG = re.compile(r"ORA-\d{5}:\s*(.*?)(?:\s*ORA-\d{5}|$)", re.S)

# По этим кодам понятно, что оборвалась связь, а не что база
# отклонила действие. Это разные вещи и вести себя надо по-разному.
_CONNECTION_CODES = (
    "DPY-4011",   # база или сеть закрыли соединение
    "DPY-1001",   # нет соединения
    "DPY-6005",   # не удалось подключиться
    "DPY-3010",
    "ORA-03113",  # конец файла на канале связи
    "ORA-03114",  # не подключён к Oracle
    "ORA-01012",  # нет активной сессии
    "ORA-02396",  # превышено время простоя
    "ORA-12571",
)

class GameError(Exception):
    """База отклонила действие. Текст можно показать игроку."""

class ConnectionLost(GameError):
    """Связь пропала. Пробуем переподключиться сами."""

def _is_connection_error(err: Exception) -> bool:
    text = str(err)
    return any(code in text for code in _CONNECTION_CODES)

def _clean(err: Exception) -> str:
    text = str(err)
    match = _ORA_MSG.search(text)
    msg = match.group(1).strip() if match else text.strip()
    for tail in ("ORA-06512", "ORA-06510"):
        msg = msg.split(tail)[0].strip()
    return msg or "Неизвестная ошибка базы данных"

class Database:
    """Одно соединение с базой. Вызовы идут по очереди, не параллельно."""

    def __init__(self, conn_settings=None) -> None:
        """conn_settings приходит с экрана подключения.

        Если его нет (запуск скриптом без окна), берём что лежит
        в config.py.
        """
        if config.USE_THICK_CLIENT:
            oracledb.init_oracle_client(lib_dir=config.ORACLE_CLIENT_LIB)
        if conn_settings is None:
            self._user = config.DB_USER
            self._password = config.DB_PASSWORD
            self._dsn = config.DB_DSN
        else:
            self._user = conn_settings.user
            self._password = conn_settings.password
            self._dsn = conn_settings.dsn()
        self._lock = threading.RLock()
        self._conn = None
        self.reconnects = 0
        self._open()

    def _open(self) -> None:
        self._conn = oracledb.connect(
            user=self._user,
            password=self._password,
            dsn=self._dsn,
        )

    @property
    def raw(self):
        """Отдаём соединение как есть. Нужно установщику схемы."""
        return self._conn

    # Всё, через что мы зовём базу
    def close(self) -> None:
        try:
            self._conn.close()
        except Exception:
            pass

    def _reopen(self) -> None:
        try:
            self._conn.close()
        except Exception:
            pass
        self._open()
        self.reconnects += 1

    def _exec(self, action):
        """Выполняет action(курсор).

        Если оборвалась связь — один раз переподключаемся и пробуем
        снова. А вот если база отклонила действие, повторять нельзя:
        так можно купить один экспонат два раза.
        """
        with self._lock:
            for attempt in (1, 2):
                try:
                    with self._conn.cursor() as cur:
                        return action(cur)
                except oracledb.DatabaseError as err:
                    if attempt == 1 and _is_connection_error(err):
                        try:
                            self._reopen()
                        except Exception as reconnect_err:  # noqa: BLE001
                            raise ConnectionLost(
                                "Нет связи с базой данных: " + _clean(reconnect_err)
                            ) from err
                        continue
                    if _is_connection_error(err):
                        raise ConnectionLost(
                            "Нет связи с базой данных: " + _clean(err)
                        ) from err
                    raise GameError(_clean(err)) from err

    def _call(self, name: str, args=()):
        self._exec(lambda cur: cur.callproc(f"{PKG}.{name}", list(args)))

    def _func(self, name: str, ret_type, args=()):
        return self._exec(lambda cur: cur.callfunc(f"{PKG}.{name}", ret_type, list(args)))

    def _rows(self, name: str, args=()) -> list[dict]:
        """Зовём функцию с курсором и читаем из него строки.

        Ключи словарей берём из описания курсора — то есть имена
        столбцов задаёт запрос в пакете, а не этот файл.
        """

        def action(cur):
            result = cur.callfunc(f"{PKG}.{name}", oracledb.CURSOR, list(args))
            cols = [d[0].lower() for d in result.description]
            data = [dict(zip(cols, row)) for row in result]
            result.close()
            return data

        return self._exec(action)

    def _one(self, name: str, args=()) -> dict | None:
        rows = self._rows(name, args)
        return rows[0] if rows else None

    def dbms_output(self, name: str, args=()) -> list[str]:
        """Процедура печатает в DBMS_OUTPUT, а мы это забираем построчно."""

        def action(cur):
            cur.callproc("dbms_output.enable", [None])
            cur.callproc(f"{PKG}.{name}", list(args))
            lines: list[str] = []
            chunk = cur.var(str)
            status = cur.var(int)
            while True:
                cur.callproc("dbms_output.get_line", [chunk, status])
                if status.getvalue() != 0:
                    break
                lines.append(chunk.getvalue() or "")
            return lines

        return self._exec(action)

    # Регистрация и вход
    def register(self, login: str, password: str) -> None:
        self._call("register_user", (login, password))

    def login(self, login: str, password: str):
        return self._func("login_user", oracledb.NUMBER, (login, password))

    # Музеи и партии
    def create_museum(self, user_id, name, difficulty_id) -> None:
        self._call("create_museum", (user_id, name, difficulty_id))

    def delete_museum(self, museum_id, reason=None) -> None:
        self._call("delete_museum", (museum_id, reason))

    def start_session(self, museum_id) -> None:
        self._call("start_session", (museum_id,))

    def resume_session(self, museum_id) -> None:
        self._call("resume_session", (museum_id,))

    def pause_session(self, session_id) -> None:
        self._call("pause_session", (session_id,))

    def finish_session(self, session_id) -> None:
        self._call("finish_session", (session_id,))

    def active_session(self, museum_id):
        return self._func("get_active_session", oracledb.NUMBER, (museum_id,))

    # Очередь. Все действия игрока идут только через неё.
    def enqueue(self, museum_id, session_id, code: str, params: dict | None = None) -> None:
        text = None
        if params:
            text = ";".join(
                f"{k}={'' if v is None else v}" for k, v in params.items()
            )
        self._call("enqueue_action", (museum_id, session_id, code, text))

    def tick(self) -> None:
        """Тик времени. База сама решит, что должно произойти."""
        self._call("process_time_tick", ())

    def process_queue(self) -> None:
        self._call("process_action_queue", ())

    # Читаем состояние для отрисовки
    def museums(self, user_id):
        return self._rows("get_user_museums", (user_id,))

    def state(self, museum_id):
        return self._one("get_museum_state", (museum_id,))

    def halls(self, museum_id):
        return self._rows("get_halls", (museum_id,))

    def exhibits(self, museum_id):
        return self._rows("get_hall_exhibits", (museum_id,))

    def storage(self, museum_id):
        return self._rows("get_storage", (museum_id,))

    def sellable(self, museum_id):
        return self._rows("get_sellable", (museum_id,))

    def preferences(self):
        return self._rows("get_preferences", ())

    def visitor_mix(self, museum_id):
        return self._rows("get_visitor_mix", (museum_id,))

    def catalog(self):
        return self._rows("get_catalog", ())

    def themes(self):
        return self._rows("get_themes", ())

    def positions(self):
        return self._rows("get_positions", ())

    def improvement_types(self):
        return self._rows("get_improvement_types", ())

    def difficulties(self):
        return self._rows("get_difficulties", ())

    def employees(self, museum_id):
        return self._rows("get_employees", (museum_id,))

    def hall_improvements(self, museum_id):
        return self._rows("get_hall_improvements", (museum_id,))

    def events(self, museum_id, limit=12):
        return self._rows("get_recent_events", (museum_id, limit))

    def actions(self, museum_id, limit=12):
        return self._rows("get_recent_actions", (museum_id, limit))

    def day_report(self, session_id, limit=10):
        return self._rows("get_day_report", (session_id, limit))

    def statistics(self, museum_id):
        return self._one("get_statistics", (museum_id,))

    def clock(self, session_id):
        return self._one("get_clock", (session_id,))

    def set_speed(self, session_id, factor) -> None:
        """Меняем скорость. Всё пересчитывает база, мы только просим."""
        self._call("set_game_speed", (session_id, factor))

    def current_visitors(self, museum_id, session_id) -> int:
        value = self._func(
            "estimate_current_visitors", oracledb.NUMBER, (museum_id, session_id)
        )
        return int(value or 0)

    # Текстовые отчёты
    def info_text(self) -> list[str]:
        return self.dbms_output("info", ())

    def museum_state_text(self, museum_id) -> list[str]:
        return self.dbms_output("show_museum_state", (museum_id,))

    def statistics_text(self, museum_id) -> list[str]:
        return self.dbms_output("show_statistics", (museum_id,))
