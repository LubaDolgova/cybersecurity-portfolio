"""Адрес базы, логин и всё такое.

Пароль специально не сохраняю: файл лежит рядом с exe, а exe таскается
по чужим компьютерам. Остальное подставится при следующем запуске.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, asdict, replace

import oracledb

import resources

# До базы можно достучаться двумя способами: по имени сервиса или по SID.
# На разных серверах по-разному, поэтому сделал переключатель.
KIND_SERVICE = "service"
KIND_SID = "sid"

DEFAULT_PORT = 1521

@dataclass
class Connection:
    host: str = ""
    port: int = DEFAULT_PORT
    kind: str = KIND_SERVICE
    database: str = ""          # имя сервиса или SID, смотря что выбрано
    user: str = ""
    password: str = ""          # в файл не попадает

    def dsn(self) -> str:
        """Собирает строку подключения.

        Короткую запись host:port:SID понимает sqlplus, а oracledb нет —
        он думает, что это имя из tnsnames.ora, и ругается DPY-4027.
        Поэтому строю полный дескриптор через makedsn, он работает
        и так, и так.
        """
        if self.kind == KIND_SID:
            return oracledb.makedsn(self.host, self.port, sid=self.database)
        return oracledb.makedsn(self.host, self.port, service_name=self.database)

    def short_dsn(self) -> str:
        """Короткая подпись для журнала, а то дескриптор длинный."""
        kind = "SID" if self.kind == KIND_SID else "сервис"
        return f"{self.host}:{self.port}, {kind} {self.database}"

    def label(self) -> str:
        """Что написать в шапке."""
        return f"{self.user}@{self.host}:{self.port}"

    def problems(self) -> list[str]:
        """Что ещё не заполнено."""
        out = []
        if not self.host.strip():
            out.append("не заполнен адрес сервера")
        if not (1 <= self.port <= 65535):
            out.append("порт должен быть числом от 1 до 65535")
        if not self.database.strip():
            name = "SID" if self.kind == KIND_SID else "имя сервиса"
            out.append(f"не заполнено {name}")
        if not self.user.strip():
            out.append("не заполнен пользователь")
        if not self.password:
            out.append("не заполнен пароль")
        return out

    def is_ready(self) -> bool:
        return not self.problems()

# Сохранение в файл
_SAVED_FIELDS = ("host", "port", "kind", "database", "user")

def load() -> Connection:
    """Читаем сохранённое. Если файл битый — просто начинаем с пустого."""
    path = resources.settings_file()
    if not path.is_file():
        return Connection()
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return Connection()
    if not isinstance(raw, dict):
        return Connection()

    conn = Connection()
    data = {}
    for field in _SAVED_FIELDS:
        if field in raw:
            data[field] = raw[field]
    # Порт мог сохраниться строкой, аккуратно переводим в число
    if "port" in data:
        try:
            data["port"] = int(data["port"])
        except (TypeError, ValueError):
            data.pop("port")
    if data.get("kind") not in (KIND_SID, KIND_SERVICE):
        data.pop("kind", None)
    for field in ("host", "database", "user"):
        if field in data and not isinstance(data[field], str):
            data.pop(field)
    return replace(conn, **data)

def save(conn: Connection) -> None:
    """Сохранить всё кроме пароля. Ошибка записи не должна ломать игру."""
    data = {k: v for k, v in asdict(conn).items() if k in _SAVED_FIELDS}
    try:
        resources.settings_file().write_text(
            json.dumps(data, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError:
        pass
