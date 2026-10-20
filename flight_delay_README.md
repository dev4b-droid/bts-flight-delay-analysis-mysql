# US Flight Delays: Carrier, Airport and Route Analysis (SQL)

A MySQL analysis of **602,378 US domestic flights from August 2025**. It ranks the worst carriers, airports and routes, breaks down what causes delays, and looks at how performance changes day to day. The queries use CTEs and window functions (`RANK`, `LAG`, rolling `AVG`, `PARTITION BY`).

## Dataset

- **Source:** US Department of Transportation, Bureau of Transportation Statistics (BTS), [TranStats](https://www.transtats.bts.gov/) → *Reporting Carrier On-Time Performance (1987-present)*
- **Period:** August 2025 (1 to 31 August)
- **Size:** 602,378 flights, 14 carriers, 348 origin airports, 6,111 routes
- **Not included in this repo** (the file is large). Download it from the link above, choose Year 2025 and Period August, and leave "Prezipped File" unchecked so you can select columns.

The table uses 31 columns: date, carrier, origin and destination (code, city, state), scheduled departure, departure and arrival delay, the 15-minute delay flags, cancelled and diverted flags, distance, and the five delay-cause columns.

## How to run

1. Install MySQL 8.0 or later.
2. Download the BTS CSV and copy it into the folder shown by `SHOW VARIABLES LIKE 'secure_file_priv';`.
3. Open `flight_delay_analysis.sql`, edit the path in the `LOAD DATA INFILE` statement, and run the script from top to bottom.
4. Compare the load checks with the expected values in the comments (602,378 rows, 133,920 flights with delay causes, 8,645 flights with no arrival delay).

## Definitions

| Term | Meaning |
|---|---|
| Completed flight | Not cancelled and not diverted (593,733 flights) |
| On time | Arrived less than 15 minutes late |
| Delayed | Arrived 15 or more minutes late |
| On-time rate | On-time flights ÷ completed flights |
| Cancellation rate | Cancelled flights ÷ all flights |

Delay causes (carrier, weather, NAS, security, late aircraft) are recorded only for delayed flights.

## What the analysis covers

1. **Data quality checks:** row counts, carrier lookup match, cancelled and diverted flights versus missing delays, flag consistency, cause totals versus arrival delay, duplicates, invalid distances.
2. **Carrier performance:** on-time rate, average delay, cancellation and diversion rates, ranked with window functions.
3. **Delay causes:** overall, by carrier, and the largest cause per carrier (`RANK ... PARTITION BY`).
4. **Airports and routes:** worst airports, worst airport per state, and worst routes, with minimum-flight cutoffs to avoid small-sample noise.
5. **DFW deep dive:** each carrier's on-time rate at Dallas/Fort Worth compared with the rest of its network.
6. **Time patterns:** daily on-time rate with a 7-day rolling average, day-of-week effects, day-over-day change with `LAG`, and the worst day's delay causes.

## Key findings

- **Baseline:** 77.4% of completed flights arrived on time, 1.1% of all flights were cancelled, and delayed flights ran about 73 minutes late on average.
- **Carriers:** Hawaiian was the most punctual (85.7% on time) and American the least (69.5%). Carrier size did not predict performance: Southwest, the largest, ranked 6th.
- **Causes:** Late aircraft (a knock-on from earlier delays) caused 40.5% of delay minutes, carrier delay 33.1%, air traffic control and airport congestion (NAS) 19.2%, and weather only 7.0%.
- **Airports and routes:** DFW was the worst large airport (65.7% on time), and 9 of the 10 worst routes start there.
- **DFW and American:** American was on time 56.4% of the time at DFW but 72.0% elsewhere, a gap of about 15.6 points. Other carriers were only 2 to 7 points worse at DFW than in their own networks. The data points to American's DFW hub operation rather than the airport alone, but it cannot prove the cause.
- **Time:** The daily on-time rate ranged from 63.1% (1 August) to 88.7% (26 August). Friday and Sunday were the worst days of the week (about 74.7%), and Tuesday the best (83.5%).

## Design decisions

- **Rates use completed flights as the base** so cancellations are reported separately rather than counted as "not on time".
- **Minimum-flight cutoffs** are applied only where group sizes vary widely: 1,500 flights per airport, 200 per route, and 100 completed flights per carrier at DFW. All 14 carriers are kept in the carrier ranking, since the smallest has 6,946 flights.
- **Conditional aggregation** (`CASE` inside `SUM`/`AVG`) is used instead of `WHERE` filters so several different counts can be computed in one query.

## Limitations

- One month of data, so no seasonality or long-term trends. August has five Fridays, Saturdays and Sundays but four of each other weekday.
- Delay causes exist only for flights delayed 15 or more minutes.
- Carriers fly different networks, so comparisons are not like-for-like.
- The data cannot explain why a particular day or route performed badly.
- Flight and tail numbers were not downloaded, so repeat aircraft cannot be analysed.

## Files

- `flight_delay_analysis.sql`: the full script (setup, import, checks and analysis, with findings in the comments)
- `README.md`: this file

## Skills demonstrated

SQL (MySQL 8.0), CTEs, window functions, conditional aggregation, joins, data validation, and turning query results into written findings.
