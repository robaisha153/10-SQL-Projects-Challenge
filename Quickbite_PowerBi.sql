-- =====================================================================
-- QuickBite: views that feed the Power BI dashboard  |  PostgreSQL
-- Run AFTER 01_dataset.sql and after creating v_order_items_clean and
-- v_master_orders in 02_questions_and_solutions.sql (Step 0 and Q9).
-- =====================================================================

SET search_path TO quickbite;

-- 1. Rider scorecard (same idea as Q4): one row per rider
CREATE OR REPLACE VIEW v_rider_scorecard AS
SELECT rider_name,
       city,
       COUNT(*)                                                         AS deliveries,
       COUNT(*) FILTER (WHERE delivery_flag = 'Late')                   AS late_deliveries,
       ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_flag = 'Late') / COUNT(*), 1) AS late_pct,
       ROUND(AVG(minutes_taken), 1)                                     AS avg_minutes
FROM v_master_orders
WHERE order_status = 'delivered'
GROUP BY rider_name, city;

-- 2. Weekly revenue (same idea as Q5): one row per week
CREATE OR REPLACE VIEW v_weekly_revenue AS
SELECT DATE_TRUNC('week', order_time)::date AS week_start,
       SUM(order_value)                     AS revenue,
       COUNT(*)                             AS delivered_orders
FROM v_master_orders
WHERE order_status = 'delivered'
GROUP BY 1;

-- 3. Customer spending groups (same idea as Q8): one row per customer who ordered
CREATE OR REPLACE VIEW v_customer_segments AS
WITH spend AS (
    SELECT customer_name, city, COUNT(*) AS orders, SUM(order_value) AS total_spent
    FROM v_master_orders
    WHERE order_status = 'delivered'
    GROUP BY customer_name, city
)
SELECT customer_name,
       city,
       orders,
       total_spent,
       NTILE(4) OVER (ORDER BY total_spent DESC) AS spend_quartile
FROM spend;

-- Quick checks
SELECT * FROM v_rider_scorecard ORDER BY late_pct DESC;
SELECT * FROM v_weekly_revenue ORDER BY week_start;
SELECT spend_quartile, COUNT(*) AS customers, SUM(total_spent) AS revenue
FROM v_customer_segments GROUP BY spend_quartile ORDER BY spend_quartile;
