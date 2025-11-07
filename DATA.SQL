/*
=============================================================
Create Database and Schemas
=============================================================
Script Purpose:
    This script creates a new database named 'DataWarehouseAnalytics' after checking if it already exists. 
    If the database exists, it is dropped and recreated. Additionally, this script creates a schema called gold
	
WARNING:
    Running this script will drop the entire 'DataWarehouseAnalytics' database if it exists. 
    All data in the database will be permanently deleted. Proceed with caution 
    and ensure you have proper backups before running this script.
*/

USE master;
GO

-- Drop and recreate the 'DataWarehouseAnalytics' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouseAnalytics')
BEGIN
    ALTER DATABASE DataWarehouseAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouseAnalytics;
END;
GO

-- Create the 'DataWarehouseAnalytics' database
CREATE DATABASE DataWarehouseAnalytics;
GO

USE DataWarehouseAnalytics;
GO

-- Create Schemas

CREATE SCHEMA gold;
GO

CREATE TABLE gold.dim_customers(
	customer_key int,
	customer_id int,
	customer_number nvarchar(50),
	first_name nvarchar(50),
	last_name nvarchar(50),
	country nvarchar(50),
	marital_status nvarchar(50),
	gender nvarchar(50),
	birthdate date,
	create_date date
);
GO

CREATE TABLE gold.dim_products(
	product_key int ,
	product_id int ,
	product_number nvarchar(50) ,
	product_name nvarchar(50) ,
	category_id nvarchar(50) ,
	category nvarchar(50) ,
	subcategory nvarchar(50) ,
	maintenance nvarchar(50) ,
	cost int,
	product_line nvarchar(50),
	start_date date 
);
GO

CREATE TABLE gold.fact_sales(
	order_number nvarchar(50),
	product_key int,
	customer_key int,
	order_date date,
	shipping_date date,
	due_date date,
	sales_amount int,
	quantity tinyint,
	price int 
);
GO

TRUNCATE TABLE gold.dim_customers;
GO

BULK INSERT gold.dim_customers
FROM 'C:\Users\tejas\Downloads\sql-data-analytics-project (1)\sql-data-analytics-project\datasets\csv-files\gold.dim_customers.csv'
WITH (
	FIRSTROW = 2,
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO

TRUNCATE TABLE gold.dim_products;
GO

BULK INSERT gold.dim_products
FROM 'C:\Users\tejas\Downloads\sql-data-analytics-project (1)\sql-data-analytics-project\datasets\csv-files\gold.dim_products.csv'
WITH (
	FIRSTROW = 2,
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO

TRUNCATE TABLE gold.fact_sales;
GO

BULK INSERT gold.fact_sales
FROM 'C:\Users\tejas\Downloads\sql-data-analytics-project (1)\sql-data-analytics-project\datasets\csv-files\gold.fact_sales.csv'
WITH (
	FIRSTROW = 2,
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO
CREATE VIEW gold.report_customers AS
--calculating changes over time
SELECT 
YEAR(order_date) as order_year,
MONTH(order_date) as order_month, 
SUM(sales_amount) as total_sales,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date);
GO
SELECT 
FORMAT(order_date, 'yyyy-MMM') as order_date,
SUM(sales_amount) as total_sales,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM') 
ORDER BY FORMAT(order_date, 'yyyy-MMM');
GO

/*calculating the total sales per month
and the running total sales over time(cumulative analysis)*/

SELECT
order_date,
total_sales,
SUM(total_sales) over (ORDER BY order_date) as running_total_sales,
AVG(avg_price) over (ORDER BY order_date) as moving_avg_price
from
(
SELECT
DATETRUNC(year, order_date) as order_date,
SUM(sales_amount) as total_sales,
AVG(price) as avg_price
from gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(year, order_date)
) t;


/*Analyze the yearly performance of products by comapring their sales to both 
the average sales performance of the product and the previous year's sales(performance analysis)*/

WITH yearly_product_sales as (
SELECT
YEAR (f.order_date) as order_year,
p.product_name,
SUM(f.sales_amount) as current_sales
from gold.fact_sales f
LEFT JOIN gold.dim_products p
on f.product_key = p.product_key
where f.order_date IS NOT NULL
GROUP BY
YEAR(f.order_date),
p.product_name
)

SELECT
order_year,
product_name,
current_sales,
AVG(current_sales) over (partition by product_name) avg_sales,
current_sales - AVG(current_sales) over (partition by product_name) as diff_avg,
CASE when current_sales - AVG(current_sales) over (partition by product_name) > 0 THEN 'Above Avg'
     when current_sales - AVG(current_sales) over (partition by product_name) < 0 THEN 'Below Avg'
	 ELSE 'AVG'
END avg_change,
--year-over-year analysis
LAG(current_sales) over (partition by product_name order by order_year) py_sales,
current_sales - LAG(current_sales) over (partition by product_name order by order_year) as diff_py,
CASE when current_sales - LAG(current_sales) over (partition by product_name order by order_year) > 0 THEN 'Increase'
     when current_sales - LAG(current_sales) over (partition by product_name order by order_year) < 0 THEN 'Decrease'
	 ELSE 'No Change'
END py_change
from yearly_product_sales
order by product_name, order_year;


--which categories contribute the most to overall sales?(part-2 whole analysis)
WITH category_sales AS(
SELECT
category,
SUM(sales_amount) total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON p.product_key = f.product_key
GROUP BY category)

SELECT
category,
total_sales,
SUM(total_sales) OVER () overall_sales,
CONCAT(ROUND((CAST(total_sales AS float) / SUM(total_sales) over())*100,2),'%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;


/*Segment products into cost ranges and (DATA SEGMENTATION)
count how many products fall into each segment*/

WITH product_segments AS(
SELECT
product_key,
product_name,
cost,
CASE WHEN cost < 100 THEN 'below 100'
     WHEN cost BETWEEN 100 AND 500 THEN '100-500'
	 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
	 ELSE 'ABOVE 1000'
END cost_range
FROM gold.dim_products)

SELECT
cost_range,
COUNT(product_key) AS total_products 
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;


/*Group customers into three segments based on their spending behaviour:
  -VIP: Customers with atleast 12 months of history and spending more than $5000.
  -Regular: Customers with atleast 12 months of history and spending less than or equal to $5000.
  -New: Customers with the lifespan of less than 12 months.
And find the total number of customers by each group
*/
WITH customer_spending AS (
SELECT
c.customer_key,
SUM(f.sales_amount) AS total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)
SELECT
customer_segment,
COUNT(customer_key) AS total_customers
FROM(
    SELECT
	customer_key,
    CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
         WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'REGULAR'
	     ELSE 'NEW'
    END customer_segment
    FROM customer_spending) t
GROUP BY customer_segment
ORDER BY total_customers DESC;

/*
=========================================================================================================================
Customer Report
=========================================================================================================================
Purpose: This report consolidates key customer metrics and behavior
Highlights:
1.Gather essential field names such as name, age etc.
2.Segment customers into categories.
3.Aggregates customer-level metrics:
  a,total orders
  b,total sales
  c,total products
  d,total quantity purchased
  e,lifespan
4.Calculates KPI like recency,average order value, avg monthly spend
=========================================================================================================================
*/
WITH base_query AS(
-- 1.Base query retreives core columns from tables
SELECT
f.order_number,
f.product_key,
f.order_date,
f.sales_amount,
f.quantity,
c.customer_key,
c.customer_number,
CONCAT(c.first_name, ' ' , c.last_name) AS customer_name,
DATEDIFF(year, c.birthdate, getdate()) age
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
WHERE order_date IS NOT NULL),

customer_aggregation AS(
--2.Customer Aggregation:Summarizes key matrics
SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    COUNT(DISTINCT order_number) AS total_orders,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    COUNT(DISTINCT product_key) AS total_products,
    MAX(order_date) AS last_order_date,
    DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
FROM base_query
GROUP BY
    customer_key,
    customer_number,
    customer_name,
    age
)
SELECT
customer_key,
customer_number,
customer_name,
age,
CASE
     WHEN age < 20 THEN 'under 20'
	 WHEN age between 20 and 29 THEN '20-29'
	 WHEN age between 30 and 39 THEN '30-39'
	 WHEN age between 40 and 49 THEN '40-49'
	 ELSE '50 and Above'
END AS age_group,
CASE 
    -- FIX 1: Changed 'total_spending' to 'total_sales'
    WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
    WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'REGULAR'
	ELSE 'NEW'
END AS customer_segment,
last_order_date,
DATEDIFF(month, last_order_date, GETDATE()) AS recency,
total_orders,
total_sales,
total_quantity,
total_products,
lifespan,
CASE WHEN total_orders = 0 THEN 0
     ELSE total_sales / total_orders 
END AS avg_order_value,
CASE 
    -- FIX 2: Changed 'life_span' to 'lifespan'
    WHEN lifespan = 0  THEN total_sales
    ELSE total_sales / lifespan
END AS avg_monthly_spend
FROM customer_aggregation;
GO

--Product Report
CREATE VIEW gold.report_products AS
 WITH base_query AS(
--RETRIEVES COLUMNS
 SELECT
    f.order_number,
    f.order_date,
    f.customer_key,
    f.sales_amount,
    f.quantity,
    p.product_key,
    p.product_name,
    p.category,
    p.subcategory,
    p.cost
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
    ON f.product_key = p.product_key
WHERE order_date IS NOT NULL
)
products_aggregations AS(
--Summarizzing key matrics
SELECT
    product_key,
	product_name,
	category,
	cost,
	DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
	MAX(order_date) AS last_sale_date,
	COUNT(DISTINCT order_number) AS total_orders,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity,0)),1) AS avg_selling_price
FROM base_query
GROUP BY
    product_key,
	product_name,
	category,
	subcategory,
	cost
)
--combines all product outputs into one output
SELECT
    product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
	CASE 
	    WHEN total_sales > 50000 THEN 'High-Performer'
		WHEN total_sales  >= 10000 THEN 'Mid-Range'
		ELSE 'Low-Performer'
    END AS product_segment,
	lifespan,
	total_orders,
    total_sales,
	total_quantity,
	total_customers,
	avg_selling_price,
	CASE
	    WHEN total_orders = 0 THEN 0 
		ELSE total_sales / total_orders
	END AS avg_order_revenue,
	CASE WHEN LIFESPAN = 0 THEN total_sales
	     ELSE total_sale / lifespan
    END AS avg_monthly_revenue
FROM products_aggregations