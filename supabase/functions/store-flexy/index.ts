// card-store → Flexy Core bridge.
//
// The browser never sees the Flexy key: this function reads it from the Edge
// secret FLEXY_CARD_STORE_KEY and calls flexy-api server-side.
//
// Owner (store admin, checked with public.store_admin_is_admin under the caller's session):
//   GET  /store-flexy/capabilities → flexy-api GET  /v1/capabilities
//   POST /store-flexy/validate     → flexy-api POST /v1/validate
// Shop (customer session token in the body; the database checks it):
//   POST /store-flexy/shop/send    → take the charge, send to flexy-api POST /v1/operations
//   POST /store-flexy/shop/refresh → follow up this shop's open requests
// Database tick (pg_cron, only while a request is open; body {secret} from Vault, checked by the database):
//   POST /store-flexy/internal/sweep → follow up every shop's open requests

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FLEXY_KEY = Deno.env.get("FLEXY_CARD_STORE_KEY") ?? "";
const FLEXY_API = `${SUPABASE_URL}/functions/v1/flexy-api/v1`;

// Built in, so a wrong setting can never lock out the official site. Other sites (e.g. a Cloudflare copy)
// are the owner setting «مواقع إضافية مسموحة» (store.settings.extra_origins, v1.32), read at most once a
// minute. Remove a site there BEFORE deleting it: a deleted name may be taken by someone else.
const BUILT_IN_ORIGINS = ["https://amordz72.github.io", "http://localhost:9000"];
const ORIGINS_TTL_MS = 60_000;
let extraOrigins: string[] = [];
let extraOriginsAt = 0;

async function allowedOrigins(): Promise<Set<string>> {
  if (Date.now() - extraOriginsAt > ORIGINS_TTL_MS) {
    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/store_site_links`, {
        method: "POST",
        headers: { apikey: SUPABASE_ANON_KEY, "content-type": "application/json" },
        body: "{}",
      });
      if (res.ok) {
        const rows = await res.json();
        extraOrigins = Array.isArray(rows?.[0]?.extra_origins) ? rows[0].extra_origins : [];
        extraOriginsAt = Date.now();
      }
    } catch (err) {
      // Keep the last known list; the built-in sites always work.
      console.error("store-flexy origins", err instanceof Error ? err.message : err);
    }
  }
  return new Set([...BUILT_IN_ORIGINS, ...extraOrigins]);
}

async function cors(req: Request): Promise<Record<string, string>> {
  const origin = req.headers.get("origin") ?? "";
  if (!(await allowedOrigins()).has(origin)) return {};
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    vary: "origin",
  };
}

const json = async (req: Request, status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...(await cors(req)) },
  });

async function isStoreAdmin(authorization: string): Promise<boolean> {
  if (!authorization.startsWith("Bearer ")) return false;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/store_admin_is_admin`, {
    method: "POST",
    headers: { apikey: SUPABASE_ANON_KEY, authorization, "content-type": "application/json" },
    body: "{}",
  });
  return res.ok && (await res.json()) === true;
}

// ---------------------------------------------------------------------------------------------
// Shops (v1.33). The shop's phone makes ONE request; the charge, the call to Flexy Core and the
// result are all done here, so a weak connection on the phone can neither lose money nor send
// twice. Every request to the core carries expires_at: after it the core refuses for certain,
// so a request that arrives late is never sent, and the money can be returned safely.
// ---------------------------------------------------------------------------------------------
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CORE_EXPIRES_MS = 120_000;
const OP_630 = "mobilis.arsselli.ordinary.630";

async function serviceRpc(fn: string, args: Record<string, unknown>): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
}

// Flexy Core status → shop job status. Accepted is still running for the shop until the SMS settles it.
function shopStatus(core: string): "sent" | "success" | "failed" | "review" | "not_sent" {
  if (core === "success") return "success";
  if (core === "failed" || core === "rejected") return "failed";
  if (core === "not_sent") return "not_sent";
  if (core === "review") return "review";
  return "sent";
}

type Job = { job_id: number; core_key: string; status: string; phone: string; amount: number; created_at: string };

// Send (or resend: same key, same request) to the core and record what it said.
// Returns the shop status, or null when the core could not be reached (the job stays as it is).
async function sendToCore(job: Job): Promise<string | null> {
  let res: Response;
  try {
    res = await fetch(`${FLEXY_API}/operations`, {
      method: "POST",
      headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({
        operation_key: OP_630,
        idempotency_key: job.core_key,
        phone: job.phone,
        amount: job.amount,
        expires_at: new Date(Date.parse(job.created_at) + CORE_EXPIRES_MS).toISOString(),
      }),
      signal: AbortSignal.timeout(25_000),
    });
  } catch {
    return null;
  }
  const body = await res.json().catch(() => ({}));
  let status: string;
  if (res.ok && body?.operation?.status) status = shopStatus(String(body.operation.status));
  // A 4xx answer means the core created nothing for this key (validation, closed, expired, no route).
  else if (res.status >= 400 && res.status < 500 && res.status !== 409) status = "not_sent";
  else return null;
  await serviceRpc("store_flexy_mark", { p_job_id: job.job_id, p_status: status, p_reply: body?.operation?.network_reply ?? null });
  return status;
}

async function followUp(job: Job): Promise<void> {
  if (job.status === "queued") {
    await sendToCore(job);
    return;
  }
  try {
    const res = await fetch(`${FLEXY_API}/operations/${encodeURIComponent(job.core_key)}`, {
      headers: { authorization: `Bearer ${FLEXY_KEY}` },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return;
    const op = (await res.json())?.operation;
    if (!op?.status) return;
    const status = shopStatus(String(op.status));
    if (status !== job.status) {
      await serviceRpc("store_flexy_mark", { p_job_id: job.job_id, p_status: status, p_reply: op.network_reply ?? null });
    }
  } catch {
    // Next refresh tries again.
  }
}

async function handleShop(req: Request, route: string): Promise<Response> {
  if (!SERVICE_KEY || !FLEXY_KEY) return json(req, 500, { ok: false, error: "FLEXY_NOT_CONFIGURED" });
  const body = await req.json().catch(() => null);
  const token = typeof body?.token === "string" ? body.token : "";
  if (!token) return json(req, 401, { ok: false, error: "INVALID_SESSION" });

  if (route === "/shop/send") {
    const created = await serviceRpc("store_flexy_create", {
      p_token: token, p_kind: "630", p_phone: String(body.phone ?? ""), p_amount: Number(body.amount),
      p_offer_code: null, p_offer_label: null, p_request_id: body.request_id ?? null,
    });
    const rows = await created.json().catch(() => null);
    // The database names the refusal (FLEXY_CLOSED, FLEXY_PHONE_BUSY, INSUFFICIENT_BALANCE...).
    if (!created.ok || !Array.isArray(rows) || !rows[0]) {
      return json(req, 422, { ok: false, error: String(rows?.message ?? "FLEXY_REFUSED") });
    }
    const job = rows[0] as Job;
    const status = job.status === "queued" ? (await sendToCore(job)) ?? "queued" : job.status;
    return json(req, 200, { ok: true, job_id: job.job_id, status });
  }

  if (route === "/shop/refresh") {
    const open = await serviceRpc("store_flexy_open_jobs", { p_customer_token: token });
    const jobs = await open.json().catch(() => null);
    if (!open.ok || !Array.isArray(jobs)) return json(req, 401, { ok: false, error: "INVALID_SESSION" });
    await Promise.all((jobs as Job[]).map(followUp));
    return json(req, 200, { ok: true, open: jobs.length });
  }

  return json(req, 404, { ok: false, error: "ROUTE_NOT_FOUND" });
}

async function sweep(req: Request): Promise<Response> {
  if (!SERVICE_KEY || !FLEXY_KEY) return json(req, 500, { ok: false, error: "FLEXY_NOT_CONFIGURED" });
  const body = await req.json().catch(() => null);
  const open = await serviceRpc("store_flexy_sweep_jobs", { p_secret: typeof body?.secret === "string" ? body.secret : "" });
  const jobs = await open.json().catch(() => null);
  if (!open.ok || !Array.isArray(jobs)) return json(req, 403, { ok: false, error: "NOT_ALLOWED" });
  await Promise.all((jobs as Job[]).map(followUp));
  return json(req, 200, { ok: true, open: jobs.length });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: await cors(req) });

  try {
    const route = new URL(req.url).pathname.replace(/^.*\/store-flexy/, "");
    if (req.method === "POST" && route.startsWith("/shop/")) return await handleShop(req, route);
    if (req.method === "POST" && route === "/internal/sweep") return await sweep(req);

    if (!(await isStoreAdmin(req.headers.get("authorization") ?? ""))) return json(req, 403, { ok: false, error: "NOT_ADMIN" });
    if (!FLEXY_KEY) return json(req, 500, { ok: false, error: "FLEXY_KEY_MISSING" });

    let upstream: Response;
    if (req.method === "GET" && route === "/capabilities") {
      upstream = await fetch(`${FLEXY_API}/capabilities`, { headers: { authorization: `Bearer ${FLEXY_KEY}` } });
    } else if (req.method === "POST" && route === "/validate") {
      upstream = await fetch(`${FLEXY_API}/validate`, {
        method: "POST",
        headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
        body: await req.text(),
      });
    } else {
      return json(req, 404, { ok: false, error: "ROUTE_NOT_FOUND" });
    }
    // flexy-api answers JSON for every case; pass status and body through unchanged.
    return json(req, upstream.status, await upstream.json());
  } catch (err) {
    console.error("store-flexy", err instanceof Error ? err.message : err);
    return json(req, 502, { ok: false, error: "FLEXY_UNAVAILABLE" });
  }
});
