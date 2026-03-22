WITH active_periods AS (
  SELECT started_at, ended_at
  FROM ip_activity_periods
  WHERE ip_id = :ip_id
    AND started_at <= :time_to
    AND (ended_at IS NULL OR ended_at >= :time_from)
),
checks_in_period AS (
  SELECT c.status, c.rtt_ms
  FROM ip_checks c
  JOIN active_periods p
    ON p.started_at <= c.checked_at
   AND (p.ended_at IS NULL OR c.checked_at < p.ended_at)
  WHERE c.ip_id = :ip_id
    AND c.checked_at >= :time_from
    AND c.checked_at <= :time_to
)
SELECT
  COUNT(*) AS total_checks,
  AVG(rtt_ms) FILTER (WHERE status = 'success') AS avg_rtt_ms,
  MIN(rtt_ms) FILTER (WHERE status = 'success') AS min_rtt_ms,
  MAX(rtt_ms) FILTER (WHERE status = 'success') AS max_rtt_ms,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rtt_ms)
    FILTER (WHERE status = 'success') AS median_rtt_ms,
  STDDEV_POP(rtt_ms) FILTER (WHERE status = 'success') AS stddev_rtt_ms,
  (100.0 * COUNT(*) FILTER (WHERE status <> 'success') / NULLIF(COUNT(*), 0)) AS loss_percent
FROM checks_in_period;
