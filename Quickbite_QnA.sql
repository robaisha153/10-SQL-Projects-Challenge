SET search_path TO quickbite;

--Step 0.1: Look for duplicate order lines
SELECT order_id, item_name, COUNT(*) AS times_listed
FROM order_items
GROUP BY order_id, item_name
HAVING COUNT(*) > 1;

--Step 0.2: Build a clean version of the table
CREATE OR REPLACE VIEW v_order_items_clean AS
SELECT DISTINCT ON (order_id, item_name)
       order_item_id, order_id, item_name, quantity, unit_price
FROM order_items
ORDER BY order_id, item_name, order_item_id;

--Step 0.3: Two quick data checks
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status;

--Expected: 71 delivered and 8 cancelled.
SELECT COUNT(*) AS customers_with_no_orders
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

--Q1: How much has each customer spent, including customers who never ordered?
SET 
SELECT c.customer_id,
       c.customer_name,
       COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_spent
FROM customers c
LEFT JOIN orders o
       ON o.customer_id = c.customer_id
      AND o.order_status = 'delivered'
LEFT JOIN v_order_items_clean oi
       ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name
ORDER BY total_spent DESC, c.customer_id;

--Q2: What share of delivered orders arrived on time vs late, and by how many minutes on average?
WITH delivered AS (
    SELECT order_id,
           promised_minutes,
           EXTRACT(EPOCH FROM (delivered_time - order_time)) / 60 AS minutes_taken
    FROM orders
    WHERE order_status = 'delivered'
)
SELECT CASE WHEN minutes_taken <= promised_minutes THEN 'On time' ELSE 'Late' END AS delivery_status,
       COUNT(*)                                                 AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct,
       ROUND(AVG(minutes_taken - promised_minutes)::numeric, 1) AS avg_minutes_vs_promise
FROM delivered
GROUP BY 1
ORDER BY 1 DESC;

--Q3: What is the best-selling item (by units) in each city?
WITH item_sales AS (
    SELECT c.city,
           oi.item_name,
           SUM(oi.quantity) AS units,
           DENSE_RANK() OVER (PARTITION BY c.city ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM orders o
    JOIN customers c            ON c.customer_id = o.customer_id
    JOIN v_order_items_clean oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.city, oi.item_name
)
SELECT city, item_name, units
FROM item_sales
WHERE rnk = 1
ORDER BY city;

--Q4: Rider scorecard

WITH delivered AS (
    SELECT order_id,
           rider_id,
           promised_minutes,
           EXTRACT(EPOCH FROM (delivered_time - order_time)) / 60 AS minutes_taken
    FROM orders
    WHERE order_status = 'delivered'
),
per_rider AS (
    SELECT r.rider_id,
           r.rider_name,
           r.city,
           COUNT(*)                                                      AS deliveries,
           COUNT(*) FILTER (WHERE d.minutes_taken > d.promised_minutes)  AS late_deliveries,
           ROUND(AVG(d.minutes_taken)::numeric, 1)                       AS avg_minutes
    FROM delivered d
    JOIN riders r ON r.rider_id = d.rider_id
    GROUP BY r.rider_id, r.rider_name, r.city
)
SELECT rider_name,
       city,
       deliveries,
       late_deliveries,
       ROUND(100.0 * late_deliveries / deliveries, 1) AS late_pct,
       avg_minutes,
       CASE WHEN 100.0 * late_deliveries / deliveries >
                 (SELECT 100.0 * SUM(late_deliveries) / SUM(deliveries) FROM per_rider)
            THEN 'Worse than average' ELSE 'OK' END   AS flag
FROM per_rider
ORDER BY late_pct DESC;

--Q5: Weekly delivered revenue and week-over-week % change

WITH order_totals AS (
    SELECT order_id, SUM(quantity * unit_price) AS order_value
    FROM v_order_items_clean
    GROUP BY order_id
),
weekly AS (
    SELECT DATE_TRUNC('week', o.order_time)::date AS week_start,
           SUM(ot.order_value)                    AS revenue
    FROM orders o
    JOIN order_totals ot ON ot.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT week_start,
       revenue,
       LAG(revenue) OVER (ORDER BY week_start) AS previous_week,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY week_start))
             / NULLIF(LAG(revenue) OVER (ORDER BY week_start), 0), 1) AS wow_change_pct
FROM weekly
ORDER BY week_start;

--Q6: Which customers ordered on 3 or more consecutive days?

WITH order_days AS (
    SELECT DISTINCT customer_id, order_time::date AS order_day
    FROM orders
    WHERE order_status = 'delivered'
),
grouped AS (
    SELECT customer_id,
           order_day,
           order_day - (ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_day))::int AS streak_group
    FROM order_days
)
SELECT customer_id,
       MIN(order_day) AS streak_start,
       MAX(order_day) AS streak_end,
       COUNT(*)       AS streak_days
FROM grouped
GROUP BY customer_id, streak_group
HAVING COUNT(*) >= 3
ORDER BY streak_days DESC, customer_id;

--Q7: Of customers who placed a delivered order, what % ordered again within 30 days of their first order?

WITH o AS (
    SELECT customer_id,
           order_time,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_time) AS rn,
           MIN(order_time) OVER (PARTITION BY customer_id)                  AS first_time
    FROM orders
    WHERE order_status = 'delivered'
)
SELECT COUNT(DISTINCT customer_id) AS customers_with_an_order,
       COUNT(DISTINCT customer_id) FILTER (
           WHERE rn = 2 AND order_time <= first_time + INTERVAL '30 days') AS reordered_within_30d,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (
           WHERE rn = 2 AND order_time <= first_time + INTERVAL '30 days')
           / COUNT(DISTINCT customer_id), 1) AS repeat_rate_pct
FROM o;

--Q8: Split customers into 4 spending groups. How much revenue does each bring?

WITH order_totals AS (
    SELECT order_id, SUM(quantity * unit_price) AS order_value
    FROM v_order_items_clean
    GROUP BY order_id
),
customer_spend AS (
    SELECT o.customer_id, SUM(ot.order_value) AS total_spent
    FROM orders o
    JOIN order_totals ot ON ot.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.customer_id
),
quartiles AS (
    SELECT customer_id,
           total_spent,
           NTILE(4) OVER (ORDER BY total_spent DESC) AS spend_quartile
    FROM customer_spend
)
SELECT spend_quartile,
       COUNT(*)                                                           AS customers,
       SUM(total_spent)                                                   AS revenue,
       ROUND(100.0 * SUM(total_spent) / SUM(SUM(total_spent)) OVER (), 1) AS pct_of_revenue
FROM quartiles
GROUP BY spend_quartile
ORDER BY spend_quartile;

--Q9 (Bonus 1): Build a master view

CREATE OR REPLACE VIEW v_master_orders AS
WITH order_totals AS (
    SELECT order_id, SUM(quantity * unit_price) AS order_value
    FROM v_order_items_clean
    GROUP BY order_id
)
SELECT o.order_id,
       c.customer_name,
       c.city,
       r.rider_name,
       o.order_time,
       o.order_status,
       ot.order_value,
       ROUND(EXTRACT(EPOCH FROM (o.delivered_time - o.order_time)) / 60) AS minutes_taken,
       CASE
           WHEN o.order_status = 'cancelled' THEN 'Cancelled'
           WHEN EXTRACT(EPOCH FROM (o.delivered_time - o.order_time)) / 60 > o.promised_minutes THEN 'Late'
           ELSE 'On time'
       END AS delivery_flag,
       o.promo_code
FROM orders o
JOIN customers c     ON c.customer_id = o.customer_id
JOIN riders r        ON r.rider_id = o.rider_id
JOIN order_totals ot ON ot.order_id = o.order_id;

--Q10 (Bonus 2): Number each customer's orders, with NULL for cancelled orders

SELECT customer_name,
       order_time,
       order_status,
       order_value,
       CASE WHEN order_status = 'cancelled' THEN NULL
            ELSE RANK() OVER (PARTITION BY customer_name, order_status ORDER BY order_time)
       END AS order_number
FROM v_master_orders
ORDER BY customer_name, order_time;