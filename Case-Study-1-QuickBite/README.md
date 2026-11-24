🍔 Case Study #1: QuickBite
<p align="center">
  <img src="https://github.com/user-attachments/assets/b876c914-1b4d-46ea-9353-a733419b6643" width="100%" alt="QuickBite - Food Delivery SQL Case Study">
</p>
## 📚 Table of Contents

* [Business Task](#business-task)
* [Entity Relationship Diagram](#entity-relationship-diagram)
* [Question and Solution](#question-and-solution)
* [Dashboard](#dashboard)

Please note that QuickBite is a fictional business and all of the data was created for SQL practice. This case study is Project #1 of my [10-SQL-Projects-Challenge](https://github.com/robaisha153/10-SQL-Projects-Challenge), but the data and questions are original.

---

## Business Task

QuickBite is a food-delivery startup that delivers orders to customers in Lahore, Karachi and Islamabad. The owner wants to use the data to answer a few important questions about the business, especially how much money customers spend, how reliable the deliveries are, which riders are running late, and how revenue changes from week to week.

---

## Entity Relationship Diagram

<p align="center">
  <img src="https://github.com/user-attachments/assets/c767e0e1-4dd7-43ff-86d6-92d4cd0326cc" width="100%" alt="QuickBite Entity Relationship Diagram">
</p>
---

## Question and Solution
You can run these queries in PostgreSQL. The full script is in Quickbite_QnA.sql.

Step 0: Clean the data

Before answering the questions I checked the data for problems.

Look for duplicate order lines

sql
SELECT order_id, item_name, COUNT(*) AS times_listed
FROM order_items
GROUP BY order_id, item_name
HAVING COUNT(*) > 1;
order_id	item_name	times_listed
1004	Garlic Naan	2

Build a clean version of the table

sql
CREATE OR REPLACE VIEW v_order_items_clean AS
SELECT DISTINCT ON (order_id, item_name)
       order_item_id, order_id, item_name, quantity, unit_price
FROM order_items
ORDER BY order_id, item_name, order_item_id;

Check the order statuses and customers with no orders

sql
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status;

SELECT COUNT(*) AS customers_with_no_orders
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

Answer:

Order 1004 lists Garlic Naan twice, so I built the view v_order_items_clean, which keeps one row per item in each order, and used it in every question below. I also checked the order statuses: there are 71 delivered and 8 cancelled orders, and 1 customer has never ordered.

1. How much has each customer spent, including customers who never ordered?
sql
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

Steps:

Start from customers and use a LEFT JOIN to orders, so customers with no orders are kept.
Put the delivered filter inside the join condition. If it were in WHERE, customers with no delivered orders would disappear.
Join v_order_items_clean (the cleaned order lines) and calculate quantity * unit_price.
Use SUM with COALESCE(..., 0) so customers with no orders show 0 instead of NULL.

Answer:

customer_id	customer_name	total_spent
3	Sana Malik	10120
6	Usman Tariq	8620
4	Hamza Ali	7720
7	Zara Hussain	7360
8	Daniyal Raza	7320
2	Bilal Ahmed	6270
1	Ayesha Khan	5660
9	Mehwish Iqbal	5510
11	Hira Aslam	4290
5	Fatima Noor	3710
10	Talha Sheikh	3240
14	Ali Raza	2970
13	Noor Fatima	2950
15	Maryam Saeed	2880
12	Saad Mirza	1910
18	Kamran Shah	1770
19	Laiba Chaudhry	1170
16	Faizan Butt	930
17	Iqra Javed	650
20	Omar Farooq	0
Sana Malik is the top spender with PKR 10,120, followed by Usman Tariq (8,620) and Hamza Ali (7,720).
Omar Farooq has never placed an order, so he shows 0.
2. What share of delivered orders arrived on time vs late, and by how many minutes on average?
sql
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

Steps:

In a CTE, calculate minutes_taken as the difference between delivered_time and order_time, using EXTRACT(EPOCH ...) / 60.
Label each delivered order On time if minutes_taken <= promised_minutes, otherwise Late.
Count the orders in each group and use SUM(COUNT(*)) OVER () to turn the counts into percentages.
Take the average of minutes_taken - promised_minutes. A negative value means the order arrived early.

Answer:

delivery_status	orders	pct	avg_minutes_vs_promise
On time	48	67.6	-6.9
Late	23	32.4	12.3
67.6% of delivered orders (48) arrived on time, and on average they came 6.9 minutes early.
32.4% (23 orders) were late, by 12.3 minutes on average.
3. What is the best-selling item (by units) in each city?
sql
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

Steps:

Join orders, customers and v_order_items_clean to connect each item to the customer's city.
Sum the quantity for every city and item.
Use DENSE_RANK() partitioned by city and ordered by units, so ties for first place are both kept.
Keep only rank 1.

Answer:

city	item_name	units
Islamabad	Pasta Alfredo	19
Karachi	Cold Drink	8
Karachi	Fries	8
Lahore	Beef Burger	10
Islamabad: Pasta Alfredo leads with 19 units.
Lahore: Beef Burger leads with 10 units.
Karachi has a tie between Cold Drink and Fries at 8 units each, which is why DENSE_RANK() is used instead of ROW_NUMBER().
4. Rider scorecard: how many deliveries did each rider make, how many were late, and who is worse than average?
sql
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

Steps:

In a CTE, calculate minutes_taken for every delivered order.
In a second CTE, group by rider and count deliveries, late deliveries (with COUNT(*) FILTER (WHERE ...)) and average minutes.
Calculate late_pct for each rider.
Compare each rider's late % with the overall late % (a subquery) and flag the riders who are worse than average.

Answer:

rider_name	city	deliveries	late_deliveries	late_pct	avg_minutes	flag
Rider Adeel	Karachi	10	10	100.0	55.7	Worse than average
Rider Imran	Lahore	13	5	38.5	35.7	Worse than average
Rider Shahid	Karachi	8	2	25.0	33.3	OK
Rider Waqas	Islamabad	12	2	16.7	33.3	OK
Rider Junaid	Islamabad	20	3	15.0	33.7	OK
Rider Kashif	Lahore	8	1	12.5	39.1	OK
Rider Adeel (Karachi) was late on all 10 deliveries (100%), with an average of 55.7 minutes per delivery.
Rider Imran (Lahore) is the second-worst at 38.5% late, and the other four riders are at 25% or below.
Adeel and Imran are the two riders flagged as worse than the overall average.
5. Weekly delivered revenue and week-over-week % change
sql
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

Steps:

In order_totals, calculate the value of each order from the cleaned order lines.
Group delivered orders by week with DATE_TRUNC('week', order_time) and sum the revenue.
Use LAG(revenue) to get the previous week's revenue.
Calculate the % change as (this week - last week) / last week, with NULLIF to avoid dividing by zero.

Answer:

week_start	revenue	previous_week	wow_change_pct
2026-08-17	6160	NULL	NULL
2026-08-24	3920	6160	-36.4
2026-08-31	8960	3920	128.6
2026-09-07	11560	8960	29.0
2026-09-14	10600	11560	-8.3
2026-09-21	12430	10600	17.3
2026-09-28	8500	12430	-31.6
2026-10-05	11790	8500	38.7
2026-10-12	6970	11790	-40.9
2026-10-19	3170	6970	-54.5
2026-10-26	990	3170	-68.8
Revenue peaked in the week of 2026-09-21 at PKR 12,430.
It then dropped for three weeks in a row, ending at PKR 990 for the week of 2026-10-26.
The last week only has two days of data (26 and 27 October), so its drop is partly because the data ends there.
6. Which customers ordered on 3 or more consecutive days?
sql
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

Steps:

Get each customer's distinct delivered order days.
Subtract ROW_NUMBER() from the order day. Days in a row give the same result, which becomes a streak_group.
Group by customer and streak_group to find the start, end and length of each streak.
Keep streaks with HAVING COUNT(*) >= 3.

Answer:

customer_id	streak_start	streak_end	streak_days
3	2026-09-06	2026-09-08	3
5	2026-10-20	2026-10-22	3
6	2026-09-23	2026-09-25	3
Three customers ordered 3 days in a row: customer 3 (Sana Malik, 6 to 8 September), customer 5 (Fatima Noor, 20 to 22 October) and customer 6 (Usman Tariq, 23 to 25 September).
7. Of customers who placed a delivered order, what % ordered again within 30 days of their first order?
sql
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

Steps:

Number each customer's delivered orders with ROW_NUMBER() and find their first order time with MIN(order_time) OVER (...).
A customer counts as a repeat customer if their second order (rn = 2) happened within 30 days of the first one.
Count those customers with COUNT(DISTINCT ...) FILTER (...) and divide by all customers who ordered.

Answer:

customers_with_an_order	reordered_within_30d	repeat_rate_pct
19	15	78.9
15 of the 19 customers who ordered came back within 30 days, a repeat rate of 78.9%.
8. Split customers into 4 spending groups. How much revenue does each group bring?
sql
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

Steps:

Calculate each customer's total delivered spend.
Use NTILE(4) ordered by spend (highest first) to split the customers into 4 equal groups. Group 1 is the top spenders.
Count the customers and sum the revenue in each group.
Use SUM(SUM(...)) OVER () to get each group's share of total revenue.

Answer:

spend_quartile	customers	revenue	pct_of_revenue
1	5	41140	48.4
2	5	25440	29.9
3	5	13950	16.4
4	4	4520	5.3
The top 5 customers (group 1) bring 48.4% of all revenue (PKR 41,140).
The bottom 4 customers (group 4) bring only 5.3%.
This means almost half of QuickBite's revenue depends on a small group of customers.
BONUS QUESTIONS
Join All The Things

Build one master view with everything about an order: customer, rider, order value, time taken and whether the delivery was on time.

sql
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

Answer: the first 6 rows of v_master_orders:

order_id	customer_name	city	rider_name	order_time	order_status	order_value	minutes_taken	delivery_flag	promo_code
1001	Sana Malik	Islamabad	Rider Waqas	2026-08-22 22:36	delivered	2810	34	On time	WELCOME20
1002	Ali Raza	Karachi	Rider Adeel	2026-08-23 19:55	delivered	1320	63	Late	WELCOME20
1003	Maryam Saeed	Islamabad	Rider Junaid	2026-08-23 22:40	delivered	2030	47	Late	WELCOME20
1004	Daniyal Raza	Islamabad	Rider Waqas	2026-08-26 14:04	delivered	1810	28	On time	NULL
1005	Bilal Ahmed	Karachi	Rider Shahid	2026-08-27 13:27	delivered	700	31	On time	WELCOME20
1006	Zara Hussain	Lahore	Rider Kashif	2026-08-29 13:05	delivered	1410	47	Late	NULL
Rank All The Things

Number each customer's orders by date, with NULL for cancelled orders.

sql
SELECT customer_name,
       order_time,
       order_status,
       order_value,
       CASE WHEN order_status = 'cancelled' THEN NULL
            ELSE RANK() OVER (PARTITION BY customer_name, order_status ORDER BY order_time)
       END AS order_number
FROM v_master_orders
ORDER BY customer_name, order_time;

Answer: the first 12 of 79 rows:

customer_name	order_time	order_status	order_value	order_number
Ali Raza	2026-08-23 19:55:00	delivered	1320	1
Ali Raza	2026-09-01 12:16:00	delivered	1650	2
Ayesha Khan	2026-09-30 13:13:00	delivered	1930	1
Ayesha Khan	2026-10-09 20:47:00	delivered	1270	2
Ayesha Khan	2026-10-18 12:55:00	delivered	1570	3
Ayesha Khan	2026-10-27 18:16:00	delivered	890	4
Bilal Ahmed	2026-08-27 13:27:00	delivered	700	1
Bilal Ahmed	2026-09-08 13:53:00	delivered	360	2
Bilal Ahmed	2026-09-20 22:58:00	cancelled	220	NULL
Bilal Ahmed	2026-09-22 16:15:00	delivered	2050	3
Bilal Ahmed	2026-10-01 20:08:00	delivered	1500	4
Bilal Ahmed	2026-10-06 23:44:00	delivered	1480	5
Cancelled orders get NULL instead of a number, and each customer's numbering restarts at 1.

---
## Dashboard

<p align="center">
  <a href="https://robaisha153.github.io/10-SQL-Projects-Challenge/Case-Study-1-QuickBite/quickbite-dashboard.html">
    <img src="https://github.com/user-attachments/assets/c9ffa868-6139-44de-b492-44cf89576886" width="100%" alt="QuickBite Dashboard">
  </a>
</p>

