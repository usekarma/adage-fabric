# Facts (Experimental)

This directory is a placeholder for **modular fact templates**.  
The idea is that instead of baking all fact definitions directly into each lane template, we can **mix and match reusable fact modules** here.

## Current state

- The lane template (`sql/templates/fabric_lane_template.sql`) still defines its own facts inline (e.g., `fact_events_minute`, `fact_latency_minute`).  
- This `facts/` directory currently contains only `fact_events_minute.sql.tmpl`, captured during design discussions. It is **not yet wired into the Makefiles**.  

## Future direction

- **Modularity:** define facts like `fact_events_minute`, `fact_latency_minute`, or domain-specific ones (`fact_order_failures`, `fact_jira_start_hour`) as separate templates here.  
- **Governance:** allow operators to enable/disable facts per lane by listing modules.  
- **Consistency:** all fact modules should include their writer materialized views into the global rollup tables (`*_all`).

## Next steps

1. Decide whether to move fact logic out of the lane template and into this directory.  
2. Update `sql/Makefile` to apply fact modules after creating each `parsed_*` table.  
3. Remove duplicate definitions from the lane template once fact modules are stable.

---

**TL;DR:**  
This directory is **experimental** and not yet used in bootstrap. Keep it around as a design sketch for modularity, but the system currently runs off the lane template alone.
