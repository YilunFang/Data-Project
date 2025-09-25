-- ============================
-- SALES DATA ANALYSIS PROJECT
-- ============================

-- =====================
-- 1. Create Customers Table
-- =====================
CREATE TABLE customers (
    customer_id VARCHAR(30) PRIMARY KEY,
    customer_name VARCHAR(100) 
);

-- =====================
-- 2. Create Orders Table
-- =====================
-- Relationships:
--   - customer_id → customers.customer_id (many-to-one)
--   - postal_code → locations.postal_code (many-to-one)
--   - product_id → products.product_id (many-to-one)
CREATE TABLE orders (
    row_id SERIAL PRIMARY KEY,
    order_id VARCHAR(20),
    order_date DATE,
    ship_date DATE,
    ship_mode VARCHAR(20),
    customer_id VARCHAR(20),
    segment VARCHAR(20),
    postal_code INT,
    product_id VARCHAR(20),
    sales NUMERIC,
    quantity INT,
    discount NUMERIC,
    profit NUMERIC
);

-- =====================
-- 3. Create Locations Table
-- =====================
-- DROP Table IF EXISTS locations; 
CREATE TABLE locations (
    postal_code VARCHAR(50),
    city VARCHAR(50),
    state VARCHAR(50),
    region VARCHAR(50),
    country_region VARCHAR(50)
);

-- DELETE FROM locations
-- WHERE postal_code = 'NA';

-- Alter the postal_code into INT
ALTER TABLE locations 
ALTER COLUMN postal_code TYPE INTEGER
USING postal_code::integer;

-- =====================
-- 4. Create Products Table
-- =====================
CREATE TABLE products (
    product_id VARCHAR(50),
    category VARCHAR(70),
    sub_category VARCHAR(50),
    product_name VARCHAR(250)
)
DELETE FROM products
WHERE product_id = 'Product ID';

-- =============================
-- Referential Integrity Check
-- =============================
-- Check for broken FK relationships (nulls in joined fields)
SELECT 
	*
FROM orders AS O
LEFT JOIN products P ON O.product_id = P.product_id
LEFT JOIN customers C ON O.customer_id = C.customer_id
LEFT JOIN locations L ON O.postal_code = L.postal_code
WHERE product_name IS NULL OR customer_name IS NULL OR city IS NULL;

-- END OF TABLE CREATING AND DATA CLEANING

-- =============================
-- BUSINESS ANALYSIS QUERIES
-- =============================

-- 1. Monthly Sales Trend (Change to profit or quantity as needed)
SELECT
    TO_CHAR(order_date, 'YYYY-MM') AS year_month,
    ROUND(SUM(sales),2) AS monthly_sales
FROM orders
WHERE TO_CHAR(order_date, 'YYYY') = '2020'
GROUP BY year_month
ORDER BY year_month ASC;

-- 2. Month-over-Month Sales Growth by Region
WITH CTE1 AS (
	SELECT 
		SUM(sales) AS current_mon_sales,
		TO_CHAR(order_date, 'YYYY-MM') AS year_month,
		region
	FROM orders AS O
	LEFT JOIN locations AS L ON O.postal_code = L.postal_code
	GROUP BY region, year_month
	ORDER BY region ASC, year_month ASC
)
, CTE2 AS (
	SELECT 
		current_mon_sales,
		LAG(current_mon_sales,1) OVER(PARTITION BY region ORDER BY year_month ASC) AS last_mon_sales,
	--current_mon_sales - last_mon_sales AS sales_dif,
		year_month,
		region
	FROM CTE1
)
SELECT
	region,
	year_month,
	ROUND(100*(current_mon_sales - last_mon_sales)/last_mon_sales,2) AS monthly_growth_rate
FROM CTE2;

-- 3. Profitability by Category → Sub-Category (Waterfall)
SELECT 
	P.category,
	P.sub_category,
	ROUND(SUM(O.profit),2) AS total_profit
FROM 
	orders AS O
LEFT JOIN products AS P ON O.product_id = P.product_id
WHERE TO_CHAR(O.order_date, 'YYYY') = '2021'
GROUP BY P.category, P.sub_category
ORDER BY total_profit DESC;

-- 4. Top N Products by Profit per Region (Change N as needed)
WITH CTE AS (SELECT 
	L.region,
	P.product_name,
	ROUND(SUM(profit),2) AS total_profit,
	DENSE_RANK() OVER(PARTITION BY region ORDER BY SUM(profit) DESC) AS RN
FROM orders O
LEFT JOIN products P ON O.product_id = P.product_id
LEFT JOIN locations L ON O.postal_code =L.postal_code
GROUP BY region,product_name
ORDER BY region ASC
)
SELECT
	region,
	product_name,
	total_profit,
	rn
FROM CTE
WHERE RN <= 5;
-- change N to some other numbers

-- 5.1 Top Customers by Total Sales
SELECT 
	C.customer_id,
	C.customer_name,
	SUM(O.sales) AS total_sales_per_customer
FROM orders O
LEFT JOIN customers C ON O.customer_id = C.customer_id
GROUP BY C.customer_id
ORDER BY total_sales_per_customer DESC
LIMIT 100;

-- 5.2 12-Month Rolling Sales per Customer
WITH CTE AS(
	SELECT 
		O.customer_id, 
		C.customer_name,
		O.order_date,
		ROUND(SUM(O.sales),2) AS daily_sales
	FROM orders O
	LEFT JOIN customers C ON O.customer_id = C.customer_id
	GROUP BY O.order_date, O.customer_id, C.customer_name
	ORDER BY O.order_date ASC
),
roll AS(
	SELECT
		customer_id,
		customer_name,
		order_date,
		SUM(daily_sales) OVER(PARTITION BY customer_id ORDER BY order_date ASC
		RANGE BETWEEN INTERVAL '12 MONTHS' PRECEDING AND CURRENT ROW) AS rolling_sum_12M
	FROM CTE
	WHERE TO_CHAR(order_date, 'YYYY') = '2023'
	-- Date is changeable 
)
SELECT
	customer_id,
	order_date,
	MAX(rolling_sum_12M) AS Highest_rolling
FROM roll
GROUP BY order_date, customer_id
ORDER BY highest_rolling DESC;

-- 6. Product Sales vs Average (Relative Performance)
WITH sales AS (
	SELECT
		product_name,
		ROUND(SUM(sales),2) AS product_sales
	FROM 
		orders O
	LEFT JOIN products P on O.product_id = P.product_id
	WHERE TO_CHAR(order_date, 'YYYY') = '2023'
	GROUP BY product_name
)
SELECT 
	product_name,
	product_sales,
	ROUND(100*(product_sales - (SELECT AVG(product_sales) FROM sales))/(SELECT AVG(product_sales) FROM sales),2)
	AS pct_diff_from_avg_sales,
	CASE 
		WHEN product_sales > (SELECT AVG(product_sales) FROM sales) THEN 'Above the average'
		ELSE 'Below the average'
		END AS sales_performance
FROM sales
ORDER BY pct_diff_from_avg_sales DESC;

-- 7. Average Shipping Time by Shipping Mode
SELECT
	ship_mode,
	ROUND(AVG(ship_date - order_date),0) AS average_ship_time_days
FROM orders
GROUP BY ship_mode
ORDER BY average_ship_time_days ASC;
	
-- 8. Impact of Discounts and Shipping on Profit Margins
SELECT 
	ship_mode,
	CASE 
        WHEN discount = 0 THEN 'No Discount'
        WHEN discount > 0 AND discount <= 0.1 THEN 'Low (0-10%)'
        WHEN discount > 0.1 AND discount <= 0.3 THEN 'Medium (10-30%)'
        ELSE 'High (>30%)'
    END AS discount_band,
    ROUND(SUM(sales),2) AS total_sales,
    ROUND(SUM(profit),2) AS total_profit,
    ROUND(100*SUM(profit) / SUM(sales),2) AS profit_margin_pct
FROM orders
GROUP BY ship_mode, discount_band
ORDER BY ship_mode ASC, discount_band ASC;





