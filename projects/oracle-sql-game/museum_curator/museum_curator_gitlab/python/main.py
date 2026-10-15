"""Окно игры на pygame.

Этот файл только рисует и ловит нажатия. Ничего игрового он не считает:
нажал кнопку — поставили действие в очередь, база его выполнила,
мы перечитали состояние и нарисовали заново.
"""
from __future__ import annotations

import queue
import random
import sys
import threading
import time

import pygame

import config
import installer
import settings as conn_settings
from db import Database, GameError
from ui import Button, ListDialog, TextDialog, TextInput, Toast, clip_text, panel, text
from config import (
    COL_ACCENT,
    COL_BG,
    COL_DIM,
    COL_LINE,
    COL_NIGHT,
    COL_OK,
    COL_PANEL,
    COL_PANEL_2,
    COL_TEXT,
    COL_WARN,
    THEME_COLORS,
)

def _wrap(message: str, width: int) -> list[str]:
    """Разбить строку на части по ширине, не разрывая слова."""
    out: list[str] = []
    for paragraph in str(message).splitlines():
        line = ""
        for word in paragraph.split():
            if not line:
                line = word
            elif len(line) + 1 + len(word) <= width:
                line += " " + word
            else:
                out.append(line)
                line = word
        out.append(line)
    return [x for x in out if x] or [""]

# Частые причины, почему не подключается. Сообщения oracledb
# непонятные, поэтому переписываю их по-человечески.
_CONNECT_HINTS = (
    ("DPY-6005", "Сервер не отвечает. Проверьте адрес, порт и что вы в той же сети."),
    ("DPY-6000", "Сервер отказал в подключении. Обычно это неверный SID или имя сервиса."),
    ("ORA-12514", "Слушатель не знает такого имени сервиса. Попробуйте переключить на SID."),
    ("ORA-12505", "Слушатель не знает такого SID. Попробуйте переключить на Service Name."),
    ("ORA-01017", "Неверный логин или пароль."),
    ("ORA-28000", "Учётная запись заблокирована — нужен администратор базы."),
    ("ORA-28001", "Срок действия пароля истёк — смените пароль и попробуйте снова."),
    ("ORA-12541", "На этом порту нет слушателя Oracle. Проверьте номер порта."),
    ("DPY-4027", "Не разобрана строка подключения — проверьте адрес, порт и SID."),
    ("DPY-4000", "Не разобрана строка подключения — проверьте адрес, порт и SID."),
)

def _connect_hint(err: Exception) -> str:
    text_err = str(err)
    for code, hint in _CONNECT_HINTS:
        if code in text_err:
            return f"{hint} ({code})"
    return text_err.strip().splitlines()[0]

FLOOR = pygame.Rect(16, 72, 872, 458)
SIDE = pygame.Rect(900, 72, 364, 674)
ACTIONS = pygame.Rect(16, 540, 872, 206)

# Отдельный поток. Все походы в базу идут отсюда, чтобы картинка
# не подвисала на каждом запросе.
class Worker(threading.Thread):
    def __init__(self, db: Database):
        super().__init__(daemon=True)
        self.db = db
        self.commands: queue.Queue = queue.Queue()
        self.results: queue.Queue = queue.Queue()
        self.snapshot: dict = {}
        self.museum_id = None
        self.session_id = None
        self.running = True
        self._last_tick = 0.0
        self._last_refresh = 0.0
        self._slow_counter = 0

    # Это зовут из основного потока
    def submit(self, fn, on_done=None, label=""):
        self.commands.put((fn, on_done, label))

    def watch(self, museum_id, session_id):
        self.museum_id = museum_id
        self.session_id = session_id
        self._last_refresh = 0.0

    def stop(self):
        self.running = False

    # А это крутится в фоне
    def run(self):
        while self.running:
            handled = self._drain_commands()
            now = time.time()

            if self.museum_id and now - self._last_tick >= config.TICK_INTERVAL:
                self._last_tick = now
                self._safe(lambda: self.db.tick(), "тик игрового времени")

            if self.museum_id and now - self._last_refresh >= config.REFRESH_INTERVAL:
                self._last_refresh = now
                self._refresh()

            if not handled:
                time.sleep(0.03)

    def _drain_commands(self) -> bool:
        handled = False
        while True:
            try:
                fn, on_done, label = self.commands.get_nowait()
            except queue.Empty:
                return handled
            handled = True
            try:
                value = fn()
                if on_done:
                    self.results.put(("done", on_done, value))
            except GameError as err:
                self.results.put(("error", None, str(err)))
            except Exception as err:  # noqa: BLE001
                self.results.put(("error", None, f"{label}: {err}"))
            else:
                self._last_refresh = 0.0

    def _safe(self, fn, label):
        try:
            fn()
        except GameError as err:
            self.results.put(("error", None, str(err)))
        except Exception as err:  # noqa: BLE001
            self.results.put(("error", None, f"{label}: {err}"))

    def _refresh(self):
        mid, sid = self.museum_id, self.session_id
        if not mid:
            return
        try:
            snap = dict(self.snapshot)
            snap["state"] = self.db.state(mid)
            snap["halls"] = self.db.halls(mid)
            snap["exhibits"] = self.db.exhibits(mid)
            if sid:
                snap["clock"] = self.db.clock(sid)
                snap["visitors"] = self.db.current_visitors(mid, sid)

            self._slow_counter += 1
            if self._slow_counter % 3 == 1:
                snap["storage"] = self.db.storage(mid)
                snap["employees"] = self.db.employees(mid)
                snap["improvements"] = self.db.hall_improvements(mid)
                snap["events"] = self.db.events(mid, 10)
                snap["actions"] = self.db.actions(mid, 10)
                snap["mix"] = self.db.visitor_mix(mid)
                if sid:
                    snap["days"] = self.db.day_report(sid, 8)
            self.snapshot = snap
        except Exception as err:  # noqa: BLE001
            self.results.put(("error", None, f"обновление состояния: {err}"))

# Точки-посетители. Просто анимация, на игру никак не влияет.
class Crowd:
    def __init__(self):
        self.dots: list[list[float]] = []

    def resize(self, count: int, area: pygame.Rect):
        count = max(0, min(count, 70))
        while len(self.dots) < count:
            self.dots.append(
                [
                    random.uniform(area.left + 8, area.right - 8),
                    random.uniform(area.top + 8, area.bottom - 8),
                    random.uniform(-22, 22),
                    random.uniform(-22, 22),
                ]
            )
        if len(self.dots) > count:
            del self.dots[count:]

    def update(self, dt: float, area: pygame.Rect):
        for dot in self.dots:
            dot[0] += dot[2] * dt
            dot[1] += dot[3] * dt
            if dot[0] < area.left + 6 or dot[0] > area.right - 6:
                dot[2] *= -1
                dot[0] = max(area.left + 6, min(area.right - 6, dot[0]))
            if dot[1] < area.top + 6 or dot[1] > area.bottom - 6:
                dot[3] *= -1
                dot[1] = max(area.top + 6, min(area.bottom - 6, dot[1]))

    def draw(self, surface):
        for dot in self.dots:
            pygame.draw.circle(surface, (236, 226, 200), (int(dot[0]), int(dot[1])), 3)
            pygame.draw.circle(surface, (120, 110, 90), (int(dot[0]), int(dot[1])), 3, 1)

# Само приложение: экраны и главный цикл
class Game:
    def __init__(self):
        pygame.init()
        pygame.display.set_caption("Куратор музея")
        self.screen = pygame.display.set_mode((config.WINDOW_W, config.WINDOW_H))
        self.clock = pygame.time.Clock()
        self.toast = Toast()
        self.crowd = Crowd()
        self.dialog = None
        self.mode = "connect"
        self.user_id = None
        self.museum_id = None
        self.session_id = None
        self.selected_hall = None
        self.museums: list[dict] = []
        self.defeat_stats: dict | None = None
        self.db: Database | None = None
        self.worker: Worker | None = None
        self.buttons: list[Button] = []
        self.login_input = TextInput((0, 0, 320, 38), "login")
        self.pass_input = TextInput((0, 0, 320, 38), "пароль", password=True)
        self.status_line = "Подключение к базе данных…"

        self.conn = conn_settings.load()
        self.conn_fields = {
            "host": TextInput((0, 0, 232, 34), "например 10.0.0.15", limit=60),
            "port": TextInput((0, 0, 92, 34), "1521", limit=5),
            "database": TextInput((0, 0, 232, 34), "ORCL", limit=60),
            "user": TextInput((0, 0, 232, 34), "ваш логин в Oracle", limit=40),
            "password": TextInput((0, 0, 232, 34), "пароль", password=True, limit=60),
        }
        self.conn_fields["host"].value = self.conn.host
        self.conn_fields["port"].value = str(self.conn.port)
        self.conn_fields["database"].value = self.conn.database
        self.conn_fields["user"].value = self.conn.user
        self.conn_busy = False
        self.conn_log: list[tuple[str, tuple]] = []
        self.conn_results: queue.Queue = queue.Queue()
        self.conn_can_install = False
        self.schema_is_empty = False

    # Экран подключения
    def read_conn_fields(self) -> conn_settings.Connection:
        """Собрать введённое в полях в объект подключения."""
        raw_port = self.conn_fields["port"].value.strip()
        try:
            port = int(raw_port) if raw_port else 0
        except ValueError:
            port = 0
        return conn_settings.Connection(
            host=self.conn_fields["host"].value.strip(),
            port=port,
            kind=self.conn.kind,
            database=self.conn_fields["database"].value.strip(),
            user=self.conn_fields["user"].value.strip(),
            password=self.conn_fields["password"].value,
        )

    def conn_say(self, message: str, tone=COL_DIM) -> None:
        self.conn_log.append((message, tone))
        del self.conn_log[:-9]

    def start_connect(self, with_install: bool) -> None:
        """Запустить подключение в фоне, чтобы окно не подвисало."""
        if self.conn_busy:
            return
        candidate = self.read_conn_fields()
        problems = candidate.problems()
        if problems:
            self.toast.show("Проверьте поля: " + ", ".join(problems), "error", 5.0)
            return

        self.conn = candidate
        self.conn_busy = True
        self.conn_can_install = False
        self.conn_log = []
        self.conn_say(f"Подключаюсь к {candidate.short_dsn()} …")
        threading.Thread(
            target=self._connect_worker,
            args=(candidate, with_install),
            daemon=True,
        ).start()

    def _connect_worker(self, candidate, with_install: bool) -> None:
        """Выполняется в отдельном потоке. Результат кладём в очередь."""
        put = self.conn_results.put
        try:
            database = Database(candidate)
        except Exception as err:  # noqa: BLE001
            put(("fail", _connect_hint(err), False))
            return

        try:
            info = installer.server_info(database.raw)
            put(("log", f"Сервер Oracle {info.version}, кодировка {info.charset}", None))
            put(("log", f"Схема: {info.schema}", None))

            if with_install:
                def progress(step, total, title):
                    put(("log", f"[{step}/{total}] {title}", None))

                installer.install(database.raw, progress)
                put(("log", "Схема установлена", COL_OK))
            else:
                if not info.version_ok():
                    put(("fail",
                         f"На сервере Oracle {info.version}. Игре нужна 12.2 "
                         "или новее: имена таблиц написаны кириллицей.", False))
                    database.close()
                    return
                ready, note = installer.schema_state(database.raw)
                if not ready:
                    # Пустая схема это не ошибка, просто ещё не ставили
                    put(("empty" if "пуст" in note else "fail", note, True))
                    database.close()
                    return
                put(("log", note, COL_OK))
        except installer.InstallError as err:
            put(("fail", str(err), True))
            database.close()
            return
        except Exception as err:  # noqa: BLE001
            put(("fail", f"Непредвиденная ошибка: {err}", True))
            database.close()
            return

        put(("ok", database, None))

    def drain_connect(self) -> None:
        """Забрать то, что успел сообщить поток подключения."""
        while True:
            try:
                kind, payload, extra = self.conn_results.get_nowait()
            except queue.Empty:
                return
            if kind == "log":
                self.conn_say(payload, extra or COL_DIM)
            elif kind == "empty":
                self.conn_busy = False
                self.conn_can_install = True
                self.schema_is_empty = True
                self.conn_say(payload + " Нажмите «Установить схему».", COL_ACCENT)
            elif kind == "fail":
                self.conn_busy = False
                self.conn_can_install = bool(extra)
                self.schema_is_empty = False
                self.conn_say(payload, COL_WARN)
            elif kind == "ok":
                self.conn_busy = False
                self.db = payload
                conn_settings.save(self.conn)
                self.worker = Worker(self.db)
                self.worker.start()
                self.mode = "login"
                self.status_line = "Введите логин и пароль"

    # Рисуем экран подключения
    def draw_connect(self):
        self.screen.fill(COL_BG)
        box = pygame.Rect(0, 0, 720, 560)
        box.center = (config.WINDOW_W // 2, config.WINDOW_H // 2)
        panel(self.screen, box, COL_PANEL, COL_LINE, radius=12)

        text(self.screen, "КУРАТОР МУЗЕЯ", (box.centerx, box.y + 30), 30, COL_ACCENT,
             bold=True, center=True)
        text(self.screen, "подключение к серверу Oracle",
             (box.centerx, box.y + 62), 14, COL_DIM, center=True)

        left = box.x + 40
        right = box.x + 390
        row = box.y + 104

        def field(column, label, key):
            text(self.screen, label, (column, row - 18), 13, COL_DIM)
            widget = self.conn_fields[key]
            widget.rect.topleft = (column, row)
            widget.draw(self.screen)

        field(left, "Адрес сервера (IP или имя)", "host")
        text(self.screen, "Порт", (left + 244, row - 18), 13, COL_DIM)
        self.conn_fields["port"].rect.topleft = (left + 244, row)
        self.conn_fields["port"].draw(self.screen)

        row += 62
        is_sid = self.conn.kind == conn_settings.KIND_SID
        label = "SID" if is_sid else "Имя сервиса (Service Name)"
        field(left, label, "database")

        # Кнопки Service / SID. На разных серверах по-разному,
        # а строка подключения от этого зависит.
        row_kind = row
        self.buttons = [
            Button((left + 244, row_kind, 88, 34), "Service",
                   lambda: self.set_conn_kind(conn_settings.KIND_SERVICE),
                   tone="accent" if not is_sid else "normal"),
            Button((left + 338, row_kind, 60, 34), "SID",
                   lambda: self.set_conn_kind(conn_settings.KIND_SID),
                   tone="accent" if is_sid else "normal"),
        ]

        row += 62
        field(left, "Пользователь Oracle", "user")
        row += 62
        field(left, "Пароль", "password")

        log_box = pygame.Rect(right + 50, box.y + 104, 246, 248)
        panel(self.screen, log_box, (28, 30, 38), COL_LINE, radius=6)
        text(self.screen, "ХОД ПОДКЛЮЧЕНИЯ", (log_box.x + 12, log_box.y + 10), 12,
             COL_ACCENT, bold=True)
        line_y = log_box.y + 34
        if not self.conn_log:
            text(self.screen, "Заполните поля слева и нажмите",
                 (log_box.x + 12, line_y), 12, COL_DIM)
            text(self.screen, "«Подключиться».",
                 (log_box.x + 12, line_y + 16), 12, COL_DIM)
        for message, tone in self.conn_log:
            for chunk in _wrap(message, 34)[:3]:
                text(self.screen, chunk, (log_box.x + 12, line_y), 12, tone)
                line_y += 15
            line_y += 3

        btn_y = box.bottom - 116
        connect_label = "Подключаюсь…" if self.conn_busy else "Подключиться"
        self.buttons += [
            Button((left, btn_y, 200, 42), connect_label,
                   lambda: self.start_connect(False), tone="accent"),
            Button((left + 214, btn_y, 230, 42), self.install_label(),
                   lambda: self.confirm_install(),
                   tone="accent" if self.conn_can_install else "normal"),
            Button((box.right - 130, btn_y, 90, 42), "Выход", self.quit),
        ]
        for b in self.buttons:
            b.draw(self.screen)

        hint = ("Установка создаёт таблицы, справочники и пакет museum_curator "
                "в указанной схеме.")
        text(self.screen, hint, (box.centerx, box.bottom - 54), 12, COL_DIM, center=True)
        text(self.screen, "Docker и клиент Oracle не нужны — игра ходит на сервер напрямую.",
             (box.centerx, box.bottom - 34), 12, COL_DIM, center=True)

    def set_conn_kind(self, kind: str) -> None:
        self.conn.kind = kind

    def back_to_connect(self) -> None:
        """Вернуться на экран подключения после обрыва связи."""
        if self.worker:
            self.worker.stop()
            self.worker = None
        if self.db:
            self.db.close()
            self.db = None
        self.user_id = None
        self.museum_id = None
        self.session_id = None
        self.conn_log = []
        self.conn_busy = False
        self.mode = "connect"

    def install_label(self) -> str:
        """В пустой схеме удалять нечего — «заново» там сбивает с толку."""
        return "Установить схему" if self.schema_is_empty else "Установить схему заново"

    def confirm_install(self) -> None:
        """Переустановка стирает прошлые партии, поэтому спрашиваем.

        Если схема пуста, спрашивать не о чем: терять нечего.
        """
        if self.conn_busy:
            return
        if self.schema_is_empty:
            self.start_connect(True)
            return

        def on_pick(value):
            if value:
                self.start_connect(True)

        self.ask(
            "Установить схему заново?",
            [
                ("Нет, вернуться", False, "ничего не менять"),
                ("Да, удалить и установить", True, "займёт около минуты"),
            ],
            on_pick,
            subtitle="Все музеи и сохранения в этой схеме будут удалены.",
        )

    # Мелкие помощники
    def snap(self, key, default=None):
        return self.worker.snapshot.get(key, default) if self.worker else default

    def run_db(self, fn, on_done=None, label=""):
        self.worker.submit(fn, on_done, label)

    def enqueue(self, code, params=None, note=""):
        """Все действия игрока проходят через очередь планировщика."""
        if not self.museum_id:
            return
        mid, sid = self.museum_id, self.session_id

        def job():
            self.db.enqueue(mid, sid, code, params)
            self.db.process_queue()

        self.run_db(job, label=code)
        self.toast.show(note or f"Действие {code} поставлено в очередь", "info", 2.5)

    def open_dialog(self, dialog):
        self.dialog = dialog

    def ask(self, title, items, on_pick, subtitle=None):
        self.open_dialog(
            ListDialog(title, items, on_pick, subtitle, self.screen.get_size())
        )

    # Вход и регистрация
    def do_login(self):
        login = self.login_input.value.strip()
        password = self.pass_input.value
        if not login or not password:
            self.toast.show("Заполните логин и пароль", "error")
            return

        def job():
            return self.db.login(login, password)

        def done(user_id):
            if user_id is None:
                self.toast.show("Неверный логин или пароль", "error")
                return
            self.user_id = int(user_id)
            self.load_museums()

        self.run_db(job, done, "вход")

    def do_register(self):
        login = self.login_input.value.strip()
        password = self.pass_input.value
        if not login or not password:
            self.toast.show("Заполните логин и пароль", "error")
            return

        def job():
            self.db.register(login, password)
            return self.db.login(login, password)

        def done(user_id):
            self.user_id = int(user_id)
            self.toast.show("Регистрация выполнена", "ok")
            self.load_museums()

        self.run_db(job, done, "регистрация")

    # Меню с музеями
    def load_museums(self):
        def job():
            return self.db.museums(self.user_id)

        def done(rows):
            self.museums = rows
            self.mode = "menu"

        self.run_db(job, done, "список музеев")

    def new_museum(self):
        def job():
            return self.db.difficulties()

        def done(rows):
            items = [
                (
                    f"{r['difficulty_name']} — бюджет {int(r['start_budget'])}",
                    r["difficulty_id"],
                    "",
                )
                for r in rows
            ]
            self.ask("Уровень сложности", items, self.create_museum_with)

        self.run_db(job, done, "уровни сложности")

    def create_museum_with(self, difficulty_id):
        name = f"Музей №{len(self.museums) + 1}"

        def job():
            self.db.create_museum(self.user_id, name, difficulty_id)
            return self.db.museums(self.user_id)

        def done(rows):
            self.museums = rows
            self.toast.show(f"Создан «{name}»", "ok")

        self.run_db(job, done, "создание музея")

    def play(self, museum):
        museum_id = museum["museum_id"]

        def job():
            self.db.start_session(museum_id)
            return self.db.active_session(museum_id)

        def done(session_id):
            self.museum_id = museum_id
            self.session_id = int(session_id) if session_id else None
            self.selected_hall = None
            self.worker.watch(self.museum_id, self.session_id)
            self.mode = "game"
            self.build_action_buttons()
            self.toast.show("Сессия запущена. Удачного дня!", "ok")

        self.run_db(job, done, "запуск сессии")

    def archive_museum(self, museum_id):
        def job():
            self.db.delete_museum(museum_id, "Мягкое удаление из меню")
            return self.db.museums(self.user_id)

        def done(rows):
            self.museums = rows
            self.toast.show("Музей отправлен в архив, данные сохранены", "ok")

        self.run_db(job, done, "архивация музея")

    # Кнопки действий
    def build_action_buttons(self):
        specs = [
            ("Открыть зал", "1", self.act_open_hall),
            ("Купить экспонат", "2", self.act_buy),
            ("Выставить в зал", "3", self.act_place),
            ("Убрать на склад", "4", self.act_remove),
            ("Продать экспонат", "5", self.act_sell),
            ("Нанять сотрудника", "6", self.act_hire),
            ("Назначить в зал", "7", self.act_assign),
            ("Улучшение зала", "8", self.act_improve),
            ("Сменить тему зала", "9", self.act_theme),
            ("Состояние музея", "Q", self.act_state_text),
            ("Статистика", "W", self.act_stats_text),
            ("Справка", "E", self.act_info),
            ("Скорость времени", "S", self.act_speed),
            ("Пауза и выход", "P", self.act_pause),
            ("Завершить партию", "F", self.act_finish),
        ]
        self.buttons = []
        cols = 5
        bw, bh, gap = 160, 40, 8
        for i, (label, key, action) in enumerate(specs):
            col, row = i % cols, i // cols
            rect = (
                ACTIONS.x + 14 + col * (bw + gap),
                ACTIONS.y + 46 + row * (bh + gap),
                bw,
                bh,
            )
            tone = "danger" if key in ("P", "F") else "normal"
            self.buttons.append(Button(rect, label, action, key, tone))

    def _hall_items(self, only_open=True, predicate=None):
        items = []
        for h in self.snap("halls", []) or []:
            if only_open and not h["is_open"]:
                continue
            if predicate and not predicate(h):
                continue
            items.append(
                (
                    f"{h['hall_name']} · {h['theme']}",
                    h["hall_id"],
                    f"{int(h['occupied'])}/{int(h['capacity'])} мест",
                )
            )
        return items

    def act_open_hall(self):
        sizes = [
            ("Маленький — 1000, 10 мест", "Маленький", ""),
            ("Средний — 2000, 20 мест", "Средний", ""),
            ("Большой — 5000, 30 мест", "Большой", ""),
        ]

        def pick_size(size):
            def job():
                return self.db.themes()

            def done(themes):
                items = [("Без темы (универсальный зал)", None, "")]
                items += [(t["theme_name"], t["theme_id"], "") for t in themes]
                self.ask(
                    "Тема нового зала",
                    items,
                    lambda theme_id: self._open_hall(size, theme_id),
                )

            self.run_db(job, done, "themes")

        self.ask("Размер нового зала", sizes, pick_size, "Стоимость спишется из бюджета")

    def _open_hall(self, size, theme_id):
        existing = {h["hall_name"] for h in (self.snap("halls", []) or [])}
        index = len(existing) + 1
        while f"Зал {index}" in existing:
            index += 1
        self.enqueue(
            "OPEN_HALL",
            {"NAME": f"Зал {index}", "SIZE": size, "THEME": theme_id},
            f"Открывается «Зал {index}» ({size})",
        )

    def act_buy(self):
        def job():
            return self.db.catalog()

        def done(rows):
            items = [
                (
                    f"{r['exhibit_name']} · {r['exhibit_type']} · {int(r['star_rating'])}★",
                    r["catalog_exhibit_id"],
                    f"{int(r['price'])} / привл. {int(r['attractiveness'])}",
                )
                for r in rows
            ]
            self.ask("Каталог экспонатов", items, self._buy, "Экспонат попадёт на склад")

        self.run_db(job, done, "каталог")

    def _buy(self, catalog_id):
        self.enqueue("BUY_EXHIBIT", {"CATALOG": catalog_id}, "Экспонат покупается")

    def act_place(self):
        storage = self.snap("storage", []) or []
        if not storage:
            self.toast.show("На складе нет экспонатов — сначала купите", "error")
            return
        items = [
            (
                f"{r['exhibit_name']} · {int(r['star_rating'])}★",
                r["museum_exhibit_id"],
                r["theme"],
            )
            for r in storage
        ]

        def pick_exhibit(exhibit_id):
            halls = self._hall_items(predicate=lambda h: h["occupied"] < h["capacity"])
            if not halls:
                self.toast.show("Нет зала со свободным местом", "error")
                return
            self.ask(
                "В какой зал выставить",
                halls,
                lambda hall_id: self.enqueue(
                    "PLACE_EXHIBIT",
                    {"EXHIBIT": exhibit_id, "HALL": hall_id},
                    "Экспонат размещается в зале",
                ),
            )

        self.ask("Склад: что выставить", items, pick_exhibit)

    def act_remove(self):
        shown = self.snap("exhibits", []) or []
        if not shown:
            self.toast.show("В залах нет выставленных экспонатов", "error")
            return
        halls = {h["hall_id"]: h["hall_name"] for h in (self.snap("halls", []) or [])}
        items = [
            (
                f"{r['exhibit_name']} · {int(r['star_rating'])}★",
                r["museum_exhibit_id"],
                halls.get(r["hall_id"], ""),
            )
            for r in shown
        ]
        self.ask(
            "Убрать экспонат на склад",
            items,
            lambda eid: self.enqueue(
                "REMOVE_EXHIBIT", {"EXHIBIT": eid}, "Экспонат возвращается на склад"
            ),
        )

    def act_sell(self):
        mid = self.museum_id

        def job():
            return self.db.sellable(mid)

        def done(rows):
            if not rows:
                self.toast.show("Продавать нечего: ни на складе, ни в залах", "error")
                return
            items = [
                (
                    f"{r['exhibit_name']} · {r['place']}",
                    r["museum_exhibit_id"],
                    f"вернётся {int(r['sale_price'])}",
                )
                for r in rows
            ]
            self.ask(
                "Продажа экспоната",
                items,
                lambda eid: self.enqueue(
                    "SELL_EXHIBIT", {"EXHIBIT": eid}, "Экспонат продаётся"
                ),
                "Выставленный экспонат снимается с экспозиции автоматически",
            )

        self.run_db(job, done, "список для продажи")

    def act_hire(self):
        halls = self._hall_items(predicate=lambda h: h["can_hire"] == 1)
        items = [("Кадровый резерв (без зала)", None, "назначить позже")] + halls

        def pick_hall(hall_id):
            def job():
                return self.db.positions()

            def done(rows):
                pos_items = [
                    (r["position_name"], r["position_id"], f"от {int(r['base_salary'])}")
                    for r in rows
                ]
                self.ask(
                    "Должность",
                    pos_items,
                    lambda pid: self._hire(hall_id, pid),
                    "Ставка растёт на 50% за каждого предыдущего",
                )

            self.run_db(job, done, "positions")

        self.ask(
            "Куда нанять сотрудника",
            items,
            pick_hall,
            "Зал доступен, если число экспонатов кратно 5",
        )

    def _hire(self, hall_id, position_id):
        last = random.choice(["Орлов", "Белова", "Крылов", "Седова", "Морозов", "Гринёва"])
        first = random.choice(["Пётр", "Анна", "Игорь", "Мария", "Олег", "Дарья"])
        self.enqueue(
            "HIRE_EMPLOYEE",
            {"HALL": hall_id, "POSITION": position_id, "LAST": last, "FIRST": first},
            f"Нанимается {last} {first}",
        )

    def act_assign(self):
        reserve = [
            e for e in (self.snap("employees", []) or []) if e["hall_id"] is None
        ]
        if not reserve:
            self.toast.show("В кадровом резерве никого нет", "error")
            return
        items = [
            (
                f"{e['last_name']} {e['first_name']} · {e['position_name']}",
                e["employee_id"],
                f"{int(e['salary'])}",
            )
            for e in reserve
        ]

        def pick_emp(emp_id):
            halls = self._hall_items()
            self.ask(
                "В какой зал назначить",
                halls,
                lambda hid: self.enqueue(
                    "ASSIGN_EMPLOYEE",
                    {"EMPLOYEE": emp_id, "HALL": hid},
                    "Сотрудник назначается в зал",
                ),
            )

        self.ask("Кадровый резерв", items, pick_emp)

    def act_improve(self):
        halls = self._hall_items()
        if not halls:
            self.toast.show("Нет открытых залов", "error")
            return

        def pick_hall(hall_id):
            def job():
                return self.db.improvement_types()

            def done(rows):
                items = [
                    (
                        f"{r['improvement_name']} — {int(r['price'])}",
                        r["improvement_type_id"],
                        clip_text(r["effect_description"] or "", 28),
                    )
                    for r in rows
                ]
                self.ask(
                    "Улучшение",
                    items,
                    lambda tid: self.enqueue(
                        "BUY_IMPROVEMENT",
                        {"HALL": hall_id, "TYPE": tid},
                        "Улучшение покупается",
                    ),
                )

            self.run_db(job, done, "типы улучшений")

        self.ask("Зал для улучшения", halls, pick_hall)

    def act_theme(self):
        halls = self._hall_items(predicate=lambda h: h["occupied"] == 0)
        if not halls:
            self.toast.show("Сменить тему можно только в пустом зале", "error")
            return

        def pick_hall(hall_id):
            def job():
                return self.db.themes()

            def done(rows):
                items = [("Без темы", None, "")]
                items += [(t["theme_name"], t["theme_id"], "") for t in rows]
                self.ask(
                    "Новая тема зала",
                    items,
                    lambda tid: self.enqueue(
                        "CHANGE_THEME", {"HALL": hall_id, "THEME": tid}, "Тема зала меняется"
                    ),
                )

            self.run_db(job, done, "themes")

        self.ask("Зал для смены темы", halls, pick_hall, "В зале не должно быть экспонатов")

    def act_state_text(self):
        mid = self.museum_id
        self.run_db(
            lambda: self.db.museum_state_text(mid),
            lambda lines: self.open_dialog(
                TextDialog("Состояние музея", lines, self.screen.get_size())
            ),
            "состояние музея",
        )

    def act_stats_text(self):
        mid = self.museum_id
        self.run_db(
            lambda: self.db.statistics_text(mid),
            lambda lines: self.open_dialog(
                TextDialog("Статистика музея", lines, self.screen.get_size())
            ),
            "статистика",
        )

    def act_info(self):
        self.run_db(
            lambda: self.db.info_text(),
            lambda lines: self.open_dialog(
                TextDialog("Справка по игре", lines, self.screen.get_size())
            ),
            "справка",
        )

    SPEEDS = (1, 2, 4, 8)

    def act_speed(self):
        """Переключить скорость игрового времени по кругу.

        Множитель хранится в сессии и применяется в пакете: клиент
        только просит сменить его. Пакет заодно сдвигает начало дня,
        чтобы часы не прыгнули.
        """
        if not self.session_id:
            return
        clock = self.snap("clock", {}) or {}
        current = int(clock.get("speed_factor", 1) or 1)
        following = self.SPEEDS[(self.SPEEDS.index(current) + 1) % len(self.SPEEDS)] \
            if current in self.SPEEDS else 1
        sid = self.session_id

        def job():
            self.db.set_speed(sid, following)

        self.run_db(job, label="смена скорости")
        self.toast.show(
            f"Скорость игрового времени: x{following}"
            + ("  (обычная)" if following == 1 else ""),
            "info", 2.5,
        )

    def act_pause(self):
        sid, uid = self.session_id, self.user_id
        if not sid:
            self.mode = "menu"
            return

        def job():
            self.db.pause_session(sid)
            return self.db.museums(uid)

        def done(rows):
            self.museums = rows
            self.worker.watch(None, None)
            self.museum_id = self.session_id = None
            self.mode = "menu"
            self.toast.show("Сессия приостановлена, состояние сохранено", "ok")

        self.run_db(job, done, "пауза")

    def act_finish(self):
        sid, uid = self.session_id, self.user_id
        if not sid:
            return

        def job():
            self.db.finish_session(sid)
            return self.db.museums(uid)

        def done(rows):
            self.museums = rows
            self.worker.watch(None, None)
            self.museum_id = self.session_id = None
            self.mode = "menu"
            self.toast.show("Партия завершена", "ok")

        self.run_db(job, done, "завершение партии")

    # Рисуем экран входа
    def draw_login(self):
        self.screen.fill(COL_BG)
        box = pygame.Rect(0, 0, 420, 330)
        box.center = (config.WINDOW_W // 2, config.WINDOW_H // 2)
        panel(self.screen, box, COL_PANEL, COL_LINE, radius=12)

        text(self.screen, "КУРАТОР МУЗЕЯ", (box.centerx, box.y + 42), 30, COL_ACCENT,
             bold=True, center=True)
        text(self.screen, "симулятор управления музеем на Oracle PL/SQL",
             (box.centerx, box.y + 72), 14, COL_DIM, center=True)

        self.login_input.rect.topleft = (box.x + 50, box.y + 110)
        self.pass_input.rect.topleft = (box.x + 50, box.y + 158)
        self.login_input.draw(self.screen)
        self.pass_input.draw(self.screen)

        self.buttons = [
            Button((box.x + 50, box.y + 212, 155, 40), "Войти", self.do_login, tone="accent"),
            Button((box.x + 215, box.y + 212, 155, 40), "Регистрация", self.do_register),
        ]
        for b in self.buttons:
            b.draw(self.screen)

        text(self.screen, self.status_line, (box.centerx, box.bottom - 34), 14,
             COL_DIM, center=True)

    # Рисуем меню музеев
    def draw_menu(self):
        self.screen.fill(COL_BG)
        text(self.screen, "Ваши музеи", (40, 36), 26, COL_ACCENT, bold=True)
        text(self.screen, "Выберите музей, чтобы продолжить игру, или создайте новый",
             (40, 70), 15, COL_DIM)

        self.buttons = [
            Button((40, config.WINDOW_H - 74, 200, 44), "Новый музей",
                   self.new_museum, tone="accent"),
            Button((252, config.WINDOW_H - 74, 200, 44), "Справка", self.act_info),
            Button((config.WINDOW_W - 240, config.WINDOW_H - 74, 200, 44), "Выход",
                   self.quit, tone="danger"),
        ]

        mouse = pygame.mouse.get_pos()
        for i, m in enumerate(self.museums[:8]):
            row = pygame.Rect(40, 110 + i * 66, config.WINDOW_W - 80, 58)
            hovered = row.collidepoint(mouse)
            panel(self.screen, row, COL_PANEL_2 if hovered else COL_PANEL, COL_LINE)
            text(self.screen, m["museum_name"], (row.x + 18, row.y + 8), 19, bold=True)
            text(self.screen,
                 f"сложность: {m['difficulty']}   бюджет: {int(m['current_budget'])}"
                 f"   рейтинг: {int(m['rating'])}   статус: {m['status']}",
                 (row.x + 18, row.y + 33), 14, COL_DIM)

            play = Button((row.right - 300, row.y + 10, 130, 38), "Играть",
                          lambda mm=m: self.play(mm), tone="accent")
            arch = Button((row.right - 160, row.y + 10, 140, 38), "В архив",
                          lambda mm=m: self.archive_museum(mm["museum_id"]), tone="danger")
            play.hover = play.rect.collidepoint(mouse)
            arch.hover = arch.rect.collidepoint(mouse)
            play.draw(self.screen)
            arch.draw(self.screen)
            self.buttons.extend([play, arch])

        if not self.museums:
            text(self.screen, "Пока нет ни одного музея — создайте первый",
                 (config.WINDOW_W // 2, 240), 18, COL_DIM, center=True)

        for b in self.buttons[:3]:
            b.hover = b.rect.collidepoint(mouse)
            b.draw(self.screen)

    # Рисуем игру
    # Экран проигрыша
    def enter_defeat(self):
        if self.mode == "defeat":
            return
        self.mode = "defeat"
        self.dialog = None
        self.defeat_stats = None
        mid = self.museum_id
        self.run_db(
            lambda: self.db.statistics(mid),
            lambda row: setattr(self, "defeat_stats", row or {}),
            "итоги партии",
        )

    def leave_defeat(self, new_museum=False):
        uid = self.user_id
        sid = self.session_id

        def job():
            if sid:
                try:
                    self.db.finish_session(sid)
                except Exception:  # noqa: BLE001
                    pass
            return self.db.museums(uid)

        def done(rows):
            self.museums = rows
            self.worker.watch(None, None)
            self.museum_id = self.session_id = None
            self.mode = "menu"
            if new_museum:
                self.new_museum()

        self.run_db(job, done, "выход из партии")

    def draw_defeat(self):
        self.screen.fill(COL_NIGHT)
        box = pygame.Rect(0, 0, 640, 420)
        box.center = (config.WINDOW_W // 2, config.WINDOW_H // 2)
        panel(self.screen, box, COL_PANEL, COL_WARN, radius=12)

        text(self.screen, "БАНКРОТСТВО", (box.centerx, box.y + 46), 34, COL_WARN,
             bold=True, center=True)
        text(self.screen, "Бюджет музея ушёл ниже допустимого предела",
             (box.centerx, box.y + 82), 15, COL_DIM, center=True)

        stats = getattr(self, "defeat_stats", None)
        y = box.y + 128
        if stats:
            rows = [
                ("Сыграно игровых дней", int(stats.get("total_days", 0))),
                ("Всего посетителей", int(stats.get("total_visitors", 0))),
                ("Общий доход", int(stats.get("total_income", 0))),
                ("Общий расход", int(stats.get("total_expense", 0))),
                ("Событий произошло", int(stats.get("total_events", 0))),
                ("Украдено экспонатов", int(stats.get("stolen", 0))),
            ]
            for label, value in rows:
                text(self.screen, label, (box.x + 60, y), 16, COL_DIM)
                text(self.screen, f"{value}", (box.right - 60, y), 16, COL_TEXT)
                y += 30
        else:
            text(self.screen, "Считаю итоги…", (box.centerx, y + 40), 16, COL_DIM,
                 center=True)

        self.buttons = [
            Button((box.x + 60, box.bottom - 72, 230, 44), "Вернуться в меню",
                   lambda: self.leave_defeat(False)),
            Button((box.right - 290, box.bottom - 72, 230, 44), "Начать новый музей",
                   lambda: self.leave_defeat(True), tone="accent"),
        ]
        mouse = pygame.mouse.get_pos()
        for b in self.buttons:
            b.hover = b.rect.collidepoint(mouse)
            b.draw(self.screen)

    # Основной игровой экран
    def draw_game(self, dt):
        state = self.snap("state")
        clock = self.snap("clock") or {}
        night = bool(clock.get("night", 1))

        if state and state.get("status") == "Банкрот":
            self.enter_defeat()
            return

        self.screen.fill(COL_NIGHT if night else COL_BG)
        self.draw_topbar(state, clock)
        self.draw_floor(night)
        self.draw_side(state)
        self.draw_actions()

        self.crowd.resize(0 if night else int(self.snap("visitors", 0) or 0), FLOOR)
        self.crowd.update(dt, FLOOR)
        if not night:
            self.crowd.draw(self.screen)

    def draw_topbar(self, state, clock):
        bar = pygame.Rect(16, 12, config.WINDOW_W - 32, 48)
        panel(self.screen, bar, COL_PANEL, COL_LINE)
        if not state:
            text(self.screen, "Загрузка состояния музея…", (bar.x + 16, bar.y + 15), 16, COL_DIM)
            return

        budget = float(state["current_budget"])
        tone = COL_OK if budget >= 0 else COL_WARN
        cells = [
            (state["museum_name"], COL_ACCENT, 240),
            (f"бюджет: {budget:,.0f}".replace(",", " "), tone, 190),
            (f"рейтинг: {int(state['rating'])}", COL_TEXT, 140),
            (f"день {int(clock.get('day_number', 0))}  {clock.get('game_time', '--:--')}",
             COL_TEXT, 170),
            (f"x{int(clock.get('speed_factor', 1) or 1)}",
             COL_ACCENT if int(clock.get("speed_factor", 1) or 1) > 1 else COL_DIM, 46),
            (f"посетителей сейчас: {int(self.snap('visitors', 0) or 0)}", COL_TEXT, 240),
            (state["status"], COL_WARN if state["status"] != "Активен" else COL_DIM, 120),
        ]
        x = bar.x + 16
        for label, color, width in cells:
            text(self.screen, clip_text(label, 30), (x, bar.y + 15), 16, color)
            x += width

    def draw_floor(self, night):
        panel(self.screen, FLOOR, (30, 33, 41) if not night else (22, 24, 33), COL_LINE)
        text(self.screen, "ПЛАН МУЗЕЯ" + ("  ·  ночь, посетителей нет" if night else ""),
             (FLOOR.x + 12, FLOOR.y + 8), 14, COL_DIM)

        halls = self.snap("halls", []) or []
        exhibits = self.snap("exhibits", []) or []
        improvements = self.snap("improvements", []) or []
        by_hall: dict = {}
        for e in exhibits:
            by_hall.setdefault(e["hall_id"], []).append(e)
        imp_by_hall: dict = {}
        for i in improvements:
            if i["status"] == "Активно":
                imp_by_hall.setdefault(i["hall_id"], []).append(i["improvement_name"])

        cols, cw, ch, gap = 4, 205, 138, 12
        mouse = pygame.mouse.get_pos()
        self._hall_rects = []

        for idx, hall in enumerate(halls[:12]):
            col, row = idx % cols, idx // cols
            rect = pygame.Rect(
                FLOOR.x + 14 + col * (cw + gap),
                FLOOR.y + 34 + row * (ch + gap),
                cw,
                ch,
            )
            self._hall_rects.append((rect, hall))
            theme_color = THEME_COLORS.get(hall["theme"], THEME_COLORS["без темы"])
            selected = self.selected_hall == hall["hall_id"]
            border = COL_ACCENT if selected else COL_LINE
            panel(self.screen, rect, (38, 41, 52), border, radius=8)

            head = pygame.Rect(rect.x, rect.y, rect.width, 26)
            pygame.draw.rect(self.screen, theme_color, head, border_top_left_radius=8,
                             border_top_right_radius=8)
            text(self.screen, clip_text(hall["hall_name"], 18), (rect.x + 8, rect.y + 5), 14,
                 (18, 18, 22), bold=True)

            занято, вместимость = int(hall["occupied"]), int(hall["capacity"])
            text(self.screen, f"{hall['theme']} · {занято}/{вместимость}",
                 (rect.x + 8, rect.y + 32), 13, COL_DIM)

            # экспонаты рисуем квадратиками
            ex_list = by_hall.get(hall["hall_id"], [])
            per_row = 10
            for j in range(вместимость):
                gx = rect.x + 9 + (j % per_row) * 18
                gy = rect.y + 54 + (j // per_row) * 18
                cell = pygame.Rect(gx, gy, 14, 14)
                if j < len(ex_list):
                    stars = int(ex_list[j]["star_rating"])
                    shade = {3: (120, 128, 146), 4: (168, 150, 108), 5: (233, 196, 106)}[stars]
                    pygame.draw.rect(self.screen, shade, cell, border_radius=3)
                else:
                    pygame.draw.rect(self.screen, (52, 56, 70), cell, width=1, border_radius=3)

            footer = rect.bottom - 22
            marks = "".join("◆" for _ in imp_by_hall.get(hall["hall_id"], []))
            if marks:
                text(self.screen, marks, (rect.x + 8, footer), 14, COL_OK)
            if int(hall["employees_count"]) > 0:
                text(self.screen, f"☺ {int(hall['employees_count'])}",
                     (rect.x + 60, footer), 13, COL_TEXT)
            if hall["can_hire"] == 1:
                text(self.screen, "можно нанять", (rect.right - 92, footer), 12, COL_ACCENT)

            if rect.collidepoint(mouse) and not selected:
                pygame.draw.rect(self.screen, (90, 98, 118), rect, width=1, border_radius=8)

        if not halls:
            text(self.screen, "Залы загружаются…", FLOOR.center, 18, COL_DIM, center=True)

    def draw_side(self, state):
        panel(self.screen, SIDE, COL_PANEL, COL_LINE)
        y = SIDE.y + 12

        text(self.screen, "ПОСЛЕДНИЕ ДНИ", (SIDE.x + 14, y), 14, COL_ACCENT, bold=True)
        y += 24
        days = self.snap("days", []) or []
        if not days:
            text(self.screen, "день ещё не закрыт", (SIDE.x + 14, y), 13, COL_DIM)
            y += 20
        for d in days[:5]:
            rating = d.get("rating")
            tail = f", рейтинг {int(rating)}" if rating is not None else ""
            text(self.screen,
                 f"день {int(d['day_number'])}: {int(d['visitors_count'])} чел., "
                 f"{int(d['income'])}{tail}",
                 (SIDE.x + 14, y), 13, COL_TEXT if d["status"] == "Закрыт" else COL_DIM)
            y += 20

        mix = self.snap("mix", []) or []
        if mix:
            y += 6
            text(self.screen, "КОГО ПРИТЯГИВАЕТ МУЗЕЙ", (SIDE.x + 14, y), 14,
                 COL_ACCENT, bold=True)
            y += 22
            for m in mix:
                share = m.get("share_percent")
                label = f"{m['category']}: {share:.0f}%" if share is not None \
                    else f"{m['category']}: —"
                text(self.screen, label, (SIDE.x + 14, y), 13, COL_DIM)
                y += 18

        y += 10
        pygame.draw.line(self.screen, COL_LINE, (SIDE.x + 10, y), (SIDE.right - 10, y))
        y += 12
        text(self.screen, "СОБЫТИЯ", (SIDE.x + 14, y), 14, COL_ACCENT, bold=True)
        y += 24
        events = self.snap("events", []) or []
        if not events:
            text(self.screen, "пока ничего не происходило", (SIDE.x + 14, y), 13, COL_DIM)
            y += 20
        for e in events[:7]:
            effect = e.get("budget_effect") or 0
            color = COL_OK if effect > 0 else (COL_WARN if effect < 0 else COL_TEXT)
            text(self.screen,
                 clip_text(f"[{e['event_context']}] {e['event_name']}", 40),
                 (SIDE.x + 14, y), 13, color)
            y += 18
            text(self.screen, clip_text(e["description"] or "", 46), (SIDE.x + 22, y), 12, COL_DIM)
            y += 20

        y += 6
        pygame.draw.line(self.screen, COL_LINE, (SIDE.x + 10, y), (SIDE.right - 10, y))
        y += 12
        text(self.screen, "ЖУРНАЛ ДЕЙСТВИЙ", (SIDE.x + 14, y), 14, COL_ACCENT, bold=True)
        y += 24
        for a in (self.snap("actions", []) or [])[:6]:
            color = COL_OK if a["result"] == "Успех" else COL_WARN
            text(self.screen, clip_text(f"{a['action_code']} — {a['result']}", 40),
                 (SIDE.x + 14, y), 13, color)
            y += 17
            if a["result"] != "Успех":
                text(self.screen, clip_text(a["description"] or "", 46),
                     (SIDE.x + 22, y), 12, COL_DIM)
                y += 17

        if state:
            text(self.screen,
                 f"склад: {int(state['in_storage'])}   сотрудников: {int(state['employees_count'])}"
                 f"   фонд з/п: {int(state['salary_fund'])}",
                 (SIDE.x + 14, SIDE.bottom - 26), 13, COL_DIM)

    def draw_actions(self):
        panel(self.screen, ACTIONS, COL_PANEL, COL_LINE)
        text(self.screen, "ДЕЙСТВИЯ КУРАТОРА", (ACTIONS.x + 14, ACTIONS.y + 10), 14,
             COL_ACCENT, bold=True)
        text(self.screen,
             "действие ставится в очередь планировщика — расчёты выполняет база данных",
             (ACTIONS.x + 220, ACTIONS.y + 11), 13, COL_DIM)
        mouse = pygame.mouse.get_pos()
        for b in self.buttons:
            b.hover = b.rect.collidepoint(mouse)
            b.draw(self.screen)

    # Главный цикл
    def quit(self):
        self.mode = "quit"

    def handle_event(self, event):
        if event.type == pygame.QUIT:
            self.mode = "quit"
            return

        if self.dialog:
            self.dialog.handle(event)
            if self.dialog.done:
                self.dialog = None
            return

        if self.mode == "connect":
            order = ["host", "port", "database", "user", "password"]
            for index, key in enumerate(order):
                if self.conn_fields[key].handle(event) == "submit":
                    if key == "password":
                        self.start_connect(False)
                    else:
                        # Enter и Tab перескакивают на следующее поле
                        for other in order:
                            self.conn_fields[other].focused = False
                        self.conn_fields[order[index + 1]].focused = True
                    break

        if self.mode == "login":
            for widget in (self.login_input, self.pass_input):
                if widget.handle(event) == "submit":
                    self.do_login()

        if self.mode == "game" and event.type == pygame.KEYDOWN:
            hotkeys = {
                pygame.K_1: 0, pygame.K_2: 1, pygame.K_3: 2, pygame.K_4: 3,
                pygame.K_5: 4, pygame.K_6: 5, pygame.K_7: 6, pygame.K_8: 7,
                pygame.K_9: 8, pygame.K_q: 9, pygame.K_w: 10, pygame.K_e: 11,
                pygame.K_s: 12, pygame.K_p: 13, pygame.K_f: 14,
            }
            index = hotkeys.get(event.key)
            if index is not None and index < len(self.buttons):
                self.buttons[index].action()

        if (
            self.mode == "game"
            and event.type == pygame.MOUSEBUTTONDOWN
            and event.button == 1
        ):
            for rect, hall in getattr(self, "_hall_rects", []):
                if rect.collidepoint(event.pos):
                    self.selected_hall = hall["hall_id"]

        for b in list(self.buttons):
            if b.handle(event):
                break

    def drain_results(self):
        if not self.worker:
            return
        while True:
            try:
                kind, callback, payload = self.worker.results.get_nowait()
            except queue.Empty:
                return
            if kind == "error":
                self.toast.show(clip_text(payload, 110), "error", 6.0)
            elif callback:
                try:
                    callback(payload)
                except Exception as err:  # noqa: BLE001
                    self.toast.show(f"Ошибка интерфейса: {err}", "error")

    def run(self):
        while self.mode != "quit":
            dt = self.clock.tick(config.FPS) / 1000.0
            for event in pygame.event.get():
                self.handle_event(event)
            self.drain_connect()
            self.drain_results()

            if self.mode == "connect":
                self.draw_connect()
            elif self.mode == "fatal":
                self.screen.fill(COL_BG)
                text(self.screen, "Нет связи с базой данных",
                     (config.WINDOW_W // 2, config.WINDOW_H // 2 - 30), 24, COL_WARN, center=True)
                text(self.screen, clip_text(self.status_line, 100),
                     (config.WINDOW_W // 2, config.WINDOW_H // 2 + 8), 15, COL_DIM, center=True)
                self.buttons = [
                    Button((config.WINDOW_W // 2 - 110, config.WINDOW_H // 2 + 44, 220, 40),
                           "Вернуться к подключению", self.back_to_connect, tone="accent"),
                ]
                for b in self.buttons:
                    b.draw(self.screen)
            elif self.mode == "login":
                self.draw_login()
            elif self.mode == "menu":
                self.draw_menu()
            elif self.mode == "game":
                self.draw_game(dt)
            elif self.mode == "defeat":
                self.draw_defeat()

            if self.dialog:
                self.dialog.draw(self.screen)
            self.toast.draw(self.screen)
            pygame.display.flip()

        if self.worker:
            self.worker.stop()
        if self.db:
            self.db.close()
        pygame.quit()

def main():
    try:
        Game().run()
    except KeyboardInterrupt:
        pygame.quit()
        sys.exit(0)

if __name__ == "__main__":
    main()
