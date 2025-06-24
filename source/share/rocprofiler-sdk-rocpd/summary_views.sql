--
-- Useful summary views
--
--
-- Sorted list of kernels which consume the most overall time
CREATE VIEW IF NOT EXISTS
    `top_kernels` AS
SELECT
    K.name,
    COUNT(K.kernel_id) AS total_calls,
    SUM(K.end - K.start) / 1000.0 AS total_duration,
    (SUM(K.end - K.start) / COUNT(K.kernel_id)) / 1000.0 AS average,
    SUM(K.end - K.start) * 100.0 / (
        SELECT
            SUM(A.end - A.start)
        FROM
            `kernels` A
    ) AS percentage
FROM
    `kernels` K
GROUP BY
    name
ORDER BY
    total_duration DESC;

--
-- GPU utilization metrics including kernels and memory copy operations
CREATE VIEW IF NOT EXISTS
    `busy` AS
SELECT
    A.agent_id,
    AG.type,
    GpuTime,
    WallTime,
    GpuTime * 1.0 / WallTime AS Busy
FROM
    (
        SELECT
            agent_id,
            `guid`,
            SUM(`end` - `start`) AS GpuTime
        FROM
            (
                SELECT
                    agent_id,
                    `guid`,
                    `end`,
                    `start`
                FROM
                    `kernels`
                UNION ALL
                SELECT
                    dst_agent_id AS agent_id,
                    `guid`,
                    `end`,
                    `start`
                FROM
                    `rocpd_memory_copy`
            )
        GROUP BY
            agent_id,
            `guid`
    ) A
    INNER JOIN (
        SELECT
            MAX(`end`) - MIN(`start`) AS WallTime
        FROM
            (
                SELECT
                    `end`,
                    `start`
                FROM
                    `rocpd_kernel_dispatch`
                UNION ALL
                SELECT
                    `end`,
                    `start`
                FROM
                    `rocpd_memory_copy`
            )
    ) W ON 1 = 1
    INNER JOIN `rocpd_info_agent` AG ON AG.id = A.agent_id
    AND AG.guid = A.guid;

--
-- Overall performance summary including kernels and memory copy operations
CREATE VIEW
    `top` AS
SELECT
    name,
    COUNT(*) AS total_calls,
    SUM(duration) / 1000.0 AS total_duration,
    (SUM(duration) / COUNT(*)) / 1000.0 AS average,
    SUM(duration) * 100.0 / total_time AS percentage
FROM
    (
        -- Kernel operations
        SELECT
            K.name,
            K.duration
        FROM
            `kernels` K
        UNION ALL
        -- Memory operations
        SELECT
            MC.name,
            MC.duration
        FROM
            `memory_copies` MC
        UNION ALL
        -- Regions
        SELECT
            R.name,
            R.duration
        FROM
            `regions` R
    ) operations
    CROSS JOIN (
        SELECT
            SUM(`end` - `start`) AS total_time
        FROM
            (
                SELECT
                    `end`,
                    `start`
                FROM
                    `kernels`
                UNION ALL
                SELECT
                    `end`,
                    `start`
                FROM
                    `memory_copies`
                UNION ALL
                SELECT
                    `end`,
                    `start`
                FROM
                    `regions`
            )
    ) TOTAL
GROUP BY
    name
ORDER BY
    total_duration DESC;

-- Kernel summary by name
CREATE VIEW
    `kernel_summary` AS
WITH
    avg_data AS (
        SELECT
            name,
            AVG(duration) AS avg_duration
        FROM
            `kernels`
        GROUP BY
            name
    ),
    aggregated_data AS (
        SELECT
            K.name,
            COUNT(*) AS calls,
            SUM(K.duration) AS total_duration,
            SUM(CAST(K.duration AS REAL) * CAST(K.duration AS REAL)) AS sqr_duration,
            A.avg_duration AS average_duration,
            MIN(K.duration) AS min_duration,
            MAX(K.duration) AS max_duration,
            SUM(CAST((K.duration - A.avg_duration) AS REAL) * CAST((K.duration - A.avg_duration) AS REAL)) / (COUNT(*) - 1) AS variance_duration,
            SQRT(
                SUM(CAST((K.duration - A.avg_duration) AS REAL) * CAST((K.duration - A.avg_duration) AS REAL)) / (COUNT(*) - 1)
            ) AS std_dev_duration
        FROM
            `kernels` K
            JOIN avg_data A ON K.name = A.name
        GROUP BY
            K.name
    ),
    total_duration AS (
        SELECT
            SUM(total_duration) AS grand_total_duration
        FROM
            aggregated_data
    )
SELECT
    AD.name AS name,
    AD.calls,
    AD.total_duration AS "DURATION (nsec)",
    AD.sqr_duration AS "SQR (nsec)",
    AD.average_duration AS "AVERAGE (nsec)",
    (CAST(AD.total_duration AS REAL) / TD.grand_total_duration) * 100 AS "PERCENT (INC)",
    AD.min_duration AS "MIN (nsec)",
    AD.max_duration AS "MAX (nsec)",
    AD.variance_duration AS "VARIANCE",
    AD.std_dev_duration AS "STD_DEV"
FROM
    aggregated_data AD
    CROSS JOIN total_duration TD;

--
-- Kernel summary by region name
CREATE VIEW
    `kernel_summary_region` AS
WITH
    avg_data AS (
        SELECT
            region,
            AVG(duration) AS avg_duration
        FROM
            `kernels`
        GROUP BY
            region
    ),
    aggregated_data AS (
        SELECT
            K.region AS name,
            COUNT(*) AS calls,
            SUM(K.duration) AS total_duration,
            SUM(CAST(K.duration AS REAL) * CAST(K.duration AS REAL)) AS sqr_duration,
            A.avg_duration AS average_duration,
            MIN(K.duration) AS min_duration,
            MAX(K.duration) AS max_duration,
            SUM(CAST((K.duration - A.avg_duration) AS REAL) * CAST((K.duration - A.avg_duration) AS REAL)) / (COUNT(*) - 1) AS variance_duration,
            SQRT(
                SUM(CAST((K.duration - A.avg_duration) AS REAL) * CAST((K.duration - A.avg_duration) AS REAL)) / (COUNT(*) - 1)
            ) AS std_dev_duration
        FROM
            `kernels` K
            JOIN avg_data A ON K.region = A.region
        GROUP BY
            K.region
    ),
    total_duration AS (
        SELECT
            SUM(total_duration) AS grand_total_duration
        FROM
            aggregated_data
    )
SELECT
    AD.name AS name,
    AD.calls,
    AD.total_duration AS "DURATION (nsec)",
    AD.sqr_duration AS "SQR (nsec)",
    AD.average_duration AS "AVERAGE (nsec)",
    (CAST(AD.total_duration AS REAL) / TD.grand_total_duration) * 100 AS "PERCENT (INC)",
    AD.min_duration AS "MIN (nsec)",
    AD.max_duration AS "MAX (nsec)",
    AD.variance_duration AS "VARIANCE",
    AD.std_dev_duration AS "STD_DEV"
FROM
    aggregated_data AD
    CROSS JOIN total_duration TD;

--
-- Memory copy summary
CREATE VIEW
    `memory_copy_summary` AS
WITH
    avg_data AS (
        SELECT
            name,
            AVG(duration) AS avg_duration
        FROM
            `memory_copies`
        GROUP BY
            name
    ),
    aggregated_data AS (
        SELECT
            MC.name,
            COUNT(*) AS calls,
            SUM(MC.duration) AS total_duration,
            SUM(CAST(MC.duration AS REAL) * CAST(MC.duration AS REAL)) AS sqr_duration,
            A.avg_duration AS average_duration,
            MIN(MC.duration) AS min_duration,
            MAX(MC.duration) AS max_duration,
            SUM(
                CAST((MC.duration - A.avg_duration) AS REAL) * CAST((MC.duration - A.avg_duration) AS REAL)
            ) / (COUNT(*) - 1) AS variance_duration,
            SQRT(
                SUM(
                    CAST((MC.duration - A.avg_duration) AS REAL) * CAST((MC.duration - A.avg_duration) AS REAL)
                ) / (COUNT(*) - 1)
            ) AS std_dev_duration
        FROM
            `memory_copies` MC
            JOIN avg_data A ON MC.name = A.name
        GROUP BY
            MC.name
    ),
    total_duration AS (
        SELECT
            SUM(total_duration) AS grand_total_duration
        FROM
            aggregated_data
    )
SELECT
    AD.name AS name,
    AD.calls,
    AD.total_duration AS "DURATION (nsec)",
    AD.sqr_duration AS "SQR (nsec)",
    AD.average_duration AS "AVERAGE (nsec)",
    (CAST(AD.total_duration AS REAL) / TD.grand_total_duration) * 100 AS "PERCENT (INC)",
    AD.min_duration AS "MIN (nsec)",
    AD.max_duration AS "MAX (nsec)",
    AD.variance_duration AS "VARIANCE",
    AD.std_dev_duration AS "STD_DEV"
FROM
    aggregated_data AD
    CROSS JOIN total_duration TD;

--
-- Memory allocation summary
CREATE VIEW
    `memory_allocation_summary` AS
WITH
    avg_data AS (
        SELECT
            type AS name,
            AVG(duration) AS avg_duration
        FROM
            `memory_allocations`
        GROUP BY
            type
    ),
    aggregated_data AS (
        SELECT
            MA.type AS name,
            COUNT(*) AS calls,
            SUM(MA.duration) AS total_duration,
            SUM(CAST(MA.duration AS REAL) * CAST(MA.duration AS REAL)) AS sqr_duration,
            A.avg_duration AS average_duration,
            MIN(MA.duration) AS min_duration,
            MAX(MA.duration) AS max_duration,
            SUM(
                CAST((MA.duration - A.avg_duration) AS REAL) * CAST((MA.duration - A.avg_duration) AS REAL)
            ) / (COUNT(*) - 1) AS variance_duration,
            SQRT(
                SUM(
                    CAST((MA.duration - A.avg_duration) AS REAL) * CAST((MA.duration - A.avg_duration) AS REAL)
                ) / (COUNT(*) - 1)
            ) AS std_dev_duration
        FROM
            `memory_allocations` MA
            JOIN avg_data A ON MA.type = A.name
        GROUP BY
            MA.type
    ),
    total_duration AS (
        SELECT
            SUM(total_duration) AS grand_total_duration
        FROM
            aggregated_data
    )
SELECT
    'MEMORY_ALLOCATION_' || AD.name AS name,
    AD.calls,
    AD.total_duration AS "DURATION (nsec)",
    AD.sqr_duration AS "SQR (nsec)",
    AD.average_duration AS "AVERAGE (nsec)",
    (CAST(AD.total_duration AS REAL) / TD.grand_total_duration) * 100 AS "PERCENT (INC)",
    AD.min_duration AS "MIN (nsec)",
    AD.max_duration AS "MAX (nsec)",
    AD.variance_duration AS "VARIANCE",
    AD.std_dev_duration AS "STD_DEV"
FROM
    aggregated_data AD
    CROSS JOIN total_duration TD;
