-- Таблицы для игры «Куратор музея».
-- Тут только структура: сами данные лежат в других файлах.
-- Порядок важен, нельзя сослаться на таблицу, которой ещё нет.

-- Справочники. Заполняются один раз при установке и дальше не меняются.

-- Игроки. Пароль храню не как есть, а хэшем.
CREATE TABLE users (
  user_id            NUMBER          NOT NULL,
  login              VARCHAR2(50)    NOT NULL,
  password_hash      VARCHAR2(255)   NOT NULL,
  registration_date  DATE            DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_users        PRIMARY KEY (user_id),
  CONSTRAINT uq_users_login  UNIQUE (login)
);

-- Сложность. Отличается только стартовым бюджетом.
CREATE TABLE difficulty_levels (
  difficulty_id    NUMBER        NOT NULL,
  difficulty_name  VARCHAR2(30)  NOT NULL,
  start_budget     NUMBER(12,2)  NOT NULL,
  description      VARCHAR2(500),
  CONSTRAINT pk_diff       PRIMARY KEY (difficulty_id),
  CONSTRAINT uq_diff_name  UNIQUE (difficulty_name),
  CONSTRAINT ck_diff_budget CHECK (start_budget > 0)
);

-- Все статусы в одной таблице. Тип объекта + название.
CREATE TABLE statuses (
  status_id    NUMBER        NOT NULL,
  object_type  VARCHAR2(30)  NOT NULL,
  status_name  VARCHAR2(50) NOT NULL,
  description  VARCHAR2(500),
  CONSTRAINT pk_status      PRIMARY KEY (status_id),
  CONSTRAINT uq_status_pair UNIQUE (object_type, status_name),
  CONSTRAINT ck_status_type CHECK (object_type IN
    ('музей','сессия','день','экспонат','сотрудник','улучшение','действие'))
);

-- Должности сотрудников и их базовая ставка.
CREATE TABLE positions (
  position_id    NUMBER        NOT NULL,
  position_name  VARCHAR2(50) NOT NULL,
  base_salary    NUMBER(12,2)  NOT NULL,
  description    VARCHAR2(1000),
  CONSTRAINT pk_position      PRIMARY KEY (position_id),
  CONSTRAINT uq_position_name UNIQUE (position_name),
  CONSTRAINT ck_position_sal  CHECK (base_salary >= 0)
);

-- Три темы: История, Искусство, Наука.
CREATE TABLE themes (
  theme_id     NUMBER        NOT NULL,
  theme_name   VARCHAR2(50)  NOT NULL,
  description  VARCHAR2(1000),
  CONSTRAINT pk_theme      PRIMARY KEY (theme_id),
  CONSTRAINT uq_theme_name UNIQUE (theme_name)
);

-- Категории посетителей. У каждой своя цена билета.
CREATE TABLE visitor_categories (
  visitor_category_id  NUMBER       NOT NULL,
  category_name        VARCHAR2(50)     NOT NULL,
  ticket_price         NUMBER(12,2)     NOT NULL,
  audioguide_price     NUMBER(12,2)     NOT NULL,
  description          VARCHAR2(1000),
  CONSTRAINT pk_vcat      PRIMARY KEY (visitor_category_id),
  CONSTRAINT uq_vcat_name UNIQUE (category_name),
  CONSTRAINT ck_vcat_price CHECK (ticket_price >= 0 AND audioguide_price >= 0)
);

-- Кому какая тема нравится. Из-за этой таблицы состав посетителей
-- зависит от того, что выставлено в залах.
-- В задании типы названы иначе, у меня они такие:
--   туристы = Обычный, дети = Учащийся, любители истории = Льготник
-- Вес: насколько сильно категорию тянет к теме.
CREATE TABLE preferences (
  preference_id        NUMBER      NOT NULL,
  visitor_category_id  NUMBER      NOT NULL,
  theme_id             NUMBER      NOT NULL,
  weight               NUMBER(4,2) NOT NULL,
  description          VARCHAR2(500),
  CONSTRAINT pk_pref       PRIMARY KEY (preference_id),
  CONSTRAINT uq_pref_pair  UNIQUE (visitor_category_id, theme_id),
  CONSTRAINT fk_pref_cat   FOREIGN KEY (visitor_category_id)
  REFERENCES           visitor_categories (visitor_category_id),
  CONSTRAINT fk_pref_theme FOREIGN KEY (theme_id) REFERENCES themes (theme_id),
  CONSTRAINT ck_pref_w     CHECK (weight >= 0)
);

-- Что можно купить в зал: кондиционер, аудиогид, сигнализация.
CREATE TABLE improvement_types (
  improvement_type_id  NUMBER        NOT NULL,
  improvement_name     VARCHAR2(50)  NOT NULL,
  price                NUMBER(12,2)  NOT NULL,
  effect_factor        NUMBER(8,2)   NOT NULL,
  effect_description   VARCHAR2(1000),
  CONSTRAINT pk_imptype      PRIMARY KEY (improvement_type_id),
  CONSTRAINT uq_imptype_name UNIQUE (improvement_name),
  CONSTRAINT ck_imptype_price CHECK (price >= 0)
);

-- Магазин экспонатов. Общий для всех игроков.
CREATE TABLE exhibit_catalog (
  catalog_exhibit_id  NUMBER       NOT NULL,
  theme_id            NUMBER,
  exhibit_name        VARCHAR2(100)  NOT NULL,
  exhibit_type        VARCHAR2(50)   NOT NULL,
  star_rating         NUMBER(1)      NOT NULL,
  price               NUMBER(12,2)   NOT NULL,
  attractiveness      NUMBER         NOT NULL,
  description         VARCHAR2(1000),
  CONSTRAINT pk_catalog       PRIMARY KEY (catalog_exhibit_id),
  CONSTRAINT fk_catalog_theme FOREIGN KEY (theme_id) REFERENCES themes (theme_id),
  CONSTRAINT ck_catalog_stars CHECK (star_rating IN (3,4,5)),
  CONSTRAINT ck_catalog_type  CHECK (exhibit_type IN ('Картина','Скульптура','Артефакт')),
  CONSTRAINT ck_catalog_price CHECK (price > 0 AND attractiveness >= 0)
);

-- Всё, чем игрок реально управляет.

-- Главная таблица. На неё ссылается почти всё остальное.
CREATE TABLE museums (
  museum_id         NUMBER        NOT NULL,
  user_id           NUMBER        NOT NULL,
  difficulty_id     NUMBER        NOT NULL,
  status_id         NUMBER        NOT NULL,
  museum_name       VARCHAR2(100) NOT NULL,
  current_budget    NUMBER(12,2)  NOT NULL,
  rating            NUMBER        DEFAULT 0,
  created_at        DATE          DEFAULT SYSDATE NOT NULL,
  last_activity_at  DATE         DEFAULT SYSDATE NOT NULL,
  is_active         NUMBER(1)     DEFAULT 1 NOT NULL,
  CONSTRAINT pk_museum         PRIMARY KEY (museum_id),
  CONSTRAINT fk_museum_user    FOREIGN KEY (user_id)     REFERENCES users (user_id),
  CONSTRAINT fk_museum_diff    FOREIGN KEY (difficulty_id) REFERENCES difficulty_levels (difficulty_id),
  CONSTRAINT fk_museum_status  FOREIGN KEY (status_id)          REFERENCES statuses (status_id),
  CONSTRAINT uq_museum_name    UNIQUE (user_id, museum_name),
  CONSTRAINT ck_museum_active  CHECK (is_active IN (0,1))
);

-- Удалённые музеи. Сами строки не удаляю, помечаю тут.
CREATE TABLE museum_archive (
  archive_id   NUMBER        NOT NULL,
  museum_id    NUMBER        NOT NULL,
  archived_at  DATE          DEFAULT SYSDATE NOT NULL,
  reason       VARCHAR2(500),
  CONSTRAINT pk_archive        PRIMARY KEY (archive_id),
  CONSTRAINT uq_archive_museum UNIQUE (museum_id),
  CONSTRAINT fk_archive_museum FOREIGN KEY (museum_id) REFERENCES museums (museum_id)
);

-- Одна партия. У музея их может быть несколько.
CREATE TABLE game_sessions (
  session_id        NUMBER NOT NULL,
  museum_id         NUMBER NOT NULL,
  started_at        DATE   DEFAULT SYSDATE NOT NULL,
  last_activity_at  DATE   DEFAULT SYSDATE NOT NULL,
  finished_at       DATE,
  status_id         NUMBER NOT NULL,
  -- Во сколько раз ускорено время. Держу это в базе, а не в игре,
  -- потому что временем управляет база.
  speed_factor      NUMBER(2) DEFAULT 1 NOT NULL,
  CONSTRAINT pk_session        PRIMARY KEY (session_id),
  CONSTRAINT ck_session_speed  CHECK (speed_factor IN (1, 2, 4, 8)),
  CONSTRAINT fk_session_museum FOREIGN KEY (museum_id)   REFERENCES museums (museum_id),
  CONSTRAINT fk_session_status FOREIGN KEY (status_id) REFERENCES statuses (status_id)
);

-- Игровой день с 09:00 до 19:00.
CREATE TABLE game_days (
  game_day_id        NUMBER       NOT NULL,
  session_id         NUMBER       NOT NULL,
  day_number         NUMBER       NOT NULL,
  day_started_at     DATE         DEFAULT SYSDATE NOT NULL,
  day_finished_at    DATE,
  game_time_start    VARCHAR2(5)  DEFAULT '09:00' NOT NULL,
  game_time_end      VARCHAR2(5)  DEFAULT '19:00' NOT NULL,
  visitors_per_day   NUMBER      DEFAULT 0 NOT NULL,
  income_per_day     NUMBER(12,2) DEFAULT 0 NOT NULL,
  -- Какой был рейтинг, когда день закрылся. Нужно, чтобы потом
  -- сравнить с рейтингом неделю назад.
  rating_at_day_end  NUMBER,
  status_id          NUMBER       NOT NULL,
  CONSTRAINT pk_gameday        PRIMARY KEY (game_day_id),
  CONSTRAINT fk_gameday_sess   FOREIGN KEY (session_id)  REFERENCES game_sessions (session_id),
  CONSTRAINT fk_gameday_status FOREIGN KEY (status_id) REFERENCES statuses (status_id),
  CONSTRAINT uq_gameday_num    UNIQUE (session_id, day_number),
  CONSTRAINT ck_gameday_num    CHECK (day_number > 0)
);

-- Сколько кого пришло за день. Отсюда считается доход.
CREATE TABLE visitors_by_category (
  record_id            NUMBER NOT NULL,
  game_day_id          NUMBER NOT NULL,
  visitor_category_id  NUMBER NOT NULL,
  quantity             NUMBER NOT NULL,
  CONSTRAINT pk_vday      PRIMARY KEY (record_id),
  CONSTRAINT fk_vday_day  FOREIGN KEY (game_day_id)         REFERENCES game_days (game_day_id),
  CONSTRAINT fk_vday_cat  FOREIGN KEY (visitor_category_id) REFERENCES visitor_categories (visitor_category_id),
  CONSTRAINT ck_vday_cnt  CHECK (quantity >= 0)
);

-- Залы музея. Размер задаёт вместимость.
CREATE TABLE halls (
  hall_id       NUMBER        NOT NULL,
  museum_id     NUMBER        NOT NULL,
  theme_id      NUMBER,
  hall_name     VARCHAR2(50)  NOT NULL,
  hall_size     VARCHAR2(20)  NOT NULL,
  capacity      NUMBER        NOT NULL,
  opening_cost  NUMBER(12,2)  NOT NULL,
  is_open       NUMBER(1)     DEFAULT 1 NOT NULL,
  CONSTRAINT pk_hall        PRIMARY KEY (hall_id),
  CONSTRAINT fk_hall_museum FOREIGN KEY (museum_id) REFERENCES museums (museum_id),
  CONSTRAINT fk_hall_theme  FOREIGN KEY (theme_id)  REFERENCES themes (theme_id),
  CONSTRAINT uq_hall_name   UNIQUE (museum_id, hall_name),
  CONSTRAINT ck_hall_size   CHECK (hall_size IN ('Стартовый','Маленький','Средний','Большой')),
  CONSTRAINT ck_hall_open   CHECK (is_open IN (0,1)),
  CONSTRAINT ck_hall_cap    CHECK (capacity > 0)
);

-- Купленные экспонаты. hall_id пустой значит лежит на складе.
CREATE TABLE museum_exhibits (
  museum_exhibit_id   NUMBER       NOT NULL,
  museum_id           NUMBER       NOT NULL,
  catalog_exhibit_id  NUMBER       NOT NULL,
  hall_id             NUMBER,
  purchased_at        DATE         DEFAULT SYSDATE NOT NULL,
  purchase_price      NUMBER(12,2) NOT NULL,
  status_id           NUMBER       NOT NULL,
  sold_at             DATE,
  sale_price          NUMBER(12,2),
  CONSTRAINT pk_mex         PRIMARY KEY (museum_exhibit_id),
  CONSTRAINT fk_mex_museum  FOREIGN KEY (museum_id)              REFERENCES museums (museum_id),
  CONSTRAINT fk_mex_catalog FOREIGN KEY (catalog_exhibit_id) REFERENCES exhibit_catalog (catalog_exhibit_id),
  CONSTRAINT fk_mex_hall    FOREIGN KEY (hall_id)               REFERENCES halls (hall_id),
  CONSTRAINT fk_mex_status  FOREIGN KEY (status_id)            REFERENCES statuses (status_id)
);

-- Сотрудники. Зарплата у каждого своя, она растёт.
CREATE TABLE employees (
  employee_id  NUMBER        NOT NULL,
  museum_id    NUMBER        NOT NULL,
  hall_id      NUMBER,
  position_id  NUMBER        NOT NULL,
  status_id    NUMBER        NOT NULL,
  last_name    VARCHAR2(50)  NOT NULL,
  first_name   VARCHAR2(50)  NOT NULL,
  middle_name  VARCHAR2(50),
  salary       NUMBER(12,2)  NOT NULL,
  is_active    NUMBER(1)     DEFAULT 1 NOT NULL,
  CONSTRAINT pk_emp          PRIMARY KEY (employee_id),
  CONSTRAINT fk_emp_museum   FOREIGN KEY (museum_id)     REFERENCES museums (museum_id),
  CONSTRAINT fk_emp_hall     FOREIGN KEY (hall_id)      REFERENCES halls (hall_id),
  CONSTRAINT fk_emp_position FOREIGN KEY (position_id) REFERENCES positions (position_id),
  CONSTRAINT fk_emp_status   FOREIGN KEY (status_id)   REFERENCES statuses (status_id),
  CONSTRAINT ck_emp_active   CHECK (is_active IN (0,1)),
  CONSTRAINT ck_emp_salary   CHECK (salary >= 0)
);

-- Какие улучшения куплены в какой зал.
CREATE TABLE hall_improvements (
  hall_improvement_id  NUMBER NOT NULL,
  hall_id              NUMBER NOT NULL,
  improvement_type_id  NUMBER NOT NULL,
  purchased_at         DATE   DEFAULT SYSDATE NOT NULL,
  status_id            NUMBER NOT NULL,
  CONSTRAINT pk_himp        PRIMARY KEY (hall_improvement_id),
  CONSTRAINT fk_himp_hall   FOREIGN KEY (hall_id)           REFERENCES halls (hall_id),
  CONSTRAINT fk_himp_type   FOREIGN KEY (improvement_type_id) REFERENCES improvement_types (improvement_type_id),
  CONSTRAINT fk_himp_status FOREIGN KEY (status_id)        REFERENCES statuses (status_id)
);

-- Журналы. Сюда только добавляем, ничего не удаляем.

-- Все движения денег, доход и расход.
CREATE TABLE financial_operations (
  operation_id    NUMBER        NOT NULL,
  museum_id       NUMBER        NOT NULL,
  game_day_id     NUMBER,
  operation_type  VARCHAR2(30)  NOT NULL,
  amount          NUMBER(12,2)  NOT NULL,
  operation_date  DATE          DEFAULT SYSDATE NOT NULL,
  description     VARCHAR2(1000),
  CONSTRAINT pk_fin        PRIMARY KEY (operation_id),
  CONSTRAINT fk_fin_museum FOREIGN KEY (museum_id)        REFERENCES museums (museum_id),
  CONSTRAINT fk_fin_day    FOREIGN KEY (game_day_id) REFERENCES game_days (game_day_id),
  CONSTRAINT ck_fin_type   CHECK (operation_type IN ('Доход','Расход'))
);

-- Что случилось: кража, пожертвование, экскурсия.
CREATE TABLE game_events (
  event_id       NUMBER        NOT NULL,
  museum_id      NUMBER        NOT NULL,
  game_day_id    NUMBER,
  event_context  VARCHAR2(20) DEFAULT 'День' NOT NULL,
  -- В какой игровой день это случилось. Заполняю даже ночью, когда
  -- открытого дня нет, иначе не посчитать «раз в неделю».
  day_number     NUMBER,
  event_name     VARCHAR2(100) NOT NULL,
  event_date     DATE          DEFAULT SYSDATE NOT NULL,
  description    VARCHAR2(1000),
  budget_effect  NUMBER(12,2),
  rating_effect  NUMBER(8,2),
  CONSTRAINT pk_event        PRIMARY KEY (event_id),
  CONSTRAINT fk_event_museum FOREIGN KEY (museum_id)        REFERENCES museums (museum_id),
  CONSTRAINT fk_event_day    FOREIGN KEY (game_day_id) REFERENCES game_days (game_day_id),
  CONSTRAINT ck_event_ctx    CHECK (event_context IN ('День','Ночь','Отсутствие'))
);

-- Очередь действий. Игрок нажал кнопку — строка сюда.
CREATE TABLE action_queue (
  action_id     NUMBER       NOT NULL,
  museum_id     NUMBER       NOT NULL,
  session_id    NUMBER,
  action_code   VARCHAR2(50) NOT NULL,
  params        CLOB,
  scheduled_at  DATE         DEFAULT SYSDATE NOT NULL,
  executed_at   DATE,
  status_id     NUMBER       NOT NULL,
  CONSTRAINT pk_queue        PRIMARY KEY (action_id),
  CONSTRAINT fk_queue_museum FOREIGN KEY (museum_id)   REFERENCES museums (museum_id),
  CONSTRAINT fk_queue_sess   FOREIGN KEY (session_id)  REFERENCES game_sessions (session_id),
  CONSTRAINT fk_queue_status FOREIGN KEY (status_id) REFERENCES statuses (status_id)
);

-- Чем закончилось действие: успех или ошибка.
CREATE TABLE action_log (
  record_id    NUMBER        NOT NULL,
  action_id    NUMBER        NOT NULL,
  result       VARCHAR2(30)  NOT NULL,
  description  VARCHAR2(1000),
  logged_at    DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_log        PRIMARY KEY (record_id),
  CONSTRAINT fk_log_action FOREIGN KEY (action_id) REFERENCES action_queue (action_id),
  CONSTRAINT ck_log_result CHECK (result IN ('Успех','Ошибка','Отменено'))
);

-- Последовательности: из них берём id для новых строк.

CREATE SEQUENCE seq_users            START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_difficulty_levels        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_statuses                 START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_positions               START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_themes                    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_visitor_categories   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_preferences            START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_improvement_types          START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_exhibit_catalog      START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_museums                   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_museum_archive            START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_game_sessions          START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_game_days             START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_visitors_by_category START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_halls                    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_museum_exhibits         START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_employees              START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_hall_improvements         START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_financial_operations     START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_game_events         START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_action_queue        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_action_log         START WITH 1 INCREMENT BY 1 NOCACHE;

-- Индексы. Поставил туда, где пакет ищет чаще всего.

CREATE INDEX ix_museum_user   ON museums (user_id, is_active);
CREATE INDEX ix_session_mus   ON game_sessions (museum_id, status_id);
CREATE INDEX ix_gameday_sess  ON game_days (session_id, status_id);
CREATE INDEX ix_hall_museum   ON halls (museum_id, is_open);
CREATE INDEX ix_mex_museum    ON museum_exhibits (museum_id, status_id);
CREATE INDEX ix_mex_hall      ON museum_exhibits (hall_id, status_id);
CREATE INDEX ix_emp_museum    ON employees (museum_id, is_active);
CREATE INDEX ix_himp_hall     ON hall_improvements (hall_id, status_id);
CREATE INDEX ix_fin_museum    ON financial_operations (museum_id, operation_date);
CREATE INDEX ix_event_museum  ON game_events (museum_id, event_date);
CREATE INDEX ix_queue_pending ON action_queue (status_id, scheduled_at);
CREATE INDEX ix_vday_day      ON visitors_by_category (game_day_id);
