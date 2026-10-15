-- Пакет museum_curator. Тут только объявления: что умеет база.
-- Реализация лежит в 05_package_body.sql.
-- Всё, что объявлено здесь, может вызвать клиент. Что не объявлено —
-- видно только внутри тела пакета.

CREATE OR REPLACE PACKAGE museum_curator AS

  -- Числа, на которых держится баланс игры. Собрал их тут, чтобы
  -- менять сложность в одном месте, а не искать по всему коду.
  c_day_start_min      CONSTANT NUMBER := 9  * 60;   -- день начинается в 09:00
  c_day_end_min        CONSTANT NUMBER := 19 * 60;   -- и заканчивается в 19:00
  c_game_min_per_sec   CONSTANT NUMBER := 1;         -- секунда реального времени = минута игрового
  c_night_real_sec     CONSTANT NUMBER := 20;        -- ночь длится 20 секунд
  c_speed_max          CONSTANT NUMBER := 8;         -- быстрее чем в 8 раз нельзя
  c_salary_base        CONSTANT NUMBER := 1000;      -- сколько стоит первый сотрудник
  c_salary_growth      CONSTANT NUMBER := 1.5;       -- каждый следующий дороже в полтора раза
  c_salary_period      CONSTANT NUMBER := 7;         -- зарплату платим раз в 7 дней
  c_sell_ratio         CONSTANT NUMBER := 0.6;       -- продаём за 60% от того, что отдали
  c_bankrupt_limit     CONSTANT NUMBER := 0;         -- ушли в минус — проиграли
  c_exhibits_per_emp   CONSTANT NUMBER := 5;         -- один сотрудник на 5 выставленных экспонатов
  c_offline_interval   CONSTANT NUMBER := 5;         -- пока игрока нет, каждые 5 минут что-то происходит
  c_offline_max        CONSTANT NUMBER := 12;        -- но не больше 12 раз, иначе за неделю всё разграбят

  -- Шансы событий. Планировщик срабатывает раз в секунду, а день идёт
  -- 600 секунд. Если поставить шанс побольше, кражи пойдут каждый день
  -- и играть станет невозможно. При 0.005 выходит около трёх проверок
  -- за день, это нормально.
  c_event_chance_day   CONSTANT NUMBER := 0.005;     -- шанс события днём
  c_event_chance_night CONSTANT NUMBER := 0.02;      -- ночью шанс выше, но и ночь короткая
  c_steal_day          CONSTANT NUMBER := 0.08;      -- шанс кражи днём
  c_steal_night        CONSTANT NUMBER := 0.15;      -- ночью крадут чаще
  c_steal_offline      CONSTANT NUMBER := 0.20;      -- а без игрока вообще часто
  c_steal_drop_boost   CONSTANT NUMBER := 2.5;       -- если рейтинг упал, красть будут в 2.5 раза чаще
  c_rating_drop_limit  CONSTANT NUMBER := 0.30;      -- считаем падением, если минус 30% за неделю
  c_guard_shield       CONSTANT NUMBER := 0.85;      -- каждый смотритель в зале снижает риск на 15%
  c_donation_visitors  CONSTANT NUMBER := 100;       -- если за неделю пришло больше 100 человек
  c_donation_bonus     CONSTANT NUMBER := 500;       -- то меценат даёт 500
  c_excursion_chance   CONSTANT NUMBER := 0.25;      -- шанс что приедут школьники
  c_game_week          CONSTANT NUMBER := 7;         -- в неделе 7 игровых дней
  c_game_month         CONSTANT NUMBER := 30;        -- в месяце 30
  c_visitor_scale      CONSTANT NUMBER := 1;         -- если поставить 0.5, посетителей станет вдвое меньше
  c_neutral_weight     CONSTANT NUMBER := 1.5;       -- экспонат без темы нравится всем одинаково

  -- Свои ошибки. Их текст игрок видит на экране, поэтому пишу
  -- человеческими словами, а не «ошибка №4».
  e_login_exists    EXCEPTION;  PRAGMA EXCEPTION_INIT(e_login_exists,    -20001);
  e_museum_exists   EXCEPTION;  PRAGMA EXCEPTION_INIT(e_museum_exists,   -20002);
  e_not_found       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_not_found,       -20003);
  e_no_money        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_no_money,        -20004);
  e_wrong_state     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_wrong_state,     -20005);
  e_hall_full       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_hall_full,       -20006);
  e_not_allowed     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_not_allowed,     -20007);
  e_bankrupt        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_bankrupt,        -20008);

  -- Справка и вход в игру
  PROCEDURE info;
  PROCEDURE register_user(p_login VARCHAR2, p_password VARCHAR2);
  FUNCTION  login_user(p_login VARCHAR2, p_password VARCHAR2) RETURN NUMBER;

  -- Музей и партия
  PROCEDURE create_museum(p_user_id NUMBER, p_museum_name VARCHAR2, p_difficulty_id NUMBER);
  PROCEDURE delete_museum(p_museum_id NUMBER, p_reason VARCHAR2 DEFAULT NULL);
  PROCEDURE start_session(p_museum_id NUMBER);
  PROCEDURE resume_session(p_museum_id NUMBER);
  PROCEDURE pause_session(p_session_id NUMBER);
  PROCEDURE finish_session(p_session_id NUMBER);

  -- Очередь действий
  PROCEDURE enqueue_action(p_museum_id NUMBER, p_session_id NUMBER,
                           p_action_code VARCHAR2, p_parameters CLOB);
  PROCEDURE process_action_queue;
  PROCEDURE process_time_tick;

  -- Залы
  PROCEDURE open_hall(p_museum_id NUMBER, p_hall_name VARCHAR2,
                      p_theme_id NUMBER, p_size VARCHAR2);
  PROCEDURE change_hall_theme(p_hall_id NUMBER, p_theme_id NUMBER);

  -- Экспонаты
  PROCEDURE buy_exhibit(p_museum_id NUMBER, p_catalog_exhibit_id NUMBER);
  PROCEDURE sell_exhibit(p_museum_exhibit_id NUMBER);
  PROCEDURE place_exhibit(p_museum_exhibit_id NUMBER, p_hall_id NUMBER);
  PROCEDURE remove_exhibit_to_storage(p_museum_exhibit_id NUMBER);

  -- Сотрудники и улучшения
  FUNCTION  can_hire_employee(p_hall_id NUMBER) RETURN NUMBER;
  PROCEDURE hire_employee(p_museum_id NUMBER, p_hall_id NUMBER DEFAULT NULL,
                          p_last_name VARCHAR2, p_first_name VARCHAR2,
                          p_middle_name VARCHAR2 DEFAULT NULL, p_position_id NUMBER);
  PROCEDURE assign_employee_to_hall(p_employee_id NUMBER, p_hall_id NUMBER);
  PROCEDURE buy_hall_improvement(p_museum_id NUMBER, p_hall_id NUMBER,
                                 p_improvement_type_id NUMBER);

  -- Игровое время и расчёты
  PROCEDURE start_game_day(p_session_id NUMBER);
  PROCEDURE finish_game_day(p_session_id NUMBER);
  FUNCTION  calculate_daily_visitors(p_museum_id NUMBER, p_game_day_id NUMBER) RETURN NUMBER;
  FUNCTION  calculate_daily_income(p_museum_id NUMBER, p_game_day_id NUMBER,
                                   p_visitors_count NUMBER) RETURN NUMBER;
  FUNCTION  calculate_rating(p_museum_id NUMBER) RETURN NUMBER;

  -- События, зарплата, проигрыш
  PROCEDURE event_handler(p_museum_id NUMBER, p_game_day_id NUMBER DEFAULT NULL,
                          p_context VARCHAR2 DEFAULT 'День');
  PROCEDURE process_offline_events(p_museum_id NUMBER);
  PROCEDURE process_week_salary(p_museum_id NUMBER, p_game_day_id NUMBER, p_day_number NUMBER);
  PROCEDURE check_bankruptcy(p_museum_id NUMBER);

  -- Записи в журналы
  PROCEDURE log_financial_operation(p_museum_id NUMBER, p_game_day_id NUMBER,
                                    p_operation_type VARCHAR2, p_amount NUMBER,
                                    p_description VARCHAR2 DEFAULT NULL);
  PROCEDURE log_action(p_action_id NUMBER, p_result VARCHAR2,
                       p_description VARCHAR2 DEFAULT NULL);

  -- Текстовые отчёты. Печатают в DBMS_OUTPUT, игра их показывает окошком.
  PROCEDURE show_museum_state(p_museum_id NUMBER);
  PROCEDURE show_statistics(p_museum_id NUMBER);

  -- Функции, которые отдают данные игре. Каждая возвращает курсор,
  -- то есть готовую таблицу строк. Игра её просто рисует и ничего
  -- сама не считает.
  FUNCTION get_museum_state(p_museum_id NUMBER)   RETURN SYS_REFCURSOR;  -- одна строка со сводкой по музею
  FUNCTION get_halls(p_museum_id NUMBER)          RETURN SYS_REFCURSOR;
  FUNCTION get_hall_exhibits(p_museum_id NUMBER)  RETURN SYS_REFCURSOR;  -- что стоит в залах
  FUNCTION get_storage(p_museum_id NUMBER)        RETURN SYS_REFCURSOR;  -- что лежит на складе
  FUNCTION get_sellable(p_museum_id NUMBER)       RETURN SYS_REFCURSOR;  -- что лежит на складе + залы
  FUNCTION get_catalog                             RETURN SYS_REFCURSOR;
  FUNCTION get_themes                              RETURN SYS_REFCURSOR;
  FUNCTION get_preferences                         RETURN SYS_REFCURSOR;  -- кому что нравится
  FUNCTION get_visitor_mix(p_museum_id NUMBER)    RETURN SYS_REFCURSOR;  -- кто к нам ходит
  FUNCTION get_positions                           RETURN SYS_REFCURSOR;
  FUNCTION get_improvement_types                   RETURN SYS_REFCURSOR;
  FUNCTION get_difficulties                        RETURN SYS_REFCURSOR;
  FUNCTION get_employees(p_museum_id NUMBER)      RETURN SYS_REFCURSOR;
  FUNCTION get_hall_improvements(p_museum_id NUMBER) RETURN SYS_REFCURSOR;
  FUNCTION get_recent_events(p_museum_id NUMBER, p_limit NUMBER DEFAULT 12) RETURN SYS_REFCURSOR;
  FUNCTION get_recent_actions(p_museum_id NUMBER, p_limit NUMBER DEFAULT 12) RETURN SYS_REFCURSOR;
  FUNCTION get_day_report(p_session_id NUMBER, p_limit NUMBER DEFAULT 10)   RETURN SYS_REFCURSOR;
  FUNCTION get_statistics(p_museum_id NUMBER)     RETURN SYS_REFCURSOR;
  FUNCTION get_user_museums(p_user_id NUMBER)     RETURN SYS_REFCURSOR;

  -- Часы: какой день, сколько времени, ночь или нет.
  FUNCTION get_clock(p_session_id NUMBER) RETURN SYS_REFCURSOR;

  -- Примерно сколько народу уже пришло. Нужно только чтобы рисовать
  -- точки на плане, на доход это не влияет.
  FUNCTION estimate_current_visitors(p_museum_id NUMBER, p_session_id NUMBER) RETURN NUMBER;

  -- Какая партия идёт и какой день открыт
  FUNCTION get_active_session(p_museum_id NUMBER) RETURN NUMBER;
  FUNCTION get_open_day(p_session_id NUMBER)     RETURN NUMBER;

  -- Ускорение времени: 1, 2, 4 или 8. Когда меняем, пересчитываем
  -- начало дня, иначе часы прыгнут вперёд и день сразу кончится.
  PROCEDURE set_game_speed(p_session_id NUMBER, p_factor NUMBER);
  FUNCTION  get_game_speed(p_session_id NUMBER) RETURN NUMBER;

END museum_curator;
/
SHOW ERRORS
