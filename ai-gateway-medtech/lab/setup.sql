-- =============================================================================
-- Cortex AI Gateway + LangChain + MCP: Setup Script
-- =============================================================================
-- Run this script before starting the notebook.
-- Creates: database, medical device commercial tables and synthetic data
--          (fiscal year Oct 2025 - Sep 2026), a product knowledge corpus and Cortex
--          Search service, two semantic views, a share-loss predictions table,
--          Cortex Agent, MCP server, AI Gateway configuration, eval set, optimizer
--          tables, app access, commercial team personas (service users and
--          roles), per-user quotas and a gateway budget.
-- Gateway Tools (Glean + Snowflake MCP for CoCo Desktop) is set up separately:
--          see lab/tools_setup.sql and the README.
-- Takes about 3 minutes on an XS warehouse (data generation).
--
-- Prerequisites:
--   - ACCOUNTADMIN, plus SYSADMIN granted to your user. Lab objects are created
--     as SYSADMIN (so the lab, notebook and app can own and extend them); the
--     gateway, grants, integration and service user steps switch to ACCOUNTADMIN.
--   - Cross-region inference enabled (for Claude model access)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

-- SYSADMIN must own the database: later sections and the notebook create views,
-- tables, tags, models and the app as SYSADMIN.
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS CORTEX_GATEWAY_MEDTECH_LAB;
USE DATABASE CORTEX_GATEWAY_MEDTECH_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS GATEWAY_MEDTECH_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE GATEWAY_MEDTECH_WH;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. MEDICAL DEVICE COMMERCIAL TABLES (fiscal year Oct 2025 - Sep 2026)
-- ─────────────────────────────────────────────────────────────────────────────
-- A global medical device manufacturer selling implants, capital-free systems and
-- consumables into hospitals, IDNs and ambulatory surgery centers (ASCs) through a
-- direct field sales team. All data is synthetic and deterministic (HASH seeds).
--
-- Entities
--   DIM_PRODUCT_FAMILY   16 product families across 5 therapy areas (+ labeling facts)
--   DIM_PRODUCT          SKUs per family
--   DIM_TERRITORY        24 sales territories / reps in 4 regions
--   DIM_ACCOUNT          300 hospitals, academic centers, ASCs and specialty clinics,
--                        rolled up to IDNs and GPOs
--   DIM_HCP              implanting physicians and surgeons per account and therapy
--   FACT_PROCEDURES      every market procedure at the account, ours or a competitor's
--   FACT_SALES_ORDERS    our implant and consumable order lines (net of contract price)
--   FACT_CONTRACTS       GPO / IDN / direct agreements per account and therapy area
--   FACT_QUOTA_ATTAINMENT territory x therapy x month quota vs actual
--   FACT_CONSIGNMENT_INVENTORY  monthly field (consigned) inventory by account and family
--   FACT_COMPETITIVE_EVENTS     evaluations, trials, VAC reviews, conversions, win-backs
--   FACT_COMPLAINTS      product complaints (no patient data)
--   ML_ACCOUNT_FEATURES  account features as of 2026-03-31 + observed H2 share change
--   PRODUCT_KNOWLEDGE_DOCS  IFU summaries, clinical evidence, battlecards, policies
--
-- A latent account "loyalty" drives everything: low-loyalty accounts face more
-- competitive pressure, run evaluations and trials in H1, and lose procedure share
-- in H2. The share-loss model in the notebook learns that from H1 signals only.

-- ======================================================= DIM_PRODUCT_FAMILY
CREATE OR REPLACE TABLE DIM_PRODUCT_FAMILY (
    FAMILY_ID            VARCHAR PRIMARY KEY,
    PRODUCT_FAMILY       VARCHAR,
    THERAPY_AREA         VARCHAR,
    OPERATING_UNIT       VARCHAR,
    PROCEDURE_TYPE       VARCHAR,   -- NULL for consumables
    IS_CONSUMABLE        BOOLEAN,
    DEVICE_CLASS         VARCHAR,
    LIST_PRICE           NUMBER(10,2),
    BASE_MONTHLY_VOLUME  FLOAT,     -- procedures per month at a 250-bed community hospital
    PRIMARY_COMPETITOR   VARCHAR,
    COMPETITOR_PRODUCT   VARCHAR,
    INDICATION           VARCHAR,
    CONTRAINDICATION     VARCHAR,
    MRI_STATUS           VARCHAR,
    LONGEVITY            VARCHAR,
    PIVOTAL_TRIAL        VARCHAR,
    TRIAL_PATIENTS       NUMBER,
    PRIMARY_ENDPOINT     VARCHAR,
    ENDPOINT_RESULT      VARCHAR,
    KEY_DIFFERENTIATOR   VARCHAR,
    LAUNCH_DATE          DATE
);

INSERT INTO DIM_PRODUCT_FAMILY VALUES
('F01','Pulsar Pacemaker','Cardiac Rhythm','Cardiovascular','Pacemaker implant',FALSE,'Class III',8200,6.0,'Corvex Medical','Corvex Rhythmia DR',
 'Symptomatic bradycardia, sick sinus syndrome and AV block requiring dual-chamber pacing','Patients with a unipolar lead system or an existing ICD','MR Conditional, full body, 1.5T and 3T','11.5 years projected battery longevity',
 'PULSE-HF',1240,'Freedom from system-related complications at 12 months','97.8%','Adaptive rate response reduced unnecessary right-ventricular pacing by 34% vs fixed-rate pacing','2021-04-12'),
('F02','Sentinel ICD','Cardiac Rhythm','Cardiovascular','ICD implant',FALSE,'Class III',24500,3.0,'Brightline Scientific','Brightline Guardian ICD',
 'Primary and secondary prevention of sudden cardiac death in patients at risk of ventricular arrhythmias','Ventricular tachyarrhythmias from a reversible cause','MR Conditional, full body, 1.5T and 3T','10.2 years projected battery longevity',
 'SENTINEL-SCD',2100,'Appropriate shock efficacy for induced VF','98.6%','Inappropriate shock rate of 1.9% at 2 years through morphology discrimination','2020-09-01'),
('F03','Lumen Leadless Pacemaker','Cardiac Rhythm','Cardiovascular','Leadless pacemaker implant',FALSE,'Class III',12800,2.0,'Brightline Scientific','Brightline Nano LP',
 'Single-chamber ventricular pacing in patients with permanent AF or high-grade AV block','Femoral venous access not feasible; mechanical tricuspid valve','MR Conditional, full body, 1.5T and 3T','12.0 years projected battery longevity',
 'LUMEN-IDE',725,'Major complication-free rate at 12 months','96.1%','63% fewer major complications than transvenous single-chamber systems in the pivotal comparison','2022-02-15'),
('F04','Arc Insertable Cardiac Monitor','Cardiac Rhythm','Cardiovascular','ICM insertion',FALSE,'Class II',3400,3.0,'Corvex Medical','Corvex InSight ICM',
 'Long-term monitoring of patients with unexplained syncope, palpitations or suspected AF, including cryptogenic stroke','None known','MR Conditional, 1.5T and 3T','4.5 years monitoring life',
 'ARC-DETECT',860,'AF episode detection sensitivity','94.2%','AI-filtered alerts cut false-positive AF alerts by 46%, reducing clinic review burden','2023-06-05'),
('F05','Valvia TAVR System','Structural Heart','Cardiovascular','TAVR',FALSE,'Class III',32500,3.0,'Brightline Scientific','Brightline Apex Valve',
 'Severe symptomatic aortic stenosis in patients at any surgical risk','Active endocarditis; bicuspid anatomy not suitable per CT sizing','MR Conditional, 1.5T and 3T','Bioprosthetic tissue valve; 5-year durability data available',
 'VALVIA-LR',1468,'All-cause mortality or disabling stroke at 1 year','5.3%','New permanent pacemaker rate of 8.1%, lowest in the self-expanding class','2021-11-08'),
('F06','Annulus Repair Ring','Structural Heart','Cardiovascular','Mitral valve repair',FALSE,'Class II',4200,1.5,'Novix Health','Novix Contour Ring',
 'Repair of mitral or tricuspid regurgitation through annuloplasty','Heavily calcified annulus; active endocarditis','MR Safe','Permanent implant',
 'ANNULUS-REG',540,'Freedom from reoperation at 3 years','95.4%','Saddle-shaped geometry preserved leaflet coaptation in 98% of repairs','2019-03-18'),
('F07','Axion SCS System','Neuromodulation','Neuroscience','Spinal cord stimulator implant',FALSE,'Class III',23800,2.0,'Novix Health','Novix Sync SCS',
 'Chronic intractable pain of the trunk and limbs, including failed back surgery syndrome and painful diabetic neuropathy','Failed trial stimulation; inability to operate the system','MR Conditional, full body, 1.5T and 3T','9 years (rechargeable)',
 'AXION-PAIN',410,'Responders with at least 50% back-pain relief at 12 months','76%','Closed-loop sensing adjusts output to spinal cord signals 50 times per second','2022-08-22'),
('F08','Axion DBS System','Neuromodulation','Neuroscience','Deep brain stimulator implant',FALSE,'Class III',31000,0.6,'Brightline Scientific','Brightline Neura DBS',
 'Parkinson disease motor symptoms, essential tremor and dystonia not adequately controlled by medication','Diathermy exposure; patients unable to operate the system','MR Conditional, full body, 1.5T','15 years (rechargeable)',
 'AXION-PD',310,'Improvement in off-medication motor score at 6 months','48%','Sensing-enabled programming shortened time to optimal settings by 40%','2021-05-10'),
('F09','Fluent Sacral Neuromodulation','Neuromodulation','Neuroscience','Sacral neuromodulation implant',FALSE,'Class III',15200,1.5,'Novix Health','Novix Calm SNM',
 'Overactive bladder, non-obstructive urinary retention and chronic fecal incontinence after failed conservative therapy','Failed test stimulation','MR Conditional, full body, 1.5T and 3T','15 years (rechargeable)',
 'FLUENT-OAB',340,'Therapy responders at 12 months','82%','Recharge interval of up to 6 weeks between charges','2023-01-23'),
('F10','Glyde Insulin Pump','Diabetes','Diabetes','Insulin pump start',FALSE,'Class II',6400,4.0,'Corvex Medical','Corvex Flowline Pump',
 'Continuous subcutaneous insulin delivery with automated adjustment for people with type 1 diabetes age 7 and older','Patients unable to use CGM or follow device instructions','MR Unsafe: remove pump before MRI','4-year warranty',
 'GLYDE-AUTO',520,'Time in range 70-180 mg/dL','74%','Automated correction boluses increased time in range by 11 points vs manual pump therapy','2022-10-03'),
('F11','Glyde CGM Sensor','Diabetes','Diabetes',NULL,TRUE,'Class II',85,0,'Corvex Medical','Corvex G-Sense',
 'Continuous glucose monitoring for diabetes management, paired with the Glyde pump or app','None known','MR Unsafe: remove sensor before MRI','7-day wear',
 'GLYDE-SENSE',380,'Mean absolute relative difference (MARD) vs reference','8.7%','No fingerstick calibration required','2022-10-03'),
('F12','Glyde Infusion Set','Diabetes','Diabetes',NULL,TRUE,'Class II',14,0,'Corvex Medical','Corvex SureSet',
 'Subcutaneous delivery of insulin from the Glyde pump','Known adhesive allergy','MR Unsafe','7-day extended wear',
 'GLYDE-EXT',260,'Infusion set survival at 7 days','77%','Extended wear halves set changes compared with 3-day sets','2023-04-17'),
('F13','Torque Powered Stapler','Surgical','Medical Surgical','Stapled surgical procedure',FALSE,'Class II',950,12.0,'Novix Health','Novix Edgeline Stapler',
 'Transection, resection and anastomosis in open and minimally invasive general, thoracic and bariatric surgery','Tissue thicker than the reload specification','Not applicable (not implanted)','Reusable handle, 300 firings',
 'TORQUE-LEAK',600,'Staple-line leak rate','0.8%','Adaptive firing senses tissue compression and adjusts speed, reducing malformed staples','2020-02-10'),
('F14','Torque Stapler Reload','Surgical','Medical Surgical',NULL,TRUE,'Class II',260,0,'Novix Health','Novix Edgeline Reload',
 'Single-use reload cartridges for the Torque Powered Stapler','Tissue thicker than the reload specification','Not applicable','Single use',
 'TORQUE-LEAK',600,'Staple-line leak rate','0.8%','Gripping surface technology reduced tissue slippage by 32%','2020-02-10'),
('F15','Fuse Energy Sealer','Surgical','Medical Surgical','Vessel sealing procedure',FALSE,'Class II',1250,10.0,'Novix Health','Novix Sealwave',
 'Ligation and division of vessels up to 7 mm and tissue bundles in open and laparoscopic surgery','Tubal sterilization or contraception procedures','Not applicable (not implanted)','Single use',
 'FUSE-SEAL',280,'Seal burst pressure relative to normal systolic pressure','3.5x','Seal cycle under 3 seconds, with lateral thermal spread under 1 mm','2021-07-19'),
('F16','Halo Hernia Mesh','Surgical','Medical Surgical','Hernia repair',FALSE,'Class II',640,8.0,'Novix Health','Novix Meshform',
 'Reinforcement of soft tissue in inguinal and ventral hernia repair','Contaminated surgical field; infants or children with planned growth','MR Safe','Permanent implant',
 'HALO-REPAIR',720,'Hernia recurrence at 2 years','2.1%','Self-gripping design eliminated fixation tacks in 91% of laparoscopic repairs','2019-09-30');

-- ======================================================= DIM_PRODUCT (SKUs)
CREATE OR REPLACE TABLE DIM_PRODUCT AS
SELECT f.FAMILY_ID || '-' || LPAD(v.k, 2, '0')                        AS PRODUCT_ID,
       f.FAMILY_ID,
       f.PRODUCT_FAMILY || ' ' || v.variant                            AS SKU_NAME,
       f.PRODUCT_FAMILY,
       f.THERAPY_AREA,
       f.OPERATING_UNIT,
       f.DEVICE_CLASS,
       f.IS_CONSUMABLE,
       ROUND(f.LIST_PRICE * v.price_mult, 2)                           AS LIST_PRICE,
       f.LAUNCH_DATE,
       IFF(v.k = 1, 'Current', 'Current')                              AS LIFECYCLE_STATUS
FROM DIM_PRODUCT_FAMILY f
JOIN (SELECT * FROM VALUES (1,'Standard',1.00),(2,'Plus',1.12),(3,'MRI-Optimized',1.20)) v(k, variant, price_mult)
  ON v.k <= IFF(f.IS_CONSUMABLE, 1, 3);

-- ======================================================= DIM_TERRITORY
CREATE OR REPLACE TABLE DIM_TERRITORY AS
WITH t AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 24))
)
SELECT 'T' || LPAD(n, 2, '0') AS TERRITORY_ID,
       ARRAY_CONSTRUCT('Northeast','Southeast','Central','West')[FLOOR((n - 1) / 6)]::VARCHAR AS REGION,
       ARRAY_CONSTRUCT('NE','SE','CE','WE')[FLOOR((n - 1) / 6)]::VARCHAR || '-' || (MOD(n - 1, 6) + 1) AS TERRITORY_NAME,
       ARRAY_CONSTRUCT('Avery Chen','Jordan Patel','Morgan Reyes','Taylor Brooks','Casey Nguyen','Riley Okafor',
                       'Drew Martinez','Quinn Sullivan','Jamie Rossi','Parker Kim','Skyler Grant','Reese Alvarez',
                       'Cameron Hughes','Dakota Singh','Emerson Cole','Hayden Price','Logan Weiss','Rowan Diaz',
                       'Sage Thompson','Blake Moreno','Finley Hart','Kendall Shaw','Peyton Lowe','Arden Wu')[n - 1]::VARCHAR AS REP_NAME,
       UNIFORM(1, 15, HASH(n, 'tenure')) AS REP_TENURE_YEARS
FROM t;

-- ======================================================= DIM_ACCOUNT
-- LOYALTY is the latent driver (not exposed in the semantic views).
CREATE OR REPLACE TABLE DIM_ACCOUNT AS
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 300))
), a AS (
    SELECT n,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'type')) AS u_type,
        UNIFORM(0, 23, HASH(n, 'terr')) AS terr_idx,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'loyalty')) AS loyalty
    FROM base
)
SELECT 'A' || LPAD(n, 4, '0') AS ACCOUNT_ID,
    ARRAY_CONSTRUCT('St. Mary','Riverside','Mercy','Lakeview','Providence','Summit','Northfield','Bayview',
                    'Sacred Heart','Pinecrest','Harbor','Valley','Memorial','Grandview','Cedar Ridge','Unity',
                    'Hillcrest','Oakwood','Fairview','Westbrook')[MOD(n, 20)]::VARCHAR || ' ' ||
    CASE WHEN u_type < 0.15 THEN 'University Medical Center'
         WHEN u_type < 0.70 THEN ARRAY_CONSTRUCT('Regional Hospital','Medical Center','Community Hospital','Health Center')[MOD(n, 4)]::VARCHAR
         WHEN u_type < 0.90 THEN 'Surgery Center'
         ELSE ARRAY_CONSTRUCT('Heart & Vascular Clinic','Diabetes & Endocrine Clinic')[MOD(n, 2)]::VARCHAR END
    || ' ' || n AS ACCOUNT_NAME,
    CASE WHEN u_type < 0.15 THEN 'Academic Medical Center'
         WHEN u_type < 0.70 THEN 'Community Hospital'
         WHEN u_type < 0.90 THEN 'Ambulatory Surgery Center'
         ELSE 'Specialty Clinic' END AS ACCOUNT_TYPE,
    t.TERRITORY_ID,
    t.REGION,
    ARRAY_CONSTRUCT('NY','MA','PA','NJ','FL','GA','NC','TN','IL','OH','TX','MN','CA','WA','AZ','CO')
        [ARRAY_POSITION(t.REGION::VARIANT, ARRAY_CONSTRUCT('Northeast','Southeast','Central','West')) * 4 + MOD(n, 4)]::VARCHAR AS STATE,
    CASE WHEN u_type < 0.15 THEN UNIFORM(550, 1100, HASH(n, 'beds'))
         WHEN u_type < 0.70 THEN UNIFORM(120, 520, HASH(n, 'beds'))
         ELSE 0 END AS BED_COUNT,
    IFF(UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'idn')) < 0.70,
        ARRAY_CONSTRUCT('Atlas Health System','Keystone Health Network','Meridian Health','Crescent Care Partners',
                        'Pioneer Health Alliance','Horizon Health System','Beacon Health Partners','Cascade Health',
                        'Liberty Health Network','Evergreen Health System','Sterling Health','Northstar Health',
                        'Coastal Care Alliance','Heartland Health System','Lakeshore Health')[MOD(HASH(n, 'idn_name'), 15)]::VARCHAR,
        'Independent') AS IDN_NAME,
    ARRAY_CONSTRUCT('Alliance Purchasing Group','Summit Health Purchasing','Keystone Sourcing Alliance')
        [MOD(HASH(n, 'gpo'), 3)]::VARCHAR AS GPO_NAME,
    (u_type < 0.70 AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'vac')) < 0.8) AS VALUE_ANALYSIS_REQUIRED,
    loyalty AS LOYALTY
FROM a
JOIN DIM_TERRITORY t ON t.TERRITORY_ID = 'T' || LPAD(a.terr_idx + 1, 2, '0');

-- Account x family portfolio, with the latent share and competitive pressure.
CREATE OR REPLACE TEMPORARY TABLE _ACCOUNT_FAMILY AS
WITH af AS (
    SELECT a.ACCOUNT_ID, a.ACCOUNT_TYPE, a.BED_COUNT, a.LOYALTY, f.*,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(a.ACCOUNT_ID, f.FAMILY_ID, 'carry')) AS u_carry
    FROM DIM_ACCOUNT a CROSS JOIN DIM_PRODUCT_FAMILY f
    WHERE NOT f.IS_CONSUMABLE
)
SELECT ACCOUNT_ID, FAMILY_ID, PRODUCT_FAMILY, THERAPY_AREA, PRIMARY_COMPETITOR, LIST_PRICE,
    BASE_MONTHLY_VOLUME * CASE ACCOUNT_TYPE
        WHEN 'Academic Medical Center' THEN 2.2
        WHEN 'Community Hospital' THEN GREATEST(0.5, BED_COUNT / 250)
        WHEN 'Ambulatory Surgery Center' THEN 0.9
        ELSE 0.8 END AS monthly_volume,
    1 / (1 + EXP(-(0.5 + 0.9 * LOYALTY + 0.4 * NORMAL(0::FLOAT, 1::FLOAT, HASH(ACCOUNT_ID, FAMILY_ID, 'share'))))) AS base_share,
    1 / (1 + EXP(-(-1.0 - 1.4 * LOYALTY + 0.3 * NORMAL(0::FLOAT, 1::FLOAT, HASH(ACCOUNT_ID, 'press'))))) AS pressure
FROM af
WHERE CASE ACCOUNT_TYPE
        WHEN 'Academic Medical Center' THEN u_carry < 0.95
        WHEN 'Community Hospital' THEN u_carry < IFF(THERAPY_AREA IN ('Surgical','Cardiac Rhythm'), 0.9, 0.45)
        WHEN 'Ambulatory Surgery Center' THEN THERAPY_AREA IN ('Surgical','Neuromodulation') AND u_carry < 0.8
        ELSE (THERAPY_AREA = 'Diabetes' OR FAMILY_ID = 'F04') AND u_carry < 0.9 END;

-- ======================================================= DIM_HCP
CREATE OR REPLACE TABLE DIM_HCP AS
WITH at AS (
    SELECT DISTINCT ACCOUNT_ID, THERAPY_AREA,
        1 + MOD(ABS(HASH(ACCOUNT_ID, THERAPY_AREA, 'nhcp')), 3) AS n_hcp
    FROM _ACCOUNT_FAMILY
), k AS (SELECT column1 AS k FROM VALUES (1),(2),(3))
SELECT 'H-' || at.ACCOUNT_ID || '-' || LEFT(REPLACE(at.THERAPY_AREA, ' ', ''), 3) || '-' || k.k AS HCP_ID,
    'Dr. ' || ARRAY_CONSTRUCT('A.','B.','C.','D.','E.','F.','G.','J.','K.','L.','M.','N.','P.','R.','S.','T.')[MOD(ABS(HASH(at.ACCOUNT_ID, at.THERAPY_AREA, k.k, 'fi')), 16)]::VARCHAR || ' ' ||
    ARRAY_CONSTRUCT('Anderson','Bennett','Carter','Dawson','Ellis','Foster','Garcia','Hayes','Iverson','Jensen','Kaur','Lopez',
                    'Mitchell','Nakamura','Owens','Petrov','Quinn','Ramirez','Sato','Turner','Underwood','Vargas','Walsh','Young')[MOD(ABS(HASH(at.ACCOUNT_ID, at.THERAPY_AREA, k.k, 'ln')), 24)]::VARCHAR AS HCP_NAME,
    CASE at.THERAPY_AREA WHEN 'Cardiac Rhythm' THEN 'Electrophysiologist'
                         WHEN 'Structural Heart' THEN 'Interventional Cardiologist'
                         WHEN 'Neuromodulation' THEN IFF(k.k = 1, 'Neurosurgeon', 'Pain Medicine')
                         WHEN 'Diabetes' THEN 'Endocrinologist'
                         ELSE 'General Surgeon' END AS SPECIALTY,
    at.THERAPY_AREA,
    at.ACCOUNT_ID AS PRIMARY_ACCOUNT_ID,
    CASE WHEN k.k = 1 THEN 'High' WHEN k.k = 2 THEN 'Medium' ELSE 'Low' END AS VOLUME_TIER,
    (k.k = 1 AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(at.ACCOUNT_ID, at.THERAPY_AREA, 'kol')) < 0.25) AS IS_KOL,
    UNIFORM(3, 32, HASH(at.ACCOUNT_ID, at.THERAPY_AREA, k.k, 'yrs')) AS YEARS_IN_PRACTICE
FROM at JOIN k ON k.k <= at.n_hcp;

-- ======================================================= FACT_PROCEDURES
-- One row per market procedure. Our share erodes in H2 (months 6-11) in
-- proportion to the account's competitive pressure.
CREATE OR REPLACE TABLE FACT_PROCEDURES AS
WITH months AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS m FROM TABLE(GENERATOR(ROWCOUNT => 12))
), nums AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS i FROM TABLE(GENERATOR(ROWCOUNT => 80))
), grid AS (
    SELECT af.*, months.m,
        GREATEST(0, ROUND(af.monthly_volume * (1 + 0.08 * SIN(months.m * 0.52))
              * (1 + 0.25 * NORMAL(0::FLOAT, 1::FLOAT, HASH(af.ACCOUNT_ID, af.FAMILY_ID, months.m, 'vol'))))) AS vol,
        LEAST(0.97, af.base_share * (1 - af.pressure * 0.65 * GREATEST(0, months.m - 5) / 6)) AS share_m
    FROM _ACCOUNT_FAMILY af CROSS JOIN months
), rows_ AS (
    SELECT g.*, nums.i,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(g.ACCOUNT_ID, g.FAMILY_ID, g.m, nums.i, 'ours')) AS u_ours
    FROM grid g JOIN nums ON nums.i <= g.vol
)
SELECT 'PR' || LPAD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID, FAMILY_ID, m, i), 7, '0') AS PROCEDURE_ID,
    DATEADD('day', UNIFORM(0, 27, HASH(ACCOUNT_ID, FAMILY_ID, m, i, 'day')), DATEADD('month', m, '2025-10-01'::DATE)) AS PROCEDURE_DATE,
    ACCOUNT_ID,
    'H-' || ACCOUNT_ID || '-' || LEFT(REPLACE(THERAPY_AREA, ' ', ''), 3) || '-' ||
        (1 + MOD(ABS(HASH(ACCOUNT_ID, FAMILY_ID, m, i, 'hcp')), 1 + MOD(ABS(HASH(ACCOUNT_ID, THERAPY_AREA, 'nhcp')), 3))) AS HCP_ID,
    FAMILY_ID,
    THERAPY_AREA,
    (u_ours < share_m) AS USED_OUR_DEVICE,
    IFF(u_ours < share_m, NULL,
        IFF(UNIFORM(0::FLOAT, 1::FLOAT, HASH(ACCOUNT_ID, FAMILY_ID, m, i, 'comp')) < 0.75, PRIMARY_COMPETITOR, 'Other competitor')) AS COMPETITOR
FROM rows_;

-- ======================================================= FACT_CONTRACTS
CREATE OR REPLACE TABLE FACT_CONTRACTS AS
WITH at AS (
    SELECT af.ACCOUNT_ID, af.THERAPY_AREA, MAX(af.pressure) AS pressure
    FROM _ACCOUNT_FAMILY af GROUP BY 1, 2
), c AS (
    SELECT at.*, a.IDN_NAME, a.GPO_NAME,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(at.ACCOUNT_ID, at.THERAPY_AREA, 'ctype')) AS u_type,
        1 + MOD(ABS(HASH(at.ACCOUNT_ID, at.THERAPY_AREA, 'tier')), 4) AS tier
    FROM at JOIN DIM_ACCOUNT a USING (ACCOUNT_ID)
)
SELECT 'K' || LPAD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID, THERAPY_AREA), 5, '0') AS CONTRACT_ID,
    ACCOUNT_ID, THERAPY_AREA,
    CASE WHEN IDN_NAME <> 'Independent' AND u_type < 0.35 THEN 'IDN Local Agreement'
         WHEN u_type < 0.85 THEN 'GPO Agreement'
         ELSE 'Direct Agreement' END AS CONTRACT_TYPE,
    CASE WHEN IDN_NAME <> 'Independent' AND u_type < 0.35 THEN IDN_NAME
         WHEN u_type < 0.85 THEN GPO_NAME ELSE 'Direct' END AS CONTRACT_HOLDER,
    'Tier ' || tier AS PRICE_TIER,
    CASE tier WHEN 1 THEN 22 WHEN 2 THEN 17 WHEN 3 THEN 12 ELSE 6 END AS DISCOUNT_PCT,
    CASE tier WHEN 1 THEN 80 WHEN 2 THEN 70 WHEN 3 THEN 60 ELSE 0 END AS COMMITTED_SHARE_PCT,
    DATEADD('month', -UNIFORM(6, 30, HASH(ACCOUNT_ID, THERAPY_AREA, 'start')), '2026-03-31'::DATE) AS START_DATE,
    -- High-pressure accounts tend to be near renewal: competitors target open contracts.
    DATEADD('day', IFF(pressure > 0.5, UNIFORM(20, 240, HASH(ACCOUNT_ID, THERAPY_AREA, 'renew')),
                                       UNIFORM(150, 720, HASH(ACCOUNT_ID, THERAPY_AREA, 'renew'))), '2026-03-31'::DATE) AS RENEWAL_DATE,
    'Active' AS STATUS
FROM c;

-- ======================================================= FACT_SALES_ORDERS
-- One implant line per procedure that used our device, plus consumable attach
-- lines: 13 CGM sensors and 30 infusion sets per pump start, 4 reloads per stapler case.
CREATE OR REPLACE TABLE FACT_SALES_ORDERS AS
WITH ours AS (
    SELECT p.*, a.ACCOUNT_TYPE, a.TERRITORY_ID, k.CONTRACT_ID, k.DISCOUNT_PCT
    FROM FACT_PROCEDURES p
    JOIN DIM_ACCOUNT a USING (ACCOUNT_ID)
    LEFT JOIN FACT_CONTRACTS k ON k.ACCOUNT_ID = p.ACCOUNT_ID AND k.THERAPY_AREA = p.THERAPY_AREA
    WHERE p.USED_OUR_DEVICE
), lines AS (
    SELECT PROCEDURE_ID, PROCEDURE_DATE, ACCOUNT_ID, ACCOUNT_TYPE, TERRITORY_ID, CONTRACT_ID, DISCOUNT_PCT,
           FAMILY_ID, 1 AS UNITS, 'implant' AS line_kind FROM ours
    UNION ALL SELECT PROCEDURE_ID, PROCEDURE_DATE, ACCOUNT_ID, ACCOUNT_TYPE, TERRITORY_ID, CONTRACT_ID, DISCOUNT_PCT,
           'F11', 13, 'consumable' FROM ours WHERE FAMILY_ID = 'F10'
    UNION ALL SELECT PROCEDURE_ID, PROCEDURE_DATE, ACCOUNT_ID, ACCOUNT_TYPE, TERRITORY_ID, CONTRACT_ID, DISCOUNT_PCT,
           'F12', 30, 'consumable' FROM ours WHERE FAMILY_ID = 'F10'
    UNION ALL SELECT PROCEDURE_ID, PROCEDURE_DATE, ACCOUNT_ID, ACCOUNT_TYPE, TERRITORY_ID, CONTRACT_ID, DISCOUNT_PCT,
           'F14', 4, 'consumable' FROM ours WHERE FAMILY_ID = 'F13'
), priced AS (
    SELECT l.*, pr.PRODUCT_ID, pr.LIST_PRICE,
        ROUND(pr.LIST_PRICE * (1 - COALESCE(l.DISCOUNT_PCT, 0) / 100)
              * (1 + 0.02 * NORMAL(0::FLOAT, 1::FLOAT, HASH(l.PROCEDURE_ID, l.FAMILY_ID, 'px'))), 2) AS NET_PRICE
    FROM lines l
    JOIN DIM_PRODUCT pr ON pr.PRODUCT_ID = l.FAMILY_ID || '-' ||
        LPAD(IFF(l.line_kind = 'consumable', 1, 1 + MOD(ABS(HASH(l.PROCEDURE_ID, 'sku')), 3)), 2, '0')
)
SELECT 'SO' || LPAD(ROW_NUMBER() OVER (ORDER BY PROCEDURE_ID, FAMILY_ID), 8, '0') AS ORDER_LINE_ID,
    PROCEDURE_ID, PROCEDURE_DATE AS ORDER_DATE, ACCOUNT_ID, TERRITORY_ID, PRODUCT_ID, FAMILY_ID, CONTRACT_ID,
    CASE WHEN line_kind = 'implant' AND ACCOUNT_TYPE IN ('Academic Medical Center','Community Hospital') THEN 'Bill-Only (Consigned)'
         ELSE 'Direct Ship' END AS ORDER_TYPE,
    UNITS, LIST_PRICE, NET_PRICE,
    ROUND(UNITS * NET_PRICE, 2) AS NET_REVENUE,
    ROUND(UNITS * (LIST_PRICE - NET_PRICE), 2) AS DISCOUNT_AMOUNT
FROM priced;

-- ======================================================= FACT_QUOTA_ATTAINMENT
-- Quota = H1 average monthly revenue for the territory and therapy, plus 6% growth.
CREATE OR REPLACE TABLE FACT_QUOTA_ATTAINMENT AS
WITH m AS (
    SELECT o.TERRITORY_ID, f.THERAPY_AREA, DATE_TRUNC('month', o.ORDER_DATE) AS MONTH, SUM(o.NET_REVENUE) AS rev
    FROM FACT_SALES_ORDERS o JOIN DIM_PRODUCT_FAMILY f USING (FAMILY_ID)
    GROUP BY 1, 2, 3
), q AS (
    SELECT *, AVG(IFF(MONTH < '2026-04-01', rev, NULL)) OVER (PARTITION BY TERRITORY_ID, THERAPY_AREA) * 1.06 AS quota
    FROM m
)
SELECT 'Q' || LPAD(ROW_NUMBER() OVER (ORDER BY TERRITORY_ID, THERAPY_AREA, MONTH), 5, '0') AS QUOTA_ID,
    TERRITORY_ID, THERAPY_AREA, MONTH,
    ROUND(quota, 2) AS QUOTA_AMOUNT,
    ROUND(rev, 2) AS ACTUAL_REVENUE,
    ROUND(100 * rev / NULLIF(quota, 0), 1) AS ATTAINMENT_PCT
FROM q;

-- ======================================================= FACT_CONSIGNMENT_INVENTORY
-- Month-end consigned stock at bill-only accounts. When usage falls (share loss),
-- stock ages and units nearing expiry rise.
CREATE OR REPLACE TABLE FACT_CONSIGNMENT_INVENTORY AS
WITH used AS (
    SELECT ACCOUNT_ID, FAMILY_ID, DATE_TRUNC('month', PROCEDURE_DATE) AS MONTH, COUNT_IF(USED_OUR_DEVICE) AS used_units
    FROM FACT_PROCEDURES GROUP BY 1, 2, 3
), inv AS (
    SELECT u.*, af.pressure, af.LIST_PRICE,
        AVG(used_units) OVER (PARTITION BY u.ACCOUNT_ID, u.FAMILY_ID ORDER BY u.MONTH ROWS BETWEEN 5 PRECEDING AND 2 PRECEDING) AS par_basis,
        DATEDIFF('month', '2025-10-01'::DATE, u.MONTH) AS m
    FROM used u
    JOIN _ACCOUNT_FAMILY af USING (ACCOUNT_ID, FAMILY_ID)
    JOIN DIM_ACCOUNT a USING (ACCOUNT_ID)
    WHERE a.ACCOUNT_TYPE IN ('Academic Medical Center','Community Hospital')
)
SELECT 'CI' || LPAD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID, FAMILY_ID, MONTH), 6, '0') AS SNAPSHOT_ID,
    ACCOUNT_ID, FAMILY_ID, LAST_DAY(MONTH) AS SNAPSHOT_DATE,
    GREATEST(2, ROUND(1.8 * COALESCE(par_basis, used_units))) AS UNITS_ON_HAND,
    used_units AS UNITS_USED_IN_MONTH,
    LEAST(GREATEST(2, ROUND(1.8 * COALESCE(par_basis, used_units))),
          ROUND(GREATEST(2, ROUND(1.8 * COALESCE(par_basis, used_units)))
                * (0.04 + 0.45 * pressure * m / 11 * UNIFORM(0.5::FLOAT, 1.5::FLOAT, HASH(ACCOUNT_ID, FAMILY_ID, MONTH, 'exp'))))) AS UNITS_EXPIRING_90D,
    ROUND(GREATEST(2, ROUND(1.8 * COALESCE(par_basis, used_units))) * LIST_PRICE, 2) AS INVENTORY_VALUE
FROM inv;

-- ======================================================= FACT_COMPETITIVE_EVENTS
-- Evaluations, trials and VAC reviews cluster in H1 at high-pressure accounts;
-- conversions follow in H2. Win-backs happen at loyal accounts.
CREATE OR REPLACE TABLE FACT_COMPETITIVE_EVENTS AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS k FROM TABLE(GENERATOR(ROWCOUNT => 6))
), ev AS (
    SELECT af.*, n.k,
        ROUND(af.pressure * 5 * UNIFORM(0.75::FLOAT, 1.25::FLOAT, HASH(af.ACCOUNT_ID, af.FAMILY_ID, 'nev'))) AS n_events,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(af.ACCOUNT_ID, af.FAMILY_ID, n.k, 'phase')) AS u_phase
    FROM _ACCOUNT_FAMILY af CROSS JOIN n
)
SELECT 'CE' || LPAD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID, FAMILY_ID, k), 5, '0') AS EVENT_ID,
    DATEADD('day', UNIFORM(0, 27, HASH(ACCOUNT_ID, FAMILY_ID, k, 'd')),
        DATEADD('month', IFF(k <= 2 OR u_phase < 0.55, UNIFORM(0, 5, HASH(ACCOUNT_ID, FAMILY_ID, k, 'mh1')),
                                                       UNIFORM(6, 11, HASH(ACCOUNT_ID, FAMILY_ID, k, 'mh2'))), '2025-10-01'::DATE)) AS EVENT_DATE,
    ACCOUNT_ID, FAMILY_ID, THERAPY_AREA, PRIMARY_COMPETITOR AS COMPETITOR,
    CASE WHEN k <= 2 OR u_phase < 0.55 THEN ARRAY_CONSTRUCT('Product Evaluation','Trial Started','Value Analysis Review')[MOD(ABS(HASH(ACCOUNT_ID, FAMILY_ID, k, 't')), 3)]::VARCHAR
         WHEN pressure > 0.45 THEN 'Converted to Competitor'
         ELSE 'Won Back' END AS EVENT_TYPE,
    ROUND(monthly_volume * 12 * LIST_PRICE * UNIFORM(0.15::FLOAT, 0.5::FLOAT, HASH(ACCOUNT_ID, FAMILY_ID, k, 'risk')), 0) AS ESTIMATED_ANNUAL_REVENUE
FROM ev
WHERE k <= n_events
UNION ALL
-- A few win-backs at loyal accounts
SELECT 'CW' || LPAD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID, FAMILY_ID), 5, '0'),
    DATEADD('day', UNIFORM(0, 300, HASH(ACCOUNT_ID, FAMILY_ID, 'wb')), '2025-10-01'::DATE),
    ACCOUNT_ID, FAMILY_ID, THERAPY_AREA, PRIMARY_COMPETITOR, 'Won Back',
    ROUND(monthly_volume * 12 * LIST_PRICE * 0.2, 0)
FROM _ACCOUNT_FAMILY
WHERE pressure < 0.15 AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(ACCOUNT_ID, FAMILY_ID, 'wbu')) < 0.25;

-- ======================================================= FACT_COMPLAINTS
-- Baseline ~0.6% of order lines; a stapler malfunction cluster in Jun-Aug 2026
-- (see the field action notice in PRODUCT_KNOWLEDGE_DOCS).
CREATE OR REPLACE TABLE FACT_COMPLAINTS AS
WITH c AS (
    SELECT o.*, UNIFORM(0::FLOAT, 1::FLOAT, HASH(o.ORDER_LINE_ID, 'cmp')) AS u,
        (o.FAMILY_ID IN ('F13','F14') AND o.ORDER_DATE BETWEEN '2026-06-01' AND '2026-08-31') AS cluster
    FROM FACT_SALES_ORDERS o
)
SELECT 'CM' || LPAD(ROW_NUMBER() OVER (ORDER BY ORDER_DATE, ORDER_LINE_ID), 5, '0') AS COMPLAINT_ID,
    DATEADD('day', UNIFORM(1, 20, HASH(ORDER_LINE_ID, 'lag')), ORDER_DATE) AS REPORTED_DATE,
    ACCOUNT_ID, PRODUCT_ID, FAMILY_ID,
    IFF(cluster, 'Device Malfunction',
        ARRAY_CONSTRUCT('Device Malfunction','Packaging or Labeling','Delivery Delay','Use Error','Sterility Concern')[MOD(ABS(HASH(ORDER_LINE_ID, 'cat')), 5)]::VARCHAR) AS CATEGORY,
    CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, HASH(ORDER_LINE_ID, 'sev')) < 0.12 THEN 'High'
         WHEN UNIFORM(0::FLOAT, 1::FLOAT, HASH(ORDER_LINE_ID, 'sev')) < 0.45 THEN 'Medium' ELSE 'Low' END AS SEVERITY,
    IFF(ORDER_DATE >= '2026-08-15', 'Under Investigation', 'Closed') AS STATUS
FROM c
WHERE u < IFF(cluster, 0.035, 0.006);

-- ======================================================= ML_ACCOUNT_FEATURES
-- Features as of 2026-03-31 (H1 only) and the observed H2 outcome. The label
-- SHARE_LOSS_FLAG = procedure share fell 8+ points in H2 vs H1.
CREATE OR REPLACE TABLE ML_ACCOUNT_FEATURES AS
WITH proc AS (
    SELECT ACCOUNT_ID,
        COUNT_IF(PROCEDURE_DATE < '2026-04-01') AS procedures_h1,
        COUNT_IF(PROCEDURE_DATE < '2026-04-01' AND USED_OUR_DEVICE) / NULLIF(COUNT_IF(PROCEDURE_DATE < '2026-04-01'), 0) AS share_h1,
        COUNT_IF(PROCEDURE_DATE >= '2026-04-01' AND USED_OUR_DEVICE) / NULLIF(COUNT_IF(PROCEDURE_DATE >= '2026-04-01'), 0) AS share_h2,
        COUNT_IF(PROCEDURE_DATE BETWEEN '2026-01-01' AND '2026-03-31' AND USED_OUR_DEVICE)
          / NULLIF(COUNT_IF(PROCEDURE_DATE BETWEEN '2026-01-01' AND '2026-03-31'), 0)
        - COUNT_IF(PROCEDURE_DATE < '2026-01-01' AND USED_OUR_DEVICE)
          / NULLIF(COUNT_IF(PROCEDURE_DATE < '2026-01-01'), 0) AS share_trend_q2_vs_q1
    FROM FACT_PROCEDURES GROUP BY 1
), rev AS (
    SELECT ACCOUNT_ID, SUM(IFF(ORDER_DATE < '2026-04-01', NET_REVENUE, 0)) AS revenue_h1
    FROM FACT_SALES_ORDERS GROUP BY 1
), ev AS (
    SELECT ACCOUNT_ID,
        COUNT_IF(EVENT_DATE < '2026-04-01' AND EVENT_TYPE IN ('Product Evaluation','Trial Started','Value Analysis Review')) AS competitive_events_h1,
        COUNT_IF(EVENT_DATE < '2026-04-01' AND EVENT_TYPE = 'Trial Started') AS competitor_trials_h1
    FROM FACT_COMPETITIVE_EVENTS GROUP BY 1
), cmp AS (
    SELECT ACCOUNT_ID, COUNT_IF(REPORTED_DATE < '2026-04-01') AS complaints_h1 FROM FACT_COMPLAINTS GROUP BY 1
), k AS (
    SELECT ACCOUNT_ID, MIN(DATEDIFF('day', '2026-03-31'::DATE, RENEWAL_DATE)) AS days_to_next_renewal,
        AVG(DISCOUNT_PCT) AS avg_discount_pct
    FROM FACT_CONTRACTS GROUP BY 1
), h AS (
    SELECT PRIMARY_ACCOUNT_ID AS ACCOUNT_ID, COUNT(*) AS hcp_count, COUNT_IF(IS_KOL) AS kol_count,
        COUNT(DISTINCT THERAPY_AREA) AS therapy_count
    FROM DIM_HCP GROUP BY 1
), inv AS (
    SELECT ACCOUNT_ID, SUM(UNITS_EXPIRING_90D) / NULLIF(SUM(UNITS_ON_HAND), 0) AS expiring_inventory_pct_h1
    FROM FACT_CONSIGNMENT_INVENTORY WHERE SNAPSHOT_DATE < '2026-04-01' GROUP BY 1
)
SELECT a.ACCOUNT_ID,
    '2026-03-31'::DATE AS FEATURE_DATE,
    a.BED_COUNT,
    IFF(a.IDN_NAME <> 'Independent', 1, 0) AS IS_IDN_MEMBER,
    IFF(a.VALUE_ANALYSIS_REQUIRED, 1, 0) AS VAC_REQUIRED,
    COALESCE(h.therapy_count, 0) AS THERAPY_COUNT,
    COALESCE(h.hcp_count, 0) AS HCP_COUNT,
    COALESCE(h.kol_count, 0) AS KOL_COUNT,
    COALESCE(p.procedures_h1, 0) AS PROCEDURES_H1,
    ROUND(COALESCE(p.share_h1, 0), 4) AS OUR_SHARE_H1,
    ROUND(COALESCE(p.share_trend_q2_vs_q1, 0), 4) AS SHARE_TREND_Q2_VS_Q1,
    ROUND(COALESCE(r.revenue_h1, 0), 2) AS REVENUE_H1,
    COALESCE(e.competitive_events_h1, 0) AS COMPETITIVE_EVENTS_H1,
    COALESCE(e.competitor_trials_h1, 0) AS COMPETITOR_TRIALS_H1,
    COALESCE(c.complaints_h1, 0) AS COMPLAINTS_H1,
    COALESCE(k.days_to_next_renewal, 999) AS DAYS_TO_NEXT_RENEWAL,
    ROUND(COALESCE(k.avg_discount_pct, 0), 2) AS AVG_DISCOUNT_PCT,
    ROUND(COALESCE(i.expiring_inventory_pct_h1, 0), 4) AS EXPIRING_INVENTORY_PCT_H1,
    ROUND(100 * (COALESCE(p.share_h2, 0) - COALESCE(p.share_h1, 0)), 2) AS SHARE_CHANGE_H2_PP,
    IFF(100 * (COALESCE(p.share_h2, 0) - COALESCE(p.share_h1, 0)) <= -8, 1, 0) AS SHARE_LOSS_FLAG,
    -- Legacy rule of thumb the field uses today: contract renewal proximity, complaints and
    -- known competitor trials, plus rep judgment (noise). It over-flags and misses quiet erosion.
    ROUND(LEAST(0.99, GREATEST(0.01,
        0.10
        + IFF(COALESCE(k.days_to_next_renewal, 999) < 180, 0.30, 0.0)
        + 0.03 * COALESCE(c.complaints_h1, 0)
        + 0.06 * COALESCE(e.competitor_trials_h1, 0)
        + 0.35 * UNIFORM(0::FLOAT, 1::FLOAT, HASH(a.ACCOUNT_ID, 'legacy')))), 4) AS LEGACY_RISK_SCORE
FROM DIM_ACCOUNT a
LEFT JOIN proc p USING (ACCOUNT_ID)
LEFT JOIN rev r USING (ACCOUNT_ID)
LEFT JOIN ev e USING (ACCOUNT_ID)
LEFT JOIN cmp c USING (ACCOUNT_ID)
LEFT JOIN k USING (ACCOUNT_ID)
LEFT JOIN h USING (ACCOUNT_ID)
LEFT JOIN inv i USING (ACCOUNT_ID);

-- ======================================================= PRODUCT_KNOWLEDGE_DOCS
-- Synthetic field-reference corpus for Cortex Search. Labeling facts come from
-- DIM_PRODUCT_FAMILY, so search answers and the eval set agree with the data.
CREATE OR REPLACE TABLE PRODUCT_KNOWLEDGE_DOCS AS
SELECT 'IFU-' || FAMILY_ID AS DOC_ID, 'IFU Summary' AS DOC_TYPE, THERAPY_AREA, PRODUCT_FAMILY,
    PRODUCT_FAMILY || ' - Instructions for Use summary' AS TITLE,
    PRODUCT_FAMILY || ' (' || DEVICE_CLASS || ', ' || OPERATING_UNIT || '). Indications: ' || INDICATION ||
    '. Contraindications: ' || CONTRAINDICATION || '. MRI status: ' || MRI_STATUS || '. Longevity and wear: ' || LONGEVITY ||
    '. This summary is for field reference only; always consult the full labeling and the current IFU before use.' AS BODY,
    '2026-01-15'::DATE AS EFFECTIVE_DATE
FROM DIM_PRODUCT_FAMILY
UNION ALL
SELECT 'CLIN-' || FAMILY_ID, 'Clinical Evidence', THERAPY_AREA, PRODUCT_FAMILY,
    PRODUCT_FAMILY || ' - ' || PIVOTAL_TRIAL || ' pivotal trial summary',
    'The ' || PIVOTAL_TRIAL || ' pivotal study of the ' || PRODUCT_FAMILY || ' enrolled ' || TRIAL_PATIENTS ||
    ' patients. Primary endpoint: ' || PRIMARY_ENDPOINT || '. Result: ' || ENDPOINT_RESULT || '. Key finding: ' || KEY_DIFFERENTIATOR ||
    '. Discuss results only within the labeled indication: ' || INDICATION || '.',
    '2025-11-03'::DATE
FROM DIM_PRODUCT_FAMILY
UNION ALL
SELECT 'RWE-' || FAMILY_ID, 'Real-World Evidence', THERAPY_AREA, PRODUCT_FAMILY,
    PRODUCT_FAMILY || ' - real-world registry outcomes',
    'A post-market registry of ' || (TRIAL_PATIENTS * 4) || ' patients treated with the ' || PRODUCT_FAMILY ||
    ' across 60 US sites reported outcomes consistent with ' || PIVOTAL_TRIAL || ' (' || PRIMARY_ENDPOINT || ': ' || ENDPOINT_RESULT ||
    ' in the pivotal trial). Health-economic analysis showed fewer follow-up procedures and shorter length of stay versus the prior standard of care. Use the registry summary in value-analysis discussions; it is not a substitute for labeling.',
    '2026-05-20'::DATE
FROM DIM_PRODUCT_FAMILY WHERE NOT IS_CONSUMABLE
UNION ALL
SELECT 'BC-' || FAMILY_ID, 'Competitive Battlecard', THERAPY_AREA, PRODUCT_FAMILY,
    PRODUCT_FAMILY || ' vs ' || COMPETITOR_PRODUCT || ' battlecard',
    'Competitor: ' || PRIMARY_COMPETITOR || ' ' || COMPETITOR_PRODUCT || '. Our differentiators: ' || KEY_DIFFERENTIATOR ||
    '; MRI status ' || MRI_STATUS || '; ' || LONGEVITY || '. Common objection: price. Response: lead with total cost of care, consignment and bill-only support, and clinical outcomes from ' || PIVOTAL_TRIAL ||
    '. Trap to avoid: do not make head-to-head clinical superiority claims; no head-to-head randomized trial against ' || COMPETITOR_PRODUCT || ' exists. Escalate competitive price matches to the deal desk.',
    '2026-07-01'::DATE
FROM DIM_PRODUCT_FAMILY WHERE NOT IS_CONSUMABLE
UNION ALL
SELECT 'REIMB-' || FAMILY_ID, 'Reimbursement Note', THERAPY_AREA, PRODUCT_FAMILY,
    PRODUCT_FAMILY || ' - coding and reimbursement note',
    'Procedure: ' || PROCEDURE_TYPE || '. Site of service: ' ||
    IFF(THERAPY_AREA IN ('Surgical','Neuromodulation'), 'hospital outpatient or ambulatory surgery center', 'hospital inpatient or outpatient') ||
    '. Confirm current CPT/HCPCS and DRG assignments with the reimbursement hotline before quoting payment; payment varies by payer and site of service. Prior authorization is commonly required for ' ||
    IFF(THERAPY_AREA = 'Neuromodulation', 'trial and permanent implant', 'elective cases') || '.',
    '2026-02-02'::DATE
FROM DIM_PRODUCT_FAMILY WHERE NOT IS_CONSUMABLE
UNION ALL
SELECT * FROM VALUES
('POL-TIER','Contract Policy','All','All','GPO and IDN price tier policy',
 'Price tiers are earned by committed procedure share in the therapy area. Tier 1: 22% discount off list for at least 80% committed share. Tier 2: 17% for at least 70%. Tier 3: 12% for at least 60%. Tier 4: 6% with no share commitment. Compliance is measured quarterly on trailing-twelve-month procedure share; accounts below their committed share for two consecutive quarters drop one tier at the next review. Discounts beyond the tier require deal desk approval.','2026-01-01'::DATE),
('POL-DEALDESK','Contract Policy','All','All','Deal desk price exception policy',
 'Any price below the contracted tier, or a competitive price match, needs a deal desk exception. Submit the competitor quote, the account''s trailing-twelve-month procedure volume and the requested duration. Exceptions of up to 5 points below tier are approved by the regional director within 2 business days; deeper exceptions go to the commercial pricing committee. Exceptions never exceed 12 months and must align with the contract renewal date.','2026-01-01'::DATE),
('POL-CONSIGN','Contract Policy','All','All','Consignment and bill-only inventory policy',
 'Implants at hospital accounts are consigned and billed on use (bill-only). Reps must submit the bill-only form within 48 hours of the case. Par levels are set at 1.8 months of average usage. Units within 90 days of expiry must be rotated to a higher-usage account or returned; expired consigned units are written off against the territory. Cycle counts are required quarterly.','2026-01-01'::DATE),
('POL-VAC','Value Analysis Guide','All','All','Value analysis committee submission guide',
 'Hospitals with a value analysis committee (VAC) require a product dossier before a new device or a competitive conversion is approved. The dossier includes the IFU summary, the pivotal trial and real-world evidence summaries, total cost of care, contract price tier and a supply-chain plan. Engage the VAC 60 to 90 days before contract renewal; competitors typically trigger VAC reviews to open a conversion.','2026-01-01'::DATE),
('POL-ONLABEL','Compliance Policy','All','All','Promotional communication and on-label policy',
 'Field communication must stay within the labeled indications in the IFU. Do not promote off-label uses, do not make comparative clinical superiority claims without head-to-head data, and do not share patient-identifiable information. Refer unsolicited off-label questions to Medical Affairs. AI-generated answers must follow the same rules.','2026-01-01'::DATE),
('FAN-TORQUE-2026','Field Action Notice','Surgical','Torque Powered Stapler','Field action notice: Torque Powered Stapler reload firing advisory',
 'Between June and August 2026, complaints of incomplete firing were reported for specific Torque Stapler Reload lots used with the Torque Powered Stapler. Root cause: a cartridge latch tolerance issue. Action: reps notify surgical services at affected accounts, quarantine the listed lots and replace them at no charge. Device Malfunction complaints for these families rose during the period and are under investigation. No change to the IFU.','2026-09-05'::DATE);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SHARE-LOSS PREDICTIONS (model scores the agent reads through the semantic view)
-- ─────────────────────────────────────────────────────────────────────────────
-- The notebook's share-loss section overwrites this with scores from the registered
-- SHARE_LOSS_MODEL (MODEL_VERSION = 'V1'). Until then it is seeded from the legacy
-- rule-of-thumb score so the agent can already answer account-risk questions.
CREATE TABLE IF NOT EXISTS SHARE_LOSS_PREDICTIONS AS
SELECT ACCOUNT_ID,
       LEGACY_RISK_SCORE::FLOAT                   AS SHARE_LOSS_SCORE,
       IFF(LEGACY_RISK_SCORE >= 0.5, 1, 0)        AS SHARE_LOSS_PREDICTION,
       'LEGACY_SEED'                              AS MODEL_VERSION,
       CURRENT_TIMESTAMP()::TIMESTAMP_NTZ         AS SCORED_AT
FROM ML_ACCOUNT_FEATURES;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEWS (Cortex Analyst: sales performance, and account health)
-- ─────────────────────────────────────────────────────────────────────────────

-- ----------------------------------------------- Sales performance view
CREATE OR REPLACE SEMANTIC VIEW CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SALES_PERFORMANCE_SV

  TABLES (
    orders AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_SALES_ORDERS
      PRIMARY KEY (ORDER_LINE_ID)
      WITH SYNONYMS ('sales', 'order lines', 'bookings')
      COMMENT = 'Our implant and consumable order lines at contract net price',
    products AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product SKUs',
    families AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_PRODUCT_FAMILY
      PRIMARY KEY (FAMILY_ID)
      COMMENT = 'Product families, therapy areas and operating units',
    accounts AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_ACCOUNT
      PRIMARY KEY (ACCOUNT_ID)
      WITH SYNONYMS ('customers', 'hospitals', 'facilities')
      COMMENT = 'Hospitals, academic medical centers, ASCs and specialty clinics',
    territories AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_TERRITORY
      PRIMARY KEY (TERRITORY_ID)
      COMMENT = 'Sales territories and their reps',
    quota AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_QUOTA_ATTAINMENT
      PRIMARY KEY (QUOTA_ID)
      COMMENT = 'Monthly quota and actual revenue by territory and therapy area',
    contracts AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_CONTRACTS
      PRIMARY KEY (CONTRACT_ID)
      COMMENT = 'GPO, IDN and direct pricing agreements by account and therapy area',
    inventory AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_CONSIGNMENT_INVENTORY
      PRIMARY KEY (SNAPSHOT_ID)
      WITH SYNONYMS ('consignment', 'field inventory', 'trunk stock')
      COMMENT = 'Month-end consigned inventory at bill-only hospital accounts'
  )

  RELATIONSHIPS (
    order_to_product AS orders(PRODUCT_ID) REFERENCES products,
    product_to_family AS products(FAMILY_ID) REFERENCES families,
    order_to_account AS orders(ACCOUNT_ID) REFERENCES accounts,
    account_to_territory AS accounts(TERRITORY_ID) REFERENCES territories,
    quota_to_territory AS quota(TERRITORY_ID) REFERENCES territories,
    contract_to_account AS contracts(ACCOUNT_ID) REFERENCES accounts,
    inventory_to_account AS inventory(ACCOUNT_ID) REFERENCES accounts,
    inventory_to_family AS inventory(FAMILY_ID) REFERENCES families
  )

  FACTS (
    orders.units AS orders.UNITS,
    orders.net_price AS orders.NET_PRICE COMMENT = 'Contract net price per unit',
    orders.list_price AS orders.LIST_PRICE,
    orders.net_revenue AS orders.NET_REVENUE COMMENT = 'Units x net price, USD',
    orders.discount_amount AS orders.DISCOUNT_AMOUNT COMMENT = 'Units x (list - net), USD',
    quota.quota_amount AS quota.QUOTA_AMOUNT,
    quota.actual_revenue AS quota.ACTUAL_REVENUE,
    contracts.discount_pct AS contracts.DISCOUNT_PCT,
    contracts.committed_share_pct AS contracts.COMMITTED_SHARE_PCT,
    inventory.units_on_hand AS inventory.UNITS_ON_HAND,
    inventory.units_expiring_90d AS inventory.UNITS_EXPIRING_90D,
    inventory.inventory_value AS inventory.INVENTORY_VALUE,
    accounts.bed_count AS accounts.BED_COUNT
  )

  DIMENSIONS (
    orders.order_date AS orders.ORDER_DATE COMMENT = 'Order (case) date; fiscal year runs Oct 2025 - Sep 2026',
    orders.order_month AS DATE_TRUNC('month', orders.ORDER_DATE),
    orders.order_type AS orders.ORDER_TYPE SAMPLE_VALUES ('Bill-Only (Consigned)', 'Direct Ship') IS_ENUM,
    products.sku_name AS products.SKU_NAME,
    families.product_family AS families.PRODUCT_FAMILY WITH SYNONYMS = ('product', 'device', 'product line')
      SAMPLE_VALUES ('Pulsar Pacemaker', 'Sentinel ICD', 'Lumen Leadless Pacemaker', 'Arc Insertable Cardiac Monitor', 'Valvia TAVR System', 'Annulus Repair Ring', 'Axion SCS System', 'Axion DBS System', 'Fluent Sacral Neuromodulation', 'Glyde Insulin Pump', 'Glyde CGM Sensor', 'Glyde Infusion Set', 'Torque Powered Stapler', 'Torque Stapler Reload', 'Fuse Energy Sealer', 'Halo Hernia Mesh') IS_ENUM,
    families.therapy_area AS families.THERAPY_AREA WITH SYNONYMS = ('therapy', 'business', 'franchise')
      SAMPLE_VALUES ('Cardiac Rhythm', 'Structural Heart', 'Neuromodulation', 'Diabetes', 'Surgical') IS_ENUM,
    families.operating_unit AS families.OPERATING_UNIT SAMPLE_VALUES ('Cardiovascular', 'Neuroscience', 'Diabetes', 'Medical Surgical') IS_ENUM,
    families.is_consumable AS families.IS_CONSUMABLE,
    accounts.account_name AS accounts.ACCOUNT_NAME,
    accounts.account_type AS accounts.ACCOUNT_TYPE SAMPLE_VALUES ('Academic Medical Center', 'Community Hospital', 'Ambulatory Surgery Center', 'Specialty Clinic') IS_ENUM,
    accounts.idn_name AS accounts.IDN_NAME WITH SYNONYMS = ('IDN', 'health system') COMMENT = 'Integrated delivery network; Independent if none',
    accounts.gpo_name AS accounts.GPO_NAME WITH SYNONYMS = ('GPO', 'group purchasing organization')
      SAMPLE_VALUES ('Alliance Purchasing Group', 'Summit Health Purchasing', 'Keystone Sourcing Alliance') IS_ENUM,
    accounts.account_state AS accounts.STATE,
    territories.region AS territories.REGION SAMPLE_VALUES ('Northeast', 'Southeast', 'Central', 'West') IS_ENUM,
    territories.territory_name AS territories.TERRITORY_NAME,
    territories.rep_name AS territories.REP_NAME WITH SYNONYMS = ('rep', 'sales rep', 'territory manager'),
    quota.quota_month AS quota.MONTH,
    quota.quota_therapy_area AS quota.THERAPY_AREA SAMPLE_VALUES ('Cardiac Rhythm', 'Structural Heart', 'Neuromodulation', 'Diabetes', 'Surgical') IS_ENUM,
    contracts.contract_type AS contracts.CONTRACT_TYPE SAMPLE_VALUES ('GPO Agreement', 'IDN Local Agreement', 'Direct Agreement') IS_ENUM,
    contracts.contract_holder AS contracts.CONTRACT_HOLDER,
    contracts.price_tier AS contracts.PRICE_TIER SAMPLE_VALUES ('Tier 1', 'Tier 2', 'Tier 3', 'Tier 4') IS_ENUM,
    contracts.contract_therapy_area AS contracts.THERAPY_AREA,
    contracts.renewal_date AS contracts.RENEWAL_DATE,
    inventory.snapshot_date AS inventory.SNAPSHOT_DATE COMMENT = 'Month-end inventory snapshot date'
  )

  METRICS (
    orders.total_net_revenue AS SUM(orders.net_revenue) WITH SYNONYMS = ('revenue', 'sales', 'net sales') COMMENT = 'Net revenue, USD',
    orders.total_units AS SUM(orders.units) COMMENT = 'Units sold',
    orders.order_line_count AS COUNT(orders.ORDER_LINE_ID),
    orders.average_selling_price AS DIV0(SUM(orders.net_revenue), SUM(orders.units)) WITH SYNONYMS = ('ASP') COMMENT = 'Net revenue per unit',
    orders.total_discount AS SUM(orders.discount_amount) COMMENT = 'Discount off list, USD',
    orders.discount_rate AS DIV0(SUM(orders.discount_amount), SUM(orders.units * orders.list_price)) COMMENT = 'Discount as a share of list value (0-1)',
    quota.total_quota AS SUM(quota.quota_amount),
    quota.total_actual_revenue AS SUM(quota.actual_revenue),
    quota.quota_attainment AS DIV0(SUM(quota.actual_revenue), SUM(quota.quota_amount)) WITH SYNONYMS = ('attainment', 'percent to plan') COMMENT = 'Actual revenue / quota (1.0 = 100%)',
    contracts.contract_count AS COUNT(contracts.CONTRACT_ID),
    contracts.avg_contract_discount_pct AS AVG(contracts.discount_pct),
    inventory.total_units_on_hand AS SUM(inventory.units_on_hand),
    inventory.total_units_expiring_90d AS SUM(inventory.units_expiring_90d) COMMENT = 'Consigned units within 90 days of expiry',
    inventory.expiring_inventory_rate AS DIV0(SUM(inventory.units_expiring_90d), SUM(inventory.units_on_hand)) COMMENT = 'Share of consigned units near expiry (0-1)',
    inventory.total_inventory_value AS SUM(inventory.inventory_value)
  )

  COMMENT = 'Medical device sales performance: net revenue, units, ASP and discount by product family, therapy area, account, IDN, GPO, territory and rep; quota attainment; contract tiers; consigned inventory.'

  AI_SQL_GENERATION 'Revenue means NET_REVENUE. The fiscal year runs October 2025 to September 2026; H1 is Oct-Mar and H2 is Apr-Sep. Show monthly trends by order_month unless asked otherwise. Quota attainment must come from the quota table, never from orders. For inventory questions use the latest snapshot_date unless a month is given. Round USD to whole dollars and rates to one decimal place as percentages.'

  AI_QUESTION_CATEGORIZATION 'This view covers sales, revenue, ASP, discounts, quota attainment, contracts and consigned inventory. For procedure share, competitive activity, complaints, physicians or share-loss risk, use the account health view.'

  AI_VERIFIED_QUERIES (
    revenue_by_therapy AS (
      QUESTION 'What is net revenue by therapy area?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SALES_PERFORMANCE_SV
             DIMENSIONS families.therapy_area
             METRICS orders.total_net_revenue)
           ORDER BY total_net_revenue DESC'
    ),
    attainment_by_region AS (
      QUESTION 'What is quota attainment by region?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SALES_PERFORMANCE_SV
             DIMENSIONS territories.region
             METRICS quota.quota_attainment)
           ORDER BY quota_attainment'
    ),
    asp_by_family AS (
      QUESTION 'What is the average selling price by product family?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SALES_PERFORMANCE_SV
             DIMENSIONS families.product_family
             METRICS orders.average_selling_price)
           ORDER BY average_selling_price DESC'
    )
  );

-- ----------------------------------------------- Account health view
CREATE OR REPLACE SEMANTIC VIEW CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ACCOUNT_HEALTH_SV

  TABLES (
    accounts AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_ACCOUNT
      PRIMARY KEY (ACCOUNT_ID)
      WITH SYNONYMS ('customers', 'hospitals', 'facilities')
      COMMENT = 'Hospitals, academic medical centers, ASCs and specialty clinics',
    territories AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_TERRITORY
      PRIMARY KEY (TERRITORY_ID)
      COMMENT = 'Sales territories and their reps',
    procedures AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_PROCEDURES
      PRIMARY KEY (PROCEDURE_ID)
      WITH SYNONYMS ('cases', 'market procedures')
      COMMENT = 'Every market procedure at the account, ours or a competitor''s',
    hcps AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_HCP
      PRIMARY KEY (HCP_ID)
      WITH SYNONYMS ('physicians', 'surgeons', 'implanters', 'doctors')
      COMMENT = 'Implanting physicians and surgeons',
    families AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.DIM_PRODUCT_FAMILY
      PRIMARY KEY (FAMILY_ID)
      COMMENT = 'Product families and therapy areas',
    competitive AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_COMPETITIVE_EVENTS
      PRIMARY KEY (EVENT_ID)
      WITH SYNONYMS ('competitive activity', 'competitor events')
      COMMENT = 'Competitor evaluations, trials, value analysis reviews, conversions and win-backs',
    complaints AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.FACT_COMPLAINTS
      PRIMARY KEY (COMPLAINT_ID)
      COMMENT = 'Product complaints reported by accounts (no patient data)',
    features AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ML_ACCOUNT_FEATURES
      PRIMARY KEY (ACCOUNT_ID)
      COMMENT = 'Account features as of 2026-03-31 plus observed H2 share change',
    preds AS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SHARE_LOSS_PREDICTIONS
      PRIMARY KEY (ACCOUNT_ID)
      COMMENT = 'Share-loss risk scores from the registered SHARE_LOSS_MODEL (batch inference in the warehouse)'
  )

  RELATIONSHIPS (
    account_to_territory AS accounts(TERRITORY_ID) REFERENCES territories,
    procedure_to_account AS procedures(ACCOUNT_ID) REFERENCES accounts,
    procedure_to_hcp AS procedures(HCP_ID) REFERENCES hcps,
    procedure_to_family AS procedures(FAMILY_ID) REFERENCES families,
    competitive_to_account AS competitive(ACCOUNT_ID) REFERENCES accounts,
    competitive_to_family AS competitive(FAMILY_ID) REFERENCES families,
    complaint_to_account AS complaints(ACCOUNT_ID) REFERENCES accounts,
    complaint_to_family AS complaints(FAMILY_ID) REFERENCES families,
    features_to_account AS features(ACCOUNT_ID) REFERENCES accounts,
    preds_to_account AS preds(ACCOUNT_ID) REFERENCES accounts
  )

  FACTS (
    procedures.ours_flag AS IFF(procedures.USED_OUR_DEVICE, 1, 0) COMMENT = '1 if the procedure used our device',
    competitive.estimated_annual_revenue AS competitive.ESTIMATED_ANNUAL_REVENUE COMMENT = 'Annual revenue at stake in the event, USD',
    features.revenue_h1 AS features.REVENUE_H1,
    features.our_share_h1 AS features.OUR_SHARE_H1,
    features.share_change_h2_pp AS features.SHARE_CHANGE_H2_PP COMMENT = 'Observed change in procedure share, H2 vs H1, percentage points',
    features.days_to_next_renewal AS features.DAYS_TO_NEXT_RENEWAL,
    preds.model_share_loss_score AS preds.SHARE_LOSS_SCORE COMMENT = 'Model probability 0-1 that the account loses 8+ points of share',
    preds.share_loss_prediction AS preds.SHARE_LOSS_PREDICTION
  )

  DIMENSIONS (
    accounts.account_name AS accounts.ACCOUNT_NAME,
    accounts.account_type AS accounts.ACCOUNT_TYPE SAMPLE_VALUES ('Academic Medical Center', 'Community Hospital', 'Ambulatory Surgery Center', 'Specialty Clinic') IS_ENUM,
    accounts.idn_name AS accounts.IDN_NAME WITH SYNONYMS = ('IDN', 'health system'),
    accounts.gpo_name AS accounts.GPO_NAME WITH SYNONYMS = ('GPO'),
    accounts.account_state AS accounts.STATE,
    accounts.value_analysis_required AS accounts.VALUE_ANALYSIS_REQUIRED COMMENT = 'Account requires value analysis committee approval for new devices',
    territories.region AS territories.REGION SAMPLE_VALUES ('Northeast', 'Southeast', 'Central', 'West') IS_ENUM,
    territories.territory_name AS territories.TERRITORY_NAME,
    territories.rep_name AS territories.REP_NAME WITH SYNONYMS = ('rep', 'sales rep'),
    procedures.procedure_date AS procedures.PROCEDURE_DATE,
    procedures.procedure_month AS DATE_TRUNC('month', procedures.PROCEDURE_DATE),
    procedures.competitor AS procedures.COMPETITOR COMMENT = 'Competitor whose device was used; NULL when ours' SAMPLE_VALUES ('Corvex Medical', 'Brightline Scientific', 'Novix Health', 'Other competitor') IS_ENUM,
    hcps.hcp_name AS hcps.HCP_NAME,
    hcps.specialty AS hcps.SPECIALTY SAMPLE_VALUES ('Electrophysiologist', 'Interventional Cardiologist', 'Neurosurgeon', 'Pain Medicine', 'Endocrinologist', 'General Surgeon') IS_ENUM,
    hcps.volume_tier AS hcps.VOLUME_TIER SAMPLE_VALUES ('High', 'Medium', 'Low') IS_ENUM,
    hcps.is_kol AS hcps.IS_KOL WITH SYNONYMS = ('key opinion leader', 'KOL'),
    families.product_family AS families.PRODUCT_FAMILY WITH SYNONYMS = ('product', 'device'),
    families.therapy_area AS families.THERAPY_AREA WITH SYNONYMS = ('therapy', 'franchise')
      SAMPLE_VALUES ('Cardiac Rhythm', 'Structural Heart', 'Neuromodulation', 'Diabetes', 'Surgical') IS_ENUM,
    competitive.event_date AS competitive.EVENT_DATE,
    competitive.event_type AS competitive.EVENT_TYPE SAMPLE_VALUES ('Product Evaluation', 'Trial Started', 'Value Analysis Review', 'Converted to Competitor', 'Won Back') IS_ENUM,
    competitive.event_competitor AS competitive.COMPETITOR SAMPLE_VALUES ('Corvex Medical', 'Brightline Scientific', 'Novix Health') IS_ENUM,
    complaints.reported_date AS complaints.REPORTED_DATE,
    complaints.complaint_month AS DATE_TRUNC('month', complaints.REPORTED_DATE),
    complaints.complaint_category AS complaints.CATEGORY SAMPLE_VALUES ('Device Malfunction', 'Packaging or Labeling', 'Delivery Delay', 'Use Error', 'Sterility Concern') IS_ENUM,
    complaints.severity AS complaints.SEVERITY SAMPLE_VALUES ('High', 'Medium', 'Low') IS_ENUM,
    complaints.complaint_status AS complaints.STATUS SAMPLE_VALUES ('Closed', 'Under Investigation') IS_ENUM,
    preds.model_version AS preds.MODEL_VERSION COMMENT = 'Model version that produced the score; LEGACY_SEED before the notebook runs',
    preds.scored_at AS preds.SCORED_AT
  )

  METRICS (
    procedures.total_procedures AS COUNT(procedures.PROCEDURE_ID) WITH SYNONYMS = ('market procedures', 'case volume'),
    procedures.our_procedures AS SUM(procedures.ours_flag),
    procedures.procedure_share AS DIV0(SUM(procedures.ours_flag), COUNT(procedures.PROCEDURE_ID)) WITH SYNONYMS = ('market share', 'share', 'share of procedures') COMMENT = 'Our share of market procedures (0-1)',
    procedures.competitor_procedures AS COUNT(procedures.PROCEDURE_ID) - SUM(procedures.ours_flag),
    competitive.competitive_event_count AS COUNT(competitive.EVENT_ID),
    competitive.conversions_to_competitor AS COUNT_IF(competitive.EVENT_TYPE = 'Converted to Competitor'),
    competitive.competitor_trials AS COUNT_IF(competitive.EVENT_TYPE = 'Trial Started'),
    competitive.revenue_at_stake AS SUM(competitive.estimated_annual_revenue) COMMENT = 'Annual revenue at stake in competitive events, USD',
    complaints.complaint_count AS COUNT(complaints.COMPLAINT_ID),
    complaints.high_severity_complaints AS COUNT_IF(complaints.SEVERITY = 'High'),
    hcps.hcp_count AS COUNT(DISTINCT hcps.HCP_ID),
    accounts.account_count AS COUNT(DISTINCT accounts.ACCOUNT_ID),
    preds.avg_share_loss_score AS AVG(preds.model_share_loss_score) WITH SYNONYMS = ('share loss risk', 'risk score', 'at-risk score'),
    preds.predicted_at_risk_accounts AS SUM(preds.share_loss_prediction) WITH SYNONYMS = ('at-risk accounts'),
    features.avg_share_change_h2_pp AS AVG(features.share_change_h2_pp) COMMENT = 'Average observed H2 vs H1 share change, points'
  )

  COMMENT = 'Medical device account health: procedure share vs competitors, physicians, competitive events, complaints, contract renewal timing and model share-loss risk.'

  AI_SQL_GENERATION 'Share means procedure_share. The fiscal year runs October 2025 to September 2026; H1 is Oct-Mar and H2 is Apr-Sep. For share-loss risk use the model score (avg_share_loss_score, predicted_at_risk_accounts) from SHARE_LOSS_PREDICTIONS unless the user asks for the legacy score. Never return patient-level data. Round rates to one decimal place as percentages.'

  AI_QUESTION_CATEGORIZATION 'This view covers procedure share, competitive activity, complaints, physicians and share-loss risk. For revenue, ASP, quota or inventory, use the sales performance view.'

  AI_VERIFIED_QUERIES (
    share_by_therapy AS (
      QUESTION 'What is our procedure share by therapy area?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ACCOUNT_HEALTH_SV
             DIMENSIONS families.therapy_area
             METRICS procedures.procedure_share)
           ORDER BY procedure_share DESC'
    ),
    risk_by_region AS (
      QUESTION 'Which region has the most accounts at risk of share loss?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ACCOUNT_HEALTH_SV
             DIMENSIONS territories.region
             METRICS preds.predicted_at_risk_accounts, preds.avg_share_loss_score)
           ORDER BY predicted_at_risk_accounts DESC'
    ),
    conversions_by_competitor AS (
      QUESTION 'How many conversions to each competitor have we had?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ACCOUNT_HEALTH_SV
             DIMENSIONS competitive.event_competitor
             METRICS competitive.conversions_to_competitor)
           ORDER BY conversions_to_competitor DESC'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5b. CORTEX SEARCH (product knowledge: IFU, clinical evidence, battlecards, policy)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE CORTEX SEARCH SERVICE CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.PRODUCT_KNOWLEDGE_SEARCH
  ON BODY
  ATTRIBUTES DOC_TYPE, THERAPY_AREA, PRODUCT_FAMILY
  WAREHOUSE = GATEWAY_MEDTECH_WH
  TARGET_LAG = '1 day'
  COMMENT = 'Field knowledge: IFU summaries, clinical and real-world evidence, battlecards, reimbursement notes, contract and compliance policy'
AS
  SELECT DOC_ID, TITLE, BODY, DOC_TYPE, THERAPY_AREA, PRODUCT_FAMILY, EFFECTIVE_DATE
  FROM CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.PRODUCT_KNOWLEDGE_DOCS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX AGENT + MCP SERVER (one governed tool for external LLM agents)
-- ─────────────────────────────────────────────────────────────────────────────
-- The agent orchestrates two Cortex Analyst tools (each generates AND runs its SQL
-- against a semantic view) and a Cortex Search tool over the product knowledge
-- corpus. The MCP server exposes only the agent, so the external client never gets
-- a raw SQL tool that could bypass the semantic views.
-- Clients connect via streamable HTTP at:
--   POST /api/v2/databases/CORTEX_GATEWAY_MEDTECH_LAB/schemas/PUBLIC/mcp-servers/MEDTECH_MCP

CREATE OR REPLACE AGENT CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.MEDTECH_SALES_AGENT
  COMMENT = 'Governed medical device field sales agent exposed via MEDTECH_MCP'
  PROFILE = '{"display_name": "Field Sales Assistant"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    You are a field sales assistant for a medical device manufacturer that sells cardiac rhythm,
    structural heart, neuromodulation, diabetes and surgical products to hospitals, IDNs and ASCs.
    Lead with the direct answer and the number. Format revenue in USD with no decimals and rates as
    percentages with one decimal. The fiscal year runs October 2025 through September 2026
    (H1 = Oct-Mar, H2 = Apr-Sep). When you use product knowledge, name the document title you used.
    Stay within labeled indications: never suggest off-label use, never claim clinical superiority over
    a competitor, and refer off-label questions to Medical Affairs. Never return patient-level data.
  orchestration: >
    Use sales_performance_analyst for revenue, units, ASP, discounts, quota attainment, contracts,
    price tiers and consigned inventory.
    Use account_health_analyst for procedure share, competitor usage, competitive events (evaluations,
    trials, value analysis reviews, conversions), complaints, physicians and share-loss risk. For
    share-loss risk use the model score (avg_share_loss_score, predicted_at_risk_accounts) unless the
    user asks for the legacy score.
    Use product_knowledge_search for IFU and labeling facts (indications, contraindications, MRI status,
    longevity), clinical and real-world evidence, competitive battlecards and objection handling,
    reimbursement notes, and contract, deal desk, consignment, value analysis and compliance policy.
    For account planning questions combine both: get the numbers first, then the evidence or policy.
    Generate a chart when the data has 3 or more rows and the user asks for a trend or comparison.
  sample_questions:
    - question: "Which accounts in the Northeast have the highest share-loss risk?"
    - question: "What is our procedure share by therapy area, H1 vs H2?"
    - question: "Which territories are furthest below quota this fiscal year?"
    - question: "Which competitor is converting the most of our accounts, and in which therapy area?"
    - question: "What does our clinical evidence say for the Valvia TAVR System versus the Brightline Apex Valve?"
    - question: "What discount does a Tier 2 GPO contract carry, and what share does it require?"
    - question: "Why did Device Malfunction complaints rise for the Torque Powered Stapler this summer?"
    - question: "How many consigned units are near expiry, by product family?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_performance_analyst"
      description: >
        Sales and commercial performance numbers from the SALES_PERFORMANCE_SV semantic view.
        Covers: net revenue, units, average selling price (ASP), discount and discount rate by product
        family, therapy area, operating unit, account, account type, IDN, GPO, state, territory, rep and
        month; quota, actual revenue and quota attainment by territory, region and therapy area; contracts
        (GPO / IDN local / direct agreements, price tier, discount %, committed share %, renewal date); and
        month-end consigned inventory (units on hand, units expiring within 90 days, inventory value).
        Do NOT use for procedure share, competitor activity, complaints, physicians or share-loss risk.
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "account_health_analyst"
      description: >
        Account health numbers from the ACCOUNT_HEALTH_SV semantic view.
        Covers: market procedures, our procedures and procedure share (market share) by account, IDN, GPO,
        region, territory, rep, therapy area, product family, physician and month; competitor usage;
        competitive events (product evaluations, trials started, value analysis reviews, conversions to
        competitor, win-backs) and annual revenue at stake; product complaints by category, severity and
        status; physicians (specialty, volume tier, KOL); and share-loss risk from the registered
        SHARE_LOSS_MODEL (avg_share_loss_score, predicted_at_risk_accounts), plus observed H2 share change.
        Do NOT use for revenue, ASP, quota or inventory.
  - tool_spec:
      type: "cortex_search"
      name: "product_knowledge_search"
      description: >
        Semantic search over the field knowledge corpus: IFU summaries (indications, contraindications,
        MRI status, longevity), clinical trial and real-world evidence summaries, competitive battlecards
        and objection handling, reimbursement and coding notes, contract price tier policy, deal desk
        exceptions, consignment and bill-only policy, value analysis committee guide, on-label compliance
        policy, and field action notices.
        Filterable attributes: DOC_TYPE (IFU Summary, Clinical Evidence, Real-World Evidence, Competitive
        Battlecard, Reimbursement Note, Contract Policy, Value Analysis Guide, Compliance Policy, Field
        Action Notice), THERAPY_AREA, PRODUCT_FAMILY. Cite results by TITLE.
        Do NOT use for numbers about sales, share or accounts.
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from structured data returned by the analyst tools."

tool_resources:
  sales_performance_analyst:
    semantic_view: "CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.SALES_PERFORMANCE_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "GATEWAY_MEDTECH_WH"
  account_health_analyst:
    semantic_view: "CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.ACCOUNT_HEALTH_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "GATEWAY_MEDTECH_WH"
  product_knowledge_search:
    name: "CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.PRODUCT_KNOWLEDGE_SEARCH"
    max_results: "5"
    title_column: "TITLE"
    id_column: "DOC_ID"
$$;

CREATE OR REPLACE MCP SERVER MEDTECH_MCP FROM SPECIFICATION $$
tools:
  - name: medtech_sales_agent
    title: "Medical device field sales agent"
    description: "Answers field sales questions end to end: revenue, ASP, discounts, quota attainment, contracts and consigned inventory; procedure share, competitive events, complaints, physicians and model share-loss risk by account, IDN, territory and therapy area; and product knowledge (IFU, clinical evidence, battlecards, reimbursement, contract and compliance policy). Pass the user's question as the message."
    type: "CORTEX_AGENT_RUN"
    identifier: "CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.MEDTECH_SALES_AGENT"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. AI GATEWAY CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────
-- The AI Gateway is auto-provisioned per account (named SNOWFLAKE).
-- Endpoint (get the exact host from SHOW AI GATEWAYS / DESCRIBE AI GATEWAY):
--   https://<account-host>/api/v2/aigateways/SNOWFLAKE
--   + /v1/chat/completions   OpenAI-compatible (all non-Claude models)
--   + /v1/messages           Anthropic-compatible (Claude models only)
-- This is a different endpoint from Cortex Inference (/api/v2/cortex): only
-- traffic through the gateway gets its access control, traces, and cost attribution.
--
-- The spec defines:
--   models:   allowlist of model name patterns (* = all models)
--   logging:  trace capture, client telemetry, payload recording
-- FROM SPECIFICATION replaces the WHOLE spec, so always submit every field.
-- Requires ACCOUNTADMIN.

USE ROLE ACCOUNTADMIN;

ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
schema_version: 1
models:
  - name: '*'
logging:
  enabled: true
  enable_client_telemetry: true
  capture_payload:
    request_response: true
$$;

-- Let the lab role read traces (AGENT_TRACE_TABLE + usage views need MONITOR)
GRANT MONITOR ON AI GATEWAY SNOWFLAKE TO ROLE SYSADMIN;
GRANT USAGE   ON AI GATEWAY SNOWFLAKE TO ROLE SYSADMIN;

-- Cost sections of the lab/app: AI_GATEWAY_USAGE_HISTORY, budgets, user tags
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER   TO ROLE SYSADMIN;
GRANT DATABASE ROLE SNOWFLAKE.BUDGET_CREATOR TO ROLE SYSADMIN;
GRANT DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER TO ROLE SYSADMIN;   -- ACCOUNT_USAGE.USERS (spend by user)
GRANT DATABASE ROLE SNOWFLAKE.QUOTA_CREATOR TO ROLE SYSADMIN;
GRANT CREATE SNOWFLAKE.CORE.QUOTA ON SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT APPLY TAG ON ACCOUNT TO ROLE SYSADMIN;

-- Verify the gateway configuration
DESCRIBE AI GATEWAY SNOWFLAKE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7b. OAUTH CLIENT FOR AI GATEWAY TOOLS (Snowflake MCP server entry)
-- ─────────────────────────────────────────────────────────────────────────────
-- Gateway Tools connects AI clients (CoCo Desktop, Claude, Cursor) to MCP servers:
-- here Glean (custom server) and this account's MEDTECH_MCP (catalog "Snowflake"
-- server). The Snowflake server entry needs a Snowflake OAuth client whose redirect
-- URI is the Tools callback. Enabling servers in Tools is done in Snowsight
-- (AI & ML > AI Gateway > MCP & Tools); then run lab/tools_setup.sql. See README.
CREATE SECURITY INTEGRATION IF NOT EXISTS GATEWAY_MEDTECH_TOOLS_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://identity.snowflake.com/oauth2/callback'
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  COMMENT = 'OAuth client for the Snowflake MCP server entry (MEDTECH_MCP) in AI Gateway Tools';

USE ROLE SYSADMIN;
USE DATABASE CORTEX_GATEWAY_MEDTECH_LAB;
USE SCHEMA PUBLIC;
USE WAREHOUSE GATEWAY_MEDTECH_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. OPTIMIZATION LOOP TABLES (used by the Trace Analyzer app)
-- ─────────────────────────────────────────────────────────────────────────────
-- EVAL_PROMPTS        : fixed question set replayed through the gateway for each config
-- OPTIMIZATION_RUNS   : one row per experiment config (model / system prompt / max_tokens)
-- OPTIMIZATION_RESULTS: one row per (run, prompt): latency, tokens, rubric judge scores,
--                       and the trace_ids of both the answer and the judge call
-- OPTIMIZER_CALLS     : every LLM call the optimizer itself makes (diagnose, propose a
--                       prompt, judge), each sent through the AI Gateway and traced
--
-- INTENT groups prompts for the model-routing analysis on the Before / after page.

-- A view, so the numeric expectations are always computed from the current data,
-- including SHARE_LOSS_PREDICTIONS after the notebook replaces the seed scores.
CREATE OR REPLACE VIEW EVAL_PROMPTS AS
WITH rev AS (
    SELECT o.*, f.THERAPY_AREA FROM FACT_SALES_ORDERS o JOIN DIM_PRODUCT_FAMILY f USING (FAMILY_ID)
), risk AS (
    SELECT p.*, a.REGION, a.ACCOUNT_TYPE FROM SHARE_LOSS_PREDICTIONS p JOIN DIM_ACCOUNT a USING (ACCOUNT_ID)
), fam AS (
    SELECT * FROM DIM_PRODUCT_FAMILY
)
SELECT 'P01' AS PROMPT_ID, 'metric' AS CATEGORY, 'sales_metric' AS INTENT,
       'What was total net revenue for fiscal year 2026 (October 2025 through September 2026)?' AS PROMPT,
       'Total net revenue was $' || TO_VARCHAR(ROUND(SUM(NET_REVENUE)), 'FM999,999,999,999') AS EXPECTED
FROM rev
UNION ALL
SELECT 'P02', 'metric', 'sales_metric', 'Which therapy area had the highest net revenue, and how much?',
       MAX_BY(THERAPY_AREA, r) || ' had the highest net revenue at $' || TO_VARCHAR(ROUND(MAX(r)), 'FM999,999,999,999')
FROM (SELECT THERAPY_AREA, SUM(NET_REVENUE) r FROM rev GROUP BY 1)
UNION ALL
SELECT 'P03', 'metric', 'sales_metric', 'What was overall quota attainment for the fiscal year?',
       'Quota attainment was ' || TO_VARCHAR(ROUND(100 * SUM(ACTUAL_REVENUE) / NULLIF(SUM(QUOTA_AMOUNT), 0), 1)) || '%'
FROM FACT_QUOTA_ATTAINMENT
UNION ALL
SELECT 'P04', 'metric', 'account_health', 'What was our overall procedure share for the fiscal year?',
       'Our procedure share was ' || TO_VARCHAR(ROUND(100 * COUNT_IF(USED_OUR_DEVICE) / COUNT(*), 1)) || '%'
FROM FACT_PROCEDURES
UNION ALL
SELECT 'P05', 'metric', 'account_health', 'Which competitor converted the most of our accounts, and how many conversions?',
       MAX_BY(COMPETITOR, n) || ' with ' || TO_VARCHAR(MAX(n)) || ' conversions'
FROM (SELECT COMPETITOR, COUNT(*) n FROM FACT_COMPETITIVE_EVENTS WHERE EVENT_TYPE = 'Converted to Competitor' GROUP BY 1)
UNION ALL
SELECT 'P06', 'metric', 'sales_metric', 'How many consigned units were within 90 days of expiry at the end of September 2026?',
       TO_VARCHAR(SUM(UNITS_EXPIRING_90D)) || ' consigned units were within 90 days of expiry'
FROM FACT_CONSIGNMENT_INVENTORY WHERE SNAPSHOT_DATE = '2026-09-30'
UNION ALL
SELECT 'P07', 'ml', 'share_loss', 'How many accounts does the share-loss model flag as at risk?',
       TO_VARCHAR(SUM(SHARE_LOSS_PREDICTION)) || ' accounts are predicted to be at risk'
FROM risk
UNION ALL
SELECT 'P08', 'ml', 'share_loss', 'Which region has the highest average share-loss risk score?',
       MAX_BY(REGION, s) || ' at ' || TO_VARCHAR(ROUND(MAX(s), 2))
FROM (SELECT REGION, AVG(SHARE_LOSS_SCORE) s FROM risk GROUP BY 1)
UNION ALL
SELECT 'P09', 'ml', 'share_loss', 'What share of academic medical centers are predicted to be at risk of share loss?',
       TO_VARCHAR(ROUND(100 * SUM(SHARE_LOSS_PREDICTION) / NULLIF(COUNT(*), 0), 1)) || '% of academic medical centers'
FROM risk WHERE ACCOUNT_TYPE = 'Academic Medical Center'
UNION ALL
SELECT 'P10', 'knowledge', 'labeling', 'What is the MRI status of the Axion DBS System?',
       MRI_STATUS FROM fam WHERE PRODUCT_FAMILY = 'Axion DBS System'
UNION ALL
SELECT 'P11', 'knowledge', 'evidence', 'What was the primary endpoint result of the Valvia TAVR pivotal trial?',
       PIVOTAL_TRIAL || ': ' || PRIMARY_ENDPOINT || ' of ' || ENDPOINT_RESULT FROM fam WHERE PRODUCT_FAMILY = 'Valvia TAVR System'
UNION ALL
SELECT 'P12', 'knowledge', 'policy', 'What discount does a Tier 2 contract carry, and what committed share does it require?',
       'Tier 2 carries a 17% discount off list and requires at least 70% committed procedure share'
UNION ALL
SELECT 'P13', 'knowledge', 'policy', 'What is the par level for consigned inventory, and what happens to units close to expiry?',
       'Par is 1.8 months of average usage; units within 90 days of expiry must be rotated to a higher-usage account or returned'
UNION ALL
SELECT 'P14', 'knowledge', 'labeling', 'How long can a Glyde CGM Sensor be worn?',
       LONGEVITY FROM fam WHERE PRODUCT_FAMILY = 'Glyde CGM Sensor'
UNION ALL
SELECT 'P15', 'knowledge', 'policy', 'Can I tell a surgeon the Pulsar Pacemaker is clinically superior to the Corvex Rhythmia DR?',
       'No. There is no head-to-head trial, so do not make comparative superiority claims; position labeled outcomes from PULSE-HF and total cost of care, and refer clinical questions outside labeling to Medical Affairs'
UNION ALL
SELECT 'P16', 'knowledge', 'policy', 'What is the field action for the Torque Stapler Reload, and what should reps do?',
       'A cartridge latch tolerance issue caused incomplete firing in specific reload lots (June to August 2026); reps notify surgical services, quarantine the listed lots and replace them at no charge'
UNION ALL SELECT 'P17', 'definition', 'definition', 'Define average selling price (ASP) in one sentence.', 'Net revenue divided by units sold'
UNION ALL SELECT 'P18', 'definition', 'definition', 'What is a bill-only (consigned) order? One sentence.', 'An implant held on consignment at the hospital and billed to the account only after it is used in a case'
UNION ALL SELECT 'P19', 'definition', 'definition', 'What is a hospital value analysis committee? One sentence.', 'A hospital committee that evaluates clinical evidence and total cost before approving new devices or conversions'
UNION ALL SELECT 'P20', 'definition', 'definition', 'Define procedure share in one sentence.', 'Our procedures as a share of all market procedures for the therapy at the account';

CREATE TABLE IF NOT EXISTS OPTIMIZATION_RUNS (
    RUN_ID              VARCHAR,
    CREATED_AT          TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    LABEL               VARCHAR,          -- 'baseline' | 'candidate' | 'prompt-opt-<n>'
    MODEL               VARCHAR,
    SYSTEM_PROMPT       VARCHAR,
    MAX_TOKENS          NUMBER,
    SOURCE_FINDING      VARCHAR,          -- advisor finding / 'prompt-optimizer' that motivated the run
    OPTIMIZER_TRACE_ID  VARCHAR           -- trace of the optimizer call that proposed this config
);

CREATE TABLE IF NOT EXISTS OPTIMIZATION_RESULTS (
    RUN_ID          VARCHAR,
    PROMPT_ID       VARCHAR,
    TRACE_ID        VARCHAR,          -- trace of the answer call
    RESPONSE        VARCHAR,
    LATENCY_MS      NUMBER,
    INPUT_TOKENS    NUMBER,
    OUTPUT_TOKENS   NUMBER,
    STATUS          VARCHAR,
    JUDGE_SCORE     FLOAT,            -- weighted rubric score 0-1
    JUDGE_DETAIL    VARIANT,          -- {correctness, completeness, conciseness, compliance, rationale}
    JUDGE_MODEL     VARCHAR,
    JUDGE_TRACE_ID  VARCHAR,          -- trace of the judge call through the gateway
    CREATED_AT      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS OPTIMIZER_CALLS (
    CALL_ID          VARCHAR,
    CREATED_AT       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    ROLE             VARCHAR,          -- 'diagnose' | 'propose_prompt' | 'judge'
    RUN_ID           VARCHAR,
    MODEL            VARCHAR,
    TRACE_ID         VARCHAR,
    CONVERSATION_ID  VARCHAR,          -- optimizer-<role>-<run_id>
    INPUT_TOKENS     NUMBER,
    OUTPUT_TOKENS    NUMBER,
    LATENCY_MS       NUMBER,
    STATUS           VARCHAR
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. STREAMLIT APP ACCESS (container runtime)
-- ─────────────────────────────────────────────────────────────────────────────
-- The Trace Analyzer app (../app) runs on the container runtime. It needs:
--   * PyPI egress to install its dependencies
--   * egress to the account host so the Live / Experiments pages can call the
--     gateway inference endpoint. The app authenticates with its container
--     session token by default; GATEWAY_PAT_SECRET is an optional fallback
--     (set SECRET_STRING to a PAT, then uncomment the SECRETS line in snowflake.yml).

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_APP_EGRESS
  TYPE = HOST_PORT
  MODE = EGRESS
  VALUE_LIST = ('pypi.org', 'pypi.python.org', 'pythonhosted.org', 'files.pythonhosted.org',
                '<% gateway_host %>');
-- ^ your account host, hyphens not underscores. ./demo.sh setup fills it in;
--   by hand: snow sql -f lab/setup.sql -D gateway_host=myorg-myaccount.snowflakecomputing.com

CREATE SECRET IF NOT EXISTS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_PAT_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = 'replace-with-a-programmatic-access-token';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GATEWAY_MEDTECH_APP_EAI
  ALLOWED_NETWORK_RULES = (CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_APP_EGRESS)
  ALLOWED_AUTHENTICATION_SECRETS = (CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_PAT_SECRET)
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GATEWAY_MEDTECH_APP_EAI TO ROLE SYSADMIN;
GRANT USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU TO ROLE SYSADMIN;
GRANT OWNERSHIP ON SECRET CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_PAT_SECRET TO ROLE SYSADMIN COPY CURRENT GRANTS;

USE ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9b. COMMERCIAL TEAM PERSONAS, PER-USER QUOTAS AND BUDGET
-- ─────────────────────────────────────────────────────────────────────────────
-- A small commercial org calls the gateway as service users, one per persona,
-- so traces, spend and chargeback break down by user and cost center:
--
--   User                               Role                         COST_CENTER           QUOTA_TIER
--   GATEWAY_MEDTECH_REP_NORTHEAST      GATEWAY_MEDTECH_FIELD_RL     FIELD_SALES           FIELD
--   GATEWAY_MEDTECH_REP_SOUTHEAST      GATEWAY_MEDTECH_FIELD_RL     FIELD_SALES           FIELD
--   GATEWAY_MEDTECH_TM_WEST            GATEWAY_MEDTECH_FIELD_RL     FIELD_SALES           FIELD
--   GATEWAY_MEDTECH_TERRITORY_PLANNER  GATEWAY_MEDTECH_FIELD_RL     FIELD_SALES           FIELD
--   GATEWAY_MEDTECH_SALES_OPS          GATEWAY_MEDTECH_ANALYST_RL   SALES_OPS             ANALYST
--   GATEWAY_MEDTECH_MARKET_ACCESS      GATEWAY_MEDTECH_ANALYST_RL   COMMERCIAL_ANALYTICS  ANALYST
--   GATEWAY_MEDTECH_AI_PLATFORM        GATEWAY_MEDTECH_PLATFORM_RL  AI_PLATFORM           PLATFORM
--
-- TERRITORY_PLANNER is a scheduled batch agent. ./demo.sh burst makes it run
-- away so the FIELD quota blocks it while the reps on the same tier keep working.
-- Each QUOTA_TIER value maps to one quota (INTERSECTION on the tag), because a
-- quota has one limit for all of its users. Keep real users OUT of the quotas:
-- a block applies to every AI domain the user touches, not just the gateway.
-- ./demo.sh setup issues a PAT per persona (~/.snowflake/gateway_medtech_<persona>.pat).

CREATE TAG IF NOT EXISTS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER
  COMMENT = 'Cost center for gateway chargeback';
CREATE TAG IF NOT EXISTS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER
  COMMENT = 'Selects which per-user quota a user falls under';

USE ROLE ACCOUNTADMIN;

-- Roles: gateway inference only. Every persona reaches models through the gateway.
CREATE ROLE IF NOT EXISTS GATEWAY_MEDTECH_FIELD_RL    COMMENT = 'Field sales: AI Gateway inference';
CREATE ROLE IF NOT EXISTS GATEWAY_MEDTECH_ANALYST_RL  COMMENT = 'Sales ops and commercial analytics: AI Gateway inference';
CREATE ROLE IF NOT EXISTS GATEWAY_MEDTECH_PLATFORM_RL COMMENT = 'AI platform team: AI Gateway inference';
GRANT USAGE ON AI GATEWAY SNOWFLAKE TO ROLE GATEWAY_MEDTECH_FIELD_RL;
GRANT USAGE ON AI GATEWAY SNOWFLAKE TO ROLE GATEWAY_MEDTECH_ANALYST_RL;
GRANT USAGE ON AI GATEWAY SNOWFLAKE TO ROLE GATEWAY_MEDTECH_PLATFORM_RL;
GRANT ROLE GATEWAY_MEDTECH_FIELD_RL    TO ROLE SYSADMIN;
GRANT ROLE GATEWAY_MEDTECH_ANALYST_RL  TO ROLE SYSADMIN;
GRANT ROLE GATEWAY_MEDTECH_PLATFORM_RL TO ROLE SYSADMIN;

-- Field sales
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_REP_NORTHEAST TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_FIELD_RL COMMENT = 'Field rep, Northeast: copilot in the CRM';
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_REP_SOUTHEAST TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_FIELD_RL COMMENT = 'Field rep, Southeast: copilot in the CRM';
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_TM_WEST TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_FIELD_RL COMMENT = 'Territory manager, West: account planning';
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_TERRITORY_PLANNER TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_FIELD_RL COMMENT = 'Scheduled batch agent: drafts territory plans for the field';
GRANT ROLE GATEWAY_MEDTECH_FIELD_RL TO USER GATEWAY_MEDTECH_REP_NORTHEAST;
GRANT ROLE GATEWAY_MEDTECH_FIELD_RL TO USER GATEWAY_MEDTECH_REP_SOUTHEAST;
GRANT ROLE GATEWAY_MEDTECH_FIELD_RL TO USER GATEWAY_MEDTECH_TM_WEST;
GRANT ROLE GATEWAY_MEDTECH_FIELD_RL TO USER GATEWAY_MEDTECH_TERRITORY_PLANNER;
ALTER USER GATEWAY_MEDTECH_REP_NORTHEAST SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'FIELD_SALES', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'FIELD';
ALTER USER GATEWAY_MEDTECH_REP_SOUTHEAST SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'FIELD_SALES', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'FIELD';
ALTER USER GATEWAY_MEDTECH_TM_WEST SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'FIELD_SALES', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'FIELD';
ALTER USER GATEWAY_MEDTECH_TERRITORY_PLANNER SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'FIELD_SALES', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'FIELD';

-- Sales ops and commercial analytics
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_SALES_OPS TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_ANALYST_RL COMMENT = 'Sales operations: QBRs, forecasts, comp plans';
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_MARKET_ACCESS TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_ANALYST_RL COMMENT = 'Market access and contracting analytics';
GRANT ROLE GATEWAY_MEDTECH_ANALYST_RL TO USER GATEWAY_MEDTECH_SALES_OPS;
GRANT ROLE GATEWAY_MEDTECH_ANALYST_RL TO USER GATEWAY_MEDTECH_MARKET_ACCESS;
ALTER USER GATEWAY_MEDTECH_SALES_OPS SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'SALES_OPS', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'ANALYST';
ALTER USER GATEWAY_MEDTECH_MARKET_ACCESS SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'COMMERCIAL_ANALYTICS', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'ANALYST';

-- AI platform team (model evaluation, new integrations)
CREATE USER IF NOT EXISTS GATEWAY_MEDTECH_AI_PLATFORM TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_MEDTECH_PLATFORM_RL COMMENT = 'AI platform team: model evaluation and new integrations';
GRANT ROLE GATEWAY_MEDTECH_PLATFORM_RL TO USER GATEWAY_MEDTECH_AI_PLATFORM;
ALTER USER GATEWAY_MEDTECH_AI_PLATFORM SET TAG
  CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER = 'AI_PLATFORM', CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER = 'PLATFORM';

-- PATs: ./demo.sh setup creates (or rotates) one per persona. They are not
-- created here because ADD fails once the token exists, which would stop a
-- re-run. By hand, for each persona, run this and copy token_secret into
-- ~/.snowflake/gateway_medtech_<persona>.pat (chmod 600), e.g.:
--   ALTER USER GATEWAY_MEDTECH_TERRITORY_PLANNER ADD PROGRAMMATIC ACCESS TOKEN ai_gateway_medtech_persona
--     ROLE_RESTRICTION = 'GATEWAY_MEDTECH_FIELD_RL' DAYS_TO_EXPIRY = 7;

USE ROLE SYSADMIN;
USE SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;

-- Per-user quotas, one per tier. Daily limits reset at 00:00 UTC; a block
-- lands within minutes of the spend that crosses the limit.
-- FIELD: copilot use is light, so 5 credits/day per user is generous for a rep.
CREATE SNOWFLAKE.CORE.QUOTA IF NOT EXISTS GATEWAY_MEDTECH_FIELD_QUOTA();
CALL GATEWAY_MEDTECH_FIELD_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL GATEWAY_MEDTECH_FIELD_QUOTA!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER', 'SESSION', 'APPLYBUDGET')), 'FIELD']],
  'INTERSECTION');
-- Tag scope resolves through TAG_REFERENCES, which can lag ~2 hours for a new
-- user. Naming the batch agent too puts it under enforcement right away.
CALL GATEWAY_MEDTECH_FIELD_QUOTA!INCLUDE_USERS(['GATEWAY_MEDTECH_TERRITORY_PLANNER']);
CALL GATEWAY_MEDTECH_FIELD_QUOTA!SET_PER_USER_LIMIT(5, 'DAILY');
CALL GATEWAY_MEDTECH_FIELD_QUOTA!SET_PER_USER_LIMIT(60);
CALL GATEWAY_MEDTECH_FIELD_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);
CALL GATEWAY_MEDTECH_FIELD_QUOTA!ADD_NOTIFICATION_THRESHOLD(80, 'ACTUAL', FALSE, 'DAILY');

-- ANALYST: long reports and QBR drafts.
CREATE SNOWFLAKE.CORE.QUOTA IF NOT EXISTS GATEWAY_MEDTECH_ANALYST_QUOTA();
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER', 'SESSION', 'APPLYBUDGET')), 'ANALYST']],
  'INTERSECTION');
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!SET_PER_USER_LIMIT(15, 'DAILY');
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!SET_PER_USER_LIMIT(200);
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);
CALL GATEWAY_MEDTECH_ANALYST_QUOTA!ADD_NOTIFICATION_THRESHOLD(80, 'ACTUAL', FALSE, 'DAILY');

-- PLATFORM: model evaluations run in bursts, so a weekly cap backs the daily one.
CREATE SNOWFLAKE.CORE.QUOTA IF NOT EXISTS GATEWAY_MEDTECH_PLATFORM_QUOTA();
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.QUOTA_TIER', 'SESSION', 'APPLYBUDGET')), 'PLATFORM']],
  'INTERSECTION');
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!SET_PER_USER_LIMIT(40, 'DAILY');
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!SET_PER_USER_LIMIT(150, 'WEEKLY');
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);
CALL GATEWAY_MEDTECH_PLATFORM_QUOTA!ADD_NOTIFICATION_THRESHOLD(80, 'ACTUAL', FALSE, 'DAILY');

-- Monthly budget for gateway spend across the commercial cost centers
-- (ENGINEERING is the cost center the notebook gives the lab user). A budget
-- tracks and alerts; the quotas above are what block.
CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS GATEWAY_BUDGET();
CALL GATEWAY_BUDGET!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER', 'SESSION', 'APPLYBUDGET')), 'FIELD_SALES'],
   [(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER', 'SESSION', 'APPLYBUDGET')), 'SALES_OPS'],
   [(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER', 'SESSION', 'APPLYBUDGET')), 'COMMERCIAL_ANALYTICS'],
   [(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER', 'SESSION', 'APPLYBUDGET')), 'AI_PLATFORM'],
   [(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER', 'SESSION', 'APPLYBUDGET')), 'ENGINEERING']],
  'UNION');
CALL GATEWAY_BUDGET!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL GATEWAY_BUDGET!SET_SPENDING_LIMIT(2500);

CALL GATEWAY_MEDTECH_FIELD_QUOTA!GET_CONFIG();

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. VERIFY SETUP
-- ─────────────────────────────────────────────────────────────────────────────

SHOW TABLES IN SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;
SHOW AGENTS IN SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;
SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;
SELECT TABLE_NAME, ROW_COUNT
FROM CORTEX_GATEWAY_MEDTECH_LAB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PUBLIC' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
