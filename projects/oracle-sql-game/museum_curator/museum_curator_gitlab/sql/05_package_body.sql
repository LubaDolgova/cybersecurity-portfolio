-- Тело пакета museum_curator. Тут вся логика игры.
-- Питон только рисует картинку и ничего сам не считает.

CREATE OR REPLACE PACKAGE BODY museum_curator AS

  -- Свои типы и переменные. Снаружи пакета их не видно.
  TYPE t_num_by_str IS TABLE OF NUMBER INDEX BY VARCHAR2(100);
  g_status_cache t_num_by_str;

  TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE t_str_tab IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;

  -- Одна категория посетителей: цены и посчитанный вес
  TYPE t_cat_rec IS RECORD (
    id     NUMBER,
    name   VARCHAR2(50),
    ticket NUMBER,
    audio  NUMBER,
    base   NUMBER,
    weight NUMBER,
    qty    NUMBER
  );
  TYPE t_cat_tab IS TABLE OF t_cat_rec INDEX BY PLS_INTEGER;

  -- Сюда складываю id всех статусов. Заполняются один раз, в самом
  -- конце файла есть блок, который это делает.
  -- Почему не функция: функцию отсюда нельзя вызвать внутри SELECT,
  -- Oracle ругается PLS-00231. А переменную можно.
  g_st_mus_act    NUMBER;  g_st_mus_bank   NUMBER;  g_st_mus_arch  NUMBER;
  g_st_ses_act    NUMBER;  g_st_ses_pause  NUMBER;  g_st_ses_fin   NUMBER;
  g_st_ses_lost   NUMBER;
  g_st_day_open   NUMBER;  g_st_day_closed NUMBER;
  g_st_ex_store   NUMBER;  g_st_ex_show    NUMBER;  g_st_ex_stolen NUMBER;
  g_st_ex_sold    NUMBER;
  g_st_emp_res    NUMBER;  g_st_emp_asg    NUMBER;  g_st_emp_fired NUMBER;
  g_st_imp_act    NUMBER;  g_st_imp_off    NUMBER;  g_st_imp_brk   NUMBER;
  g_st_act_wait   NUMBER;  g_st_act_run    NUMBER;  g_st_act_done  NUMBER;
  g_st_act_err    NUMBER;

  -- Находит id статуса по типу и названию. Второй раз уже не ищет,
  -- берёт из памяти.
  FUNCTION f_status(p_type VARCHAR2, p_name VARCHAR2) RETURN NUMBER IS
    v_key VARCHAR2(100) := p_type || '#' || p_name;
    v_id  NUMBER;
  BEGIN
    IF g_status_cache.EXISTS(v_key) THEN
      RETURN g_status_cache(v_key);
    END IF;
    SELECT status_id INTO v_id
      FROM statuses
     WHERE object_type = p_type AND status_name = p_name;
    g_status_cache(v_key) := v_id;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20003, 'Не найден статус: ' || v_key);
  END f_status;

  -- Достаёт параметр из строки вида 'HALL=3;THEME=1'
  FUNCTION f_param(p_params CLOB, p_key VARCHAR2) RETURN VARCHAR2 IS
    v_src VARCHAR2(4000) := ';' || TO_CHAR(SUBSTR(NVL(p_params, ' '), 1, 3900)) || ';';
    v_pos PLS_INTEGER;
    v_end PLS_INTEGER;
  BEGIN
    v_pos := INSTR(v_src, ';' || p_key || '=');
    IF v_pos = 0 THEN
      RETURN NULL;
    END IF;
    v_pos := v_pos + LENGTH(p_key) + 2;
    v_end := INSTR(v_src, ';', v_pos);
    IF v_end = 0 THEN
      RETURN NULL;
    END IF;
    RETURN SUBSTR(v_src, v_pos, v_end - v_pos);
  END f_param;

  FUNCTION f_param_num(p_params CLOB, p_key VARCHAR2) RETURN NUMBER IS
    v_txt VARCHAR2(4000) := f_param(p_params, p_key);
  BEGIN
    IF v_txt IS NULL OR TRIM(v_txt) IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TO_NUMBER(TRIM(v_txt));
  EXCEPTION
    WHEN VALUE_ERROR THEN RETURN NULL;
  END f_param_num;

  -- Мелкие функции, которые нужны везде
  FUNCTION get_active_session(p_museum_id NUMBER) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT MAX(session_id) INTO v_id
      FROM game_sessions
     WHERE museum_id = p_museum_id
       AND status_id IN (g_st_ses_act, g_st_ses_pause);
    RETURN v_id;
  END get_active_session;

  FUNCTION get_open_day(p_session_id NUMBER) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT MAX(game_day_id) INTO v_id
      FROM game_days
     WHERE session_id = p_session_id
       AND status_id = g_st_day_open;
    RETURN v_id;
  END get_open_day;

  FUNCTION f_last_closed_day(p_session_id NUMBER) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT MAX(game_day_id) INTO v_id
      FROM game_days
     WHERE session_id = p_session_id
       AND status_id = g_st_day_closed;
    RETURN v_id;
  END f_last_closed_day;

  -- К какому дню записать трату. Если день открыт — к нему,
  -- иначе к последнему закрытому, а если дней ещё нет — ни к какому.
  FUNCTION f_billing_day(p_museum_id NUMBER) RETURN NUMBER IS
    v_sess NUMBER := get_active_session(p_museum_id);
    v_day  NUMBER;
  BEGIN
    IF v_sess IS NULL THEN
      RETURN NULL;
    END IF;
    v_day := get_open_day(v_sess);
    IF v_day IS NULL THEN
      v_day := f_last_closed_day(v_sess);
    END IF;
    RETURN v_day;
  END f_billing_day;

  -- Какой сейчас игровой день по счёту. Все «раз в неделю» и «раз в
  -- месяц» считаю по нему, а не по настоящей дате. Партия идёт минуты,
  -- так что от настоящей даты толку нет.
  FUNCTION f_day_number(p_museum_id NUMBER) RETURN NUMBER IS
    v_sess NUMBER := get_active_session(p_museum_id);
    v_num  NUMBER;
  BEGIN
    IF v_sess IS NULL THEN
      RETURN 0;
    END IF;
    SELECT NVL(MAX(day_number), 0) INTO v_num
      FROM game_days WHERE session_id = v_sess;
    RETURN v_num;
  END f_day_number;

  -- Сколько народу пришло за последние несколько игровых дней
  FUNCTION f_visitors_last_days(p_museum_id NUMBER, p_days NUMBER) RETURN NUMBER IS
    v_today NUMBER := f_day_number(p_museum_id);
    v_sum   NUMBER;
  BEGIN
    SELECT NVL(SUM(d.visitors_per_day), 0) INTO v_sum
      FROM game_days d
      JOIN game_sessions s ON s.session_id = d.session_id
     WHERE s.museum_id = p_museum_id
       AND d.day_number > v_today - p_days;
    RETURN v_sum;
  END f_visitors_last_days;

  -- Сколько раз это событие уже было за последние дни
  FUNCTION f_event_count(p_museum_id NUMBER, p_name VARCHAR2, p_days NUMBER) RETURN NUMBER IS
    v_today NUMBER := f_day_number(p_museum_id);
    v_cnt   NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt
      FROM game_events
     WHERE museum_id = p_museum_id
       AND event_name = p_name
       AND NVL(day_number, 0) > v_today - p_days;
    RETURN v_cnt;
  END f_event_count;

  -- Какой был рейтинг неделю назад. Если истории мало — вернёт пусто.
  FUNCTION f_rating_week_ago(p_museum_id NUMBER) RETURN NUMBER IS
    v_today  NUMBER := f_day_number(p_museum_id);
    v_rating NUMBER;
  BEGIN
    SELECT rating_at_day_end INTO v_rating
      FROM (SELECT d.rating_at_day_end
              FROM game_days d
              JOIN game_sessions s ON s.session_id = d.session_id
             WHERE s.museum_id = p_museum_id
               AND d.day_number <= v_today - c_game_week
               AND d.rating_at_day_end IS NOT NULL
             ORDER BY d.day_number DESC)
     WHERE ROWNUM = 1;
    RETURN v_rating;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
  END f_rating_week_ago;

  -- Проверяет, что с музеем всё в порядке и можно что-то делать
  PROCEDURE p_check_museum(p_museum_id NUMBER, p_spending BOOLEAN DEFAULT TRUE) IS
    v_active NUMBER;
    v_status NUMBER;
  BEGIN
    SELECT is_active, status_id INTO v_active, v_status
      FROM museums WHERE museum_id = p_museum_id;

    IF v_active = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 'Музей архивирован и недоступен для действий');
    END IF;
    IF p_spending AND v_status = g_st_mus_bank THEN
      RAISE_APPLICATION_ERROR(-20008, 'Музей банкрот: расходные действия заблокированы');
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20003, 'Музей не найден: ' || p_museum_id);
  END p_check_museum;

  -- Списать деньги. Если передать минус — наоборот, начислит.
  PROCEDURE p_charge(p_museum_id NUMBER, p_amount NUMBER) IS
    v_budget NUMBER;
  BEGIN
    SELECT current_budget INTO v_budget FROM museums WHERE museum_id = p_museum_id FOR UPDATE;
    IF p_amount > 0 AND v_budget < p_amount THEN
      RAISE_APPLICATION_ERROR(-20004,
        'Недостаточно средств: нужно ' || TO_CHAR(p_amount) || ', в кассе ' || TO_CHAR(v_budget));
    END IF;
    UPDATE museums
       SET current_budget = current_budget - p_amount,
           last_activity_at = SYSDATE
     WHERE museum_id = p_museum_id;
  END p_charge;

  -- Не стоит ли такое же задание в очереди. Чтобы не дублировать.
  FUNCTION f_has_pending(p_session_id NUMBER, p_code VARCHAR2) RETURN BOOLEAN IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt
      FROM action_queue
     WHERE session_id = p_session_id
       AND action_code = p_code
       AND status_id IN (g_st_act_wait, g_st_act_run);
    RETURN v_cnt > 0;
  END f_has_pending;

  -- Сколько игровых минут прошло с начала дня
  FUNCTION f_day_minutes(p_game_day_id NUMBER) RETURN NUMBER IS
    v_start DATE;
    v_speed NUMBER;
  BEGIN
    -- Скорость лежит в сессии. Одна секунда = столько игровых минут,
    -- какой стоит множитель.
    SELECT d.day_started_at, s.speed_factor
      INTO v_start, v_speed
      FROM game_days d
      JOIN game_sessions s ON s.session_id = d.session_id
     WHERE d.game_day_id = p_game_day_id;

    RETURN c_day_start_min
           + (SYSDATE - v_start) * 86400 * c_game_min_per_sec * NVL(v_speed, 1);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN c_day_start_min;
  END f_day_minutes;

  -- Скорость отдельно. Ночью дня нет, а скорость знать надо.
  FUNCTION f_speed(p_session_id NUMBER) RETURN NUMBER IS
    v_speed NUMBER;
  BEGIN
    SELECT speed_factor INTO v_speed
      FROM game_sessions WHERE session_id = p_session_id;
    RETURN NVL(v_speed, 1);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 1;
  END f_speed;

  -- Справка по игре
  PROCEDURE info IS
    PROCEDURE l(p VARCHAR2) IS BEGIN DBMS_OUTPUT.PUT_LINE(p); END;
  BEGIN
    l('==========================================================');
    l('              ИГРА «КУРАТОР МУЗЕЯ»                         ');
    l('==========================================================');
    l('ЦЕЛЬ СЕССИИ');
    l('  Развить музей: открывать залы, покупать экспонаты,');
    l('  привлекать посетителей и не допустить банкротства.');
    l('');
    l('РАЗВИТИЕ МУЗЕЯ');
    l('  1. Купить экспонат из каталога -> он попадает на склад.');
    l('  2. Разместить экспонат в зале -> он начинает работать.');
    l('  3. Чем выше суммарная привлекательность и рейтинг,');
    l('     тем больше посетителей и дохода.');
    l('  4. Залы: Маленький 1000/10 мест, Средний 2000/20,');
    l('     Большой 5000/30. Стартовый зал даётся бесплатно.');
    l('');
    l('РЕЙТИНГ');
    l('  рейтинг = залы*10 + пятизвёздочные*5 + улучшения*2');
    l('            + тематический бонус - штрафы событий.');
    l('  Высокий рейтинг = больше посетителей.');
    l('');
    l('ИГРОВОЙ ДЕНЬ');
    l('  Время 09:00-19:00 — игровое и не совпадает с реальным:');
    l('  одна реальная секунда равна одной игровой минуте.');
    l('  В конце дня считаются посетители, доход и новый рейтинг.');
    l('  Каждые 7 игровых дней выплачивается зарплата.');
    l('');
    l('ДЕЙСТВИЯ КУРАТОРА');
    l('  open_hall                 — открыть зал');
    l('  change_hall_theme         — сменить тему зала');
    l('  buy_exhibit / sell_exhibit — купить / продать экспонат');
    l('  place_exhibit             — выставить экспонат в зал');
    l('  remove_exhibit_to_storage — убрать экспонат на склад');
    l('  hire_employee             — нанять сотрудника');
    l('  assign_employee_to_hall   — назначить сотрудника в зал');
    l('  buy_hall_improvement      — купить улучшение для зала');
    l('  show_museum_state         — состояние музея');
    l('  show_statistics           — итоговая статистика');
    l('  pause_session / finish_session — выйти / завершить партию');
    l('');
    l('СЛУЧАЙНЫЕ СОБЫТИЯ');
    l('  «Пожертвование мецената» — бонус к бюджету;');
    l('  «Кража экспоната»        — потеря экспоната, если нет');
    l('                             системы безопасности;');
    l('  «Приезд школьной экскурсии» — 10-20 учащихся с билетами.');
    l('  События возможны днём, ночью и во время отсутствия игрока.');
    l('');
    l('ДОХОДЫ И ПОСЕТИТЕЛИ');
    l('  посетители = (рейтинг/100)*(залы*10) + привлекательность/100,');
    l('  с поправкой на активные улучшения.');
    l('  Доход = билеты + аудиогиды.');
    l('  Расходы — зарплата, покупки, последствия событий.');
    l('');
    l('ТИПЫ ПОСЕТИТЕЛЕЙ И ТЕМЫ');
    l('  Состав публики зависит от того, какие темы выставлены.');
    l('  Чем больше экспонатов «своей» темы, тем большую долю');
    l('  посетителей составит категория. Пока экспонатов нет,');
    l('  действует базовое распределение 50 / 30 / 20.');
    FOR p IN (SELECT kp.category_name AS cat, t.theme_name AS theme, p.weight
                FROM preferences p
                JOIN visitor_categories kp
                  ON kp.visitor_category_id = p.visitor_category_id
                JOIN themes t ON t.theme_id = p.theme_id
               ORDER BY kp.ticket_price DESC, p.weight DESC)
    LOOP
      l('    ' || RPAD(p.cat, 10) || RPAD(p.theme, 12) || 'вес ' || p.weight);
    END LOOP;
    l('');
    l('ЗАВЕРШЕНИЕ');
    l('  Обычный выход приостанавливает сессию, повторный вход');
    l('  продолжает её с того же места. Статус «Завершена»');
    l('  ставится только при явном завершении партии,');
    l('  «Проиграна» — при банкротстве.');
    l('==========================================================');
  END info;

  -- Регистрация и вход
  PROCEDURE register_user(p_login VARCHAR2, p_password VARCHAR2) IS
    v_cnt NUMBER;
  BEGIN
    IF p_login IS NULL OR LENGTH(TRIM(p_login)) < 3 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Логин должен содержать не менее 3 символов');
    END IF;
    IF p_password IS NULL OR LENGTH(p_password) < 3 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Пароль должен содержать не менее 3 символов');
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM users WHERE login = TRIM(p_login);
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Логин уже занят: ' || p_login);
    END IF;

    INSERT INTO users (user_id, login, password_hash, registration_date)
    VALUES (seq_users.NEXTVAL, TRIM(p_login),
            RAWTOHEX(STANDARD_HASH(p_password, 'SHA256')), SYSDATE);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END register_user;

  FUNCTION login_user(p_login VARCHAR2, p_password VARCHAR2) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT user_id INTO v_id
      FROM users
     WHERE login = TRIM(p_login)
       AND password_hash = RAWTOHEX(STANDARD_HASH(p_password, 'SHA256'));
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
  END login_user;

  -- Создание и удаление музея
  PROCEDURE create_museum(p_user_id NUMBER, p_museum_name VARCHAR2, p_difficulty_id NUMBER) IS
    v_cnt    NUMBER;
    v_budget NUMBER;
    v_museum NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt FROM users WHERE user_id = p_user_id;
    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Пользователь не найден');
    END IF;

    SELECT COUNT(*) INTO v_cnt
      FROM museums
     WHERE user_id = p_user_id
       AND museum_name = TRIM(p_museum_name)
       AND is_active = 1;
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'У вас уже есть музей с таким названием');
    END IF;

    BEGIN
      SELECT start_budget INTO v_budget
        FROM difficulty_levels WHERE difficulty_id = p_difficulty_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20003, 'Указан несуществующий уровень сложности');
    END;

    v_museum := seq_museums.NEXTVAL;
    INSERT INTO museums (museum_id, user_id, difficulty_id, status_id,
                       museum_name, current_budget, rating,
                       created_at, last_activity_at, is_active)
    VALUES (v_museum, p_user_id, p_difficulty_id, g_st_mus_act,
            TRIM(p_museum_name), v_budget, 0, SYSDATE, SYSDATE, 1);

    -- Сразу даём один зал бесплатно, иначе играть не с чего
    INSERT INTO halls (hall_id, museum_id, theme_id, hall_name, hall_size,
                      capacity, opening_cost, is_open)
    VALUES (seq_halls.NEXTVAL, v_museum, NULL, 'Стартовый зал', 'Стартовый', 10, 0, 1);

    COMMIT;

    DECLARE v_r NUMBER; BEGIN v_r := calculate_rating(v_museum); COMMIT; END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END create_museum;

  PROCEDURE delete_museum(p_museum_id NUMBER, p_reason VARCHAR2 DEFAULT NULL) IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt FROM museums WHERE museum_id = p_museum_id AND is_active = 1;
    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Активный музей не найден');
    END IF;

    -- Если партия шла — закрываем её
    UPDATE game_sessions
       SET status_id = g_st_ses_fin, finished_at = SYSDATE
     WHERE museum_id = p_museum_id
       AND status_id IN (g_st_ses_act, g_st_ses_pause);

    UPDATE museums
       SET is_active = 0,
           status_id = g_st_mus_arch,
           last_activity_at = SYSDATE
     WHERE museum_id = p_museum_id;

    INSERT INTO museum_archive (archive_id, museum_id, archived_at, reason)
    VALUES (seq_museum_archive.NEXTVAL, p_museum_id, SYSDATE,
            NVL(p_reason, 'Мягкое удаление по решению игрока'));

    -- Насовсем ничего не удаляю, только помечаю
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END delete_museum;

  -- Партия: начать, продолжить, поставить на паузу
  PROCEDURE start_session(p_museum_id NUMBER) IS
    v_existing NUMBER;
  BEGIN
    p_check_museum(p_museum_id, FALSE);

    v_existing := get_active_session(p_museum_id);
    IF v_existing IS NOT NULL THEN
      -- Новую партию не создаём, продолжаем старую
      resume_session(p_museum_id);
      RETURN;
    END IF;

    INSERT INTO game_sessions (session_id, museum_id, started_at,
                                last_activity_at, finished_at, status_id)
    VALUES (seq_game_sessions.NEXTVAL, p_museum_id, SYSDATE, SYSDATE, NULL,
            g_st_ses_act);

    UPDATE museums SET last_activity_at = SYSDATE WHERE museum_id = p_museum_id;
    COMMIT;

    start_game_day(get_active_session(p_museum_id));
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END start_session;

  PROCEDURE resume_session(p_museum_id NUMBER) IS
    v_sess  NUMBER := get_active_session(p_museum_id);
    v_day   NUMBER;
    v_pause NUMBER;
  BEGIN
    IF v_sess IS NULL THEN
      RAISE_APPLICATION_ERROR(-20003, 'Нет сохранённой сессии для этого музея');
    END IF;

    -- Игрок вышел посреди дня — сдвигаем начало дня вперёд на то время,
    -- пока его не было. Иначе он вернётся, а день уже как будто прошёл.
    v_day := get_open_day(v_sess);
    IF v_day IS NOT NULL THEN
      SELECT (SYSDATE - last_activity_at) INTO v_pause
        FROM game_sessions WHERE session_id = v_sess;

      IF v_pause > 0 THEN
        UPDATE game_days
           SET day_started_at = day_started_at + v_pause
         WHERE game_day_id = v_day;
      END IF;
    END IF;

    -- Разыгрываем то, что случилось без игрока
    process_offline_events(p_museum_id);

    UPDATE game_sessions
       SET status_id = g_st_ses_act,
           last_activity_at = SYSDATE
     WHERE session_id = v_sess;

    UPDATE museums SET last_activity_at = SYSDATE WHERE museum_id = p_museum_id;
    COMMIT;

    -- Дня нет — начинаем новый
    IF get_open_day(v_sess) IS NULL THEN
      start_game_day(v_sess);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END resume_session;

  PROCEDURE pause_session(p_session_id NUMBER) IS
  BEGIN
    UPDATE game_sessions
       SET status_id = g_st_ses_pause,
           last_activity_at = SYSDATE
     WHERE session_id = p_session_id
       AND status_id = g_st_ses_act;

    UPDATE museums m
       SET last_activity_at = SYSDATE
     WHERE museum_id = (SELECT museum_id FROM game_sessions WHERE session_id = p_session_id);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END pause_session;

  PROCEDURE finish_session(p_session_id NUMBER) IS
    v_open NUMBER := get_open_day(p_session_id);
  BEGIN
    IF v_open IS NOT NULL THEN
      finish_game_day(p_session_id);   -- принудительное закрытие дня
    END IF;

    UPDATE game_sessions
       SET finished_at = SYSDATE,
           last_activity_at = SYSDATE,
           status_id = g_st_ses_fin
     WHERE session_id = p_session_id
       AND status_id <> g_st_ses_lost;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END finish_session;

  -- Залы
  PROCEDURE open_hall(p_museum_id NUMBER, p_hall_name VARCHAR2,
                      p_theme_id NUMBER, p_size VARCHAR2) IS
    v_price NUMBER;
    v_cap   NUMBER;
    v_cnt   NUMBER;
    v_day   NUMBER;
  BEGIN
    p_check_museum(p_museum_id);

    SELECT COUNT(*) INTO v_cnt
      FROM halls WHERE museum_id = p_museum_id AND hall_name = TRIM(p_hall_name);
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Зал с таким названием уже есть в музее');
    END IF;

    CASE p_size
      WHEN 'Маленький' THEN v_price := 1000; v_cap := 10;
      WHEN 'Средний'   THEN v_price := 2000; v_cap := 20;
      WHEN 'Большой'   THEN v_price := 5000; v_cap := 30;
      ELSE RAISE_APPLICATION_ERROR(-20007, 'Недопустимый размер зала: ' || p_size);
    END CASE;

    IF p_theme_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_cnt FROM themes WHERE theme_id = p_theme_id;
      IF v_cnt = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Указана несуществующая тема');
      END IF;
    END IF;

    p_charge(p_museum_id, v_price);

    INSERT INTO halls (hall_id, museum_id, theme_id, hall_name, hall_size,
                      capacity, opening_cost, is_open)
    VALUES (seq_halls.NEXTVAL, p_museum_id, p_theme_id, TRIM(p_hall_name), p_size,
            v_cap, v_price, 1);

    v_day := f_billing_day(p_museum_id);
    log_financial_operation(p_museum_id, v_day, 'Расход', v_price,
                            'Открытие зала «' || TRIM(p_hall_name) || '» (' || p_size || ')');
    COMMIT;
  END open_hall;

  PROCEDURE change_hall_theme(p_hall_id NUMBER, p_theme_id NUMBER) IS
    v_museum NUMBER;
    v_cnt    NUMBER;
  BEGIN
    BEGIN
      SELECT museum_id INTO v_museum FROM halls WHERE hall_id = p_hall_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Зал не найден');
    END;
    p_check_museum(v_museum, FALSE);

    SELECT COUNT(*) INTO v_cnt
      FROM museum_exhibits
     WHERE hall_id = p_hall_id AND status_id = g_st_ex_show;
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20005,
        'Сначала уберите экспонаты на склад или продайте их: в зале ' || v_cnt || ' экспонат(ов)');
    END IF;

    IF p_theme_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_cnt FROM themes WHERE theme_id = p_theme_id;
      IF v_cnt = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Указана несуществующая тема');
      END IF;
    END IF;

    UPDATE halls SET theme_id = p_theme_id WHERE hall_id = p_hall_id;
    COMMIT;
  END change_hall_theme;

  -- Экспонаты: купить, выставить, убрать, продать
  PROCEDURE buy_exhibit(p_museum_id NUMBER, p_catalog_exhibit_id NUMBER) IS
    v_price NUMBER;
    v_name  VARCHAR2(100);
    v_day   NUMBER;
  BEGIN
    p_check_museum(p_museum_id);

    BEGIN
      SELECT price, exhibit_name INTO v_price, v_name
        FROM exhibit_catalog WHERE catalog_exhibit_id = p_catalog_exhibit_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20003, 'Экспонат каталога не найден');
    END;

    p_charge(p_museum_id, v_price);

    INSERT INTO museum_exhibits (museum_exhibit_id, museum_id, catalog_exhibit_id,
                                 hall_id, purchased_at, purchase_price, status_id)
    VALUES (seq_museum_exhibits.NEXTVAL, p_museum_id, p_catalog_exhibit_id,
            NULL, SYSDATE, v_price, g_st_ex_store);

    v_day := f_billing_day(p_museum_id);
    log_financial_operation(p_museum_id, v_day, 'Расход', v_price,
                            'Покупка экспоната «' || v_name || '»');
    COMMIT;
  END buy_exhibit;

  PROCEDURE sell_exhibit(p_museum_exhibit_id NUMBER) IS
    v_museum NUMBER;
    v_status NUMBER;
    v_price  NUMBER;
    v_name   VARCHAR2(100);
    v_sum    NUMBER;
    v_day    NUMBER;
  BEGIN
    BEGIN
      SELECT e.museum_id, e.status_id, e.purchase_price, k.exhibit_name
        INTO v_museum, v_status, v_price, v_name
        FROM museum_exhibits e
        JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
       WHERE e.museum_exhibit_id = p_museum_exhibit_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Экспонат музея не найден');
    END;

    p_check_museum(v_museum, FALSE);

    IF v_status IN (g_st_ex_stolen, g_st_ex_sold) THEN
      RAISE_APPLICATION_ERROR(-20005, 'Экспонат уже украден или продан');
    END IF;

    v_sum := ROUND(v_price * c_sell_ratio, 2);

    UPDATE museum_exhibits
       SET hall_id = NULL,
           status_id = g_st_ex_sold,
           sold_at = SYSDATE,
           sale_price = v_sum
     WHERE museum_exhibit_id = p_museum_exhibit_id;

    p_charge(v_museum, -v_sum);   -- отрицательное списание = зачисление

    v_day := f_billing_day(v_museum);
    log_financial_operation(v_museum, v_day, 'Доход', v_sum,
                            'Продажа экспоната «' || v_name || '»');
    COMMIT;
  END sell_exhibit;

  PROCEDURE place_exhibit(p_museum_exhibit_id NUMBER, p_hall_id NUMBER) IS
    v_museum   NUMBER;
    v_status   NUMBER;
    v_h_museum NUMBER;
    v_open     NUMBER;
    v_cap      NUMBER;
    v_cnt      NUMBER;
  BEGIN
    BEGIN
      SELECT museum_id, status_id INTO v_museum, v_status
        FROM museum_exhibits WHERE museum_exhibit_id = p_museum_exhibit_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Экспонат музея не найден');
    END;

    IF v_status <> g_st_ex_store THEN
      RAISE_APPLICATION_ERROR(-20005, 'Выставить можно только экспонат со склада');
    END IF;

    BEGIN
      SELECT museum_id, is_open, capacity INTO v_h_museum, v_open, v_cap
        FROM halls WHERE hall_id = p_hall_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Зал не найден');
    END;

    IF v_h_museum <> v_museum THEN
      RAISE_APPLICATION_ERROR(-20007, 'Зал принадлежит другому музею');
    END IF;
    IF v_open = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 'Зал закрыт');
    END IF;

    SELECT COUNT(*) INTO v_cnt
      FROM museum_exhibits
     WHERE hall_id = p_hall_id AND status_id = g_st_ex_show;

    IF v_cnt >= v_cap THEN
      RAISE_APPLICATION_ERROR(-20006,
        'Зал заполнен: ' || v_cnt || ' из ' || v_cap || ' мест занято');
    END IF;

    UPDATE museum_exhibits
       SET hall_id = p_hall_id, status_id = g_st_ex_show
     WHERE museum_exhibit_id = p_museum_exhibit_id;
    COMMIT;
  END place_exhibit;

  PROCEDURE remove_exhibit_to_storage(p_museum_exhibit_id NUMBER) IS
    v_status NUMBER;
    v_museum NUMBER;
  BEGIN
    BEGIN
      SELECT status_id, museum_id INTO v_status, v_museum
        FROM museum_exhibits WHERE museum_exhibit_id = p_museum_exhibit_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Экспонат музея не найден');
    END;

    IF v_status <> g_st_ex_show THEN
      RAISE_APPLICATION_ERROR(-20005, 'Убрать на склад можно только выставленный экспонат');
    END IF;

    UPDATE museum_exhibits
       SET hall_id = NULL, status_id = g_st_ex_store
     WHERE museum_exhibit_id = p_museum_exhibit_id;
    COMMIT;
  END remove_exhibit_to_storage;

  -- Сотрудники
  FUNCTION can_hire_employee(p_hall_id NUMBER) RETURN NUMBER IS
    v_exhibits  NUMBER;
    v_employees NUMBER;
    v_allowed   NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_exhibits
      FROM museum_exhibits
     WHERE hall_id = p_hall_id AND status_id = g_st_ex_show;

    SELECT COUNT(*) INTO v_employees
      FROM employees
     WHERE hall_id = p_hall_id AND is_active = 1;

    -- Один сотрудник на каждые 5 выставленных экспонатов.
    -- Сначала я проверял только кратность, и при 5 экспонатах можно было
    -- нанимать сколько угодно. Теперь сравниваю с тем, сколько уже есть.
    v_allowed := TRUNC(v_exhibits / c_exhibits_per_emp);

    IF v_allowed > v_employees THEN
      RETURN 1;
    END IF;
    RETURN 0;
  END can_hire_employee;

  PROCEDURE hire_employee(p_museum_id NUMBER, p_hall_id NUMBER DEFAULT NULL,
                          p_last_name VARCHAR2, p_first_name VARCHAR2,
                          p_middle_name VARCHAR2 DEFAULT NULL, p_position_id NUMBER) IS
    v_count  NUMBER;
    v_salary NUMBER;
    v_base   NUMBER;
    v_status NUMBER;
  BEGIN
    p_check_museum(p_museum_id);

    IF p_hall_id IS NOT NULL THEN
      IF can_hire_employee(p_hall_id) = 0 THEN
        RAISE_APPLICATION_ERROR(-20007,
          'Нанять сотрудника в этот зал нельзя: число выставленных экспонатов '
          || 'должно быть кратно ' || c_exhibits_per_emp || ' и больше 0');
      END IF;
    END IF;

    BEGIN
      SELECT base_salary INTO v_base FROM positions WHERE position_id = p_position_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Должность не найдена');
    END;

    -- Каждый следующий сотрудник в зале дороже предыдущего в 1.5 раза
    IF p_hall_id IS NULL THEN
      SELECT COUNT(*) INTO v_count
        FROM employees WHERE museum_id = p_museum_id AND is_active = 1;
    ELSE
      SELECT COUNT(*) INTO v_count
        FROM employees WHERE hall_id = p_hall_id AND is_active = 1;
    END IF;

    v_salary := ROUND(NVL(v_base, c_salary_base) * POWER(c_salary_growth, v_count), 2);

    IF p_hall_id IS NULL THEN
      v_status := g_st_emp_res;
    ELSE
      v_status := g_st_emp_asg;
    END IF;

    INSERT INTO employees (employee_id, museum_id, hall_id, position_id, status_id,
                            last_name, first_name, middle_name, salary, is_active)
    VALUES (seq_employees.NEXTVAL, p_museum_id, p_hall_id, p_position_id, v_status,
            TRIM(p_last_name), TRIM(p_first_name), TRIM(p_middle_name), v_salary, 1);
    COMMIT;
  END hire_employee;

  PROCEDURE assign_employee_to_hall(p_employee_id NUMBER, p_hall_id NUMBER) IS
    v_museum   NUMBER;
    v_active   NUMBER;
    v_h_museum NUMBER;
    v_open     NUMBER;
  BEGIN
    BEGIN
      SELECT museum_id, is_active INTO v_museum, v_active
        FROM employees WHERE employee_id = p_employee_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Сотрудник не найден');
    END;

    IF v_active = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 'Сотрудник уволен');
    END IF;

    BEGIN
      SELECT museum_id, is_open INTO v_h_museum, v_open
        FROM halls WHERE hall_id = p_hall_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Зал не найден');
    END;

    IF v_h_museum <> v_museum THEN
      RAISE_APPLICATION_ERROR(-20007, 'Зал принадлежит другому музею');
    END IF;
    IF v_open = 0 THEN
      RAISE_APPLICATION_ERROR(-20005, 'Зал закрыт');
    END IF;

    UPDATE employees
       SET hall_id = p_hall_id, status_id = g_st_emp_asg
     WHERE employee_id = p_employee_id;
    COMMIT;
  END assign_employee_to_hall;

  -- Улучшения залов
  PROCEDURE buy_hall_improvement(p_museum_id NUMBER, p_hall_id NUMBER,
                                 p_improvement_type_id NUMBER) IS
    v_price NUMBER;
    v_name  VARCHAR2(50);
    v_cnt   NUMBER;
    v_day   NUMBER;
  BEGIN
    p_check_museum(p_museum_id);

    SELECT COUNT(*) INTO v_cnt
      FROM halls WHERE hall_id = p_hall_id AND museum_id = p_museum_id AND is_open = 1;
    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Открытый зал этого музея не найден');
    END IF;

    BEGIN
      SELECT price, improvement_name INTO v_price, v_name
        FROM improvement_types WHERE improvement_type_id = p_improvement_type_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Тип улучшения не найден');
    END;

    SELECT COUNT(*) INTO v_cnt
      FROM hall_improvements
     WHERE hall_id = p_hall_id
       AND improvement_type_id = p_improvement_type_id
       AND status_id = g_st_imp_act;
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'В этом зале уже установлено улучшение «' || v_name || '»');
    END IF;

    p_charge(p_museum_id, v_price);

    INSERT INTO hall_improvements (hall_improvement_id, hall_id, improvement_type_id,
                                 purchased_at, status_id)
    VALUES (seq_hall_improvements.NEXTVAL, p_hall_id, p_improvement_type_id,
            SYSDATE, g_st_imp_act);

    v_day := f_billing_day(p_museum_id);
    log_financial_operation(p_museum_id, v_day, 'Расход', v_price,
                            'Покупка улучшения «' || v_name || '»');
    COMMIT;
  END buy_hall_improvement;

  -- Игровой день и все расчёты
  PROCEDURE start_game_day(p_session_id NUMBER) IS
    v_num    NUMBER;
    v_museum NUMBER;
    v_open   NUMBER;
  BEGIN
    BEGIN
      SELECT museum_id INTO v_museum FROM game_sessions
       WHERE session_id = p_session_id AND status_id = g_st_ses_act;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20005, 'Активная сессия не найдена');
    END;

    v_open := get_open_day(p_session_id);
    IF v_open IS NOT NULL THEN
      RETURN;   -- день уже идёт
    END IF;

    SELECT NVL(MAX(day_number), 0) + 1 INTO v_num
      FROM game_days WHERE session_id = p_session_id;

    INSERT INTO game_days (game_day_id, session_id, day_number, day_started_at,
                             game_time_start, game_time_end,
                             visitors_per_day, income_per_day, status_id)
    VALUES (seq_game_days.NEXTVAL, p_session_id, v_num, SYSDATE,
            '09:00', '19:00', 0, 0, g_st_day_open);

    UPDATE game_sessions SET last_activity_at = SYSDATE WHERE session_id = p_session_id;
    UPDATE museums SET last_activity_at = SYSDATE WHERE museum_id = v_museum;
    COMMIT;
  END start_game_day;

  -- Сколько примерно придёт народу. Ничего не меняет, только считает.
  FUNCTION f_predict_visitors(p_museum_id NUMBER) RETURN NUMBER IS
    v_rating   NUMBER;
    v_halls    NUMBER;
    v_attract  NUMBER;
    v_coef     NUMBER;
    v_result   NUMBER;
    v_exhibits NUMBER;
  BEGIN
    SELECT NVL(rating, 0) INTO v_rating FROM museums WHERE museum_id = p_museum_id;

    SELECT COUNT(*) INTO v_halls
      FROM halls WHERE museum_id = p_museum_id AND is_open = 1;

    SELECT NVL(SUM(k.attractiveness), 0), COUNT(*)
      INTO v_attract, v_exhibits
      FROM museum_exhibits e
      JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
     WHERE e.museum_id = p_museum_id
       AND e.status_id = g_st_ex_show;

    -- Складываем эффект всех кондиционеров в музее
    SELECT NVL(SUM(t.effect_factor), 0) INTO v_coef
      FROM hall_improvements u
      JOIN improvement_types t ON t.improvement_type_id = u.improvement_type_id
      JOIN halls z           ON z.hall_id = u.hall_id
     WHERE z.museum_id = p_museum_id
       AND u.status_id = g_st_imp_act
       AND t.improvement_name = 'Кондиционер';

    -- Формула из задания. Сверху добавил кондиционеры и общий
    -- множитель сложности, сейчас он равен 1 и ничего не меняет.
    v_result := ROUND(((v_rating / 100) * (v_halls * 10)) + (v_attract / 100));
    v_result := ROUND(v_result * (1 + v_coef) * c_visitor_scale);

    -- Если экспонаты есть, пусть хотя бы пять человек, да придёт
    IF v_exhibits > 0 AND v_result < 5 THEN
      v_result := 5;
    END IF;

    RETURN GREATEST(NVL(v_result, 0), 0);
  END f_predict_visitors;

  FUNCTION calculate_daily_visitors(p_museum_id NUMBER, p_game_day_id NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN f_predict_visitors(p_museum_id);
  END calculate_daily_visitors;

  FUNCTION estimate_current_visitors(p_museum_id NUMBER, p_session_id NUMBER) RETURN NUMBER IS
    v_day  NUMBER := get_open_day(p_session_id);
    v_frac NUMBER;
  BEGIN
    IF v_day IS NULL THEN
      RETURN 0;
    END IF;
    v_frac := (f_day_minutes(v_day) - c_day_start_min) / (c_day_end_min - c_day_start_min);
    v_frac := LEAST(GREATEST(v_frac, 0), 1);
    RETURN ROUND(f_predict_visitors(p_museum_id) * v_frac);
  END estimate_current_visitors;

  -- Доход за день
  -- Раскидываем посетителей по категориям.
  -- Считаю так: вес категории = вес её предпочтения умножить на то,
  -- сколько экспонатов этой темы выставлено. Экспонаты без темы
  -- прибавляют всем поровну. Если экспонатов вообще нет, беру
  -- обычные доли 50 / 30 / 20.
  PROCEDURE p_visitor_mix(p_museum_id      NUMBER,
                          p_visitors_count NUMBER,
                          p_cats       OUT t_cat_tab) IS
    v_total_w  NUMBER := 0;
    v_neutral  NUMBER;
    v_weight   NUMBER;
    v_assigned NUMBER := 0;
    v_best     PLS_INTEGER := 1;
    v_i        PLS_INTEGER := 0;
  BEGIN
    SELECT COUNT(*) INTO v_neutral
      FROM museum_exhibits e
      JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
     WHERE e.museum_id = p_museum_id
       AND e.status_id = g_st_ex_show
       AND k.theme_id IS NULL;

    FOR c IN (SELECT visitor_category_id, category_name,
                     ticket_price, audioguide_price, base_share
                FROM (SELECT kp.visitor_category_id, kp.category_name,
                             kp.ticket_price, kp.audioguide_price,
                             CASE kp.category_name
                               WHEN 'Обычный'  THEN 0.5
                               WHEN 'Учащийся' THEN 0.3
                               ELSE 0.2
                             END AS base_share
                        FROM visitor_categories kp)
               ORDER BY base_share DESC, visitor_category_id)
    LOOP
      v_i := v_i + 1;
      p_cats(v_i).id      := c.visitor_category_id;
      p_cats(v_i).name    := c.category_name;
      p_cats(v_i).ticket  := c.ticket_price;
      p_cats(v_i).audio   := c.audioguide_price;
      p_cats(v_i).base    := c.base_share;
      p_cats(v_i).qty     := 0;

      SELECT NVL(SUM(p.weight * t.cnt), 0) INTO v_weight
        FROM preferences p
        JOIN (SELECT k.theme_id, COUNT(*) AS cnt
                FROM museum_exhibits e
                JOIN exhibit_catalog k
                  ON k.catalog_exhibit_id = e.catalog_exhibit_id
               WHERE e.museum_id = p_museum_id
                 AND e.status_id = g_st_ex_show
                 AND k.theme_id IS NOT NULL
               GROUP BY k.theme_id) t ON t.theme_id = p.theme_id
       WHERE p.visitor_category_id = c.visitor_category_id;

      p_cats(v_i).weight := v_weight + v_neutral * c_neutral_weight;
      v_total_w := v_total_w + p_cats(v_i).weight;
    END LOOP;

    IF p_cats.COUNT = 0 OR p_visitors_count <= 0 THEN
      RETURN;
    END IF;

    -- Экспонатов нет, делим по обычным долям
    IF v_total_w = 0 THEN
      FOR i IN 1 .. p_cats.COUNT LOOP
        p_cats(i).qty := FLOOR(p_visitors_count * p_cats(i).base);
        v_assigned := v_assigned + p_cats(i).qty;
      END LOOP;
    ELSE
      FOR i IN 1 .. p_cats.COUNT LOOP
        p_cats(i).qty := FLOOR(p_visitors_count * p_cats(i).weight / v_total_w);
        v_assigned := v_assigned + p_cats(i).qty;
        IF p_cats(i).weight > p_cats(v_best).weight THEN
          v_best := i;
        END IF;
      END LOOP;
    END IF;

    -- После округления кто-то остался лишним, отдаём его самой
    -- популярной категории
    IF v_assigned < p_visitors_count THEN
      p_cats(v_best).qty := p_cats(v_best).qty + (p_visitors_count - v_assigned);
    END IF;
  END p_visitor_mix;

  FUNCTION calculate_daily_income(p_museum_id NUMBER, p_game_day_id NUMBER,
                                  p_visitors_count NUMBER) RETURN NUMBER IS
    v_income    NUMBER := 0;
    v_has_audio NUMBER;
    v_cats      t_cat_tab;
  BEGIN
    -- Аудиогид продаём, если он куплен хоть куда-нибудь
    SELECT COUNT(*) INTO v_has_audio
      FROM hall_improvements u
      JOIN improvement_types t ON t.improvement_type_id = u.improvement_type_id
      JOIN halls z           ON z.hall_id = u.hall_id
     WHERE z.museum_id = p_museum_id
       AND u.status_id = g_st_imp_act
       AND t.improvement_name = 'Аудиогид';

    p_visitor_mix(p_museum_id, p_visitors_count, v_cats);

    FOR i IN 1 .. v_cats.COUNT LOOP
      INSERT INTO visitors_by_category (record_id, game_day_id,
                                            visitor_category_id, quantity)
      VALUES (seq_visitors_by_category.NEXTVAL, p_game_day_id,
              v_cats(i).id, v_cats(i).qty);

      v_income := v_income + v_cats(i).qty * v_cats(i).ticket;
      IF v_has_audio > 0 THEN
        v_income := v_income + v_cats(i).qty * v_cats(i).audio;
      END IF;
    END LOOP;

    v_income := ROUND(v_income, 2);

    UPDATE game_days
       SET visitors_per_day = visitors_per_day + p_visitors_count,
           income_per_day = income_per_day + v_income
     WHERE game_day_id = p_game_day_id;

    UPDATE museums
       SET current_budget = current_budget + v_income,
           last_activity_at = SYSDATE
     WHERE museum_id = p_museum_id;

    log_financial_operation(p_museum_id, p_game_day_id, 'Доход', v_income,
      'Доход за день: билеты и аудиогиды, посетителей ' || p_visitors_count);

    RETURN v_income;
  END calculate_daily_income;

  -- Рейтинг
  FUNCTION calculate_rating(p_museum_id NUMBER) RETURN NUMBER IS
    v_halls   NUMBER;
    v_stars5  NUMBER;
    v_imp     NUMBER;
    v_theme   NUMBER := 0;
    v_events  NUMBER;
    v_rating  NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_halls
      FROM halls WHERE museum_id = p_museum_id AND is_open = 1;

    SELECT COUNT(*) INTO v_stars5
      FROM museum_exhibits e
      JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
     WHERE e.museum_id = p_museum_id
       AND e.status_id = g_st_ex_show
       AND k.star_rating = 5;

    -- В задании написано «сумма коэффициентов на 2», но коэффициенты
    -- тут 0.10-0.20, и в сумме выходило меньше единицы при рейтинге
    -- в несколько десятков. Улучшения вообще не чувствовались,
    -- поэтому беру просто их количество.
    SELECT COUNT(*) INTO v_imp
      FROM hall_improvements u
      JOIN halls z ON z.hall_id = u.hall_id
     WHERE z.museum_id = p_museum_id
       AND u.status_id = g_st_imp_act;

    -- Бонус за тему: если хотя бы половина экспонатов зала подходит
    -- под его тему, плюс 10
    FOR h IN (SELECT z.hall_id, z.theme_id
                FROM halls z
               WHERE z.museum_id = p_museum_id
                 AND z.is_open = 1
                 AND z.theme_id IS NOT NULL)
    LOOP
      DECLARE
        v_total NUMBER;
        v_match NUMBER;
      BEGIN
        SELECT COUNT(*),
               SUM(CASE WHEN k.theme_id = h.theme_id THEN 1 ELSE 0 END)
          INTO v_total, v_match
          FROM museum_exhibits e
          JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
         WHERE e.hall_id = h.hall_id
           AND e.status_id = g_st_ex_show;

        IF NVL(v_total, 0) > 0 AND NVL(v_match, 0) / v_total >= 0.5 THEN
          v_theme := v_theme + 10;
        END IF;
      END;
    END LOOP;

    -- Всё, что накопилось от событий
    SELECT NVL(SUM(rating_effect), 0) INTO v_events
      FROM game_events WHERE museum_id = p_museum_id;

    v_rating := ROUND((v_halls * 10) + (v_stars5 * 5) + (v_imp * 2) + v_theme + v_events, 2);
    IF v_rating < 0 THEN
      v_rating := 0;
    END IF;

    UPDATE museums SET rating = v_rating WHERE museum_id = p_museum_id;
    RETURN v_rating;
  END calculate_rating;

  -- Закрываем день и считаем итоги
  PROCEDURE finish_game_day(p_session_id NUMBER) IS
    v_day      NUMBER := get_open_day(p_session_id);
    v_museum   NUMBER;
    v_num      NUMBER;
    v_visitors NUMBER;
    v_income   NUMBER;
    v_rating   NUMBER;
  BEGIN
    IF v_day IS NULL THEN
      RETURN;
    END IF;

    SELECT s.museum_id, d.day_number INTO v_museum, v_num
      FROM game_days d
      JOIN game_sessions s ON s.session_id = d.session_id
     WHERE d.game_day_id = v_day;

    v_visitors := calculate_daily_visitors(v_museum, v_day);
    v_income   := calculate_daily_income(v_museum, v_day, v_visitors);
    COMMIT;   -- посетители и доход зафиксированы до обработки событий

    event_handler(v_museum, v_day, 'День');

    IF MOD(v_num, c_salary_period) = 0 THEN
      process_week_salary(v_museum, v_day, v_num);
    END IF;

    v_rating := calculate_rating(v_museum);

    UPDATE game_days
       SET day_finished_at = SYSDATE,
           rating_at_day_end = v_rating,
           status_id = g_st_day_closed
     WHERE game_day_id = v_day;

    UPDATE game_sessions SET last_activity_at = SYSDATE WHERE session_id = p_session_id;
    COMMIT;

    check_bankruptcy(v_museum);
  END finish_game_day;

  -- События: кража, пожертвование, экскурсия
  PROCEDURE p_add_event(p_museum_id NUMBER, p_day NUMBER, p_context VARCHAR2,
                        p_name VARCHAR2, p_desc VARCHAR2,
                        p_budget NUMBER, p_rating NUMBER) IS
    -- Номер дня считаем заранее, до INSERT. Если вызвать функцию прямо
    -- внутри запроса, Oracle не соберёт пакет: PLS-00231.
    v_day_num NUMBER := f_day_number(p_museum_id);
  BEGIN
    INSERT INTO game_events (event_id, museum_id, game_day_id, event_context,
                                 day_number, event_name, event_date, description,
                                 budget_effect, rating_effect)
    VALUES (seq_game_events.NEXTVAL, p_museum_id, p_day, p_context,
            v_day_num, p_name, SYSDATE, p_desc, p_budget, p_rating);
  END p_add_event;

  PROCEDURE event_handler(p_museum_id NUMBER, p_game_day_id NUMBER DEFAULT NULL,
                          p_context VARCHAR2 DEFAULT 'День') IS
    v_visitors_week NUMBER;
    v_cnt           NUMBER;
    v_bonus         NUMBER;
    v_secure        NUMBER;
    v_guards        NUMBER;
    v_ex_id         NUMBER;
    v_ex_name       VARCHAR2(100);
    v_ex_price      NUMBER;
    v_steal_chance  NUMBER;
    v_students      NUMBER;
    v_cat           NUMBER;
    v_ticket        NUMBER;
    v_income        NUMBER;
    v_rating_now    NUMBER;
    v_rating_was    NUMBER;
    v_drop_note     VARCHAR2(200);
  BEGIN
    -- Пожертвование мецената.
    -- Условие из задания: за неделю пришло больше 100 человек и в этом
    -- месяце такого ещё не было. Неделя и месяц игровые, не настоящие.
    v_visitors_week := f_visitors_last_days(p_museum_id, c_game_week);
    v_cnt := f_event_count(p_museum_id, 'Пожертвование мецената', c_game_month);

    IF v_visitors_week > c_donation_visitors AND v_cnt = 0 THEN
      v_bonus := c_donation_bonus;
      UPDATE museums SET current_budget = current_budget + v_bonus WHERE museum_id = p_museum_id;
      p_add_event(p_museum_id, p_game_day_id, p_context, 'Пожертвование мецената',
                  'Меценат отметил высокую посещаемость и внёс ' || v_bonus || ' в кассу музея.',
                  v_bonus, 2);
      log_financial_operation(p_museum_id, p_game_day_id, 'Доход', v_bonus,
                              'Пожертвование мецената');
    END IF;

    -- Кража.
    -- Начальный шанс зависит от того, день сейчас или ночь.
    v_steal_chance := CASE p_context
                        WHEN 'День'       THEN c_steal_day
                        WHEN 'Ночь'       THEN c_steal_night
                        WHEN 'Отсутствие' THEN c_steal_offline
                        ELSE c_steal_day
                      END;

    -- В задании сказано, что кража происходит, если рейтинг упал
    -- на 30% за неделю. Но рейтинг почти всегда растёт, и кража тогда
    -- вообще никогда не случалась бы. Поэтому падение не включает
    -- кражу, а просто сильно повышает шанс.
    SELECT NVL(rating, 0) INTO v_rating_now FROM museums WHERE museum_id = p_museum_id;
    v_rating_was := f_rating_week_ago(p_museum_id);

    IF v_rating_was IS NOT NULL AND v_rating_was > 0
       AND v_rating_now < v_rating_was * (1 - c_rating_drop_limit) THEN
      v_steal_chance := v_steal_chance * c_steal_drop_boost;
      v_drop_note := ' Музей потерял репутацию, охрана ослабла.';
    ELSE
      v_drop_note := NULL;
    END IF;

    -- Смотрители в залах уменьшают шанс кражи
    SELECT COUNT(*) INTO v_guards
      FROM employees
     WHERE museum_id = p_museum_id AND is_active = 1 AND hall_id IS NOT NULL;
    v_steal_chance := v_steal_chance * POWER(c_guard_shield, LEAST(v_guards, 5));

    IF DBMS_RANDOM.VALUE(0, 1) < v_steal_chance THEN
      -- Берём случайный экспонат из тех, что стоят в залах
      BEGIN
        SELECT museum_exhibit_id, exhibit_name, purchase_price
          INTO v_ex_id, v_ex_name, v_ex_price
          FROM (SELECT e.museum_exhibit_id, k.exhibit_name, e.purchase_price, e.hall_id
                  FROM museum_exhibits e
                  JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
                 WHERE e.museum_id = p_museum_id
                   AND e.status_id = g_st_ex_show
                 ORDER BY DBMS_RANDOM.VALUE)
         WHERE ROWNUM = 1;

        -- Стоит ли в этом зале сигнализация
        SELECT COUNT(*) INTO v_secure
          FROM hall_improvements u
          JOIN improvement_types t ON t.improvement_type_id = u.improvement_type_id
         WHERE u.hall_id = (SELECT hall_id FROM museum_exhibits
                             WHERE museum_exhibit_id = v_ex_id)
           AND u.status_id = g_st_imp_act
           AND t.improvement_name = 'Система безопасности';

        IF v_secure > 0 THEN
          -- Сигнализация сработала, но после этого сломалась
          UPDATE hall_improvements
             SET status_id = g_st_imp_brk
           WHERE hall_id = (SELECT hall_id FROM museum_exhibits
                             WHERE museum_exhibit_id = v_ex_id)
             AND status_id = g_st_imp_act
             AND improvement_type_id = (SELECT improvement_type_id FROM improvement_types
                                       WHERE improvement_name = 'Система безопасности');

          p_add_event(p_museum_id, p_game_day_id, p_context, 'Кража экспоната',
            'Попытка кражи «' || v_ex_name || '» предотвращена. Система безопасности вышла из строя.',
            0, 0);
        ELSE
          UPDATE museum_exhibits
             SET status_id = g_st_ex_stolen, hall_id = NULL
           WHERE museum_exhibit_id = v_ex_id;

          UPDATE museums SET current_budget = current_budget - v_ex_price
           WHERE museum_id = p_museum_id;

          p_add_event(p_museum_id, p_game_day_id, p_context, 'Кража экспоната',
            'Похищен экспонат «' || v_ex_name || '». Убыток ' || v_ex_price || '.'
            || v_drop_note,
            -v_ex_price, -5);

          log_financial_operation(p_museum_id, p_game_day_id, 'Расход', v_ex_price,
                                  'Утрата экспоната «' || v_ex_name || '» в результате кражи');
        END IF;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN NULL;   -- красть нечего
      END;
    END IF;

    -- Школьная экскурсия. Только днём и не чаще раза в неделю.
    IF p_context = 'День' AND p_game_day_id IS NOT NULL THEN
      v_cnt := f_event_count(p_museum_id, 'Приезд школьной экскурсии', c_game_week);

      IF v_cnt = 0 AND DBMS_RANDOM.VALUE(0, 1) < c_excursion_chance THEN
        v_students := ROUND(DBMS_RANDOM.VALUE(10, 20));

        SELECT visitor_category_id, ticket_price INTO v_cat, v_ticket
          FROM visitor_categories WHERE category_name = 'Учащийся';

        INSERT INTO visitors_by_category (record_id, game_day_id,
                                              visitor_category_id, quantity)
        VALUES (seq_visitors_by_category.NEXTVAL, p_game_day_id, v_cat, v_students);

        v_income := v_students * v_ticket;

        UPDATE game_days
           SET visitors_per_day = visitors_per_day + v_students,
               income_per_day = income_per_day + v_income
         WHERE game_day_id = p_game_day_id;

        UPDATE museums SET current_budget = current_budget + v_income
         WHERE museum_id = p_museum_id;

        p_add_event(p_museum_id, p_game_day_id, p_context, 'Приезд школьной экскурсии',
          'Музей посетили ' || v_students || ' учащихся. Доход ' || v_income || '.',
          v_income, 1);

        log_financial_operation(p_museum_id, p_game_day_id, 'Доход', v_income,
                                'Билеты школьной экскурсии (' || v_students || ' чел.)');
      END IF;
    END IF;

    COMMIT;
    check_bankruptcy(p_museum_id);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END event_handler;

  -- Что случилось, пока игрока не было
  PROCEDURE process_offline_events(p_museum_id NUMBER) IS
    v_last      DATE;
    v_intervals NUMBER;
  BEGIN
    SELECT last_activity_at INTO v_last FROM museums WHERE museum_id = p_museum_id;

    v_intervals := FLOOR((SYSDATE - v_last) * 24 * 60 / c_offline_interval);
    v_intervals := LEAST(NVL(v_intervals, 0), c_offline_max);

    IF v_intervals <= 0 THEN
      RETURN;
    END IF;

    FOR i IN 1 .. v_intervals LOOP
      event_handler(p_museum_id, NULL, 'Отсутствие');
    END LOOP;

    UPDATE museums SET last_activity_at = SYSDATE WHERE museum_id = p_museum_id;
    COMMIT;
  END process_offline_events;

  -- Зарплата и проигрыш
  PROCEDURE process_week_salary(p_museum_id NUMBER, p_game_day_id NUMBER, p_day_number NUMBER) IS
    v_total  NUMBER;
    v_budget NUMBER;
  BEGIN
    IF MOD(NVL(p_day_number, 0), c_salary_period) <> 0 THEN
      RETURN;
    END IF;

    SELECT NVL(SUM(salary), 0) INTO v_total
      FROM employees WHERE museum_id = p_museum_id AND is_active = 1;

    IF v_total = 0 THEN
      RETURN;
    END IF;

    UPDATE museums
       SET current_budget = current_budget - v_total
     WHERE museum_id = p_museum_id
    RETURNING current_budget INTO v_budget;

    log_financial_operation(p_museum_id, p_game_day_id, 'Расход', v_total,
                            'Выплата зарплаты за неделю (день ' || p_day_number || ')');
    COMMIT;

    IF v_budget < c_bankrupt_limit THEN
      check_bankruptcy(p_museum_id);
    END IF;
  END process_week_salary;

  PROCEDURE check_bankruptcy(p_museum_id NUMBER) IS
    v_budget NUMBER;
    v_status NUMBER;
    v_sess   NUMBER;
  BEGIN
    SELECT current_budget, status_id INTO v_budget, v_status
      FROM museums WHERE museum_id = p_museum_id;

    IF v_budget >= c_bankrupt_limit OR v_status = g_st_mus_bank THEN
      RETURN;
    END IF;

    UPDATE museums SET status_id = g_st_mus_bank WHERE museum_id = p_museum_id;

    v_sess := get_active_session(p_museum_id);
    IF v_sess IS NOT NULL THEN
      p_add_event(p_museum_id, get_open_day(v_sess), 'День', 'Банкротство',
                  'Бюджет опустился ниже допустимого предела: ' || v_budget, 0, 0);

      IF NOT f_has_pending(v_sess, 'LOSE_SESSION') THEN
        INSERT INTO action_queue (action_id, museum_id, session_id, action_code,
                                      params, scheduled_at, status_id)
        VALUES (seq_action_queue.NEXTVAL, p_museum_id, v_sess, 'LOSE_SESSION',
                NULL, SYSDATE, g_st_act_wait);
      END IF;
    END IF;
    COMMIT;
  END check_bankruptcy;

  -- Записи в журналы
  PROCEDURE log_financial_operation(p_museum_id NUMBER, p_game_day_id NUMBER,
                                    p_operation_type VARCHAR2, p_amount NUMBER,
                                    p_description VARCHAR2 DEFAULT NULL) IS
  BEGIN
    -- Нули не пишем, иначе журнал забьётся строчками «доход 0»
    -- в те дни, когда музей ещё пустой.
    IF NVL(p_amount, 0) = 0 THEN
      RETURN;
    END IF;

    -- Тут только запись. Бюджет меняет тот, кто вызвал.
    INSERT INTO financial_operations (operation_id, museum_id, game_day_id,
                                     operation_type, amount, operation_date, description)
    VALUES (seq_financial_operations.NEXTVAL, p_museum_id, p_game_day_id,
            p_operation_type, ABS(p_amount), SYSDATE, p_description);
  END log_financial_operation;

  PROCEDURE log_action(p_action_id NUMBER, p_result VARCHAR2,
                       p_description VARCHAR2 DEFAULT NULL) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    -- Тоже только запись, ничего не считаем
    INSERT INTO action_log (record_id, action_id, result, description, logged_at)
    VALUES (seq_action_log.NEXTVAL, p_action_id, p_result,
            SUBSTR(p_description, 1, 1000), SYSDATE);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
  END log_action;

  -- Очередь действий и фоновый планировщик
  PROCEDURE enqueue_action(p_museum_id NUMBER, p_session_id NUMBER,
                           p_action_code VARCHAR2, p_parameters CLOB) IS
  BEGIN
    -- Пока просто кладём в очередь, ничего не выполняем
    INSERT INTO action_queue (action_id, museum_id, session_id, action_code,
                                  params, scheduled_at, executed_at, status_id)
    VALUES (seq_action_queue.NEXTVAL, p_museum_id, p_session_id, p_action_code,
            p_parameters, SYSDATE, NULL, g_st_act_wait);
    COMMIT;
  END enqueue_action;

  PROCEDURE p_dispatch(p_museum NUMBER, p_session NUMBER,
                       p_code VARCHAR2, p_params CLOB) IS
  BEGIN
    CASE p_code
      WHEN 'OPEN_HALL' THEN
        open_hall(p_museum,
                  f_param(p_params, 'NAME'),
                  f_param_num(p_params, 'THEME'),
                  f_param(p_params, 'SIZE'));

      WHEN 'CHANGE_THEME' THEN
        change_hall_theme(f_param_num(p_params, 'HALL'), f_param_num(p_params, 'THEME'));

      WHEN 'BUY_EXHIBIT' THEN
        buy_exhibit(p_museum, f_param_num(p_params, 'CATALOG'));

      WHEN 'SELL_EXHIBIT' THEN
        sell_exhibit(f_param_num(p_params, 'EXHIBIT'));

      WHEN 'PLACE_EXHIBIT' THEN
        place_exhibit(f_param_num(p_params, 'EXHIBIT'), f_param_num(p_params, 'HALL'));

      WHEN 'REMOVE_EXHIBIT' THEN
        remove_exhibit_to_storage(f_param_num(p_params, 'EXHIBIT'));

      WHEN 'HIRE_EMPLOYEE' THEN
        hire_employee(p_museum_id  => p_museum,
                      p_hall_id    => f_param_num(p_params, 'HALL'),
                      p_last_name  => NVL(f_param(p_params, 'LAST'),  'Иванов'),
                      p_first_name => NVL(f_param(p_params, 'FIRST'), 'Иван'),
                      p_middle_name=> f_param(p_params, 'MIDDLE'),
                      p_position_id=> f_param_num(p_params, 'POSITION'));

      WHEN 'ASSIGN_EMPLOYEE' THEN
        assign_employee_to_hall(f_param_num(p_params, 'EMPLOYEE'), f_param_num(p_params, 'HALL'));

      WHEN 'BUY_IMPROVEMENT' THEN
        buy_hall_improvement(p_museum, f_param_num(p_params, 'HALL'),
                             f_param_num(p_params, 'TYPE'));

      WHEN 'START_DAY' THEN
        start_game_day(p_session);

      WHEN 'FINISH_DAY' THEN
        finish_game_day(p_session);

      WHEN 'EVENT_DAY' THEN
        event_handler(p_museum, get_open_day(p_session), 'День');

      WHEN 'EVENT_NIGHT' THEN
        event_handler(p_museum, NULL, 'Ночь');

      WHEN 'OFFLINE' THEN
        process_offline_events(p_museum);

      WHEN 'FINISH_SESSION' THEN
        finish_session(p_session);

      WHEN 'LOSE_SESSION' THEN
        UPDATE game_sessions
           SET status_id = g_st_ses_lost,
               finished_at = SYSDATE
         WHERE session_id = p_session;
        COMMIT;

      ELSE
        RAISE_APPLICATION_ERROR(-20007, 'Неизвестный код действия: ' || p_code);
    END CASE;
  END p_dispatch;

  PROCEDURE process_action_queue IS
    v_ids     t_num_tab;
    v_museums t_num_tab;
    v_sess    t_num_tab;
    v_codes   t_str_tab;
    v_params  t_str_tab;
    v_rating  NUMBER;
  BEGIN
    SELECT action_id, museum_id, session_id, action_code,
           TO_CHAR(SUBSTR(params, 1, 3900))
      BULK COLLECT INTO v_ids, v_museums, v_sess, v_codes, v_params
      FROM action_queue
     WHERE status_id = g_st_act_wait
     ORDER BY scheduled_at, action_id;

    IF v_ids.COUNT = 0 THEN
      RETURN;
    END IF;

    FOR i IN 1 .. v_ids.COUNT LOOP
      UPDATE action_queue
         SET status_id = g_st_act_run
       WHERE action_id = v_ids(i);
      COMMIT;

      BEGIN
        -- Вызываем нужную процедуру по коду действия
        p_dispatch(v_museums(i), v_sess(i), v_codes(i), v_params(i));

        -- Сразу пересчитываем рейтинг
        v_rating := calculate_rating(v_museums(i));
        COMMIT;

        -- Потом проверяем, не проиграли ли
        check_bankruptcy(v_museums(i));

        UPDATE action_queue
           SET status_id = g_st_act_done,
               executed_at = SYSDATE
         WHERE action_id = v_ids(i);
        COMMIT;

        -- И только в конце пишем в журнал
        log_action(v_ids(i), 'Успех', 'Действие ' || v_codes(i) || ' выполнено');
      EXCEPTION
        WHEN OTHERS THEN
          ROLLBACK;
          UPDATE action_queue
             SET status_id = g_st_act_err,
                 executed_at = SYSDATE
           WHERE action_id = v_ids(i);
          COMMIT;
          log_action(v_ids(i), 'Ошибка', SUBSTR(SQLERRM, 1, 1000));
      END;
    END LOOP;
  END process_action_queue;

  -- Это вызывается раз в секунду и решает, что должно случиться само
  PROCEDURE process_time_tick IS
    v_day     NUMBER;
    v_minutes NUMBER;
    v_last    DATE;
    v_speed   NUMBER;
  BEGIN
    FOR s IN (SELECT s.session_id, s.museum_id
                FROM game_sessions s
                JOIN museums m ON m.museum_id = s.museum_id
               WHERE s.status_id = g_st_ses_act
                 AND m.is_active = 1)
    LOOP
      v_day := get_open_day(s.session_id);

      IF v_day IS NOT NULL THEN
        -- День идёт
        v_minutes := f_day_minutes(v_day);

        IF v_minutes >= c_day_end_min THEN
          IF NOT f_has_pending(s.session_id, 'FINISH_DAY') THEN
            enqueue_action(s.museum_id, s.session_id, 'FINISH_DAY', NULL);
          END IF;
        ELSIF DBMS_RANDOM.VALUE(0, 1) < c_event_chance_day
              AND NOT f_has_pending(s.session_id, 'EVENT_DAY') THEN
          enqueue_action(s.museum_id, s.session_id, 'EVENT_DAY', NULL);
        END IF;
      ELSE
        -- Сейчас ночь
        SELECT MAX(day_finished_at) INTO v_last
          FROM game_days
         WHERE session_id = s.session_id AND status_id = g_st_day_closed;

        -- При ускорении ночь тоже короче. Иначе на скорости 8
        -- ночь была бы длиннее дня.
        v_speed := f_speed(s.session_id);

        IF v_last IS NULL
           OR (SYSDATE - v_last) * 86400 >= c_night_real_sec / v_speed THEN
          IF NOT f_has_pending(s.session_id, 'START_DAY') THEN
            enqueue_action(s.museum_id, s.session_id, 'START_DAY', NULL);
          END IF;
        ELSIF DBMS_RANDOM.VALUE(0, 1) < c_event_chance_night
              AND NOT f_has_pending(s.session_id, 'EVENT_NIGHT') THEN
          enqueue_action(s.museum_id, s.session_id, 'EVENT_NIGHT', NULL);
        END IF;
      END IF;
    END LOOP;

    process_action_queue;
  END process_time_tick;

  -- Текстовые отчёты для окошка со справкой
  PROCEDURE show_museum_state(p_museum_id NUMBER) IS
    v_name   VARCHAR2(100);
    v_budget NUMBER;
    v_rating NUMBER;
    v_status VARCHAR2(50);
    PROCEDURE l(p VARCHAR2) IS BEGIN DBMS_OUTPUT.PUT_LINE(p); END;
  BEGIN
    SELECT m.museum_name, m.current_budget, NVL(m.rating, 0), st.status_name
      INTO v_name, v_budget, v_rating, v_status
      FROM museums m JOIN statuses st ON st.status_id = m.status_id
     WHERE m.museum_id = p_museum_id;

    l('==========================================================');
    l('МУЗЕЙ: ' || v_name || '   [' || v_status || ']');
    l('Бюджет: ' || TO_CHAR(v_budget, 'FM999999990.00') || '   Рейтинг: ' || v_rating);
    l('----------------------------------------------------------');

    FOR h IN (SELECT z.hall_id, z.hall_name, z.hall_size, z.capacity,
                     NVL(t.theme_name, 'без темы') AS theme, z.is_open
                FROM halls z LEFT JOIN themes t ON t.theme_id = z.theme_id
               WHERE z.museum_id = p_museum_id
               ORDER BY z.hall_id)
    LOOP
      l('ЗАЛ «' || h.hall_name || '» (' || h.hall_size || ', тема: ' || h.theme ||
        ', мест: ' || h.capacity || ', ' ||
        CASE h.is_open WHEN 1 THEN 'открыт' ELSE 'закрыт' END || ')');

      FOR e IN (SELECT k.exhibit_name, k.star_rating, k.attractiveness
                  FROM museum_exhibits em
                  JOIN exhibit_catalog k ON k.catalog_exhibit_id = em.catalog_exhibit_id
                 WHERE em.hall_id = h.hall_id
                   AND em.status_id = g_st_ex_show
                 ORDER BY k.exhibit_name)
      LOOP
        l('    * ' || e.exhibit_name || ' (' || e.star_rating || '*, привл. ' ||
          e.attractiveness || ')');
      END LOOP;

      FOR u IN (SELECT t.improvement_name, st.status_name
                  FROM hall_improvements u
                  JOIN improvement_types t ON t.improvement_type_id = u.improvement_type_id
                  JOIN statuses st       ON st.status_id = u.status_id
                 WHERE u.hall_id = h.hall_id)
      LOOP
        l('    + улучшение: ' || u.improvement_name || ' [' || u.status_name || ']');
      END LOOP;
    END LOOP;

    l('----------------------------------------------------------');
    l('СКЛАД:');
    FOR e IN (SELECT k.exhibit_name, e.purchase_price
                FROM museum_exhibits e
                JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
               WHERE e.museum_id = p_museum_id
                 AND e.status_id = g_st_ex_store)
    LOOP
      l('    - ' || e.exhibit_name || ' (куплен за ' || e.purchase_price || ')');
    END LOOP;

    l('----------------------------------------------------------');
    l('СОТРУДНИКИ:');
    FOR s IN (SELECT c.last_name, c.first_name, d.position_name, c.salary,
                     NVL(z.hall_name, 'кадровый резерв') AS hall
                FROM employees c
                JOIN positions d ON d.position_id = c.position_id
                LEFT JOIN halls z ON z.hall_id = c.hall_id
               WHERE c.museum_id = p_museum_id AND c.is_active = 1)
    LOOP
      l('    - ' || s.last_name || ' ' || s.first_name || ', ' || s.position_name ||
        ', ' || s.salary || ' (' || s.hall || ')');
    END LOOP;
    l('==========================================================');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('Музей не найден: ' || p_museum_id);
  END show_museum_state;

  PROCEDURE show_statistics(p_museum_id NUMBER) IS
    v_days     NUMBER;
    v_visitors NUMBER;
    v_income   NUMBER;
    v_expense  NUMBER;
    PROCEDURE l(p VARCHAR2) IS BEGIN DBMS_OUTPUT.PUT_LINE(p); END;
  BEGIN
    SELECT COUNT(*), NVL(SUM(d.visitors_per_day), 0),
           NVL(SUM(d.income_per_day), 0)
      INTO v_days, v_visitors, v_income
      FROM game_days d
      JOIN game_sessions s ON s.session_id = d.session_id
     WHERE s.museum_id = p_museum_id;

    SELECT NVL(SUM(f.amount), 0) INTO v_expense
      FROM financial_operations f
     WHERE f.museum_id = p_museum_id AND f.operation_type = 'Расход';

    l('=================== СТАТИСТИКА МУЗЕЯ =====================');
    l('Сыграно игровых дней : ' || v_days);
    l('Всего посетителей    : ' || v_visitors);
    l('Общий доход          : ' || TO_CHAR(v_income,  'FM999999990.00'));
    l('Общий расход         : ' || TO_CHAR(v_expense, 'FM999999990.00'));
    l('Итоговый баланс      : ' || TO_CHAR(v_income - v_expense, 'FM999999990.00'));
    l('----------------------------------------------------------');
    l('Посетители по категориям:');

    FOR c IN (SELECT kp.category_name, SUM(pk.quantity) AS cnt
                FROM visitors_by_category pk
                JOIN visitor_categories kp
                  ON kp.visitor_category_id = pk.visitor_category_id
                JOIN game_days d    ON d.game_day_id = pk.game_day_id
                JOIN game_sessions s ON s.session_id = d.session_id
               WHERE s.museum_id = p_museum_id
               GROUP BY kp.category_name
               ORDER BY kp.category_name)
    LOOP
      l('    ' || RPAD(c.category_name, 12) || ' : ' || c.cnt);
    END LOOP;

    l('----------------------------------------------------------');
    l('События (включая ночные и офлайн):');
    FOR e IN (SELECT event_name, COUNT(*) AS cnt
                FROM game_events
               WHERE museum_id = p_museum_id
               GROUP BY event_name
               ORDER BY event_name)
    LOOP
      l('    ' || RPAD(e.event_name, 28) || ' : ' || e.cnt);
    END LOOP;
    l('==========================================================');
  END show_statistics;

  -- Функции, которые отдают данные игре. Каждая просто открывает
  -- курсор с готовыми строками.
  FUNCTION get_museum_state(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT m.museum_id, m.museum_name, m.current_budget, NVL(m.rating,0) AS rating,
             st.status_name AS status, u.difficulty_name AS difficulty,
             (SELECT COUNT(*) FROM halls z WHERE z.museum_id = m.museum_id AND z.is_open = 1)
               AS halls_count,
             (SELECT COUNT(*) FROM museum_exhibits e
               WHERE e.museum_id = m.museum_id
                 AND e.status_id = g_st_ex_show) AS displayed_count,
             (SELECT COUNT(*) FROM museum_exhibits e
               WHERE e.museum_id = m.museum_id
                 AND e.status_id = g_st_ex_store) AS in_storage,
             (SELECT COUNT(*) FROM employees c
               WHERE c.museum_id = m.museum_id AND c.is_active = 1) AS employees_count,
             (SELECT NVL(SUM(c.salary),0) FROM employees c
               WHERE c.museum_id = m.museum_id AND c.is_active = 1) AS salary_fund
        FROM museums m
        JOIN statuses st          ON st.status_id = m.status_id
        JOIN difficulty_levels u  ON u.difficulty_id = m.difficulty_id
       WHERE m.museum_id = p_museum_id;
    RETURN c;
  END get_museum_state;

  FUNCTION get_halls(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT z.hall_id, z.hall_name, z.hall_size, z.capacity,
             z.is_open, z.theme_id, NVL(t.theme_name, 'без темы') AS theme,
             (SELECT COUNT(*) FROM museum_exhibits e
               WHERE e.hall_id = z.hall_id
                 AND e.status_id = g_st_ex_show) AS occupied,
             (SELECT COUNT(*) FROM employees c
               WHERE c.hall_id = z.hall_id AND c.is_active = 1) AS employees_count,
             museum_curator.can_hire_employee(z.hall_id) AS can_hire
        FROM halls z LEFT JOIN themes t ON t.theme_id = z.theme_id
       WHERE z.museum_id = p_museum_id
       ORDER BY z.hall_id;
    RETURN c;
  END get_halls;

  FUNCTION get_hall_exhibits(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT e.museum_exhibit_id, e.hall_id, k.exhibit_name, k.exhibit_type,
             k.star_rating, k.attractiveness, NVL(t.theme_name, 'без темы') AS theme,
             k.theme_id
        FROM museum_exhibits e
        JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
        LEFT JOIN themes t          ON t.theme_id = k.theme_id
       WHERE e.museum_id = p_museum_id
         AND e.status_id = g_st_ex_show
       ORDER BY e.hall_id, e.museum_exhibit_id;
    RETURN c;
  END get_hall_exhibits;

  FUNCTION get_storage(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c       SYS_REFCURSOR;
    v_ratio NUMBER := c_sell_ratio;
  BEGIN
    OPEN c FOR
      SELECT e.museum_exhibit_id, k.exhibit_name, k.exhibit_type, k.star_rating,
             k.attractiveness, e.purchase_price,
             ROUND(e.purchase_price * v_ratio, 2) AS sale_price,
             NVL(t.theme_name, 'без темы') AS theme
        FROM museum_exhibits e
        JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
        LEFT JOIN themes t          ON t.theme_id = k.theme_id
       WHERE e.museum_id = p_museum_id
         AND e.status_id = g_st_ex_store
       ORDER BY k.exhibit_name;
    RETURN c;
  END get_storage;

  -- Всё, что можно продать: и склад, и то, что стоит в залах.
  -- Выставленный экспонат при продаже сам снимается с экспозиции,
  -- поэтому отдельно убирать его не надо.
  FUNCTION get_sellable(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c       SYS_REFCURSOR;
    v_ratio NUMBER := c_sell_ratio;
  BEGIN
    OPEN c FOR
      SELECT e.museum_exhibit_id, k.exhibit_name, k.exhibit_type, k.star_rating,
             k.attractiveness, e.purchase_price,
             ROUND(e.purchase_price * v_ratio, 2) AS sale_price,
             NVL(t.theme_name, 'без темы') AS theme,
             NVL(z.hall_name, 'склад') AS place,
             CASE WHEN e.hall_id IS NULL THEN 0 ELSE 1 END AS displayed
        FROM museum_exhibits e
        JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
        LEFT JOIN themes t ON t.theme_id = k.theme_id
        LEFT JOIN halls z ON z.hall_id = e.hall_id
       WHERE e.museum_id = p_museum_id
         AND e.status_id IN (g_st_ex_store, g_st_ex_show)
       ORDER BY displayed, k.exhibit_name;
    RETURN c;
  END get_sellable;

  FUNCTION get_catalog RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT k.catalog_exhibit_id, k.exhibit_name, k.exhibit_type, k.star_rating,
             k.price, k.attractiveness, NVL(t.theme_name, 'без темы') AS theme, k.description
        FROM exhibit_catalog k LEFT JOIN themes t ON t.theme_id = k.theme_id
       ORDER BY k.price, k.exhibit_name;
    RETURN c;
  END get_catalog;

  FUNCTION get_themes RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR SELECT theme_id, theme_name, description FROM themes ORDER BY theme_id;
    RETURN c;
  END get_themes;

  FUNCTION get_preferences RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT kp.category_name AS category, t.theme_name AS theme,
             p.weight, p.description, kp.ticket_price, kp.audioguide_price
        FROM preferences p
        JOIN visitor_categories kp
          ON kp.visitor_category_id = p.visitor_category_id
        JOIN themes t ON t.theme_id = p.theme_id
       ORDER BY kp.ticket_price DESC, p.weight DESC;
    RETURN c;
  END get_preferences;

  FUNCTION get_visitor_mix(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c         SYS_REFCURSOR;
    v_neutral NUMBER := c_neutral_weight;
    v_shown   NUMBER := g_st_ex_show;
  BEGIN
    OPEN c FOR
      WITH museum_themes AS (
        SELECT k.theme_id, COUNT(*) AS cnt
          FROM museum_exhibits e
          JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
         WHERE e.museum_id = p_museum_id
           AND e.status_id = v_shown
           AND k.theme_id IS NOT NULL
         GROUP BY k.theme_id),
      no_theme AS (
        SELECT COUNT(*) AS cnt
          FROM museum_exhibits e
          JOIN exhibit_catalog k ON k.catalog_exhibit_id = e.catalog_exhibit_id
         WHERE e.museum_id = p_museum_id
           AND e.status_id = v_shown
           AND k.theme_id IS NULL),
      weights AS (
        SELECT kp.category_name AS category,
               NVL((SELECT SUM(p.weight * tm.cnt)
                      FROM preferences p
                      JOIN museum_themes tm ON tm.theme_id = p.theme_id
                     WHERE p.visitor_category_id = kp.visitor_category_id), 0)
               + (SELECT cnt FROM no_theme) * v_neutral AS weight
          FROM visitor_categories kp)
      SELECT category, weight,
             ROUND(weight / NULLIF(SUM(weight) OVER (), 0) * 100, 1) AS share_percent
        FROM weights
       ORDER BY weight DESC, category;
    RETURN c;
  END get_visitor_mix;

  FUNCTION get_positions RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT position_id, position_name, base_salary, description
        FROM positions ORDER BY position_id;
    RETURN c;
  END get_positions;

  FUNCTION get_improvement_types RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT improvement_type_id, improvement_name, price, effect_factor, effect_description
        FROM improvement_types ORDER BY price;
    RETURN c;
  END get_improvement_types;

  FUNCTION get_difficulties RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT difficulty_id, difficulty_name, start_budget, description
        FROM difficulty_levels ORDER BY start_budget DESC;
    RETURN c;
  END get_difficulties;

  FUNCTION get_employees(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT s.employee_id, s.last_name, s.first_name, s.middle_name, s.salary,
             d.position_name, s.hall_id, NVL(z.hall_name, 'кадровый резерв') AS hall,
             st.status_name AS status
        FROM employees s
        JOIN positions d ON d.position_id = s.position_id
        JOIN statuses st  ON st.status_id  = s.status_id
        LEFT JOIN halls z ON z.hall_id = s.hall_id
       WHERE s.museum_id = p_museum_id AND s.is_active = 1
       ORDER BY s.employee_id;
    RETURN c;
  END get_employees;

  FUNCTION get_hall_improvements(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT u.hall_improvement_id, u.hall_id, z.hall_name,
             t.improvement_name, t.effect_factor,
             st.status_name AS status, u.purchased_at
        FROM hall_improvements u
        JOIN halls z           ON z.hall_id = u.hall_id
        JOIN improvement_types t ON t.improvement_type_id = u.improvement_type_id
        JOIN statuses st       ON st.status_id = u.status_id
       WHERE z.museum_id = p_museum_id
       ORDER BY u.hall_id, t.improvement_name;
    RETURN c;
  END get_hall_improvements;

  FUNCTION get_recent_events(p_museum_id NUMBER, p_limit NUMBER DEFAULT 12) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT * FROM (
        SELECT event_name, event_context, description,
               budget_effect, rating_effect, event_date
          FROM game_events
         WHERE museum_id = p_museum_id
         ORDER BY event_date DESC, event_id DESC)
       WHERE ROWNUM <= p_limit;
    RETURN c;
  END get_recent_events;

  FUNCTION get_recent_actions(p_museum_id NUMBER, p_limit NUMBER DEFAULT 12) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT * FROM (
        SELECT q.action_code, j.result, j.description, j.logged_at
          FROM action_log j
          JOIN action_queue q ON q.action_id = j.action_id
         WHERE q.museum_id = p_museum_id
         ORDER BY j.logged_at DESC, j.record_id DESC)
       WHERE ROWNUM <= p_limit;
    RETURN c;
  END get_recent_actions;

  FUNCTION get_day_report(p_session_id NUMBER, p_limit NUMBER DEFAULT 10) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT * FROM (
        SELECT d.day_number, d.visitors_per_day AS visitors_count,
               d.income_per_day AS income, d.rating_at_day_end AS rating,
               st.status_name AS status, d.day_finished_at
          FROM game_days d
          JOIN statuses st ON st.status_id = d.status_id
         WHERE d.session_id = p_session_id
         ORDER BY d.day_number DESC)
       WHERE ROWNUM <= p_limit;
    RETURN c;
  END get_day_report;

  FUNCTION get_statistics(p_museum_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT
        (SELECT COUNT(*) FROM game_days d JOIN game_sessions s ON s.session_id = d.session_id
          WHERE s.museum_id = p_museum_id) AS total_days,
        (SELECT NVL(SUM(d.visitors_per_day),0)
           FROM game_days d JOIN game_sessions s ON s.session_id = d.session_id
          WHERE s.museum_id = p_museum_id) AS total_visitors,
        (SELECT NVL(SUM(d.income_per_day),0)
           FROM game_days d JOIN game_sessions s ON s.session_id = d.session_id
          WHERE s.museum_id = p_museum_id) AS total_income,
        (SELECT NVL(SUM(amount),0) FROM financial_operations
          WHERE museum_id = p_museum_id AND operation_type = 'Расход') AS total_expense,
        (SELECT COUNT(*) FROM game_events WHERE museum_id = p_museum_id) AS total_events,
        (SELECT COUNT(*) FROM museum_exhibits
          WHERE museum_id = p_museum_id
            AND status_id = g_st_ex_stolen) AS stolen
      FROM dual;
    RETURN c;
  END get_statistics;

  FUNCTION get_user_museums(p_user_id NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT m.museum_id, m.museum_name, m.current_budget, NVL(m.rating,0) AS rating,
             u.difficulty_name AS difficulty, st.status_name AS status,
             m.created_at,
             museum_curator.get_active_session(m.museum_id) AS session_id
        FROM museums m
        JOIN difficulty_levels u ON u.difficulty_id = m.difficulty_id
        JOIN statuses st         ON st.status_id = m.status_id
       WHERE m.user_id = p_user_id AND m.is_active = 1
       ORDER BY m.created_at DESC;
    RETURN c;
  END get_user_museums;

  -- Переключение скорости
  PROCEDURE set_game_speed(p_session_id NUMBER, p_factor NUMBER) IS
    v_day   NUMBER;
    v_min   NUMBER;
    v_old   NUMBER;
  BEGIN
    IF p_factor NOT IN (1, 2, 4, 8) THEN
      RAISE_APPLICATION_ERROR(
        -20007, 'Допустимые скорости: 1, 2, 4 и ' || c_speed_max);
    END IF;

    SELECT speed_factor INTO v_old
      FROM game_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF v_old = p_factor THEN
      RETURN;
    END IF;

    -- Если день идёт, запоминаем текущий игровой час
    v_day := get_open_day(p_session_id);
    IF v_day IS NOT NULL THEN
      v_min := f_day_minutes(v_day);
    END IF;

    UPDATE game_sessions
       SET speed_factor     = p_factor,
           last_activity_at = SYSDATE
     WHERE session_id = p_session_id;

    -- Время считается от начала дня, поэтому начало надо сдвинуть.
    -- Иначе при ускорении вдвое день бы тут же и закончился.
    IF v_day IS NOT NULL THEN
      UPDATE game_days
         SET day_started_at =
               SYSDATE - (LEAST(v_min, c_day_end_min) - c_day_start_min)
                         / (86400 * c_game_min_per_sec * p_factor)
       WHERE game_day_id = v_day;
    END IF;

    COMMIT;
  END set_game_speed;

  FUNCTION get_game_speed(p_session_id NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN f_speed(p_session_id);
  END get_game_speed;

  FUNCTION get_clock(p_session_id NUMBER) RETURN SYS_REFCURSOR IS
    c        SYS_REFCURSOR;
    v_day    NUMBER := get_open_day(p_session_id);
    v_min    NUMBER;
    v_num    NUMBER := 0;
    v_night  NUMBER := 1;
    v_frac   NUMBER := 0;
    v_speed  NUMBER := f_speed(p_session_id);
  BEGIN
    IF v_day IS NOT NULL THEN
      v_min   := LEAST(f_day_minutes(v_day), c_day_end_min);
      v_night := 0;
      v_frac  := (v_min - c_day_start_min) / (c_day_end_min - c_day_start_min);
      SELECT day_number INTO v_num FROM game_days WHERE game_day_id = v_day;
    ELSE
      v_min := c_day_end_min;
      SELECT NVL(MAX(day_number), 0) INTO v_num FROM game_days WHERE session_id = p_session_id;
    END IF;

    OPEN c FOR
      SELECT v_num AS day_number,
             LPAD(TRUNC(v_min / 60), 2, '0') || ':' ||
             LPAD(TRUNC(MOD(v_min, 60)), 2, '0') AS game_time,
             ROUND(LEAST(GREATEST(v_frac, 0), 1), 4) AS day_share,
             v_night AS night,
             v_day   AS game_day_id,
             v_speed AS speed_factor
        FROM dual;
    RETURN c;
  END get_clock;

-- Этот блок выполняется один раз, когда к пакету обращаются впервые.
-- Тут заполняются все переменные со статусами.
BEGIN
  g_st_mus_act    := f_status('музей','Активен');
  g_st_mus_bank   := f_status('музей','Банкрот');
  g_st_mus_arch   := f_status('музей','Архивирован');

  g_st_ses_act    := f_status('сессия','Активна');
  g_st_ses_pause  := f_status('сессия','Приостановлена');
  g_st_ses_fin    := f_status('сессия','Завершена');
  g_st_ses_lost   := f_status('сессия','Проиграна');

  g_st_day_open   := f_status('день','Открыт');
  g_st_day_closed := f_status('день','Закрыт');

  g_st_ex_store   := f_status('экспонат','На складе');
  g_st_ex_show    := f_status('экспонат','Выставлен');
  g_st_ex_stolen  := f_status('экспонат','Украден');
  g_st_ex_sold    := f_status('экспонат','Продан');

  g_st_emp_res    := f_status('сотрудник','В резерве');
  g_st_emp_asg    := f_status('сотрудник','Назначен');
  g_st_emp_fired  := f_status('сотрудник','Уволен');

  g_st_imp_act    := f_status('улучшение','Активно');
  g_st_imp_off    := f_status('улучшение','Отключено');
  g_st_imp_brk    := f_status('улучшение','Сломано');

  g_st_act_wait   := f_status('действие','Ожидает');
  g_st_act_run    := f_status('действие','Выполняется');
  g_st_act_done   := f_status('действие','Выполнено');
  g_st_act_err    := f_status('действие','Ошибка');
END museum_curator;
/
SHOW ERRORS
