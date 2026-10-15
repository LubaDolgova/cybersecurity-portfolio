"""Играет целую партию через базу, без окна и картинок.

Регистрируется, создаёт музей, запускает сессию, выполняет все девять
действий куратора, крутит игровое время, закрывает день и смотрит
отчёты. Заодно сравнивает имена столбцов, которые реально пришли из
базы, с ключами, по которым клиент лезет в словари.

Эта сверка нужна вот зачем: один раз игра падала с «Ошибка интерфейса:
'id_уровня_сложности'», а смоук-тесты молчали. Потому что в заглушке
стоял ровно такой же неправильный ключ, как и в клиенте. Здесь ключи
сверяются с настоящей базой, и подменить их нечем.

Запуск:

    .\\.venv\\Scripts\\python.exe python\\check_runtime.py ^
        10.22.10.41 1521 sid orcl KS2318_11 пароль

В конце скрипт удаляет созданный тестовый музей, поэтому запускать
можно сколько угодно раз.
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path

import oracledb

import db as db_module
import settings

# Эти ключи клиент придумывает сам, из базы они не приходят.
OWN_KEYS = {
    "state", "halls", "exhibits", "clock", "visitors", "storage",
    "employees", "improvements", "events", "actions", "mix", "days",
    "host", "port", "kind", "database", "user", "password",
}

FAILS: list[str] = []
NOTES: list[str] = []

def ok(title: str, good: bool, note: str = "") -> bool:
    print(("  OK     " if good else "  ПРОВАЛ ") + title + (f"   [{note}]" if note else ""))
    if not good:
        FAILS.append(f"{title} — {note}" if note else title)
    return good

def warn(title: str, note: str = "") -> None:
    print("  ВНИМ   " + title + (f"   [{note}]" if note else ""))
    NOTES.append(f"{title} — {note}" if note else title)

def probe_columns(db, routine: str, args) -> list[str]:
    """Имена столбцов курсора, даже если строк он не вернул вообще.

    Обычный путь — прочитать ключи первой строки — на пустом курсоре
    ничего не даёт: журнал событий у нового музея пуст по определению.
    Поэтому здесь курсор открывается напрямую и читается его описание.
    """
    with db.raw.cursor() as cur:
        result = cur.callfunc(f"museum_curator.{routine}", oracledb.CURSOR, list(args))
        names = [d[0].lower() for d in result.description]
        result.close()
    return names

def require(rows, title: str, needed: list[str]) -> bool:
    """Проверить, что курсор вернул нужные столбцы.

    Без этого отсутствующий столбец превращался в KeyError и трейсбек
    посреди проверки. Теперь видно и чего не хватает, и что пришло
    на самом деле — этого достаточно, чтобы опознать старую схему.
    """
    if not rows:
        ok(f"{title}: состав столбцов", False, "нет строк")
        return False
    actual = set(rows[0].keys())
    missing = [name for name in needed if name not in actual]
    if missing:
        ok(f"{title}: состав столбцов", False,
           f"нет {', '.join(missing)}; пришли: {', '.join(sorted(actual))}")
        return False
    ok(f"{title}: состав столбцов", True, f"{len(needed)} нужных на месте")
    return True

def client_keys() -> set[str]:
    """Собирает все ключи, по которым main.py лезет в словари из базы."""
    source = (Path(__file__).resolve().parent / "main.py").read_text(encoding="utf-8")
    pattern = re.compile(r"""(?:(?<=[\w)\]])\[\s*|\.get\(\s*)(['"])([A-Za-z_]\w*)\1""")
    return {m.group(2) for m in pattern.finditer(source)} - OWN_KEYS

def main(argv: list[str]) -> int:
    if len(argv) != 6:
        print(__doc__)
        return 2
    host, port, kind, database, user, password = argv
    if kind not in (settings.KIND_SID, settings.KIND_SERVICE):
        print("Третий аргумент — service или sid")
        return 2

    conn = settings.Connection(host=host, port=int(port), kind=kind,
                               database=database, user=user, password=password)
    print(f"Подключение: {conn.short_dsn()}")
    try:
        db = db_module.Database(conn)
    except Exception as err:  # noqa: BLE001
        print(f"ПРОВАЛ: {err}")
        return 1

    print("\n=== 1. СПРАВОЧНИКИ ===")
    columns_seen: set[str] = set()

    def grab(title, fn, expect_rows=True):
        """Зовём геттер, печатаем столбцы и запоминаем их имена."""
        try:
            rows = fn()
        except Exception as err:  # noqa: BLE001
            ok(title, False, str(err)[:90])
            return []
        if isinstance(rows, dict):
            rows = [rows]
        if rows:
            columns_seen.update(rows[0].keys())
            ok(title, True, f"строк {len(rows)}, столбцов {len(rows[0])}")
        elif expect_rows:
            ok(title, False, "пусто, а должны быть данные")
        else:
            ok(title, True, "пусто — допустимо")
        return rows

    difficulties = grab("difficulties (уровни сложности)", db.difficulties)
    catalog = grab("catalog (каталог экспонатов)", db.catalog)
    themes = grab("themes (темы)", db.themes)
    positions = grab("positions (должности)", db.positions)
    improvements = grab("improvement_types (типы улучшений)", db.improvement_types)
    grab("preferences (предпочтения)", db.preferences)

    ok("в каталоге 20 экспонатов", len(catalog) == 20, str(len(catalog)))
    ok("три уровня сложности", len(difficulties) == 3, str(len(difficulties)))
    ok("три темы", len(themes) == 3, str(len(themes)))

    if not (difficulties and catalog and themes and positions and improvements):
        print("\nБез справочников дальше проверять нечего.")
        return 1

    # Сначала смотрим, какие столбцы пришли, и только потом ими пользуемся.
    shape = all([
        require(difficulties, "difficulties",
                ["difficulty_id", "difficulty_name", "start_budget"]),
        require(catalog, "catalog", ["catalog_exhibit_id", "price"]),
        require(themes, "themes", ["theme_id"]),
        require(positions, "positions", ["position_id"]),
        require(improvements, "improvement_types", ["improvement_type_id"]),
    ])
    if not shape:
        print("\nСхема в базе не та, которую ожидает клиент.")
        print("Скорее всего установлена старая версия — переустановите:")
        print("  python check_install.py <адрес> <порт> service|sid <база> "
              "<пользователь> <пароль>")
        return 1

    print("\n=== 2. РЕГИСТРАЦИЯ И МУЗЕЙ ===")
    login = f"chk_{int(time.time()) % 100000000}"
    try:
        db.register(login, "test1234")
        user_id = db.login(login, "test1234")
        ok("регистрация и вход", bool(user_id), f"id_пользователя {user_id}")
    except Exception as err:  # noqa: BLE001
        ok("регистрация и вход", False, str(err)[:90])
        return 1

    easy = min(difficulties, key=lambda d: -d["start_budget"])
    museum_name = f"Проверка {login}"
    try:
        db.create_museum(user_id, museum_name, easy["difficulty_id"])
    except Exception as err:  # noqa: BLE001
        ok("создание музея", False, str(err)[:90])
        return 1

    museums = grab("museums (список музеев)", lambda: db.museums(user_id))
    if not require(museums, "museums", ["museum_id", "museum_name"]):
        return 1
    mine = [m for m in museums if m["museum_name"] == museum_name]
    if not ok("музей создан и виден в списке", bool(mine)):
        return 1
    museum_id = mine[0]["museum_id"]

    state = grab("state (состояние музея)", lambda: db.state(museum_id))
    if state and require(state, "state", ["current_budget", "halls_count"]):
        budget = state[0]["current_budget"]
        ok("стартовый бюджет соответствует сложности",
           float(budget) == float(easy["start_budget"]),
           f"{budget} против {easy['start_budget']}")
        ok("музей начинается с одного зала", int(state[0]["halls_count"]) == 1,
           str(state[0]["halls_count"]))

    try:
        db.start_session(museum_id)
        session_id = db.active_session(museum_id)
        ok("сессия открыта", bool(session_id), f"id_сессии {session_id}")
    except Exception as err:  # noqa: BLE001
        ok("сессия открыта", False, str(err)[:90])
        return 1

    grab("clock (игровые часы)", lambda: db.clock(session_id))
    grab("halls (залы)", lambda: db.halls(museum_id))

    print("\n=== 3. ДЕЙСТВИЯ КУРАТОРА ===")
    # Порядок тут важен: сначала открыть зал и купить, потом остальное.
    halls = db.halls(museum_id)
    if not require(halls, "halls", ["hall_id"]):
        return 1
    first_hall = halls[0]["hall_id"]
    cheap = sorted(catalog, key=lambda c: c["price"])[0]
    theme_id = themes[0]["theme_id"]
    position_id = positions[0]["position_id"]
    improvement_id = improvements[0]["improvement_type_id"]

    def act(code, params, title):
        try:
            db.enqueue(museum_id, session_id, code, params)
            db.process_queue()
        except Exception as err:  # noqa: BLE001
            ok(f"{title} ({code})", False, str(err)[:90])
            return False
        log = db.actions(museum_id, 5)
        row = next((a for a in log if a["action_code"] == code), None)
        if row is None:
            ok(f"{title} ({code})", False, "действия нет в журнале")
            return False
        good = row["result"] == "Успех"
        ok(f"{title} ({code})", good, row["result"] + ": " + str(row["description"])[:60])
        return good

    def act_refused(code, params, title, because):
        """Действие, на которое пакет ОБЯЗАН ответить отказом.

        Проверять только успешные пути мало: правила игры живут в
        отказах, и если отказ однажды перестанет срабатывать, партию
        можно будет сломать. Поэтому запрет проверяется явно.
        """
        db.enqueue(museum_id, session_id, code, params)
        db.process_queue()
        log = db.actions(museum_id, 5)
        row = next((a for a in log if a["action_code"] == code), None)
        refused = row is not None and row["result"] != "Успех"
        ok(f"{title} — должно быть отклонено ({because})", refused,
           (row["description"] or "")[:70] if row else "действия нет в журнале")

    act("OPEN_HALL", {"NAME": "Зал проверки", "SIZE": "Маленький", "THEME": None},
        "Открыть зал")

    # Тему меняем, пока зал пустой. Если в нём уже стоят экспонаты,
    # пакет менять тему не даст, это проверяем чуть ниже отдельно.
    act("CHANGE_THEME", {"HALL": first_hall, "THEME": theme_id},
        "Сменить тему пустого зала")

    # Сотрудник положен один на пять выставленных экспонатов
    # (константа c_exhibits_per_emp). Поэтому сначала покупаем и
    # выставляем пять штук, иначе нанять не дадут, и правильно.
    per_employee = 5
    cheapest = sorted(catalog, key=lambda c: c["price"])[:per_employee]
    for item in cheapest:
        act("BUY_EXHIBIT", {"CATALOG": item["catalog_exhibit_id"]},
            f"Купить «{item['exhibit_name']}»")

    storage = grab("storage (склад)", lambda: db.storage(museum_id))
    ok(f"на складе {per_employee} экспонатов", len(storage) == per_employee,
       str(len(storage)))

    placed = []
    for row in storage:
        if act("PLACE_EXHIBIT",
               {"EXHIBIT": row["museum_exhibit_id"], "HALL": first_hall},
               f"Выставить «{row['exhibit_name']}»"):
            placed.append(row["museum_exhibit_id"])

    shown = grab("exhibits (экспонаты в залах)", lambda: db.exhibits(museum_id))
    ok(f"в зале {per_employee} экспонатов", len(shown) == per_employee, str(len(shown)))
    grab("sellable (что можно продать)", lambda: db.sellable(museum_id))

    other_theme = next((x["theme_id"] for x in themes if x["theme_id"] != theme_id),
                       theme_id)
    act_refused("CHANGE_THEME", {"HALL": first_hall, "THEME": other_theme},
                "Смена темы зала с экспонатами", "в зале стоят экспонаты")

    act("HIRE_EMPLOYEE",
        {"HALL": first_hall, "POSITION": position_id,
         "LAST": "Проверкин", "FIRST": "Тест"},
        "Нанять сотрудника")

    employees = grab("employees (сотрудники)", lambda: db.employees(museum_id))
    if employees:
        act("ASSIGN_EMPLOYEE",
            {"EMPLOYEE": employees[0]["employee_id"], "HALL": first_hall},
            "Перевести сотрудника")

    # Второго нанять уже нельзя: экспонатов по-прежнему пять.
    before_hire = len(db.employees(museum_id))
    act_refused("HIRE_EMPLOYEE",
                {"HALL": first_hall, "POSITION": position_id,
                 "LAST": "Лишний", "FIRST": "Тест"},
                "Второй наём на те же пять экспонатов",
                "один сотрудник на пять экспонатов")
    ok("число сотрудников не изменилось",
       len(db.employees(museum_id)) == before_hire, f"было {before_hire}")

    # Покупка дороже, чем есть денег, тоже должна отвалиться.
    dearest = max(catalog, key=lambda c: c["price"])
    # Осторожно: db.state отдаёт ОДИН словарь, а не список.
    state_now = db.state(museum_id)
    if state_now and float(state_now["current_budget"]) < float(dearest["price"]):
        act_refused("BUY_EXHIBIT", {"CATALOG": dearest["catalog_exhibit_id"]},
                    "Покупка дороже бюджета", "не хватает средств")

    # Берём один экспонат: снимаем с экспозиции и продаём.
    if placed:
        act("REMOVE_EXHIBIT", {"EXHIBIT": placed[0]}, "Убрать на склад")
        act("SELL_EXHIBIT", {"EXHIBIT": placed[0]}, "Продать экспонат")

    act("BUY_IMPROVEMENT", {"HALL": first_hall, "TYPE": improvement_id},
        "Купить улучшение")
    grab("hall_improvements (улучшения залов)", lambda: db.hall_improvements(museum_id))

    print("\n=== 4. ИГРОВОЕ ВРЕМЯ ===")
    # Игровое время считается от настоящего: секунда реального времени
    # это минута игрового. Поэтому дёргать tick подряд бесполезно,
    # надо реально подождать.
    before = db.clock(session_id)
    db.tick()
    time.sleep(4)
    db.tick()
    after = db.clock(session_id)
    ok("игровое время идёт вслед за реальным",
       before["game_time"] != after["game_time"],
       f"{before['game_time']} -> {after['game_time']} за 4 с")
    # Ускорение: на x4 часы должны идти вчетверо быстрее, а когда
    # вернём обычную скорость, время не должно скакнуть.
    db.set_speed(session_id, 4)
    fast_before = db.clock(session_id)
    ok("скорость переключилась на x4",
       int(fast_before["speed_factor"]) == 4, str(fast_before["speed_factor"]))

    def minutes(row):
        hours, mins = str(row["game_time"]).split(":")
        return int(hours) * 60 + int(mins)

    db.tick()
    time.sleep(3)
    db.tick()
    fast_after = db.clock(session_id)
    gained = minutes(fast_after) - minutes(fast_before)
    ok("на x4 за 3 с проходит около 12 игровых минут",
       10 <= gained <= 14, f"прошло {gained}")

    at_switch = minutes(fast_after)
    db.set_speed(session_id, 1)
    back = db.clock(session_id)
    ok("при возврате на x1 часы не прыгнули",
       abs(minutes(back) - at_switch) <= 2,
       f"{at_switch} -> {minutes(back)} игровых минут")
    ok("скорость вернулась на x1", int(back["speed_factor"]) == 1,
       str(back["speed_factor"]))
    ok("current_visitors отвечает числом",
       isinstance(db.current_visitors(museum_id, session_id), int),
       str(db.current_visitors(museum_id, session_id)))
    grab("visitor_mix (состав посетителей)", db_mix(db, museum_id), expect_rows=False)
    grab("events (события)", lambda: db.events(museum_id, 10), expect_rows=False)
    grab("day_report (отчёт по дням)", lambda: db.day_report(session_id, 5),
         expect_rows=False)
    grab("statistics (статистика)", lambda: db.statistics(museum_id))

    print("\n=== 5. ТЕКСТОВЫЕ ОТЧЁТЫ (DBMS_OUTPUT) ===")
    for title, fn in (("info_text (справка)", db.info_text),
                      ("museum_state_text (состояние)",
                       lambda: db.museum_state_text(museum_id)),
                      ("statistics_text (статистика)",
                       lambda: db.statistics_text(museum_id))):
        try:
            lines = fn()
            ok(title, bool(lines), f"строк {len(lines)}")
        except Exception as err:  # noqa: BLE001
            ok(title, False, str(err)[:90])

    print("\n=== 6. ПАУЗА И ВОЗОБНОВЛЕНИЕ ===")
    try:
        db.pause_session(session_id)
        db.resume_session(museum_id)
        again = db.active_session(museum_id)
        ok("сессия снимается с паузы", bool(again), f"id_сессии {again}")
    except Exception as err:  # noqa: BLE001
        ok("сессия снимается с паузы", False, str(err)[:90])

    print("\n=== 7. СВЕРКА КЛЮЧЕЙ КЛИЕНТА СО СТОЛБЦАМИ БАЗЫ ===")
    # Столбцы спрашиваем у КАЖДОГО курсора напрямую. Нельзя надеяться,
    # что курсор вернёт хоть одну строку: у нового музея журнал событий
    # пустой, и раньше его столбцы вообще не попадали в сверку.
    probes = (
        ("get_museum_state", [museum_id]),
        ("get_halls", [museum_id]),
        ("get_hall_exhibits", [museum_id]),
        ("get_storage", [museum_id]),
        ("get_sellable", [museum_id]),
        ("get_catalog", []),
        ("get_themes", []),
        ("get_preferences", []),
        ("get_visitor_mix", [museum_id]),
        ("get_positions", []),
        ("get_improvement_types", []),
        ("get_difficulties", []),
        ("get_employees", [museum_id]),
        ("get_hall_improvements", [museum_id]),
        ("get_recent_events", [museum_id, 12]),
        ("get_recent_actions", [museum_id, 12]),
        ("get_day_report", [session_id, 10]),
        ("get_statistics", [museum_id]),
        ("get_user_museums", [user_id]),
        ("get_clock", [session_id]),
    )
    for routine, args in probes:
        try:
            columns_seen.update(probe_columns(db, routine, args))
        except Exception as err:  # noqa: BLE001
            ok(f"опрос столбцов {routine}", False, str(err)[:80])

    needed = client_keys()
    missing = sorted(needed - columns_seen)
    print(f"  курсоров опрошено: {len(probes)}, столбцов всего: {len(columns_seen)}")
    print(f"  клиент использует ключей: {len(needed)}")
    ok("каждый ключ клиента есть среди столбцов базы", not missing,
       ", ".join(missing[:8]) if missing else "")
    unused = sorted(columns_seen - needed)
    if unused:
        warn("столбцы, которые клиент не читает",
             f"{len(unused)}: {', '.join(unused[:6])}…")

    print("\n=== 8. УБОРКА ===")
    try:
        db.finish_session(session_id)
        db.delete_museum(museum_id, "проверка завершена")
        left = [m for m in db.museums(user_id) if m["museum_id"] == museum_id
                and m["status"] != "Архивирован"]
        ok("тестовый музей убран в архив", not left)
    except Exception as err:  # noqa: BLE001
        ok("уборка", False, str(err)[:90])

    db.close()

    print("\n" + "=" * 70)
    if FAILS:
        print(f"ИТОГ: ПРОВАЛОВ {len(FAILS)}")
        for line in FAILS:
            print("   - " + line)
        return 1
    print(">>> СКВОЗНАЯ ПРОВЕРКА ПРОЙДЕНА. Игра работает на этом сервере.")
    if NOTES:
        print(f"    предупреждений: {len(NOTES)} (не ошибки)")
    return 0

def db_mix(db, museum_id):
    """visitor_mix хочет id музея, поэтому заворачиваем его для grab()."""
    return lambda: db.visitor_mix(museum_id)

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyError as err:
        key = err.args[0] if err.args else None
        if isinstance(key, str):
            # Нет такого столбца — почти всегда в базе старая схема.
            print(f"\nПРОВАЛ: база не вернула столбец {key!r}.")
            print("Похоже, в схеме стоит другая версия пакета.")
            print("Переустановите схему через check_install.py и повторите.")
        else:
            # Числовой ключ у словаря — это я накосячил в самом скрипте,
            # база тут ни при чём.
            print(f"\nПРОВАЛ: ошибка в скрипте проверки, обращение по ключу {key!r}.")
            print("Это не проблема схемы: сообщите мне текст целиком.")
        sys.exit(1)
