# Client Data Entitlements for Wealth Management

**Owner:** Janet Cho · **Last reviewed:** November 2026 · **License:** [Apache 2.0](LICENSE)

A customer-facing, step-by-step guide to serving one wealth-management dataset to many audiences, with access enforced on the data itself:

- **A mapping-table row access policy**: advisors see their book, branch managers their branch, compliance everything
- **Masking policies**, including **net-worth banding**
- **Tag-based masking** that protects new columns the moment they're tagged
- **An aggregation policy**: an external research partner can only query groups of 10 or more clients
- **A secure, de-identified research view**, ready to share with a partner account

**Live guide:** https://sfc-gh-jacho.github.io/sfguide-fsi-client-entitlements/

The site is fully static and doesn't connect to any Snowflake account. Its result tables come from a real end-to-end run of the script on synthetic data.

## Prerequisites

- **Enterprise Edition or higher** (row access, masking, tag-based masking and aggregation policies)
- **A role to run it.** ACCOUNTADMIN is simplest in a sandbox. For regulated environments, use the least-privilege option below.

### Least-privilege option (no ACCOUNTADMIN)

The script starts with `SET demo_role = 'ACCOUNTADMIN';`. To run without ACCOUNTADMIN, an administrator runs the commented block at the top of Step 1 once:

```sql
USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS ENT_DEMO_ROLE;
GRANT CREATE DATABASE  ON ACCOUNT TO ROLE ENT_DEMO_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE ENT_DEMO_ROLE;      -- or USAGE on an existing warehouse
GRANT CREATE ROLE      ON ACCOUNT TO ROLE ENT_DEMO_ROLE;      -- advisor / manager / compliance / partner roles
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE ENT_DEMO_ROLE;  -- tag-based masking (Step 7)
GRANT ROLE ENT_DEMO_ROLE TO ROLE SYSADMIN;                    -- admins keep control of what it creates
GRANT ROLE ENT_DEMO_ROLE TO USER <YOUR_USER>;
```

Then change the first line to `SET demo_role = 'ENT_DEMO_ROLE';`. This path was tested end to end and produced identical results.

> **Why `GRANT ... TO ROLE SYSADMIN`?** A custom role that isn't in the role hierarchy owns objects that even ACCOUNTADMIN can't drop. Granting it to SYSADMIN keeps administrators in control.

## Run the demo in Snowsight

1. Download [`sql/client_entitlements.sql`](sql/client_entitlements.sql).
2. In Snowsight, open **Projects → Worksheets** and create a new SQL worksheet.
3. Paste the script and run it top to bottom in the same worksheet. No find-and-replace is needed.
4. Step 2 runs `USE SECONDARY ROLES NONE`, so each test role relies only on its own grants. With secondary roles on, a missing grant wouldn't show up when you switch roles. The cleanup step restores the setting.
5. When you're done, uncomment and run Step 12 (Cleanup).

## What the run produces

| Role | Clients visible | Tax ID | Net worth |
|---|---|---|---|
| `ENT_ADVISOR_01` | 50 (own book) | `***-**-6033` | banded: `1,000,000` |
| `ENT_BRANCH_MGR_EAST` | 100 (2 books) | `***-**-****` | banded: `1,000,000` |
| `ENT_COMPLIANCE` | 300 (all) | `901-00-6033` | exact: `2,631,000` |
| `ENT_RESEARCH_PARTNER` | none at row level. Grouped queries of 10+ clients only. | n/a | n/a |

## What gets created

| Object | Name |
|---|---|
| Database | `ENT_DEMO_DB` (schema `WEALTH`) |
| Warehouse | `ENT_WH` (XSMALL, 60 s auto-suspend) |
| Tables | `ENT_CLIENTS` (300), `ENT_ACCOUNTS` (600), `ENT_HOLDINGS` (about 3,850), `ENT_INSTRUMENTS`, `ENT_ENTITLEMENTS` |
| Views | `ENT_CLIENT_PROFILE` (aggregation-constrained), `ENT_RESEARCH_SECTOR_EXPOSURE` (secure) |
| Policies and tag | `ent_book_policy`, `ent_mask_tax_id`, `ent_mask_account_no`, `ent_mask_email`, `ent_band_net_worth`, `ent_mask_sensitive`, `ent_min_10_clients`, tag `CLIENT_SENSITIVITY` |
| Roles | `ENT_ADVISOR_01`–`06`, `ENT_BRANCH_MGR_EAST` / `CENTRAL` / `WEST`, `ENT_COMPLIANCE`, `ENT_RESEARCH_PARTNER` |

## Customize with Cortex Code

[Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code) can adapt this guide to your own data. Open the repo folder in Cortex Code and try prompts like:

- "Map my client, account and holdings tables to this guide, propose the entitlements mapping from my advisor-to-client relationships, and show me the policies before applying anything."
- "Switch the row access policy from role-based entitlements to CURRENT_USER(), so each advisor's Snowflake user maps to their book, and show how to onboard a new advisor."
- "Change the research partner's minimum group size from 10 to 25 and show which grouped queries now fold into the remainder row."

Ask it to review the plan with you before it creates or changes any objects in your account.

## Repository layout

```
LICENSE                       Apache License 2.0
vendor/prism/                 Prism.js (MIT), served locally
index.html                    Single-page guide
styles.css                    Styling (Snowflake palette)
script.js                     Loads SQL steps, Prism highlighting, copy buttons, results tables
sql/client_entitlements.sql   Full demo script (split into steps by "-- [step:<id>]" markers)
data/sample_results.json      Results captured from a real run
```

To preview locally: `python3 -m http.server 8000`

## License

Licensed under the [Apache License, Version 2.0](LICENSE). Prism.js, used for syntax highlighting, is bundled in `vendor/prism/` under its own MIT license, so the pages make no third-party requests.

## Disclaimer

All clients, advisors, accounts and holdings are synthetic. Names are generated, emails use the reserved `@example.com` domain, tax IDs start with 9 (a range never issued as Social Security numbers), phone numbers use the fictional 555-01xx range, and tickers are fictional. This guide is not compliance advice. The repository contains no credentials, account identifiers or connection details.
