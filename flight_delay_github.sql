-- =====================================================================
-- US FLIGHT DELAYS: CARRIER, AIRPORT AND ROUTE ANALYSIS (MySQL 8.0)
-- =====================================================================
-- Data    : US DOT Bureau of Transportation Statistics (BTS)
--           On-Time Performance, Reporting Carrier, August 2025
--           602,378 flights | 14 carriers | 348 origin airports | 6,111 routes
-- Source  : transtats.bts.gov -> "Reporting Carrier On-Time Performance (1987-present)"
--           (one month, 31 columns, "Prezipped File" unchecked)
-- Goal    : Rank the worst carriers, airports and routes and break down
--           delay causes, using CTEs and window functions.
--
-- Definitions used throughout
--   completed flight : not cancelled and not diverted (593,733 flights)
--   on time          : arrived less than 15 minutes late (arr_del15 = 0)
--   delayed          : arrived 15 or more minutes late    (arr_del15 = 1)
--   on-time rate     : on-time flights / completed flights
--   cancel rate      : cancelled flights / all flights
--   Delay causes (carrier, weather, NAS, security, late aircraft) are only
--   recorded for delayed flights, so cause totals describe those flights.
--
-- Contents
--   1. Setup and import
--   2. Data quality checks
--   3. Baseline numbers
--   4. Carrier performance
--   5. Delay causes
--   6. Airports and routes
--   7. DFW vs the rest of each carrier's network
--   8. Time patterns
--   9. Limitations
-- =====================================================================


-- =====================================================================
-- 1. SETUP AND IMPORT
-- =====================================================================
-- Copy the CSV into the folder shown by:  SHOW VARIABLES LIKE 'secure_file_priv';
-- then edit the path in LOAD DATA below.

-- Database
CREATE DATABASE IF NOT EXISTS flight_delays;
USE flight_delays;

-- Flights table
CREATE TABLE flights (
    flight_id           INT AUTO_INCREMENT PRIMARY KEY,
    fl_date             DATE NOT NULL,
    carrier             VARCHAR(3) NOT NULL,
    origin              CHAR(3) NOT NULL,
    origin_city         VARCHAR(100),
    origin_state        CHAR(2),
    dest                CHAR(3) NOT NULL,
    dest_city           VARCHAR(100),
    dest_state          CHAR(2),
    crs_dep_time        CHAR(4),
    dep_delay           DECIMAL(7,2),
    dep_del15           TINYINT,
    arr_delay           DECIMAL(7,2),
    arr_del15           TINYINT,
    cancelled           TINYINT NOT NULL,
    cancellation_code   CHAR(1),
    diverted            TINYINT NOT NULL,
    distance            DECIMAL(7,2),
    carrier_delay       DECIMAL(7,2),
    weather_delay       DECIMAL(7,2),
    nas_delay           DECIMAL(7,2),
    security_delay      DECIMAL(7,2),
    late_aircraft_delay DECIMAL(7,2)
);

-- Import (the CSV has 31 columns; the @variables skip the ones we do not need)
LOAD DATA INFILE "path/to/T_ONTIME_REPORTING.csv"
INTO TABLE flights
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@year, @quarter, @month, @fl_date, @carrier,
 @origin_id, @origin_seq, @origin_mkt, @origin, @origin_city, @origin_state,
 @dest_id, @dest_seq, @dest_mkt, @dest, @dest_city, @dest_state,
 @crs_dep, @dep_delay, @dep_del15, @arr_delay, @arr_del15,
 @cancelled, @cancel_code, @diverted, @distance,
 @carrier_delay, @weather_delay, @nas_delay, @security_delay, @late_aircraft_delay)
SET
    fl_date             = STR_TO_DATE(@fl_date, '%m/%d/%Y %h:%i:%s %p'),
    carrier             = @carrier,
    origin              = @origin,
    origin_city         = @origin_city,
    origin_state        = @origin_state,
    dest                = @dest,
    dest_city           = @dest_city,
    dest_state          = @dest_state,
    crs_dep_time        = @crs_dep,
    dep_delay           = NULLIF(@dep_delay, ''),
    dep_del15           = ROUND(NULLIF(@dep_del15, '')),
    arr_delay           = NULLIF(@arr_delay, ''),
    arr_del15           = ROUND(NULLIF(@arr_del15, '')),
    cancelled           = ROUND(@cancelled),
    cancellation_code   = NULLIF(@cancel_code, ''),
    diverted            = ROUND(@diverted),
    distance            = NULLIF(@distance, ''),
    carrier_delay       = NULLIF(@carrier_delay, ''),
    weather_delay       = NULLIF(@weather_delay, ''),
    nas_delay           = NULLIF(@nas_delay, ''),
    security_delay      = NULLIF(@security_delay, ''),
    late_aircraft_delay = NULLIF(@late_aircraft_delay, '');

-- Carrier lookup table (BTS gives codes only, so the 14 names are entered by hand)
CREATE TABLE carriers (
    carrier      VARCHAR(3) PRIMARY KEY,
    carrier_name VARCHAR(50) NOT NULL
);

INSERT INTO carriers VALUES
('AA','American Airlines'), ('AS','Alaska Airlines'), ('B6','JetBlue Airways'),
('DL','Delta Air Lines'), ('F9','Frontier Airlines'), ('G4','Allegiant Air'),
('HA','Hawaiian Airlines'), ('MQ','Envoy Air'), ('NK','Spirit Airlines'),
('OH','PSA Airlines'), ('OO','SkyWest Airlines'), ('UA','United Airlines'),
('WN','Southwest Airlines'), ('YX','Republic Airways');

-- =====================================================================
-- 2. DATA QUALITY CHECKS
-- =====================================================================
-- Load verification (expected values in the comments)
SELECT COUNT(*) FROM flights;                    -- expect 602378
SELECT MIN(fl_date), MAX(fl_date) FROM flights;  -- expect 2025-08-01 to 2025-08-31
SELECT COUNT(*) FROM flights WHERE carrier_delay IS NOT NULL;  -- expect 133920
SELECT COUNT(*) FROM flights WHERE arr_delay IS NULL;          -- expect 8645

SELECT COUNT( DISTINCT c.carrier), COUNT(DISTINCT f.carrier) 
FROM flights AS f
RIGHT JOIN carriers AS c
ON f.carrier = c.carrier;

SELECT COUNT(*) , c.carrier
FROM flights AS f 
INNER JOIN carriers AS c
ON f.carrier = c.carrier
GROUP BY f.carrier;

SELECT COUNT(cancelled)
FROM flights
WHERE cancelled = 1;

SELECT COUNT(diverted)
FROM flights 
WHERE diverted = 1;

SELECT COUNT(cancelled)
FROM flights 
WHERE arr_delay IS NULL AND cancelled = 1;

SELECT COUNT(diverted)
FROM flights
WHERE arr_delay IS NULL AND diverted = 1;

SELECT arr_del15, arr_delay
FROM flights
WHERE arr_delay >=15 and arr_del15 = 0;

SELECT COUNT(*) 
FROM flights
WHERE arr_del15 = 0 AND carrier_delay IS NULL AND weather_delay IS NULL AND nas_delay IS NULL AND security_delay IS NULL AND late_aircraft_delay IS NULL;

WITH R AS 
(
SELECT COUNT(*) AS COUNT_1
FROM flights 
WHERE arr_del15 = 1
),
S AS
(
SELECT COUNT(*) AS COUNT_2
FROM flights
WHERE arr_del15 = 1 AND carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay = arr_delay
)

SELECT 
CASE WHEN R.COUNT_1 = S.COUNT_2 THEN "RIGHT"
ELSE "WRONG"
END AS CHECKING
FROM R
CROSS JOIN S;

SELECT COUNT(*)
FROM flights
WHERE origin = dest; 

SELECT COUNT(*)
FROM flights
WHERE distance <= 0;

SELECT COUNT(*) AS C1
FROM flights
GROUP BY fl_date, carrier, origin, origin_city, origin_sTate, dest, dest_city, dest_state, crs_dep_time, dep_delay, dep_del15, arr_delay, arr_del15, cancelled, cancellation_code, diverted, distance, carrier_delay,weather_delay, nas_delay, security_delay, late_aircraft_delay
HAVING C1 > 1;

-- Findings
--   * 602,378 rows covering 1-31 August 2025; all 14 carriers match the lookup.
--   * 6,483 cancelled + 2,162 diverted = 8,645 flights, which is exactly the
--     number of rows with a NULL arr_delay. Every other flight has a delay value.
--   * Delay-cause columns are filled only for the 133,920 delayed flights, and
--     the five causes add up to arr_delay for every one of them.
--   * arr_del15 is consistent with arr_delay, and there are no exact duplicate
--     rows (checked on every column except the surrogate key flight_id).
--   * No zero or negative distances, and no flights with origin = destination.

-- =====================================================================
-- 3. BASELINE NUMBERS
-- =====================================================================
SELECT 
SUM(CASE 
WHEN cancelled = 1 THEN 1
ELSE 0
END) * 100 / COUNT(*) AS cancelled_per
FROM flights;  

SELECT 
SUM(CASE 
WHEN diverted = 1 THEN 1
ELSE 0
END) * 100 / COUNT(*) AS diverted_per
FROM flights;  

SELECT COUNT(*)
FROM flights 
WHERE arr_delay IS NOT NULL;
-- 602378 - 2162 - 6483 = 593733 

SELECT COUNT(*)
FROM flights
WHERE arr_del15 = 0;

SELECT AVG(arr_delay)
FROM flights 
WHERE arr_delay >= 15;

-- Findings
--   * 1.08% of flights were cancelled and 0.36% diverted.
--   * Of 593,733 completed flights, 459,813 (77.4%) arrived on time and
--     133,920 (22.6%) were delayed 15+ minutes.
--   * A delayed flight is late by about 73 minutes on average, so delays
--     that do happen are long.

-- =====================================================================
-- 4. CARRIER PERFORMANCE (all 14 carriers ranked on three measures)
-- =====================================================================
-- Rank 1 = best on every measure (highest on-time rate, lowest average delay,
-- lowest cancellation rate). No minimum-flight filter is needed here: the
-- smallest carrier (HA) still has 6,946 flights.
WITH carrier_stats AS (
    SELECT
        c.carrier_name,
        f.carrier,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN f.cancelled = 0 AND f.diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
        SUM(CASE WHEN f.arr_del15 = 0 THEN 1 ELSE 0 END) AS on_time_flights,
        AVG(f.arr_delay) AS avg_arr_delay,
        SUM(f.cancelled) AS cancelled_flights,
        SUM(f.diverted) AS diverted_flights
    FROM flights f
    JOIN carriers c ON f.carrier = c.carrier
    GROUP BY c.carrier_name, f.carrier
),
rates AS (
    SELECT
        carrier_name,
        carrier,
        total_flights,
        100.0 * on_time_flights / completed_flights AS on_time_rate,
        avg_arr_delay,
        100.0 * cancelled_flights / total_flights AS cancel_rate,
        100.0 * diverted_flights / total_flights AS divert_rate
    FROM carrier_stats
)
SELECT
    carrier_name,
    carrier,
    total_flights,
    ROUND(on_time_rate, 2)   AS on_time_rate,
    ROUND(avg_arr_delay, 2)  AS avg_arr_delay,
    ROUND(cancel_rate, 2)    AS cancel_rate,
    ROUND(divert_rate, 2)    AS divert_rate,
    RANK() OVER (ORDER BY on_time_rate DESC)  AS on_time_rank,
    RANK() OVER (ORDER BY avg_arr_delay ASC)  AS delay_rank,
    RANK() OVER (ORDER BY cancel_rate ASC)    AS cancel_rank
FROM rates
ORDER BY on_time_rank;

-- Findings
--   * Hawaiian (HA) is the most punctual carrier at 85.7% on time; American (AA)
--     is the least at 69.5%, with the longest average delay (20.4 min).
--   * Size does not predict performance. Southwest (114,519 flights) ranks 6th
--     on on-time rate, and American, the 3rd largest, ranks last.
--   * The rankings disagree: Republic (YX) has the lowest average delay but
--     1.7% cancellations, while Allegiant (G4) cancels only 0.07% of flights
--     yet ranks 13th on delay. PSA (OH) has the highest cancellation rate (2.6%).
--   * Networks differ (HA flies short island routes), so this compares
--     operations, not carriers on identical routes.

-- =====================================================================
-- 5. DELAY CAUSES (delayed flights only)
-- =====================================================================
-- 5a. Overall share of delay minutes by cause
WITH delay_summary AS (
    SELECT
        'Carrier delay' AS delay_type,
        SUM(carrier_delay) AS total_delay
    FROM flights

    UNION ALL

    SELECT
        'Weather delay',
        SUM(weather_delay)
    FROM flights

    UNION ALL

    SELECT
        'NAS delay',
        SUM(nas_delay)
    FROM flights

    UNION ALL

    SELECT
        'Security delay',
        SUM(security_delay)
    FROM flights

    UNION ALL

    SELECT
        'Late aircraft delay',
        SUM(late_aircraft_delay)
    FROM flights
)
SELECT
    delay_type,
    total_delay,
    ROUND(total_delay * 100.0 / SUM(total_delay) OVER (), 2) AS delay_per,
    RANK() OVER (ORDER BY total_delay DESC) AS delay_rank
FROM delay_summary
ORDER BY delay_rank;

-- 5b. Cause mix by carrier (% of each carrier's delay minutes) and delay per flight
WITH stat_1 AS 
(
SELECT c.carrier_name AS carrier_name, 
f.carrier AS carrier,
SUM(f.arr_delay) AS total_delay, 
ROUND(SUM(f.carrier_delay) * 100 /(SUM(carrier_delay) + SUM(weather_delay) + SUM(nas_delay) + SUM(security_delay) + SUM(late_aircraft_delay)), 2) AS carrier_del_pct, 
ROUND(SUM(f.weather_delay) * 100 /(SUM(carrier_delay) + SUM(weather_delay) + SUM(nas_delay) + SUM(security_delay) + SUM(late_aircraft_delay)), 2) AS weather_del_pct, 
ROUND(SUM(f.nas_delay) * 100 /(SUM(carrier_delay) + SUM(weather_delay) + SUM(nas_delay) + SUM(security_delay) + SUM(late_aircraft_delay)), 2) AS nas_del_pct, 
ROUND(SUM(f.security_delay) * 100/(SUM(carrier_delay) + SUM(weather_delay) + SUM(nas_delay) + SUM(security_delay) + SUM(late_aircraft_delay)), 2) AS security_del_pct, 
ROUND(SUM(f.late_aircraft_delay) * 100/(SUM(carrier_delay) + SUM(weather_delay) + SUM(nas_delay) + SUM(security_delay) + SUM(late_aircraft_delay)), 2) AS aircraft_del_pct,
SUM(arr_del15) AS delay_flights
FROM flights AS f
LEFT JOIN carriers AS c
ON f.carrier = c.carrier
WHERE f.arr_del15 = 1
GROUP BY f.carrier, c.carrier_name
),
stat_2 AS
(
SELECT carrier,
SUM(CASE WHEN arr_del15 IS NOT NULL THEN 1 ELSE 0 END) AS completed_flights
FROM flights
GROUP BY carrier
)
SELECT c.carrier, 
s.carrier_name, 
s.total_delay, 
s.carrier_del_pct, 
s.weather_del_pct, 
s.nas_del_pct, 
s.security_del_pct, 
s.aircraft_del_pct,
ROUND(s.total_delay / c.completed_flights, 2) AS del_per_flights,
s.delay_flights,
c.completed_flights
FROM stat_1 AS s
LEFT JOIN stat_2 AS c
ON s.carrier = c.carrier;

-- 5c. Largest cause for each carrier (window function, PARTITION BY carrier)
WITH delay_data AS (
    SELECT
        carrier,
        'Carrier delay' AS delay_type,
        SUM(carrier_delay) AS total_delay
    FROM flights
    GROUP BY carrier

    UNION ALL

    SELECT
        carrier,
        'Weather delay',
        SUM(weather_delay)
    FROM flights
    GROUP BY carrier

    UNION ALL

    SELECT
        carrier,
        'NAS delay',
        SUM(nas_delay)
    FROM flights
    GROUP BY carrier

    UNION ALL

    SELECT
        carrier,
        'Security delay',
        SUM(security_delay)
    FROM flights
    GROUP BY carrier

    UNION ALL

    SELECT
        carrier,
        'Late aircraft delay',
        SUM(late_aircraft_delay)
    FROM flights
    GROUP BY carrier
),
ranked_delays AS (
    SELECT *,
        RANK() OVER (
            PARTITION BY carrier
            ORDER BY total_delay DESC
        ) AS delay_rank
    FROM delay_data
)
SELECT *
FROM ranked_delays
WHERE delay_rank = 1;

-- Findings
--   * 9.8 million delay minutes across 133,920 delayed flights. Late aircraft
--     (a previous delay carrying over) causes 40.5%, carrier delay 33.1%,
--     NAS (air traffic control, airport congestion) 19.2%, weather 7.0% and
--     security 0.1%. Weather matters far less than most people assume.
--   * Late-aircraft delay includes the knock-on effect of earlier carrier
--     problems, so airlines' real share of delays is above the 33% shown.
--   * Late aircraft is the top cause for 9 carriers, carrier delay for 4
--     (DL, G4, HA, OO) and NAS for 1 (NK, 42.9% of its delay minutes).
--   * AA: 49% late aircraft, 31% carrier delay, and the heaviest delay per
--     flight (about 27 min). HA: 74% carrier delay, but the lowest delay per
--     flight (about 7 min).

-- =====================================================================
-- 6. AIRPORTS AND ROUTES
-- =====================================================================
-- Minimum-flight cutoffs are used because rates from small groups swing
-- widely. Airports: at least 1,500 flights (74 of 348 airports).
-- Routes (origin to destination): at least 200 flights (818 of 6,111 routes).
-- 6a. Ten worst airports by on-time rate
WITH airport_data AS (
    SELECT
        origin,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
        SUM(cancelled) AS total_cancel,
        AVG(arr_delay) AS avg_delay,
        100.0 * SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END)
              / SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS on_time_rate
    FROM flights
    GROUP BY origin
    HAVING COUNT(*) >= 1500
),
time_rank AS (
    SELECT *, RANK() OVER (ORDER BY on_time_rate ASC) AS airport_rank
    FROM airport_data
)
SELECT origin, total_flights, completed_flights, total_cancel,
       ROUND(avg_delay, 2)   AS avg_delay,
       ROUND(on_time_rate, 2) AS on_time_rate,
       airport_rank
FROM time_rank
WHERE airport_rank <= 10
ORDER BY airport_rank;

-- 6b. Worst airport in each state
WITH airport_data AS (
    SELECT
        origin,
        origin_state,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
        SUM(cancelled) AS total_cancel,
        AVG(arr_delay) AS avg_delay,
        100.0 * SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END)
              / SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS on_time_rate
    FROM flights
    GROUP BY origin, origin_state
    HAVING COUNT(*) >= 1500
),
time_rank AS (
    SELECT *, RANK() OVER (PARTITION BY origin_state ORDER BY on_time_rate ASC) AS state_rank
    FROM airport_data
)
SELECT origin, origin_state, total_flights, completed_flights, total_cancel,
       ROUND(avg_delay, 2)    AS avg_delay,
       ROUND(on_time_rate, 2) AS on_time_rate,
       state_rank
FROM time_rank
WHERE state_rank = 1
ORDER BY origin_state;

-- 6c. Ten worst routes
WITH route_data AS (
    SELECT
        origin,
        dest,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
        SUM(cancelled) AS total_cancel,
        AVG(arr_delay) AS avg_delay,
        100.0 * SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END)
              / SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS on_time_rate
    FROM flights
    GROUP BY origin, dest
    HAVING COUNT(*) >= 200
),
route_ranked AS (
    SELECT *, RANK() OVER (ORDER BY on_time_rate ASC) AS route_rank
    FROM route_data
)
SELECT origin, dest, total_flights, completed_flights, total_cancel,
       ROUND(avg_delay, 2)    AS avg_delay,
       ROUND(on_time_rate, 2) AS on_time_rate,
       route_rank
FROM route_ranked
WHERE route_rank <= 10
ORDER BY route_rank;

-- Findings
--   * Dallas/Fort Worth (DFW) is the worst large airport: 65.7% on time and
--     a 22.8-minute average delay, followed by MCO (67.5%), MIA (67.6%) and
--     DEN (70.1%).
--   * 9 of the 10 worst routes start at DFW (the other is CLT to MCO), and the
--     worst, DFW to MCO, is only 48.9% on time.
--   * Ranking on completed flights matters: counting cancellations as "not on
--     time" would push ORD up the list and change the order of MCO and MIA.

-- =====================================================================
-- 7. DFW VS THE REST OF EACH CARRIER'S NETWORK
-- =====================================================================
-- Is DFW bad for everyone, or is it one airline? American flies about half
-- of DFW's departures and is also the worst carrier overall.
WITH dfw_stat AS
(
    SELECT origin,
           carrier,
           COUNT(*) AS total_flights,
           SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
           SUM(cancelled) AS total_cancel,
           AVG(arr_delay) AS avg_delay,
           100.0 * SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END)
                 / SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS on_time_rate
    FROM flights
    WHERE origin = 'DFW'
    GROUP BY origin, carrier
),
non_dfw_data AS
(
    SELECT carrier,
           COUNT(*) AS total_flights,
           SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS completed_flights,
           SUM(cancelled) AS total_cancel,
           AVG(arr_delay) AS avg_delay,
           100.0 * SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END)
                 / SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 ELSE 0 END) AS on_time_rate
    FROM flights
    WHERE origin != 'DFW'
    GROUP BY carrier
)
-- Cutoff: carriers need at least 100 completed flights at DFW to be compared,
-- because rates from tiny samples (e.g. YX with 6 flights) are meaningless.
SELECT c.carrier_name,
       d.carrier,
       d.completed_flights                              AS dfw_flights,
       ROUND(d.on_time_rate, 2)                         AS dfw_on_time,
       n.completed_flights                              AS other_flights,
       ROUND(n.on_time_rate, 2)                         AS other_on_time,
       ROUND(d.on_time_rate - n.on_time_rate, 2)        AS gap_points,
       ROUND(d.avg_delay, 2)                            AS dfw_avg_delay,
       ROUND(n.avg_delay, 2)                            AS other_avg_delay
FROM dfw_stat d
JOIN non_dfw_data n ON d.carrier = n.carrier
JOIN carriers c     ON d.carrier = c.carrier
WHERE d.completed_flights >= 100
ORDER BY gap_points ASC;

-- Findings
--   * AA is far worse at DFW than anywhere else: 56.4% on time vs 72.0%, and a
--     33.0-minute average delay vs 18.0. With over 13,000 flights this is
--     not noise.
--   * Other carriers are mildly worse at DFW than in their own networks
--     (MQ, OO, OH, DL, UA by 2 to 7 points), so DFW is somewhat harder for
--     everyone, but AA's gap is more than twice as large.
--   * Without AA, DFW would be about 75.0% on time, against 65.7% with AA.
--   * Small gaps on small samples (for example F9, +3.3 points) are not evidence.
--   * The data suggests a problem in AA's DFW hub operation but cannot prove
--     the cause: AA's DFW network is also more connection-heavy.

-- =====================================================================
-- 8. TIME PATTERNS (window functions: rolling average, LAG, RANK)
-- =====================================================================
-- 8a. Daily on-time rate with a 7-day rolling average
--     (the first six rolling values average fewer than seven days)
WITH daily_stats AS (
    SELECT
        fl_date,
        COUNT(*) AS total_flights,
        SUM(CASE
            WHEN cancelled = 0 AND diverted = 0 THEN 1
            ELSE 0
        END) AS completed_flights,
        SUM(cancelled) AS total_cancel,
        AVG(arr_delay) AS avg_delay,
        100.0 * SUM(CASE
            WHEN arr_del15 = 0 THEN 1
            ELSE 0
        END) /
        NULLIF(SUM(CASE
            WHEN cancelled = 0 AND diverted = 0 THEN 1
            ELSE 0
        END), 0) AS on_time_rate
    FROM flights
    GROUP BY fl_date
)
SELECT
    *,
    AVG(on_time_rate) OVER (
        ORDER BY fl_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7day_on_time_rate
FROM daily_stats
ORDER BY fl_date;

-- 8b. On-time rate by day of week
SELECT
    DAYNAME(fl_date) AS day_of_week,

    COUNT(*) AS total_flights,

    SUM(
        CASE
            WHEN arr_del15 = 0 THEN 1
            ELSE 0
        END
    ) AS on_time_flights,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN arr_del15 = 0 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS on_time_rate

FROM flights
WHERE cancelled = 0
  AND diverted = 0

GROUP BY
    DAYNAME(fl_date),
    DAYOFWEEK(fl_date)

ORDER BY DAYOFWEEK(fl_date);

-- 8c. Best and worst day of the week
WITH daily_stats AS (
    SELECT
        DAYNAME(fl_date) AS day_of_week,
        DAYOFWEEK(fl_date) AS day_number,
        COUNT(*) AS total_flights,
        ROUND(
            100.0 * SUM(
                CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END
            ) / COUNT(*),
            2
        ) AS on_time_rate
    FROM flights
    WHERE cancelled = 0
      AND diverted = 0
    GROUP BY DAYNAME(fl_date), DAYOFWEEK(fl_date)
),
ranked_days AS (
    SELECT *,
        RANK() OVER (ORDER BY on_time_rate ASC) AS worst_rank,
        RANK() OVER (ORDER BY on_time_rate DESC) AS best_rank
    FROM daily_stats
)
SELECT
    day_of_week,
    total_flights,
    on_time_rate,
    CASE
        WHEN worst_rank = 1 THEN 'Worst'
        WHEN best_rank = 1 THEN 'Best'
    END AS day_category
FROM ranked_days
WHERE worst_rank = 1 OR best_rank = 1
ORDER BY day_number;

-- 8d. Day-over-day change in on-time rate
WITH daily_stats AS (
    SELECT
        fl_date,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END) AS on_time_flights,
        100.0 * SUM(
            CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END
        ) / COUNT(*) AS on_time_rate
    FROM flights
    WHERE cancelled = 0
      AND diverted = 0
    GROUP BY fl_date
),
daily_changes AS (
    SELECT
        fl_date,
        total_flights,
        on_time_flights,
        on_time_rate,
        LAG(on_time_rate) OVER (
            ORDER BY fl_date
        ) AS previous_day_rate
    FROM daily_stats
)
SELECT
    fl_date,
    total_flights,
    on_time_rate,
    previous_day_rate,
    on_time_rate - previous_day_rate AS change_percentage_points
FROM daily_changes
ORDER BY fl_date;

-- 8e. Three biggest drops and rises
WITH daily_stats AS (
    SELECT
        fl_date,
        100.0 * SUM(
            CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END
        ) / COUNT(*) AS on_time_rate
    FROM flights
    WHERE cancelled = 0
      AND diverted = 0
    GROUP BY fl_date
),
daily_changes AS (
    SELECT
        fl_date,
        on_time_rate,
        LAG(on_time_rate) OVER (
            ORDER BY fl_date
        ) AS previous_day_rate
    FROM daily_stats
),
changes AS (
    SELECT
        fl_date,
        on_time_rate,
        previous_day_rate,
        on_time_rate - previous_day_rate AS change_pp
    FROM daily_changes
    WHERE previous_day_rate IS NOT NULL
)
(
    SELECT
        fl_date,
        on_time_rate,
        previous_day_rate,
        change_pp,
        'Biggest Drop' AS change_type
    FROM changes
    WHERE change_pp < 0
    ORDER BY change_pp ASC
    LIMIT 3
)
UNION ALL
(
    SELECT
        fl_date,
        on_time_rate,
        previous_day_rate,
        change_pp,
        'Biggest Rise' AS change_type
    FROM changes
    WHERE change_pp > 0
    ORDER BY change_pp DESC
    LIMIT 3
);

-- 8f. Worst day of the month and its largest delay cause
WITH daily_stats AS (
    SELECT
        fl_date,
        100.0 * SUM(
            CASE WHEN arr_del15 = 0 THEN 1 ELSE 0 END
        ) / COUNT(*) AS on_time_rate
    FROM flights
    WHERE cancelled = 0
      AND diverted = 0
    GROUP BY fl_date
),
worst_day AS (
    SELECT fl_date, on_time_rate
    FROM daily_stats
    ORDER BY on_time_rate ASC, fl_date
    LIMIT 1
),
delay_causes AS (
    SELECT
        'Carrier delay' AS delay_cause,
        SUM(COALESCE(f.carrier_delay, 0)) AS total_delay
    FROM flights f
    JOIN worst_day w ON f.fl_date = w.fl_date

    UNION ALL

    SELECT
        'Weather delay',
        SUM(COALESCE(f.weather_delay, 0))
    FROM flights f
    JOIN worst_day w ON f.fl_date = w.fl_date

    UNION ALL

    SELECT
        'NAS delay',
        SUM(COALESCE(f.nas_delay, 0))
    FROM flights f
    JOIN worst_day w ON f.fl_date = w.fl_date

    UNION ALL

    SELECT
        'Security delay',
        SUM(COALESCE(f.security_delay, 0))
    FROM flights f
    JOIN worst_day w ON f.fl_date = w.fl_date

    UNION ALL

    SELECT
        'Late aircraft delay',
        SUM(COALESCE(f.late_aircraft_delay, 0))
    FROM flights f
    JOIN worst_day w ON f.fl_date = w.fl_date
)
SELECT
    w.fl_date AS worst_date,
    w.on_time_rate,
    d.delay_cause,
    d.total_delay
FROM delay_causes d
CROSS JOIN worst_day w
ORDER BY d.total_delay DESC
LIMIT 1;

-- Findings
--   * The daily on-time rate ranged from 63.1% (1 August) to 88.7% (26 August),
--     averaging 77.6%.
--   * 1 August was the worst day: 35% of flights delayed, 4.1% cancelled (vs
--     1.1% for the month), and late aircraft the top cause (43.9% of delay
--     minutes). Weather was only 6.1%, so this looks like knock-on disruption
--     rather than a weather event.
--   * Biggest rises: 11 Aug (+11.1 points) and 5 Aug (+10.4). Biggest drops:
--     10 Aug (-7.3) and 28 Aug (-7.3). Bad days tend to recover sharply.
--   * The rolling average climbed from about 75% mid-month to 82.9% by 31 Aug.
--   * Friday (74.7%) and Sunday (74.7%) are effectively tied as the worst days;
--     Tuesday (83.5%) is the best.

-- =====================================================================
-- 9. LIMITATIONS
-- =====================================================================
--   * One month (August 2025) only, so no seasonality or long-term trends.
--     August has five Fridays, Saturdays and Sundays but four of other days.
--   * Delay causes exist only for flights delayed 15+ minutes.
--   * Cutoffs (1,500 flights per airport, 200 per route, 100 for DFW
--     carriers) are judgement calls chosen to avoid small-sample noise.
--   * Carriers fly different networks, so carrier comparisons are not
--     like-for-like. The data cannot explain why a specific day was bad.
--   * Flight numbers and tail numbers were not downloaded, so repeat
--     aircraft cannot be analysed.
