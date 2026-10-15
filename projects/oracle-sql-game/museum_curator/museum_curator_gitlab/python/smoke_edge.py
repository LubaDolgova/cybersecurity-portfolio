"""Неудобные случаи, на которых игра может упасть.

Запуск: python smoke_edge.py

Смотрю, что будет, если музей совсем пустой, если игрок обанкротился,
если пакет отказывает на каждое действие и если связь с базой
оборвалась посреди партии. Oracle для этого не нужен.
"""
import os

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")

import pygame  # noqa: E402

import oracledb  # noqa: E402

import db as db_module  # noqa: E402
from db import GameError  # noqa: E402

REAL_DATABASE = db_module.Database   # запоминаем настоящий, пока не подменили
from smoke_ui import FakeDB, _pump  # noqa: E402

RESULTS = []

def settle(game, seconds=2.5):
    """Крутит кадры несколько настоящих секунд, чтобы фоновый поток
    успел сходить в базу: он обновляется раз в 0.7 с."""
    import time
    deadline = time.time() + seconds
    while time.time() < deadline:
        _pump(game, 5)

def wait_for(game, predicate, seconds=4.0):
    import time
    deadline = time.time() + seconds
    while time.time() < deadline:
        _pump(game, 3)
        if predicate():
            return True
    return False

def check(name, ok, note=""):
    RESULTS.append((name, ok, note))
    print(("  OK   " if ok else "  ПРОВАЛ ") + name + (f"  [{note}]" if note else ""))

class EmptyDB(FakeDB):
    """Совсем новый музей: ни залов, ни экспонатов, ни событий."""

    def halls(self, _mid):
        return []

    def exhibits(self, _mid):
        return []

    def storage(self, _mid):
        return []

    def sellable(self, _mid):
        return []

    def visitor_mix(self, _mid):
        return []

    def employees(self, _mid):
        return []

    def hall_improvements(self, _mid):
        return []

    def events(self, _mid, limit=12):
        return []

    def actions(self, _mid, limit=12):
        return []

    def day_report(self, _sid, limit=10):
        return []

    def current_visitors(self, *_):
        return 0

    def state(self, _mid):
        s = super().state(_mid)
        s.update({"halls_count": 0, "displayed_count": 0, "in_storage": 0,
                  "employees_count": 0, "salary_fund": 0})
        return s

class BankruptDB(FakeDB):
    def state(self, _mid):
        s = super().state(_mid)
        s.update({"current_budget": -1500, "status": "Банкрот", "rating": 0})
        return s

    def clock(self, _sid):
        return {"day_number": 9, "game_time": "19:00", "day_share": 1.0,
                "night": 1, "game_day_id": None}

class FailingDB(FakeDB):
    """База отказывает на любое действие."""

    def enqueue(self, *_a, **_k):
        raise GameError("Недостаточно средств: нужно 5200, в кассе 10")

class DeadDB(FakeDB):
    """Связь отвалилась прямо посреди партии."""

    def state(self, _mid):
        raise RuntimeError("DPY-4011: the database or network closed the connection")

    def halls(self, _mid):
        raise RuntimeError("DPY-4011: the database or network closed the connection")

def run_case(title, db_class, actions=()):
    print(f"\n--- {title}")
    db_module.Database = db_class
    import main as client

    # main.py написал "from db import Database", значит у него своё имя
    # Database, и подменять надо именно его. Сам модуль между случаями
    # не перезагружается, он кэшируется.
    client.Database = db_class

    game = client.Game()
    # Экран подключения пропускаем, соединение как будто уже есть.
    game.db = db_class()
    game.worker = client.Worker(game.db)
    game.worker.start()
    game.mode = "login"
    game.login_input.value = "t"
    game.pass_input.value = "t"
    game.do_login()
    _pump(game, 30)
    if game.mode != "menu":
        check(f"{title}: вход", False, f"режим {game.mode}")
        return game, client
    game.play(game.museums[0])
    _pump(game, 40)
    check(f"{title}: партия началась", game.mode in ("game", "defeat"), game.mode)
    settle(game)
    for act in actions:
        getattr(game, act)()
        _pump(game, 15)
    settle(game)
    return game, client

def main():
    # 1. Пустой музей: рисуется ли и не ломается ли на действиях без данных
    game, _ = run_case("пустой музей", EmptyDB,
                       ["act_place", "act_remove", "act_sell", "act_improve", "act_theme"])
    check("пустой музей: клиент не упал", game.mode == "game")
    check("пустой музей: действия без данных дали подсказку, а не диалог",
          game.dialog is None, "диалог не открылся — верно")
    game.worker.stop()

    # 2. Ушли в минус
    game, _ = run_case("банкротство", BankruptDB)
    check("банкротство: открылся экран поражения", game.mode == "defeat", game.mode)
    loaded = wait_for(game, lambda: game.defeat_stats is not None)
    check("банкротство: итоги партии загружены", loaded,
          str(game.defeat_stats)[:60] if game.defeat_stats else "пусто")
    check("банкротство: на экране есть кнопки выхода", len(game.buttons) == 2,
          f"кнопок {len(game.buttons)}")
    game.worker.stop()

    # 3. База на всё отвечает отказом
    game, _ = run_case("отказы пакета", FailingDB, ["act_buy"])
    dialog = game.dialog
    if dialog and getattr(dialog, "items", None):
        game.dialog = None
        dialog.on_pick(dialog.items[0][1])
    shown = wait_for(game, lambda: "Недостаточно средств" in game.toast.message)
    check("отказ пакета: текст ошибки из пакета показан игроку", shown,
          game.toast.message[:70] or "плашка пуста")
    check("отказ пакета: клиент продолжает работать", game.mode == "game")
    game.worker.stop()

    # 4. Связь оборвалась
    game, _ = run_case("обрыв связи", DeadDB)
    check("обрыв связи: клиент не упал", game.mode == "game")
    shown = wait_for(game, lambda: "DPY-4011" in game.toast.message)
    check("обрыв связи: сообщение показано", shown,
          game.toast.message[:70] or "плашка пуста")
    game.worker.stop()

    # 5. Умеет ли db.py сам переподключиться после обрыва
    print("\n--- переподключение к базе")
    made = []
    original_connect = oracledb.connect

    class FakeCursor:
        def __init__(self, conn):
            self.conn = conn

        def __enter__(self):
            return self

        def __exit__(self, *_a):
            return False

        def callproc(self, name, args):
            self.conn.calls += 1
            if self.conn.fail_once:
                self.conn.fail_once = False
                raise oracledb.DatabaseError(
                    "DPY-4011: the database or network closed the connection")

    class FakeConn:
        def __init__(self, fail_once):
            self.fail_once = fail_once
            self.calls = 0

        def cursor(self):
            return FakeCursor(self)

        def close(self):
            pass

    def fake_connect(**_kw):
        conn = FakeConn(fail_once=(len(made) == 0))
        made.append(conn)
        return conn

    oracledb.connect = fake_connect
    try:
        real = REAL_DATABASE()
        real._call("info")
        check("обрыв связи: соединение переоткрыто автоматически",
              real.reconnects == 1 and len(made) == 2,
              f"переподключений {real.reconnects}, соединений {len(made)}")
        real._call("info")
        check("после переподключения вызовы проходят", made[-1].calls >= 1)
    finally:
        oracledb.connect = original_connect

    pygame.quit()
    ok = sum(1 for _, good, _ in RESULTS if good)
    print(f"\nИтого проверок: {len(RESULTS)}, прошло {ok}, дефектов {len(RESULTS) - ok}")
    for name, good, note in RESULTS:
        if not good:
            print(f"  ДЕФЕКТ: {name} — {note}")

if __name__ == "__main__":
    main()
