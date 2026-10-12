// Single source of truth for Cortex Code *bundled* skills used by this project.
// `npm run gen:skills` renders AGENTS.md, .snowflake/cortex/skills/acme-project/SKILL.md
// and coco-runner/skills.json from this file. Never hand-edit the generated files.

export interface BuildSkillRoute {
  task: string;
  skills: string[];
}

/** Tasks a developer performs on this project, mapped to bundled CoCo skills. */
export const BUILD_ROUTES: BuildSkillRoute[] = [
  { task: "Semantic view, Cortex Analyst, agent create/deploy/eval", skills: ["agent-studio"] },
  { task: "Any Snowflake SQL", skills: ["sql-author"] },
  { task: "Agent quality/debugging", skills: ["agent-optimization"] },
  { task: "App Runtime (Next.js) build/deploy/operate", skills: ["snowflake-apps", "sar-actions-desktop"] },
  { task: "SPCS image/service deploy", skills: ["deploy-to-spcs"] },
  { task: "Grants, roles, caller's rights", skills: ["data-governance", "access-troubleshooter"] },
  { task: "Streamlit generation (Studio)", skills: ["developing-with-streamlit-in-snowflake"] },
  { task: "Python / Snowpark in generated code", skills: ["snowpark-python"] },
  { task: "HTML reports (Studio)", skills: ["html-authoring", "snowflake-publish-report"] },
  { task: "Cost of agents/Studio usage", skills: ["cost-intelligence"] },
];

export interface StudioIntent {
  id: string;
  /** Case-insensitive regex source matched against the user prompt. */
  pattern: string;
  skills: string[];
  note?: string;
}

/** Studio (CoCo runner) intent routing. XLSX/PDF use the runner's Python libraries. */
export const STUDIO_INTENTS: StudioIntent[] = [
  { id: "sql", pattern: "\\b(sql|query|data|table|sales|orders|inventory|region)\\b", skills: ["sql-author"] },
  { id: "streamlit", pattern: "\\bstreamlit|dashboard app|data app\\b", skills: ["developing-with-streamlit-in-snowflake"] },
  { id: "html", pattern: "\\bhtml|web report\\b", skills: ["html-authoring"] },
  { id: "publish", pattern: "\\bpublish|share (the )?report\\b", skills: ["snowflake-publish-report"] },
  { id: "semantic", pattern: "\\bsemantic (view|model)|cortex analyst\\b", skills: ["agent-studio"] },
  { id: "snowpark", pattern: "\\bsnowpark|udf|stored procedure\\b", skills: ["snowpark-python"] },
  { id: "cost", pattern: "\\b(cost|credits|spend)\\b", skills: ["cost-intelligence"] },
  { id: "xlsx", pattern: "\\b(xlsx|excel|spreadsheet)\\b", skills: [], note: "openpyxl in the runner image" },
  { id: "pdf", pattern: "\\bpdf\\b", skills: [], note: "reportlab + matplotlib in the runner image" },
];

export const PROJECT_FACTS = {
  database: "ACME_ASSIST_DEMO",
  dataSchema: "ACME_ASSIST_DEMO.DATA",
  appSchema: "ACME_ASSIST_DEMO.APP",
  semanticView: "ACME_ASSIST_DEMO.DATA.ACME_SEMANTIC_VIEW",
  agent: "ACME_ASSIST_DEMO.DATA.ACME_ASSIST_AGENT",
  powerAgent: "ACME_ASSIST_DEMO.DATA.ACME_POWER_AGENT",
  warehouse: "ACME_ASSIST_WH",
  roles: ["ACME_DEMO_ROLE", "ACME_HISTORY_ROLE", "ACME_APP_ROLE", "ACME_STUDIO_ROLE"],
  historyTable: "ACME_ASSIST_DEMO.APP.CONVERSATIONS",
  brands: ["acme", "northwind"],
};

/** Returns bundled skills matched by a Studio prompt (deduplicated, stable order). */
export function matchStudioSkills(prompt: string): { skills: string[]; intents: string[] } {
  const skills: string[] = [];
  const intents: string[] = [];
  for (const i of STUDIO_INTENTS) {
    if (new RegExp(i.pattern, "i").test(prompt)) {
      intents.push(i.id);
      for (const s of i.skills) if (!skills.includes(s)) skills.push(s);
    }
  }
  return { skills, intents };
}
