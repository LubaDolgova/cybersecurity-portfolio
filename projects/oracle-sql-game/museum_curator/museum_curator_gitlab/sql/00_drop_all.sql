-- Чистит схему перед установкой. Запускать только в учебной базе,
-- тут удаляются все таблицы игры.
--
-- Удаляю в три захода, и каждый нужен.
--
-- Первый — просто по именам таблиц, обычный случай.
--
-- Второй — по именам ограничений. Я переименовывал таблицы с русских
-- на английские, а имена ограничений всегда были латинскими. В Oracle
-- имя ограничения одно на всю схему, поэтому старая таблица
-- «пользователи» со своим pk_users не даёт создать новую users.
-- Ошибка ORA-02264.
--
-- Третий — вообще по любым объектам, не только таблицам. Если вместо
-- таблицы окажется представление с тем же именем, будет ORA-00955,
-- а первые два захода его не увидят, они смотрят только таблицы.
--
-- Каждое удаление в своём обработчике ошибок. Один раз у меня
-- занятая таблица оборвала весь блок, и половина объектов осталась.
SET SERVEROUTPUT ON

DECLARE
  PROCEDURE drop_object(p_name VARCHAR2, p_type VARCHAR2) IS
    v_sql VARCHAR2(500);
  BEGIN
    v_sql := CASE p_type
               WHEN 'TABLE'            THEN 'DROP TABLE "'||p_name||'" CASCADE CONSTRAINTS PURGE'
               WHEN 'VIEW'             THEN 'DROP VIEW "'||p_name||'"'
               WHEN 'SYNONYM'          THEN 'DROP SYNONYM "'||p_name||'"'
               WHEN 'MATERIALIZED VIEW' THEN 'DROP MATERIALIZED VIEW "'||p_name||'"'
               WHEN 'SEQUENCE'         THEN 'DROP SEQUENCE "'||p_name||'"'
               ELSE NULL
             END;
    IF v_sql IS NULL THEN
      RETURN;
    END IF;
    EXECUTE IMMEDIATE v_sql;
    DBMS_OUTPUT.PUT_LINE('Удалено: '||p_type||' '||p_name);
  EXCEPTION
    WHEN OTHERS THEN
      -- Мог удалиться вместе с другой таблицей или быть занят.
      -- Не останавливаемся, установщик потом проверит что осталось.
      DBMS_OUTPUT.PUT_LINE('Не удалось удалить '||p_type||' '||p_name
                           ||': '||SQLERRM);
  END drop_object;
BEGIN
  -- Проход 1: таблицы текущей версии.
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN (
              'USERS','DIFFICULTY_LEVELS','STATUSES','POSITIONS','THEMES',
              'VISITOR_CATEGORIES','PREFERENCES','IMPROVEMENT_TYPES',
              'EXHIBIT_CATALOG','MUSEUMS','MUSEUM_ARCHIVE','GAME_SESSIONS',
              'GAME_DAYS','VISITORS_BY_CATEGORY','HALLS','MUSEUM_EXHIBITS',
              'EMPLOYEES','HALL_IMPROVEMENTS','FINANCIAL_OPERATIONS',
              'GAME_EVENTS','ACTION_QUEUE','ACTION_LOG'))
  LOOP
    drop_object(t.table_name, 'TABLE');
  END LOOP;

  -- Заход 2: старые таблицы ищем по именам ограничений
  FOR t IN (SELECT DISTINCT table_name FROM user_constraints
            WHERE constraint_name IN (
              'CK_CATALOG_PRICE','CK_CATALOG_STARS','CK_CATALOG_TYPE',
              'CK_DIFF_BUDGET','CK_EMP_ACTIVE','CK_EMP_SALARY',
              'CK_EVENT_CTX','CK_FIN_TYPE','CK_GAMEDAY_NUM','CK_HALL_CAP',
              'CK_HALL_OPEN','CK_HALL_SIZE','CK_IMPTYPE_PRICE',
              'CK_LOG_RESULT','CK_MUSEUM_ACTIVE','CK_POSITION_SAL',
              'CK_PREF_W','CK_SESSION_SPEED','CK_STATUS_TYPE',
              'CK_VCAT_PRICE','CK_VDAY_CNT','FK_ARCHIVE_MUSEUM',
              'FK_CATALOG_THEME','FK_EMP_HALL','FK_EMP_MUSEUM',
              'FK_EMP_POSITION','FK_EMP_STATUS','FK_EVENT_DAY',
              'FK_EVENT_MUSEUM','FK_FIN_DAY','FK_FIN_MUSEUM',
              'FK_GAMEDAY_SESS','FK_GAMEDAY_STATUS','FK_HALL_MUSEUM',
              'FK_HALL_THEME','FK_HIMP_HALL','FK_HIMP_STATUS',
              'FK_HIMP_TYPE','FK_LOG_ACTION','FK_MEX_CATALOG','FK_MEX_HALL',
              'FK_MEX_MUSEUM','FK_MEX_STATUS','FK_MUSEUM_DIFF',
              'FK_MUSEUM_STATUS','FK_MUSEUM_USER','FK_PREF_CAT',
              'FK_PREF_THEME','FK_QUEUE_MUSEUM','FK_QUEUE_SESS',
              'FK_QUEUE_STATUS','FK_SESSION_MUSEUM','FK_SESSION_STATUS',
              'FK_VDAY_CAT','FK_VDAY_DAY','PK_ARCHIVE','PK_CATALOG',
              'PK_DIFF','PK_EMP','PK_EVENT','PK_FIN','PK_GAMEDAY','PK_HALL',
              'PK_HIMP','PK_IMPTYPE','PK_LOG','PK_MEX','PK_MUSEUM',
              'PK_POSITION','PK_PREF','PK_QUEUE','PK_SESSION','PK_STATUS',
              'PK_THEME','PK_USERS','PK_VCAT','PK_VDAY','UQ_ARCHIVE_MUSEUM',
              'UQ_DIFF_NAME','UQ_GAMEDAY_NUM','UQ_HALL_NAME',
              'UQ_IMPTYPE_NAME','UQ_MUSEUM_NAME','UQ_POSITION_NAME',
              'UQ_PREF_PAIR','UQ_STATUS_PAIR','UQ_THEME_NAME',
              'UQ_USERS_LOGIN','UQ_VCAT_NAME'))
  LOOP
    drop_object(t.table_name, 'TABLE');
  END LOOP;

  -- Заход 3: всё, что осталось с нашими именами
  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('TABLE', 'VIEW', 'SYNONYM',
                                  'MATERIALIZED VIEW')
              AND object_name IN (
                'USERS','DIFFICULTY_LEVELS','STATUSES','POSITIONS','THEMES',
                'VISITOR_CATEGORIES','PREFERENCES','IMPROVEMENT_TYPES',
                'EXHIBIT_CATALOG','MUSEUMS','MUSEUM_ARCHIVE',
                'GAME_SESSIONS','GAME_DAYS','VISITORS_BY_CATEGORY','HALLS',
                'MUSEUM_EXHIBITS','EMPLOYEES','HALL_IMPROVEMENTS',
                'FINANCIAL_OPERATIONS','GAME_EVENTS','ACTION_QUEUE',
                'ACTION_LOG'))
  LOOP
    drop_object(o.object_name, o.object_type);
  END LOOP;

  -- Последовательности, у них имя всегда начинается с seq_
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name LIKE 'SEQ!_%' ESCAPE '!')
  LOOP
    drop_object(s.sequence_name, 'SEQUENCE');
  END LOOP;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP PACKAGE museum_curator';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
