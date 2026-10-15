"""Прогоняет все экраны игры без базы.

Вместо настоящего Database подставляю заглушку с выдуманными данными
и прокликиваю вход, меню и игровой экран. Логику тут не проверяю,
только то, что интерфейс не падает и рисует то, что ему дали.

Запуск:
    python smoke_ui.py            без окна, отчёт в консоли
    python smoke_ui.py --window   с окном, видно как всё кликается
"""
import os
import sys

if "--window" not in sys.argv:
    os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    os.environ.setdefault("SDL_AUDIODRIVER", "dummy")

import pygame  # noqa: E402

import db as db_module  # noqa: E402

class FakeDB:
    def __init__(self):
        self.queued = []
        self.speed = 1

    def register(self, *_):
        return None

    def login(self, *_):
        return 1

    def close(self):
        pass

    def museums(self, _uid):
        return [
            {
                "museum_id": 1,
                "museum_name": "Музей №1",
                "current_budget": 8400,
                "rating": 34,
                "difficulty": "Лёгкая",
                "status": "Активен",
                "created_at": None,
                "session_id": 5,
            }
        ]

    def create_museum(self, *_):
        return None

    def delete_museum(self, *_):
        return None

    def start_session(self, _mid):
        return None

    def active_session(self, _mid):
        return 5

    def pause_session(self, _sid):
        return None

    def finish_session(self, _sid):
        return None

    def enqueue(self, mid, sid, code, params=None):
        self.queued.append((code, params))

    def process_queue(self):
        return None

    def tick(self):
        return None

    def set_speed(self, _sid, factor):
        self.speed = factor

    def state(self, _mid):
        return {
            "museum_id": 1,
            "museum_name": "Музей №1",
            "current_budget": 8400,
            "rating": 34,
            "status": "Активен",
            "difficulty": "Лёгкая",
            "halls_count": 2,
            "displayed_count": 6,
            "in_storage": 2,
            "employees_count": 1,
            "salary_fund": 1000,
        }

    def halls(self, _mid):
        return [
            {
                "hall_id": 1, "hall_name": "Стартовый зал", "hall_size": "Стартовый",
                "capacity": 10, "is_open": 1, "theme_id": None, "theme": "без темы",
                "occupied": 4, "employees_count": 0, "can_hire": 0,
            },
            {
                "hall_id": 2, "hall_name": "Зал 2", "hall_size": "Средний",
                "capacity": 20, "is_open": 1, "theme_id": 1, "theme": "История",
                "occupied": 5, "employees_count": 1, "can_hire": 1,
            },
            {
                "hall_id": 3, "hall_name": "Зал 3", "hall_size": "Маленький",
                "capacity": 10, "is_open": 1, "theme_id": None, "theme": "без темы",
                "occupied": 0, "employees_count": 0, "can_hire": 0,
            },
        ]

    def exhibits(self, _mid):
        out = []
        for i in range(9):
            out.append(
                {
                    "museum_exhibit_id": i + 1,
                    "hall_id": 1 if i < 4 else 2,
                    "exhibit_name": f"Экспонат {i + 1}",
                    "exhibit_type": "Картина",
                    "star_rating": 3 + i % 3,
                    "attractiveness": 80 + i,
                    "theme": "История",
                    "theme_id": 1,
                }
            )
        return out

    def storage(self, _mid):
        return [
            {
                "museum_exhibit_id": 90, "exhibit_name": "Мозаичный пол",
                "exhibit_type": "Артефакт", "star_rating": 3, "attractiveness": 95,
                "purchase_price": 1300, "sale_price": 780, "theme": "без темы",
            }
        ]

    def sellable(self, _mid):
        return [
            {
                "museum_exhibit_id": 90, "exhibit_name": "Мозаичный пол",
                "exhibit_type": "Артефакт", "star_rating": 3, "attractiveness": 95,
                "purchase_price": 1300, "sale_price": 780, "theme": "без темы",
                "place": "склад", "displayed": 0,
            },
            {
                "museum_exhibit_id": 3, "exhibit_name": "Экспонат 3",
                "exhibit_type": "Картина", "star_rating": 5, "attractiveness": 120,
                "purchase_price": 4000, "sale_price": 2400, "theme": "История",
                "place": "Зал 2", "displayed": 1,
            },
        ]

    def preferences(self):
        return [
            {"category": "Обычный", "theme": "Искусство", "weight": 3, "description": "",
             "ticket_price": 300, "audioguide_price": 150},
        ]

    def visitor_mix(self, _mid):
        return [
            {"category": "Льготник", "weight": 18.0, "share_percent": 45.0},
            {"category": "Обычный", "weight": 13.0, "share_percent": 32.5},
            {"category": "Учащийся", "weight": 9.0, "share_percent": 22.5},
        ]

    def catalog(self):
        return [
            {
                "catalog_exhibit_id": 1, "exhibit_name": "Берестяная грамота",
                "exhibit_type": "Артефакт", "star_rating": 3, "price": 900,
                "attractiveness": 70, "theme": "История", "description": "Письмо XII века",
            }
        ]

    def themes(self):
        return [{"theme_id": 1, "theme_name": "История", "description": ""}]

    def positions(self):
        return [
            {"position_id": 1, "position_name": "Смотритель",
             "base_salary": 1000, "description": ""}
        ]

    def improvement_types(self):
        return [
            {"improvement_type_id": 1, "improvement_name": "Кондиционер", "price": 1500,
             "effect_factor": 0.15, "effect_description": "+15% посетителей"}
        ]

    def difficulties(self):
        return [
            {"difficulty_id": 1, "difficulty_name": "Лёгкая",
             "start_budget": 10000, "description": ""}
        ]

    def employees(self, _mid):
        return [
            {"employee_id": 1, "last_name": "Орлов", "first_name": "Пётр", "middle_name": None,
             "salary": 1000, "position_name": "Смотритель", "hall_id": None,
             "hall": "кадровый резерв", "status": "В резерве"}
        ]

    def hall_improvements(self, _mid):
        return [
            {"hall_improvement_id": 1, "hall_id": 2, "hall_name": "Зал 2",
             "improvement_name": "Аудиогид", "effect_factor": 0.2,
             "status": "Активно", "purchased_at": None}
        ]

    def events(self, _mid, limit=12):
        return [
            {"event_name": "Приезд школьной экскурсии", "event_context": "День",
             "description": "Музей посетили 14 учащихся", "budget_effect": 2100,
             "rating_effect": 1, "event_date": None},
            {"event_name": "Кража экспоната", "event_context": "Ночь",
             "description": "Похищен экспонат «Монетный клад»", "budget_effect": -1000,
             "rating_effect": -5, "event_date": None},
        ]

    def actions(self, _mid, limit=12):
        return [
            {"action_code": "BUY_EXHIBIT", "result": "Успех",
             "description": "Действие выполнено", "logged_at": None},
            {"action_code": "OPEN_HALL", "result": "Ошибка",
             "description": "Недостаточно средств", "logged_at": None},
        ]

    def day_report(self, _sid, limit=10):
        return [
            {"day_number": 3, "visitors_count": 41, "income": 9800, "rating": 34,
             "status": "Закрыт", "day_finished_at": None},
            {"day_number": 4, "visitors_count": 0, "income": 0, "rating": None,
             "status": "Открыт", "day_finished_at": None},
        ]

    def statistics(self, _mid):
        return {"total_days": 9, "total_visitors": 214, "total_income": 41200,
                "total_expense": 46800, "total_events": 6, "stolen": 2}

    def clock(self, _sid):
        return {"day_number": 4, "game_time": "13:40", "day_share": 0.46,
                "night": 0, "game_day_id": 12, "speed_factor": self.speed}

    def current_visitors(self, *_):
        return 23

    def info_text(self):
        return ["СПРАВКА", "строка 1", "строка 2"]

    def museum_state_text(self, _mid):
        return ["МУЗЕЙ: Музей №1", "Бюджет: 8400"]

    def statistics_text(self, _mid):
        return ["Сыграно дней: 4"]

def main():
    db_module.Database = FakeDB
    import main as client  # noqa: PLC0415

    game = client.Game()
    assert game.mode == "connect", "первым должен открываться экран подключения"
    game.draw_connect()          # просто проверяем, что он рисуется

    # Дальше делаем вид, что подключение уже прошло, и работаем
    # с заглушкой вместо настоящей базы.
    client.Database = FakeDB
    game.db = FakeDB()
    game.worker = client.Worker(game.db)
    game.worker.start()
    game.mode = "login"
    assert game.mode == "login", game.status_line

    # Пробуем войти
    game.login_input.value = "test"
    game.pass_input.value = "test"
    game.do_login()
    _pump(game, 40)
    assert game.mode == "menu", f"ожидалось меню, получено {game.mode}"
    assert game.museums, "список музеев пуст"

    # Начинаем партию
    game.play(game.museums[0])
    _pump(game, 40)
    assert game.mode == "game", f"ожидался игровой экран, получено {game.mode}"

    # Открываем по очереди все действия и смотрим на их окошки
    checks = [
        ("act_open_hall", "Размер нового зала"),
        ("act_buy", "Каталог экспонатов"),
        ("act_place", "Склад: что выставить"),
        ("act_remove", "Убрать экспонат на склад"),
        ("act_sell", "Продажа экспоната"),
        ("act_hire", "Куда нанять сотрудника"),
        ("act_assign", "Кадровый резерв"),
        ("act_improve", "Зал для улучшения"),
        ("act_theme", "Зал для смены темы"),
    ]
    for name, title in checks:
        getattr(game, name)()
        _pump(game, 12)
        assert game.dialog is not None, f"{name}: диалог не открылся"
        assert game.dialog.title == title, f"{name}: заголовок «{game.dialog.title}»"
        # проходим всю цепочку окошек, везде выбирая первый пункт
        for _step in range(3):
            dialog = game.dialog
            if dialog is None or not getattr(dialog, "items", None):
                break
            game.dialog = None
            dialog.on_pick(dialog.items[0][1])
            _pump(game, 15)
        game.dialog = None

    # Текстовые окна, которые печатает сам пакет
    for name in ("act_state_text", "act_stats_text", "act_info"):
        getattr(game, name)()
        _pump(game, 15)
        assert isinstance(game.dialog, client.TextDialog), f"{name}: нет текстового окна"
        game.dialog = None

    # После паузы должно вернуть в меню
    game.act_pause()
    _pump(game, 30)
    assert game.mode == "menu", f"после паузы ожидалось меню, получено {game.mode}"

    queued = {code for code, _ in game.db.queued}
    print("поставлено в очередь:", sorted(queued))
    assert "OPEN_HALL" in queued and "BUY_EXHIBIT" in queued

    game.worker.stop()
    pygame.quit()
    print("SMOKE UI OK — все экраны отрисованы, диалоги работают")

def _pump(game, frames):
    """Крутит несколько кадров: забрать ответы из потока и перерисовать."""
    for _ in range(frames):
        pygame.event.pump()
        game.drain_results()
        if game.mode == "login":
            game.draw_login()
        elif game.mode == "menu":
            game.draw_menu()
        elif game.mode == "game":
            game.draw_game(0.016)
        elif game.mode == "defeat":
            game.draw_defeat()
        if game.dialog:
            game.dialog.draw(game.screen)
        game.toast.draw(game.screen)
        pygame.display.flip()
        pygame.time.wait(10)

if __name__ == "__main__":
    main()
