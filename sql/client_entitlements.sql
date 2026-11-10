/*
================================================================================
 CLIENT DATA ENTITLEMENTS FOR WEALTH MANAGEMENT - DEMO SCRIPT
 One holdings dataset, many audiences, enforced on the data itself:
 - A mapping-table row access policy (advisor book, branch, firm-wide)
 - Masking policies, including net-worth banding
 - Tag-based masking that protects new columns automatically
 - An aggregation policy so a research partner sees only groups of 10+ clients
 - A secure, de-identified research view

 Scenario: a fictional wealth firm with 3 branches, 6 advisors and 300
 clients. Advisors see their own book, branch managers their branch,
 compliance everything, and an external research partner only aggregates.

 This script creates its own objects (ENT_DEMO_DB, ENT_WH and ENT_ roles)
 and changes nothing that already exists. Step 12 removes everything.

 ALL DATA IS SYNTHETIC. Names are generated, emails use @example.com,
 tax IDs start with 9 (never issued as SSNs), tickers are fictional.
================================================================================
*/

-- [step:setup]
-- ============================================================================
-- STEP 1: SETUP
-- ============================================================================

-- Choose the role that runs the guide:
--   'ACCOUNTADMIN'  - simplest, for sandbox accounts
--   'ENT_DEMO_ROLE' - least privilege; create it once with the block below
SET demo_role = 'ACCOUNTADMIN';

-- OPTIONAL: least-privilege demo role. An administrator runs this ONCE,
-- then set demo_role = 'ENT_DEMO_ROLE' above.
-- USE ROLE ACCOUNTADMIN;
-- CREATE ROLE IF NOT EXISTS ENT_DEMO_ROLE COMMENT = 'Runs the client entitlements demo';
-- GRANT CREATE DATABASE  ON ACCOUNT TO ROLE ENT_DEMO_ROLE;        -- demo database (owned by this role)
-- GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ENT_DEMO_ROLE;        -- XSMALL demo warehouse
-- GRANT CREATE ROLE      ON ACCOUNT TO ROLE ENT_DEMO_ROLE;        -- advisor / manager / compliance / partner roles
-- GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE ENT_DEMO_ROLE;    -- tag-based masking (Step 7)
-- GRANT ROLE ENT_DEMO_ROLE TO ROLE SYSADMIN;                      -- admins keep control of what it creates
-- SET my_user = CURRENT_USER();
-- GRANT ROLE ENT_DEMO_ROLE TO USER IDENTIFIER($my_user);

USE ROLE IDENTIFIER($demo_role);

CREATE WAREHOUSE IF NOT EXISTS ENT_WH
    WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE ENT_WH;

CREATE OR REPLACE DATABASE ENT_DEMO_DB;
CREATE SCHEMA IF NOT EXISTS ENT_DEMO_DB.WEALTH;
USE SCHEMA ENT_DEMO_DB.WEALTH;

-- [step:roles]
-- ============================================================================
-- STEP 2: ROLES - One per Advisor Book, Branch, Compliance and Partner
-- ============================================================================

CREATE ROLE IF NOT EXISTS ENT_ADVISOR_01;         -- EAST
CREATE ROLE IF NOT EXISTS ENT_ADVISOR_02;         -- EAST
CREATE ROLE IF NOT EXISTS ENT_ADVISOR_03;         -- CENTRAL
CREATE ROLE IF NOT EXISTS ENT_ADVISOR_04;         -- CENTRAL
CREATE ROLE IF NOT EXISTS ENT_ADVISOR_05;         -- WEST
CREATE ROLE IF NOT EXISTS ENT_ADVISOR_06;         -- WEST
CREATE ROLE IF NOT EXISTS ENT_BRANCH_MGR_EAST;
CREATE ROLE IF NOT EXISTS ENT_BRANCH_MGR_CENTRAL;
CREATE ROLE IF NOT EXISTS ENT_BRANCH_MGR_WEST;
CREATE ROLE IF NOT EXISTS ENT_COMPLIANCE;
CREATE ROLE IF NOT EXISTS ENT_RESEARCH_PARTNER;

-- Grant every demo role to the role running the script, for easy switching
GRANT ROLE ENT_ADVISOR_01         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_ADVISOR_02         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_ADVISOR_03         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_ADVISOR_04         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_ADVISOR_05         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_ADVISOR_06         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_BRANCH_MGR_EAST    TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_BRANCH_MGR_CENTRAL TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_BRANCH_MGR_WEST    TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_COMPLIANCE         TO ROLE IDENTIFIER($demo_role);
GRANT ROLE ENT_RESEARCH_PARTNER   TO ROLE IDENTIFIER($demo_role);

-- Make each test role rely ONLY on its own privileges. With secondary roles
-- on (the Snowsight default for many users), privilege checks would also use
-- your other roles, and a missing grant would not show up in the tests.
USE SECONDARY ROLES NONE;

-- [step:data]
-- ============================================================================
-- STEP 3: SYNTHETIC CLIENTS, ACCOUNTS AND HOLDINGS
-- ============================================================================
-- Every table carries ADVISOR_ID and BRANCH so one row access policy can
-- protect all three without nested lookups.

-- 300 clients: client n goes to branch MOD(n,3), then one of its 2 advisors
CREATE OR REPLACE TABLE ENT_CLIENTS AS
WITH g AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 300))),
names AS (
    SELECT n,
           GET(['Avery','Blake','Casey','Devon','Emerson','Finley','Harper','Jordan','Kendall','Logan',
                'Morgan','Parker','Quinn','Reese','Rowan','Sawyer','Skyler','Taylor','Tatum','Wren'],
               MOD(ABS(HASH(n, 'f')), 20))::STRING AS first_name,
           GET(['Alder','Birch','Calloway','Dunmore','Ellison','Fairbanks','Garrow','Hollis','Ingram','Jessup',
                'Keating','Lockhart','Marlow','Northcott','Oakley','Pemberton','Quill','Radford','Sterling','Thorne'],
               MOD(ABS(HASH(n, 'l')), 20))::STRING AS last_name
    FROM g
)
SELECT
    'C' || LPAD(n + 1, 4, '0')                                                    AS client_id,
    first_name, last_name,
    LOWER(first_name) || '.' || LOWER(last_name) || (n + 1) || '@example.com'     AS email,
    '9' || LPAD(MOD(ABS(HASH(n, 'tin1')), 100), 2, '0') || '-' ||
        LPAD(MOD(ABS(HASH(n, 'tin2')), 100), 2, '0') || '-' ||
        LPAD(MOD(ABS(HASH(n, 'tin3')), 10000), 4, '0')                            AS tax_id,
    DECODE(MOD(n, 3), 0, 'EAST', 1, 'CENTRAL', 'WEST')                            AS branch,
    'ADV' || LPAD(MOD(n, 3) * 2 + MOD(FLOOR(n / 3), 2) + 1, 2, '0')               AS advisor_id,
    DECODE(MOD(ABS(HASH(n, 'seg')), 4), 0, 'ULTRA_HIGH_NET_WORTH', 1, 'HIGH_NET_WORTH', 'MASS_AFFLUENT') AS segment,
    DECODE(MOD(ABS(HASH(n, 'risk')), 3), 0, 'CONSERVATIVE', 1, 'BALANCED', 'GROWTH')                     AS risk_profile,
    ROUND(CASE MOD(ABS(HASH(n, 'seg')), 4)
              WHEN 0 THEN 10000000 + MOD(ABS(HASH(n, 'nw')), 40000000)
              WHEN 1 THEN  1000000 + MOD(ABS(HASH(n, 'nw')), 9000000)
              ELSE          250000 + MOD(ABS(HASH(n, 'nw')), 750000) END, -3)      AS net_worth_usd
FROM names;

-- About 600 accounts (2 per client), inheriting the client's advisor and branch
CREATE OR REPLACE TABLE ENT_ACCOUNTS AS
SELECT
    'AC' || LPAD(ROW_NUMBER() OVER (ORDER BY c.client_id, t.account_type), 5, '0') AS account_id,
    LPAD(MOD(ABS(HASH(c.client_id, t.account_type)), 100000000), 8, '0')        AS account_number,
    c.client_id, c.advisor_id, c.branch, t.account_type
FROM ENT_CLIENTS c
CROSS JOIN (SELECT column1 AS account_type FROM VALUES ('BROKERAGE'), ('IRA')) t;

-- 40 fictional instruments across 8 sectors
CREATE OR REPLACE TABLE ENT_INSTRUMENTS AS
SELECT 'TKR' || LPAD(SEQ4() + 1, 2, '0')                                          AS ticker,
       GET(['TECHNOLOGY','HEALTHCARE','FINANCIALS','ENERGY','CONSUMER','INDUSTRIALS','UTILITIES','REAL_ESTATE'],
           MOD(SEQ4(), 8))::STRING                                               AS sector
FROM TABLE(GENERATOR(ROWCOUNT => 40));

-- About 3,850 holdings, sized to each client's net worth
CREATE OR REPLACE TABLE ENT_HOLDINGS AS
WITH h AS (
    SELECT a.account_id, a.client_id, a.advisor_id, a.branch, c.net_worth_usd, s.k
    FROM ENT_ACCOUNTS a
    JOIN ENT_CLIENTS c ON c.client_id = a.client_id
    JOIN (SELECT SEQ4() AS k FROM TABLE(GENERATOR(ROWCOUNT => 9))) s
      ON s.k < 4 + MOD(ABS(HASH(a.account_id, 'n')), 6)
)
SELECT
    h.account_id, h.client_id, h.advisor_id, h.branch,
    'TKR' || LPAD(MOD(ABS(HASH(h.account_id, h.k)), 40) + 1, 2, '0')              AS ticker,
    ROUND(h.net_worth_usd * (0.02 + MOD(ABS(HASH(h.account_id, h.k, 'w')), 100) / 1000), 2) AS market_value_usd
FROM h;

SELECT branch, advisor_id, COUNT(*) AS clients
FROM ENT_CLIENTS GROUP BY branch, advisor_id ORDER BY advisor_id;

SELECT (SELECT COUNT(*) FROM ENT_CLIENTS) AS clients,
       (SELECT COUNT(*) FROM ENT_ACCOUNTS) AS accounts,
       (SELECT COUNT(*) FROM ENT_HOLDINGS) AS holdings;

-- [step:entitlements]
-- ============================================================================
-- STEP 4: THE ENTITLEMENTS MAPPING TABLE
-- ============================================================================
-- Who may see what, as data. Changing access is an INSERT or DELETE here,
-- never a policy rewrite.
--   SCOPE_TYPE = 'ADVISOR' -> rows whose ADVISOR_ID = SCOPE_VALUE
--   SCOPE_TYPE = 'BRANCH'  -> rows whose BRANCH     = SCOPE_VALUE
--   SCOPE_TYPE = 'ALL'     -> every row

CREATE OR REPLACE TABLE ENT_ENTITLEMENTS (ROLE_NAME VARCHAR, SCOPE_TYPE VARCHAR, SCOPE_VALUE VARCHAR);
INSERT INTO ENT_ENTITLEMENTS VALUES
    ('ENT_ADVISOR_01', 'ADVISOR', 'ADV01'),
    ('ENT_ADVISOR_02', 'ADVISOR', 'ADV02'),
    ('ENT_ADVISOR_03', 'ADVISOR', 'ADV03'),
    ('ENT_ADVISOR_04', 'ADVISOR', 'ADV04'),
    ('ENT_ADVISOR_05', 'ADVISOR', 'ADV05'),
    ('ENT_ADVISOR_06', 'ADVISOR', 'ADV06'),
    ('ENT_BRANCH_MGR_EAST',    'BRANCH', 'EAST'),
    ('ENT_BRANCH_MGR_CENTRAL', 'BRANCH', 'CENTRAL'),
    ('ENT_BRANCH_MGR_WEST',    'BRANCH', 'WEST'),
    ('ENT_COMPLIANCE',         'ALL', NULL),
    ('ENT_RESEARCH_PARTNER',   'ALL', NULL);   -- partner reaches data only through aggregated views

SELECT * FROM ENT_ENTITLEMENTS ORDER BY ROLE_NAME;

-- [step:rowaccess]
-- ============================================================================
-- STEP 5: ROW ACCESS POLICY DRIVEN BY THE MAPPING TABLE
-- ============================================================================

CREATE OR REPLACE ROW ACCESS POLICY ent_book_policy
    AS (advisor_val VARCHAR, branch_val VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE')
    OR EXISTS (
        SELECT 1 FROM ENT_DEMO_DB.WEALTH.ENT_ENTITLEMENTS e
        WHERE e.role_name = CURRENT_ROLE()
          AND (   e.scope_type = 'ALL'
               OR (e.scope_type = 'ADVISOR' AND e.scope_value = advisor_val)
               OR (e.scope_type = 'BRANCH'  AND e.scope_value = branch_val))
    );

-- One policy protects all three tables
ALTER TABLE ENT_CLIENTS  ADD ROW ACCESS POLICY ent_book_policy ON (advisor_id, branch);
ALTER TABLE ENT_ACCOUNTS ADD ROW ACCESS POLICY ent_book_policy ON (advisor_id, branch);
ALTER TABLE ENT_HOLDINGS ADD ROW ACCESS POLICY ent_book_policy ON (advisor_id, branch);

-- Internal roles get SELECT on the tables; the partner gets views only (Steps 8-9)
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_01;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_02;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_03;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_04;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_05;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_ADVISOR_06;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_BRANCH_MGR_EAST;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_BRANCH_MGR_CENTRAL;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_BRANCH_MGR_WEST;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_COMPLIANCE;
GRANT USAGE ON WAREHOUSE ENT_WH TO ROLE ENT_RESEARCH_PARTNER;

GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_01;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_02;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_03;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_04;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_05;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_ADVISOR_06;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_BRANCH_MGR_EAST;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_BRANCH_MGR_CENTRAL;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_BRANCH_MGR_WEST;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_COMPLIANCE;
GRANT USAGE ON DATABASE ENT_DEMO_DB TO ROLE ENT_RESEARCH_PARTNER;

GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_01;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_02;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_03;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_04;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_05;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_ADVISOR_06;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_BRANCH_MGR_EAST;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_BRANCH_MGR_CENTRAL;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_BRANCH_MGR_WEST;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_COMPLIANCE;
GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO ROLE ENT_RESEARCH_PARTNER;

GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_01;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_02;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_03;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_04;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_05;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_ADVISOR_06;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_BRANCH_MGR_EAST;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_BRANCH_MGR_CENTRAL;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_BRANCH_MGR_WEST;
GRANT SELECT ON TABLE ENT_CLIENTS  TO ROLE ENT_COMPLIANCE;
GRANT SELECT ON TABLE ENT_ACCOUNTS TO ROLE ENT_ADVISOR_01;
GRANT SELECT ON TABLE ENT_ACCOUNTS TO ROLE ENT_BRANCH_MGR_EAST;
GRANT SELECT ON TABLE ENT_ACCOUNTS TO ROLE ENT_COMPLIANCE;
GRANT SELECT ON TABLE ENT_HOLDINGS TO ROLE ENT_ADVISOR_01;
GRANT SELECT ON TABLE ENT_HOLDINGS TO ROLE ENT_BRANCH_MGR_EAST;
GRANT SELECT ON TABLE ENT_HOLDINGS TO ROLE ENT_COMPLIANCE;

-- Rows visible per role
USE ROLE ENT_ADVISOR_01;
SELECT 'ENT_ADVISOR_01' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE ENT_ADVISOR_02;
SELECT 'ENT_ADVISOR_02' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE ENT_BRANCH_MGR_EAST;
SELECT 'ENT_BRANCH_MGR_EAST' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE ENT_BRANCH_MGR_WEST;
SELECT 'ENT_BRANCH_MGR_WEST' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE ENT_COMPLIANCE;
SELECT 'ENT_COMPLIANCE' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE IDENTIFIER($demo_role);

-- Entitlements are data: move client book ADV02 to advisor 01 for a coverage
-- change, check the effect, then put it back
INSERT INTO ENT_ENTITLEMENTS VALUES ('ENT_ADVISOR_01', 'ADVISOR', 'ADV02');
USE ROLE ENT_ADVISOR_01;
SELECT 'ENT_ADVISOR_01 (covering ADV02)' AS role, COUNT(*) AS clients_visible, LISTAGG(DISTINCT advisor_id, ',') AS books FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS;
USE ROLE IDENTIFIER($demo_role);
DELETE FROM ENT_ENTITLEMENTS WHERE role_name = 'ENT_ADVISOR_01' AND scope_value = 'ADV02';

-- [step:masking]
-- ============================================================================
-- STEP 6: MASKING POLICIES (including net-worth banding)
-- ============================================================================
-- Compliance sees everything. Advisors see what they need to serve their own
-- clients. Branch managers see oversight-level detail.

CREATE OR REPLACE MASKING POLICY ent_mask_tax_id AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE') THEN val
        WHEN CURRENT_ROLE() LIKE 'ENT_ADVISOR_%' THEN '***-**-' || RIGHT(val, 4)
        ELSE '***-**-****'
    END;

CREATE OR REPLACE MASKING POLICY ent_mask_account_no AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE') THEN val
        ELSE '****' || RIGHT(val, 4)
    END;

CREATE OR REPLACE MASKING POLICY ent_mask_email AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE')
          OR CURRENT_ROLE() LIKE 'ENT_ADVISOR_%' THEN val
        ELSE '****@' || SPLIT_PART(val, '@', 2)
    END;

-- Banding: anyone but compliance sees the lower bound of the client's band
-- (a masking policy must return the column's own type, so the band is a number)
CREATE OR REPLACE MASKING POLICY ent_band_net_worth AS (val NUMBER) RETURNS NUMBER ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE') THEN val
        WHEN val >= 10000000 THEN 10000000
        WHEN val >=  5000000 THEN  5000000
        WHEN val >=  1000000 THEN  1000000
        WHEN val >=   250000 THEN   250000
        ELSE 0
    END;

ALTER TABLE ENT_CLIENTS  MODIFY COLUMN tax_id         SET MASKING POLICY ent_mask_tax_id;
ALTER TABLE ENT_CLIENTS  MODIFY COLUMN email          SET MASKING POLICY ent_mask_email;
ALTER TABLE ENT_CLIENTS  MODIFY COLUMN net_worth_usd  SET MASKING POLICY ent_band_net_worth;
ALTER TABLE ENT_ACCOUNTS MODIFY COLUMN account_number SET MASKING POLICY ent_mask_account_no;

-- Client C0001 (advisor ADV01, EAST branch) as each role sees them
USE ROLE ENT_ADVISOR_01;
SELECT 'ENT_ADVISOR_01' AS role, c.client_id, c.first_name || ' ' || c.last_name AS name, c.email, c.tax_id, c.net_worth_usd, a.account_number
FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS c JOIN ENT_DEMO_DB.WEALTH.ENT_ACCOUNTS a ON a.client_id = c.client_id
WHERE c.client_id = 'C0001' AND a.account_type = 'BROKERAGE';
USE ROLE ENT_BRANCH_MGR_EAST;
SELECT 'ENT_BRANCH_MGR_EAST' AS role, c.client_id, c.first_name || ' ' || c.last_name AS name, c.email, c.tax_id, c.net_worth_usd, a.account_number
FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS c JOIN ENT_DEMO_DB.WEALTH.ENT_ACCOUNTS a ON a.client_id = c.client_id
WHERE c.client_id = 'C0001' AND a.account_type = 'BROKERAGE';
USE ROLE ENT_COMPLIANCE;
SELECT 'ENT_COMPLIANCE' AS role, c.client_id, c.first_name || ' ' || c.last_name AS name, c.email, c.tax_id, c.net_worth_usd, a.account_number
FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS c JOIN ENT_DEMO_DB.WEALTH.ENT_ACCOUNTS a ON a.client_id = c.client_id
WHERE c.client_id = 'C0001' AND a.account_type = 'BROKERAGE';
USE ROLE ENT_ADVISOR_02;
SELECT 'ENT_ADVISOR_02' AS role, COUNT(*) AS rows_for_c0001 FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS WHERE client_id = 'C0001';
USE ROLE IDENTIFIER($demo_role);

-- [step:tags]
-- ============================================================================
-- STEP 7: TAG-BASED MASKING FOR NEW COLUMNS
-- ============================================================================
-- Attach a policy to a tag once; any string column tagged later is masked
-- immediately, with no new policy to write.

CREATE OR REPLACE TAG CLIENT_SENSITIVITY ALLOWED_VALUES 'CONFIDENTIAL', 'RESTRICTED';

CREATE OR REPLACE MASKING POLICY ent_mask_sensitive AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE')
          OR CURRENT_ROLE() LIKE 'ENT_ADVISOR_%' THEN val
        ELSE '*** RESTRICTED ***'
    END;

ALTER TAG CLIENT_SENSITIVITY SET MASKING POLICY ent_mask_sensitive;

-- A new column arrives: a mobile phone number. Tag it and it's protected.
ALTER TABLE ENT_CLIENTS ADD COLUMN mobile_phone VARCHAR;
UPDATE ENT_CLIENTS SET mobile_phone = '555-01' || LPAD(MOD(ABS(HASH(client_id)), 100), 2, '0');
ALTER TABLE ENT_CLIENTS MODIFY COLUMN mobile_phone SET TAG CLIENT_SENSITIVITY = 'CONFIDENTIAL';

USE ROLE ENT_ADVISOR_01;
SELECT 'ENT_ADVISOR_01' AS role, client_id, mobile_phone FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS WHERE client_id = 'C0001';
USE ROLE ENT_BRANCH_MGR_EAST;
SELECT 'ENT_BRANCH_MGR_EAST' AS role, client_id, mobile_phone FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS WHERE client_id = 'C0001';
USE ROLE IDENTIFIER($demo_role);

-- [step:aggregation]
-- ============================================================================
-- STEP 8: AGGREGATION POLICY FOR THE RESEARCH PARTNER
-- ============================================================================
-- The partner may only run grouped queries, and groups with fewer than 10
-- clients are folded into a single "remainder" row, so no individual client
-- can be singled out. The view has one row per client, so "10 rows" means
-- "10 clients".

CREATE OR REPLACE VIEW ENT_CLIENT_PROFILE AS
SELECT c.client_id, c.branch, c.segment, c.risk_profile,
       SUM(h.market_value_usd) AS aum_usd
FROM ENT_CLIENTS c
JOIN ENT_HOLDINGS h ON h.client_id = c.client_id
GROUP BY c.client_id, c.branch, c.segment, c.risk_profile;

CREATE OR REPLACE AGGREGATION POLICY ent_min_10_clients
    AS () RETURNS AGGREGATION_CONSTRAINT ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'ENT_DEMO_ROLE', 'ENT_COMPLIANCE') THEN NO_AGGREGATION_CONSTRAINT()
        ELSE AGGREGATION_CONSTRAINT(MIN_GROUP_SIZE => 10)
    END;

ALTER VIEW ENT_CLIENT_PROFILE SET AGGREGATION POLICY ent_min_10_clients;
GRANT SELECT ON VIEW ENT_CLIENT_PROFILE TO ROLE ENT_RESEARCH_PARTNER;

USE ROLE ENT_RESEARCH_PARTNER;

-- 8a. A row-level query is rejected (captured here so the script keeps going)
EXECUTE IMMEDIATE $$
DECLARE
    rs RESULTSET;
BEGIN
    rs := (SELECT client_id, aum_usd FROM ENT_DEMO_DB.WEALTH.ENT_CLIENT_PROFILE LIMIT 5);
    RETURN 'Row-level query ALLOWED';
EXCEPTION
    WHEN OTHER THEN RETURN 'Row-level query BLOCKED: ' || SQLERRM;
END;
$$;

-- 8b. Grouped queries work; small groups land in the remainder (NULL) row
SELECT branch, segment, COUNT(*) AS clients, ROUND(AVG(aum_usd)) AS avg_aum_usd
FROM ENT_DEMO_DB.WEALTH.ENT_CLIENT_PROFILE
GROUP BY branch, segment
ORDER BY branch, segment;

USE ROLE IDENTIFIER($demo_role);

-- [step:research]
-- ============================================================================
-- STEP 9: SECURE, DE-IDENTIFIED RESEARCH VIEW
-- ============================================================================
-- A secure view hides its definition and exposes only sector exposure by
-- branch: no client, account or advisor identifiers at all.

CREATE OR REPLACE SECURE VIEW ENT_RESEARCH_SECTOR_EXPOSURE AS
SELECT h.branch, i.sector,
       COUNT(DISTINCT h.client_id)          AS clients,
       ROUND(SUM(h.market_value_usd), -3)   AS market_value_usd
FROM ENT_HOLDINGS h
JOIN ENT_INSTRUMENTS i ON i.ticker = h.ticker
GROUP BY h.branch, i.sector
HAVING COUNT(DISTINCT h.client_id) >= 10;

GRANT SELECT ON VIEW ENT_RESEARCH_SECTOR_EXPOSURE TO ROLE ENT_RESEARCH_PARTNER;

USE ROLE ENT_RESEARCH_PARTNER;
SELECT branch, sector, clients, market_value_usd
FROM ENT_DEMO_DB.WEALTH.ENT_RESEARCH_SECTOR_EXPOSURE
WHERE branch = 'EAST'
ORDER BY market_value_usd DESC;

-- The partner cannot read the underlying client table at all
EXECUTE IMMEDIATE $$
DECLARE
    rs RESULTSET;
BEGIN
    rs := (SELECT COUNT(*) FROM ENT_DEMO_DB.WEALTH.ENT_CLIENTS);
    RETURN 'Client table ALLOWED';
EXCEPTION
    WHEN OTHER THEN RETURN 'Client table BLOCKED: ' || SQLERRM;
END;
$$;

USE ROLE IDENTIFIER($demo_role);

-- [step:testing]
-- ============================================================================
-- STEP 10: TEST AS EACH ROLE - Assets under management by book
-- ============================================================================
-- The same query, five roles, five different answers, with no WHERE clause
-- and no application logic.

USE ROLE ENT_ADVISOR_01;
SELECT 'ENT_ADVISOR_01' AS role, COUNT(DISTINCT client_id) AS clients, ROUND(SUM(market_value_usd), -3) AS aum_usd FROM ENT_DEMO_DB.WEALTH.ENT_HOLDINGS;
USE ROLE ENT_BRANCH_MGR_EAST;
SELECT 'ENT_BRANCH_MGR_EAST' AS role, COUNT(DISTINCT client_id) AS clients, ROUND(SUM(market_value_usd), -3) AS aum_usd FROM ENT_DEMO_DB.WEALTH.ENT_HOLDINGS;
USE ROLE ENT_COMPLIANCE;
SELECT 'ENT_COMPLIANCE' AS role, COUNT(DISTINCT client_id) AS clients, ROUND(SUM(market_value_usd), -3) AS aum_usd FROM ENT_DEMO_DB.WEALTH.ENT_HOLDINGS;
USE ROLE IDENTIFIER($demo_role);

-- [step:share]
-- ============================================================================
-- STEP 11: (OPTIONAL) SHARE THE RESEARCH VIEW WITH A PARTNER ACCOUNT
-- ============================================================================
-- Needs a second Snowflake account. Secure views can be shared directly;
-- the partner queries live data with no copies or file transfers.
-- Replace <PARTNER_ORG>.<PARTNER_ACCOUNT> with the consumer's identifier.

-- CREATE SHARE ENT_RESEARCH_SHARE;
-- GRANT USAGE ON DATABASE ENT_DEMO_DB TO SHARE ENT_RESEARCH_SHARE;
-- GRANT USAGE ON SCHEMA ENT_DEMO_DB.WEALTH TO SHARE ENT_RESEARCH_SHARE;
-- GRANT SELECT ON VIEW ENT_DEMO_DB.WEALTH.ENT_RESEARCH_SECTOR_EXPOSURE TO SHARE ENT_RESEARCH_SHARE;
-- ALTER SHARE ENT_RESEARCH_SHARE ADD ACCOUNTS = <PARTNER_ORG>.<PARTNER_ACCOUNT>;

-- [step:cleanup]
-- ============================================================================
-- STEP 12: CLEANUP (Optional - uncomment to remove demo objects)
-- ============================================================================

-- USE ROLE IDENTIFIER($demo_role);
-- USE SECONDARY ROLES ALL;               -- restore your usual setting if you use it
-- DROP SHARE IF EXISTS ENT_RESEARCH_SHARE;
-- DROP DATABASE IF EXISTS ENT_DEMO_DB;     -- tables, views, policies and tag
-- DROP WAREHOUSE IF EXISTS ENT_WH;
-- DROP ROLE IF EXISTS ENT_ADVISOR_01;
-- DROP ROLE IF EXISTS ENT_ADVISOR_02;
-- DROP ROLE IF EXISTS ENT_ADVISOR_03;
-- DROP ROLE IF EXISTS ENT_ADVISOR_04;
-- DROP ROLE IF EXISTS ENT_ADVISOR_05;
-- DROP ROLE IF EXISTS ENT_ADVISOR_06;
-- DROP ROLE IF EXISTS ENT_BRANCH_MGR_EAST;
-- DROP ROLE IF EXISTS ENT_BRANCH_MGR_CENTRAL;
-- DROP ROLE IF EXISTS ENT_BRANCH_MGR_WEST;
-- DROP ROLE IF EXISTS ENT_COMPLIANCE;
-- DROP ROLE IF EXISTS ENT_RESEARCH_PARTNER;
-- UNSET demo_role;
-- If you created the least-privilege role, an administrator removes it:
-- USE ROLE ACCOUNTADMIN;
-- DROP ROLE IF EXISTS ENT_DEMO_ROLE;
