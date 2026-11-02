SELECT * FROM events;

SELECT * FROM ab_assignments;

SELECT * FROM orders;

SELECT * FROM users;

-- 1.1 Соотношение тестовой и контрольной групп
SELECT "group",
       COUNT(*)                AS rows_cnt,
       COUNT(DISTINCT user_id) AS users_cnt
FROM ab_assignments
GROUP BY "group";

-- 1.2 пользователи, у которых больше одной строки в ab_assignments
SELECT user_id,
       COUNT(*)                AS rows_cnt,
       COUNT(DISTINCT "group") AS groups_cnt
FROM ab_assignments
GROUP BY user_id
HAVING COUNT(*) > 1
ORDER BY groups_cnt DESC, rows_cnt DESC;

-- 1.3 Сколько пользователей попало сразу в обе группы?
SELECT COUNT(*) AS users_in_both_groups
FROM (
    SELECT user_id
    FROM ab_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT "group") > 1
) t;

-- 2.1 Пропуски по каждому столбцу отдельно (общий подсчет скрывает, где именно проблема)
SELECT COUNT(*)                                                  AS total_rows,
       SUM(CASE WHEN registration_date IS NULL THEN 1 ELSE 0 END) AS null_registration_date,
       SUM(CASE WHEN platform          IS NULL THEN 1 ELSE 0 END) AS null_platform,
       SUM(CASE WHEN traffic_source    IS NULL THEN 1 ELSE 0 END) AS null_traffic_source,
       SUM(CASE WHEN city              IS NULL THEN 1 ELSE 0 END) AS null_city
FROM users;

-- 2.2 Дубли user_id в справочнике
SELECT user_id, COUNT(*)
FROM users
GROUP BY user_id
HAVING COUNT(*) > 1;

-- 2.3 Диапазон дат регистрации
SELECT MIN(registration_date) AS min_reg, MAX(registration_date) AS max_reg
FROM users;


-- 3.1 Пользователи из эксперимента, которых нет в users
SELECT COUNT(*) AS not_in_users
FROM ab_assignments a
LEFT JOIN users u ON u.user_id = a.user_id
WHERE u.user_id IS NULL;

-- 3.2 События пользователей, которых нет в эксперименте
SELECT COUNT(DISTINCT e.user_id) AS not_in_experiment
FROM events e
LEFT JOIN ab_assignments a ON a.user_id = e.user_id
WHERE a.user_id IS NULL;

-- 3.3 Заказы пользователей, которых нет в эксперименте
SELECT COUNT(*) AS not_in_experiment
FROM orders o
LEFT JOIN ab_assignments a ON a.user_id = o.user_id
WHERE a.user_id IS NULL;


-- 4.1 Пропуски
SELECT COUNT(*)                                             AS total_rows,
       SUM(CASE WHEN event_id   IS NULL THEN 1 ELSE 0 END)  AS null_event_id,
       SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END)  AS null_user_id,
       SUM(CASE WHEN event_time IS NULL THEN 1 ELSE 0 END)  AS null_event_time,
       SUM(CASE WHEN event_name IS NULL THEN 1 ELSE 0 END)  AS null_event_name
FROM events;

-- 4.2 Какие вообще бывают события и сколько их
SELECT event_name, COUNT(*) AS cnt, COUNT(DISTINCT user_id) AS users
FROM events
GROUP BY event_name
ORDER BY cnt DESC;

-- 4.3 Дубли событий
SELECT COUNT(*) - COUNT(DISTINCT event_id) AS extra_rows_by_event_id FROM events;

SELECT user_id, event_time, event_name, COUNT(*) AS cnt
FROM events
GROUP BY user_id, event_time, event_name
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 20;

-- 4.4 События раньше момента попадания в эксперимент
SELECT COUNT(*) AS before_asmnt
FROM events e
JOIN (SELECT user_id, MIN(assigned_at) AS assigned_at
      FROM ab_assignments GROUP BY user_id) a
  ON a.user_id = e.user_id
WHERE e.event_time < a.assigned_at;

-- 4.5 Активность на пользователя (максимальная активность)
SELECT user_id,
       COUNT(*) AS events_cnt,
       SUM(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS purchases
FROM events
GROUP BY user_id
ORDER BY events_cnt DESC
LIMIT 50;

SELECT user_id,
       COUNT(*) AS events_cnt, event_name
FROM events
GROUP BY event_name, user_id
HAVING COUNT(*) > 50
ORDER BY user_id
LIMIT 50;

-- 4.6 Как выглядит типичный пользователь
SELECT PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY cnt) AS median_events,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cnt) AS p95_events,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY cnt) AS p99_events,
       MAX(cnt)                                          AS max_events
FROM (SELECT user_id, COUNT(*) AS cnt FROM events GROUP BY user_id) t;


-- 5.1 Пропуски и некорректные значения
SELECT COUNT(*)                                                 AS total_rows,
       SUM(CASE WHEN user_id     IS NULL THEN 1 ELSE 0 END)     AS null_user_id,
       SUM(CASE WHEN revenue_rub IS NULL THEN 1 ELSE 0 END)     AS null_revenue,
       SUM(CASE WHEN items_count IS NULL THEN 1 ELSE 0 END)     AS null_items,
       SUM(CASE WHEN revenue_rub <= 0    THEN 1 ELSE 0 END)     AS nonpositive_revenue,
       SUM(CASE WHEN items_count <= 0    THEN 1 ELSE 0 END)     AS nonpositive_items
FROM orders;

-- 5.2 Дубли заказов
SELECT order_id, COUNT(*) FROM orders GROUP BY order_id HAVING COUNT(*) > 1;

-- 5.3 Распределение суммы заказа
SELECT MIN(revenue_rub)                                       AS min_rev,
       PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY revenue_rub) AS median_rev,
       AVG(revenue_rub)                                       AS mean_rev,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY revenue_rub) AS p99_rev,
       MAX(revenue_rub)                                       AS max_rev
FROM orders;

-- 5.4 Самые крупные заказы
SELECT *
FROM orders
ORDER BY revenue_rub DESC
LIMIT 20;

-- 5.5 Сходится ли число покупок в events и заказов в orders?
SELECT (SELECT COUNT(DISTINCT event_id) FROM events WHERE event_name = 'purchase') AS purchase_events,
       (SELECT COUNT(*) FROM orders)                                               AS orders_cnt;

-- 6 Временное окно эксперимента
SELECT 'assignments' AS tbl, MIN(assigned_at) AS min_t, MAX(assigned_at) AS max_t FROM ab_assignments
UNION ALL
SELECT 'events',      MIN(event_time), MAX(event_time) FROM events
UNION ALL
SELECT 'orders',      MIN(order_time), MAX(order_time) FROM orders;


-- 7 Баланс групп по признакам
SELECT a."group", u.platform,
       COUNT(DISTINCT a.user_id) AS users,
       ROUND(100.0 * COUNT(DISTINCT a.user_id)
             / SUM(COUNT(DISTINCT a.user_id)) OVER (PARTITION BY a."group"), 1) AS pct
FROM ab_assignments a
JOIN users u ON u.user_id = a.user_id
GROUP BY a."group", u.platform
ORDER BY u.platform, a."group";

SELECT a."group", u.traffic_source,
       COUNT(DISTINCT a.user_id) AS users,
       ROUND(100.0 * COUNT(DISTINCT a.user_id)
             / SUM(COUNT(DISTINCT a.user_id)) OVER (PARTITION BY a."group"), 1) AS pct
FROM ab_assignments a
JOIN users u ON u.user_id = a.user_id
GROUP BY a."group", u.traffic_source
ORDER BY u.traffic_source, a."group";


-- Итог: 60 пользователей в A и B группах одновременно; найдено 120 дублей активности; пользователи с ненормальной активностью