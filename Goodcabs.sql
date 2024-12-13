use trips_db;

# 1.City Level Fare and Trip Summary Report
SELECT 
  c.city_name, 
  COUNT(trip_id) as total_trips,
  ROUND((SUM(fare_amount) /SUM(distance_travelled_km)),2) as Avg_fare_per_km,
  ROUND(SUM(fare_amount) / COUNT(trip_id),2) AS avg_fare_per_trip,
  ROUND((COUNT(t.trip_id) * 100.0 / SUM(COUNT(t.trip_id)) OVER()),2) AS pct_trip_contribution
FROM fact_trips t 
JOIN dim_city c ON c.city_id = t.city_id
GROUP BY city_name;
----------------------------------------------------
-- 2. Monthly City-Level Trips Target Performance Report
WITH Actual_trips AS (
       SELECT
        c.city_name,
        d.month_name,
        COUNT(f.trip_id) AS actual_trips                 
    FROM trips_db.fact_trips f
    JOIN trips_db.dim_city c ON f.city_id = c.city_id 
    JOIN trips_db.dim_date d ON d.date = f.date   
    GROUP BY c.city_name, d.month_name
),
Target_trips AS (
       SELECT
        c.city_name,
        d.month_name,
        SUM(total_target_trips) AS target_trips                
    FROM targets_db.monthly_target_trips mt
    JOIN trips_db.dim_city c ON mt.city_id = c.city_id
    JOIN trips_db.dim_date d ON d.date = mt.month   
    GROUP BY c.city_name, d.month_name)
SELECT 
    a.city_name,
    a.month_name,
    a.actual_trips,
    t.target_trips,
     ROUND(((a.actual_trips - t.target_trips) / t.target_trips) * 100, 2) AS percentage_difference,
    CASE WHEN a.actual_trips > t.target_trips THEN 'Above Target'
        ELSE 'Below Target'
    END AS performance_status
FROM Actual_trips a
JOIN Target_trips t
ON a.city_name = t.city_name AND a.month_name = t.month_name
ORDER BY a.city_name, a.month_name;

---------------------------------------------------------------------
# 3. city-level repeat passengers Trip frequency report

SELECT 
    c.city_name,
    ROUND(SUM(CASE WHEN td.trip_count = '2-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "2_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '3-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "3_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '4-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "4_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '5-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "5_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '6-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "6_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '7-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "7_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '8-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "8_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '9-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "9_Trips_%",
    ROUND(SUM(CASE WHEN td.trip_count = '10-Trips' THEN td.repeat_passenger_count ELSE 0 END) / fp.total_repeat_passengers * 100, 2) AS "10_Trips_%"
FROM dim_repeat_trip_distribution td
JOIN 
    (SELECT 
         city_id, 
         SUM(repeat_passengers) AS total_repeat_passengers 
     FROM fact_passenger_summary 
     GROUP BY city_id) fp
ON td.city_id = fp.city_id
JOIN dim_city c ON td.city_id = c.city_id
GROUP BY c.city_name, 
fp.total_repeat_passengers;
-----------------------------------------------------------
# 4. Identify cities highest and lowest total new passengers

WITH RankedCities AS (
    SELECT 
        c.city_name,
        SUM(new_passengers) AS total_new_passengers,
        DENSE_RANK() OVER (ORDER BY SUM(new_passengers) DESC) AS rank_top,
        DENSE_RANK() OVER (ORDER BY SUM(new_passengers)) AS rank_bottom
    FROM 
        fact_passenger_summary P 
        join dim_city c on p.city_id = c.city_id
    GROUP BY 
        c.city_name)
SELECT 
    city_name,
    total_new_passengers,
    CASE 
        WHEN rank_top <= 3 THEN 'top_3'
        WHEN rank_bottom <= 3 THEN 'bottom_3'
        ELSE 'other'
    END AS city_category
FROM RankedCities
WHERE rank_top <= 3 OR rank_bottom <= 3
order by rank_top;
------------
-- overall rank 
with cte as(
select c.city_name,
sum(new_passengers) as total_new_passengers,
DENSE_RANK() over(order by sum(new_passengers) desc ) as 'top_3',
DENSE_RANK() over(order by sum(new_passengers) ) as  'bottom_3'
from fact_passenger_summary p
join dim_city c on c.city_id = p.city_id
GROUP BY c.city_id)
select city_name, top_3, bottom_3
from cte;
----------------------------------------------------------------------
# 5. Identify month highest revenue for each city
WITH cte AS (
    SELECT 
	city_id, 
	MONTHNAME(date) AS highest_revenue_month,
	SUM(fare_amount) AS revenue
    FROM fact_trips 
    GROUP BY city_id, MONTHNAME(date)
),
ranked_revenue AS (
    SELECT 
	city_id, 
	highest_revenue_month, 
	revenue,
	ROW_NUMBER() OVER (PARTITION BY city_id ORDER BY revenue DESC) AS revenue_rank
    FROM cte
),
total_revenue AS (
    SELECT 
	city_id, 
	SUM(revenue) AS total_city_revenue
    FROM cte
    GROUP BY city_id)
SELECT 
    c.city_name, 
    r.highest_revenue_month , 
    r.revenue,
    ROUND((r.revenue / t.total_city_revenue) * 100, 2) AS pct_contribution
FROM ranked_revenue r
JOIN dim_city c ON r.city_id = c.city_id
JOIN total_revenue t ON r.city_id = t.city_id
WHERE r.revenue_rank = 1;

  ----------------------------------------------
  # 6. Repeat Passengers Rate Analysis
   WITH monthly_repeat_passenger_rt AS(
    SELECT 
    c.city_name,
    MONTHNAME(month) AS month_name,
    SUM(repeat_passengers) AS total_repeat_passengers,
    SUM(total_passengers) AS total_passengers,
    ROUND(SUM(repeat_passengers) * 100.0 / SUM(total_passengers), 2) AS monthly_repeat_passenger_rate
FROM 
    fact_passenger_summary P 
    JOIN dim_city c ON p.city_id=c.city_id
GROUP BY 
    city_name, MONTHNAME(month)),
    city_wide_repeat_rate AS(
    SELECT 
    c.city_name,
    SUM(repeat_passengers) AS total_repeat_passengers_city,
    SUM(total_passengers) AS total_passengers_city,
    ROUND(SUM(repeat_passengers) * 100.0 / SUM(total_passengers), 2) AS city_repeat_passenger_rate
FROM fact_passenger_summary P 
JOIN dim_city c ON p.city_id=c.city_id
GROUP BY c.city_name)
SELECT 
    mr.city_name, 
    mr.month_name,
    mr.total_passengers, 
    mr.total_repeat_passengers,
    mr.monthly_repeat_passenger_rate, 
    cr.city_repeat_passenger_rate
FROM monthly_repeat_passenger_rt AS mr 
JOIN city_wide_repeat_rate AS cr 
ON mr.city_name=cr.city_name;
    
------------------
-- 6. part 2
SELECT 
    city_name,
    SUM(repeat_passengers) AS total_repeat_passengers,
    SUM(total_passengers) AS total_passengers,
    ROUND(SUM(repeat_passengers) * 100.0 / SUM(total_passengers), 2) AS repeat_passenger_rate
FROM fact_passenger_summary p
join dim_city c on p.city_id=c.city_id
GROUP BY city_name;


--------------
-- power bi cross check values
with cte as(
select city_id,count(trip_id) as total_trips from fact_trips
group by city_id)
select city_id,total_trips,
rank() over(order by total_trips desc ) as rnk
from cte;
-------------------------------------------
select city_id, 
sum(fare_amount)/sum(distance_travelled_km) as avg_fare
from fact_trips
group by city_id;
---------------------------------
WITH city_summary AS (
    SELECT 
	city_id,
	AVG(fare_amount) AS avg_fare_per_trip,
	AVG(distance_travelled_km) AS avg_trip_distance
    FROM fact_trips
    GROUP BY city_id)
SELECT 
    city_id,
    avg_fare_per_trip,
    avg_trip_distance
FROM city_summary
ORDER BY avg_fare_per_trip DESC;
----------------------------------------
select d.day_type,count(trip_id) as total_trip 
from fact_trips f
join dim_date d on d.date = f.date
group by day_type;
