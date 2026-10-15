-- Заполняем справочники. Эти данные одинаковые у всех игроков
-- и в самой игре не меняются.

-- Статусы для всех семи видов объектов
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'музей','Активен','Музей работает, доступны все действия');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'музей','Банкрот','Достигнут порог банкротства, расходные действия заблокированы');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'музей','Архивирован','Мягкое удаление, данные сохранены');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сессия','Активна','Партия идёт');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сессия','Приостановлена','Обычный выход игрока, состояние сохранено');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сессия','Завершена','Явное завершение партии игроком');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сессия','Проиграна','Партия завершена банкротством');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'день','Открыт','Идёт игровой день, музей принимает посетителей');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'день','Закрыт','День подведён, посчитаны посетители и доход');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'экспонат','На складе','Куплен, но не выставлен');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'экспонат','Выставлен','Размещён в зале, влияет на привлекательность');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'экспонат','Украден','Утрачен в результате события «Кража экспоната»');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'экспонат','Продан','Продан игроком, вернул часть стоимости');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сотрудник','В резерве','Нанят, но не назначен в зал');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сотрудник','Назначен','Работает в конкретном зале и даёт игровой эффект');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'сотрудник','Уволен','Не получает зарплату и не даёт эффекта');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'улучшение','Активно','Улучшение работает');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'улучшение','Отключено','Улучшение временно не действует');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'улучшение','Сломано','Сработало при краже и вышло из строя');

INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'действие','Ожидает','Задание поставлено в очередь планировщика');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'действие','Выполняется','Планировщик обрабатывает задание');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'действие','Выполнено','Задание успешно выполнено');
INSERT INTO statuses (status_id, object_type, status_name, description) VALUES (seq_statuses.NEXTVAL,'действие','Ошибка','Задание отклонено, изменения откачены');

-- Три сложности, отличаются стартовым бюджетом
INSERT INTO difficulty_levels (difficulty_id, difficulty_name, start_budget, description) VALUES (seq_difficulty_levels.NEXTVAL,'Лёгкая',10000,'Стартовый бюджет 10000. Подходит для знакомства с механиками');
INSERT INTO difficulty_levels (difficulty_id, difficulty_name, start_budget, description) VALUES (seq_difficulty_levels.NEXTVAL,'Средняя',7000,'Стартовый бюджет 7000. Требует планирования расходов');
INSERT INTO difficulty_levels (difficulty_id, difficulty_name, start_budget, description) VALUES (seq_difficulty_levels.NEXTVAL,'Сложная',5000,'Стартовый бюджет 5000. Ошибки быстро ведут к банкротству');

-- Должности и базовые ставки
INSERT INTO positions (position_id, position_name, base_salary, description) VALUES (seq_positions.NEXTVAL,'Смотритель',1000,'Следит за залом, снижает вероятность кражи экспоната');
INSERT INTO positions (position_id, position_name, base_salary, description) VALUES (seq_positions.NEXTVAL,'Экскурсовод',1200,'Повышает интерес посетителей к тематическому залу');
INSERT INTO positions (position_id, position_name, base_salary, description) VALUES (seq_positions.NEXTVAL,'Реставратор',1500,'Поддерживает состояние экспонатов зала');

-- Три темы
INSERT INTO themes (theme_id, theme_name, description) VALUES (seq_themes.NEXTVAL,'История','Исторические артефакты и документы. Любима любителями истории');
INSERT INTO themes (theme_id, theme_name, description) VALUES (seq_themes.NEXTVAL,'Искусство','Живопись и скульптура. Привлекает туристов');
INSERT INTO themes (theme_id, theme_name, description) VALUES (seq_themes.NEXTVAL,'Наука','Приборы, макеты и опыты. Особенно интересна детям');

-- Категории посетителей и цены
INSERT INTO visitor_categories (visitor_category_id, category_name, ticket_price, audioguide_price, description) VALUES (seq_visitor_categories.NEXTVAL,'Обычный',300,150,'Взрослый посетитель, полный билет');
INSERT INTO visitor_categories (visitor_category_id, category_name, ticket_price, audioguide_price, description) VALUES (seq_visitor_categories.NEXTVAL,'Учащийся',150,100,'Школьник или студент, льготный билет');
INSERT INTO visitor_categories (visitor_category_id, category_name, ticket_price, audioguide_price, description) VALUES (seq_visitor_categories.NEXTVAL,'Льготник',0,50,'Бесплатный вход, доход только с аудиогида');

-- Кому какая тема нравится. Чем больше вес, тем сильнее тянет.
-- Вес показывает, насколько тема интересна категории посетителей.
-- Чем больше в залах экспонатов «своей» темы, тем большую долю
-- посетителей составит соответствующая категория.
DECLARE
  PROCEDURE add_pref(p_cat VARCHAR2, p_theme VARCHAR2, p_w NUMBER, p_desc VARCHAR2) IS
    v_cat   NUMBER;
    v_theme NUMBER;
  BEGIN
    SELECT visitor_category_id INTO v_cat
      FROM visitor_categories WHERE category_name = p_cat;
    SELECT theme_id INTO v_theme FROM themes WHERE theme_name = p_theme;
    INSERT INTO preferences (preference_id, visitor_category_id, theme_id, weight, description)
    VALUES (seq_preferences.NEXTVAL, v_cat, v_theme, p_w, p_desc);
  END;
BEGIN
  -- Обычный = туристы: идут смотреть искусство
  add_pref('Обычный',  'Искусство', 3, 'Туристы едут за живописью и скульптурой');
  add_pref('Обычный',  'История',   2, 'Исторические залы тоже в списке обязательного');
  add_pref('Обычный',  'Наука',     1, 'Наука интересует туриста меньше всего');

  -- Учащийся = дети и студенты: тянутся к науке
  add_pref('Учащийся', 'Наука',     3, 'Школьникам интереснее всего опыты и макеты');
  add_pref('Учащийся', 'История',   2, 'История нужна по программе');
  add_pref('Учащийся', 'Искусство', 1, 'Живопись школьника увлекает слабее');

  -- Льготник = любители истории, в том числе пенсионеры
  add_pref('Льготник', 'История',   3, 'Любители истории приходят за артефактами');
  add_pref('Льготник', 'Искусство', 2, 'Классическое искусство им тоже близко');
  add_pref('Льготник', 'Наука',     1, 'Научный отдел посещают реже');
  COMMIT;
END;
/

-- Что можно купить в зал
INSERT INTO improvement_types (improvement_type_id, improvement_name, price, effect_factor, effect_description) VALUES (seq_improvement_types.NEXTVAL,'Кондиционер',1500,0.15,'Посетители задерживаются дольше: +15% к числу посетителей музея');
INSERT INTO improvement_types (improvement_type_id, improvement_name, price, effect_factor, effect_description) VALUES (seq_improvement_types.NEXTVAL,'Аудиогид',2000,0.20,'Открывает продажу аудиогидов: дополнительный доход с каждого посетителя');
INSERT INTO improvement_types (improvement_type_id, improvement_name, price, effect_factor, effect_description) VALUES (seq_improvement_types.NEXTVAL,'Система безопасности',2500,0.10,'Предотвращает первую кражу в зале, после чего выходит из строя');

COMMIT;
