// Single catch-all API route: a thin adapter over the shared framework-neutral handlers.
// The run registry lives on globalThis (server/runs.ts), so it survives module reloads.
import { dispatch } from "../../../acme/server/handlers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const handle = (req: Request) => dispatch(req);
export { handle as GET, handle as POST, handle as PUT, handle as DELETE };
