/*========================================================
 -- 1. Sales, revenue, and freight trends grouped by month
 ==========================================================*/
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(i.price), 2) AS gross_revenue,
    ROUND(SUM(i.freight_value), 2) AS total_freight
FROM olist_orders_dataset o
INNER JOIN olist_order_items_dataset i 
    ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY total_orders DESC;


/*=======================================================================
-- 2. Map product IDs to Portuguese names and their English translations
==========================================================================*/
SELECT 
    p.product_id,
    p.product_category_name AS portuguese_name,
    t.product_category_name_english AS english_name
FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t 
    ON p.product_category_name = t.product_category_name;


/*==================================================================================
-- 3. Check pipeline health: count orders and track missing delivery dates by status
====================================================================================*/
SELECT 
    order_status,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivery_dates
FROM olist_orders_dataset
GROUP BY order_status;



/*=====================================================================
-- 4. Top 5 product categories by total volume (translated to English)
=======================================================================*/
WITH product_counts AS (
    SELECT 
        product_id, 
        COUNT(DISTINCT order_id) AS total_orders
    FROM olist_order_items_dataset
    GROUP BY product_id
),
category_counts AS (
    SELECT 
        p.product_category_name,
        SUM(pc.total_orders) AS total_orders
    FROM product_counts pc
    INNER JOIN olist_products_dataset p 
        ON pc.product_id = p.product_id
    GROUP BY p.product_category_name
)
SELECT 
    t.product_category_name_english AS category_name,
    c.total_orders
FROM category_counts c
INNER JOIN product_category_name_translation t 
    ON c.product_category_name = t.product_category_name
ORDER BY total_orders DESC
LIMIT 5;



/*========================================================
-- 5. Top 5 product categories by total gross revenue
==========================================================*/
WITH product_financials AS (
    SELECT 
        product_id, 
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(price) AS gross_revenue
    FROM olist_order_items_dataset
    GROUP BY product_id
),
category_financials AS (
    SELECT 
        p.product_category_name,
        SUM(pf.total_orders) AS total_orders,
        ROUND(SUM(pf.gross_revenue), 2) AS total_revenue
    FROM product_financials pf
    INNER JOIN olist_products_dataset p 
        ON pf.product_id = p.product_id
    GROUP BY p.product_category_name
)
SELECT 
    t.product_category_name_english AS category_name,
    c.total_orders,
    c.total_revenue
FROM category_financials c
INNER JOIN product_category_name_translation t 
    ON c.product_category_name = t.product_category_name
ORDER BY total_revenue DESC
LIMIT 5;



/*====================================================================================
-- 6. Calculate financial exposure and order volume trapped in non-successful statuses
======================================================================================*/
WITH total_financial_exposure AS (
    SELECT 
        ood.order_status, 
        COUNT(DISTINCT ood.order_id) AS total_orders, 
        ROUND(SUM(oopd.payment_value), 2) AS total_amount
    FROM olist_orders_dataset ood 
    LEFT JOIN olist_order_payments_dataset oopd 
        ON ood.order_id = oopd.order_id 
    GROUP BY ood.order_status
)
SELECT 
    order_status,
    total_orders,
    total_amount,
    ROUND(total_amount * 100.0 / SUM(total_amount) OVER(), 2) AS pct_of_total
FROM total_financial_exposure
ORDER BY total_amount DESC;



/*=====================================================================
-- 7. Average delivery speed (purchase to arrival) broken down by year
=======================================================================*/
SELECT 
    YEAR(order_purchase_timestamp) AS purchase_year,
    COUNT(order_id) AS total_clean_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
GROUP BY YEAR(order_purchase_timestamp)
ORDER BY purchase_year ASC;



/*====================================================================================================================================
-- 8. 2018 Logistics Drill-down: Rank customer states from slowest to fastest delivery
-- Note for the viewers: Filtered to 2018 for data consistency. Modify or remove the YEAR() filter in the WHERE clause to analyze different periods.
=======================================================================================================================================*/ 
SELECT 
    ocd.customer_state, 
    ROUND(AVG(DATEDIFF(ood.order_delivered_customer_date, ood.order_purchase_timestamp)), 2) AS avg_delivery_time
FROM olist_orders_dataset ood 
LEFT JOIN olist_customers_dataset ocd 
    ON ood.customer_id = ocd.customer_id 
WHERE YEAR(ood.order_purchase_timestamp) = 2018 
  AND ood.order_delivered_customer_date IS NOT NULL
GROUP BY ocd.customer_state 
ORDER BY avg_delivery_time DESC;



/*==================================================================================================================================
-- 9. Combined 2018 regional analysis: delivery speeds vs. order volumes and revenue share
-- Note for the viewers: Set to 2018 to evaluate peak operations. The YEAR() filters inside both CTE WHERE clauses can be adjusted for other years.
=====================================================================================================================================*/

WITH logistics_speeds AS (
    SELECT 
        ocd.customer_state,
        ROUND(AVG(DATEDIFF(ood.order_delivered_customer_date, ood.order_purchase_timestamp)), 1) AS avg_delivery_days
    FROM olist_orders_dataset ood
    INNER JOIN olist_customers_dataset ocd 
        ON ood.customer_id = ocd.customer_id
    WHERE YEAR(ood.order_purchase_timestamp) = 2018
      AND ood.order_status = 'delivered'
      AND ood.order_delivered_customer_date IS NOT NULL
    GROUP BY ocd.customer_state
),
financial_totals AS (
    SELECT 
        ocd.customer_state,
        COUNT(DISTINCT ood.order_id) AS total_orders,
        ROUND(SUM(oi.price), 2) AS total_revenue
    FROM olist_orders_dataset ood
    INNER JOIN olist_customers_dataset ocd 
        ON ood.customer_id = ocd.customer_id
    INNER JOIN olist_order_items_dataset oi 
        ON ood.order_id = oi.order_id
    WHERE YEAR(ood.order_purchase_timestamp) = 2018
    GROUP BY ocd.customer_state
)
SELECT 
    f.customer_state,
    f.total_orders,
    f.total_revenue,
    ROUND(f.total_revenue * 100.0 / SUM(f.total_revenue) OVER(), 2) AS revenue_percentage,
    l.avg_delivery_days
FROM financial_totals f
INNER JOIN logistics_speeds l 
    ON f.customer_state = l.customer_state
ORDER BY l.avg_delivery_days DESC;



/*=================================================================================
-- 10. Customer purchase frequency matrix (identifying one-time vs. repeat buyers)
===================================================================================*/
WITH customer_purchase_counts AS (
    SELECT 
        ocd.customer_unique_id AS unique_customer_id, 
        COUNT(DISTINCT ood.order_id) AS total_orders_placed
    FROM olist_orders_dataset ood 
    LEFT JOIN olist_customers_dataset ocd 
        ON ood.customer_id = ocd.customer_id 
    GROUP BY ocd.customer_unique_id
)
SELECT 
    cpc.total_orders_placed AS purchase_frequency, 
    COUNT(cpc.unique_customer_id) AS total_unique_customers
FROM customer_purchase_counts cpc
GROUP BY cpc.total_orders_placed
ORDER BY purchase_frequency ASC;



/*=========================================================================
-- 11. Identify the 10 worst-rated marketplace sellers (minimum 50 reviews)
===========================================================================*/
SELECT 
    oi.seller_id,
    COUNT(DISTINCT oord.review_id) AS total_reviews_received,
    ROUND(AVG(oord.review_score), 2) AS avg_review_score
FROM olist_order_items_dataset oi
INNER JOIN olist_order_reviews_dataset oord 
    ON oi.order_id = oord.order_id
INNER JOIN olist_orders_dataset ood 
    ON oi.order_id = ood.order_id
WHERE ood.order_status = 'delivered'
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oord.review_id) >= 50
ORDER BY avg_review_score ASC
LIMIT 10;



/*==================================================================================================================================
-- 12. 2018 Shipping Costs: Compare true order delivery durations against average freight costs by state
-- Note for the viewers: Focused on 2018 to track stable freight trends. The YEAR() filter in the base CTE can be customized to change the timeline.
=====================================================================================================================================*/
WITH order_freight_totals AS (
    SELECT 
        oi.order_id,
        SUM(oi.freight_value) AS total_order_freight_cost
    FROM olist_order_items_dataset oi
    GROUP BY oi.order_id
),
state_logistics_base AS (
    SELECT 
        ood.order_id,
        ocd.customer_state,
        DATEDIFF(ood.order_delivered_customer_date, ood.order_purchase_timestamp) AS order_delivery_days
    FROM olist_orders_dataset ood
    INNER JOIN olist_customers_dataset ocd 
        ON ood.customer_id = ocd.customer_id
    WHERE YEAR(ood.order_purchase_timestamp) = 2018
      AND ood.order_status = 'delivered'
      AND ood.order_delivered_customer_date IS NOT NULL
)
SELECT 
    slb.customer_state,
    COUNT(slb.order_id) AS total_orders,
    ROUND(AVG(slb.order_delivery_days), 1) AS avg_delivery_days,
    ROUND(AVG(oft.total_order_freight_cost), 2) AS avg_freight_cost_per_order,
    ROUND(SUM(oft.total_order_freight_cost), 2) AS total_freight_bill
FROM state_logistics_base slb
INNER JOIN order_freight_totals oft 
    ON slb.order_id = oft.order_id
GROUP BY slb.customer_state
ORDER BY avg_delivery_days DESC;



/*============================================================================================
-- 13. Catalog audit: Find English product categories handled by the 10 lowest-rated sellers
==============================================================================================*/
WITH low_quality_sellers AS (
    SELECT 
        oi.seller_id,
        ROUND(AVG(oord.review_score), 2) AS avg_review_score
    FROM olist_order_items_dataset oi
    INNER JOIN olist_order_reviews_dataset oord 
        ON oi.order_id = oord.order_id
    GROUP BY oi.seller_id
    HAVING COUNT(DISTINCT oord.review_id) >= 50
    ORDER BY avg_review_score ASC
    LIMIT 10
)
SELECT 
    lqs.seller_id,
    lqs.avg_review_score,
    oi.product_id,
    pct.product_category_name_english AS product_category
FROM low_quality_sellers lqs
INNER JOIN olist_order_items_dataset oi 
    ON lqs.seller_id = oi.seller_id
INNER JOIN olist_products_dataset opd 
    ON oi.product_id = opd.product_id
INNER JOIN product_category_name_translation pct 
    ON opd.product_category_name = pct.product_category_name
GROUP BY lqs.seller_id, lqs.avg_review_score, oi.product_id, pct.product_category_name_english
ORDER BY lqs.avg_review_score ASC;