-- Подготовка чистых данных для A/B-теста

-- 1 События без дублей
DROP TABLE IF EXISTS events_dedup;
CREATE TABLE events_dedup AS
SELECT DISTINCT event_id, user_id, event_time, event_name
FROM events;

-- Контроль: должно быть удалено ровно 120 строк
SELECT (SELECT COUNT(*) FROM events)       AS before_cnt,
       (SELECT COUNT(*) FROM events_dedup) AS after_cnt,
       (SELECT COUNT(*) FROM events) - (SELECT COUNT(*) FROM events_dedup) AS removed;

-- 2 Список пользователей, которых исключаем
DROP TABLE IF EXISTS excluded_users;
CREATE TABLE excluded_users AS
-- 2.1 попали в обе группы
SELECT user_id, 'both_groups' AS reason
FROM ab_assignments
GROUP BY user_id
HAVING COUNT(DISTINCT "group") > 1
UNION
-- 2.2 аномальная активность
SELECT user_id, 'abnormal_activity' AS reason
FROM events_dedup
GROUP BY user_id
HAVING COUNT(*) > 100;

-- Контроль: сколько пользователей и по какой причине исключено
SELECT reason, COUNT(*) AS users
FROM excluded_users
GROUP BY reason;

-- Обновление предыдущих таблиц
-- 3.1 Назначение в группы: по одной строке на пользователя
DROP TABLE IF EXISTS assignments_clean;
CREATE TABLE assignments_clean AS
SELECT user_id,
       MIN("group")      AS "group",       -- у оставшихся пользователей группа одна
       MIN(assigned_at)  AS assigned_at
FROM ab_assignments
WHERE user_id NOT IN (SELECT user_id FROM excluded_users)
GROUP BY user_id;

-- 3.2 События только оставшихся пользователей
DROP TABLE IF EXISTS events_clean;
CREATE TABLE events_clean AS
SELECT *
FROM events_dedup
WHERE user_id NOT IN (SELECT user_id FROM excluded_users);

-- 3.3 Заказы только оставшихся пользователей
DROP TABLE IF EXISTS orders_clean;
CREATE TABLE orders_clean AS
SELECT *
FROM orders
WHERE user_id NOT IN (SELECT user_id FROM excluded_users);


-- 4 Итоговая таблица для анализа, одна строка на пользователя
DROP TABLE IF EXISTS ab_users;
CREATE TABLE ab_users AS
SELECT a.user_id,
       a."group",
       a.assigned_at,
       u.platform,
       u.traffic_source,
       COUNT(o.order_id)                                 AS orders_cnt,
       COALESCE(SUM(o.revenue_rub), 0)                   AS revenue_rub,
       CASE WHEN COUNT(o.order_id) > 0 THEN 1 ELSE 0 END AS bought_any,
       MAX(CASE WHEN o.order_time::timestamp >= a.assigned_at::timestamp
                 AND o.order_time::timestamp <  a.assigned_at::timestamp + INTERVAL '7 days'
                THEN 1 ELSE 0 END)                       AS bought_7d
FROM assignments_clean a
LEFT JOIN users u         ON u.user_id = a.user_id
LEFT JOIN orders_clean o  ON o.user_id = a.user_id
GROUP BY a.user_id, a."group", a.assigned_at, u.platform, u.traffic_source;


-- Проверка результатов
-- 5.1 Одна строка на пользователя
SELECT COUNT(*) AS rows_cnt, COUNT(DISTINCT user_id) AS users_cnt
FROM ab_users;

-- 5.2 Размер групп после очистки
SELECT "group", COUNT(*) AS users
FROM ab_users
GROUP BY "group";

-- 5.3 Сколько всего убрали по сравнению с исходными данными
SELECT (SELECT COUNT(DISTINCT user_id) FROM ab_assignments) AS users_before,
       (SELECT COUNT(*) FROM ab_users)                      AS users_after;