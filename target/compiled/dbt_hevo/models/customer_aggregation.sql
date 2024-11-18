WITH customer_orders AS (
    SELECT
        c.id AS customer_id,
        c.first_name,
        c.last_name,
        MIN(o.order_date) AS first_order,
        MAX(o.order_date) AS most_recent_order,
        COUNT(o.id) AS number_of_orders
    FROM HEVO_DB.HEVO_SCHEMA.raw_customers c
    LEFT JOIN HEVO_DB.HEVO_SCHEMA.raw_orders o
    ON c.id = o.user_id
    GROUP BY c.id, c.first_name, c.last_name
),
customer_lifetime_value AS (
    SELECT
        o.user_id AS customer_id,
        SUM(p.amount) AS customer_lifetime_value
    FROM HEVO_DB.HEVO_SCHEMA.raw_orders o
    LEFT JOIN HEVO_DB.HEVO_SCHEMA.raw_payments p
    ON o.id = p.order_id
    GROUP BY o.user_id
)
SELECT
    co.customer_id,
    co.first_name,
    co.last_name,
    co.first_order,
    co.most_recent_order,
    co.number_of_orders,
    clv.customer_lifetime_value
FROM customer_orders co
LEFT JOIN customer_lifetime_value clv
ON co.customer_id = clv.customer_id