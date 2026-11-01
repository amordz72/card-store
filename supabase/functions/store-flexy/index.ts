// card-store → Flexy Core bridge.
//
// The browser never sees the Flexy key: this function reads it from the Edge
// secret FLEXY_CARD_STORE_KEY and calls flexy-api server-side.
//
// Owner (store admin, checked with public.store_admin_is_admin under the caller's session):
//   GET  /store-flexy/capabilities → flexy-api GET  /v1/capabilities
//   POST /store-flexy/validate     → flexy-api POST /v1/validate
// Shop (customer session token in the body; the database checks it):
//   POST /store-flexy/shop/send    → ask flexy-api POST /v1/availability («غير متاح» = nothing taken),
//                                    then take the charge, send to flexy-api POST /v1/operations
//   POST /store-flexy/shop/refresh → follow up this shop's open requests
//   POST /store-flexy/shop/offers  → the offers a number can take (Flexy Core: line group, no money)
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
// A request the core still has not decided after this long goes to the owner's review (he decides:
// «تم الإرسال» or «فشل، أرجع المبلغ»). The core itself sends its accepted ones to review after 2 hours.
const UNDECIDED_REVIEW_MS = 3 * 60 * 60_000;
const OP_630 = "mobilis.arsselli.ordinary.630";
const OP_OFFER = "mobilis.sama.offer.665";
// Ordinary credit on the other operators (owner 2026-10-29, v1.39): the key follows the number's prefix.
const OP_760 = "djezzy.flexy.ordinary.760";
const OP_590 = "ooredoo.flexy.ordinary.590";
// The shops' Ooredoo offers (owner 2026-10-30, v1.55): bought by the catalog name, at the price Flexy Core names
const OP_OFFER_585 = "ooredoo.flexy.offer.585";
// … and Djezzy's (v1.56), the same way
const OP_OFFER_760 = "djezzy.flexy.offer.760";
const offerKey = (phone: string) => (phone.startsWith("05") ? OP_OFFER_585 : phone.startsWith("07") ? OP_OFFER_760 : OP_OFFER);

// The shop's switches: v4 (v1.55) names its Ooredoo offers; before it, v1 (Mobilis offers only)
async function flexyStatusOf(token: string): Promise<Record<string, unknown> | null> {
  for (const fn of ["store_flexy_status_v4", "store_flexy_status"]) {
    const st = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { apikey: SUPABASE_ANON_KEY, "content-type": "application/json" },
      body: JSON.stringify({ p_token: token }),
    });
    const row = (await st.json().catch(() => null))?.[0];
    if (st.ok && row) return row;
    if (st.status !== 404) return null;
  }
  return null;
}

// An Ooredoo or Djezzy offer's price is not in its name: the one Flexy Core shows for this number now (its kept menu)
async function corePrice(phone: string, label: string): Promise<number | null> {
  try {
    const res = await fetch(`${FLEXY_API}/offers/lookup`, {
      method: "POST",
      headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ phone }),
      signal: AbortSignal.timeout(15_000),
    });
    const b = await res.json().catch(() => ({}));
    const o = (Array.isArray(b?.offers) ? b.offers : []).find((x: { label?: string }) => x.label === label);
    return o && Number.isFinite(Number(o.amount)) ? Number(o.amount) : null;
  } catch {
    return null;
  }
}
function creditKey(phone: string): string {
  if (phone.startsWith("07")) return OP_760;
  if (phone.startsWith("05")) return OP_590;
  return OP_630;
}

// Before any charge (owner 2026-10-29): is there a SIM the core could send on, with enough balance?
// «غير متاح» = nothing taken, nothing written for the shop; the core tells the owner. The core not
// answering never blocks a sale (the send itself still decides, and refunds, as before).
async function coreAvailable(operationKey: string, amount: number, offer: string | null = null): Promise<boolean> {
  if (!offer && (!Number.isFinite(amount) || amount <= 0)) return true;
  try {
    const res = await fetch(`${FLEXY_API}/availability`, {
      method: "POST",
      headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
      // An offer is asked by its name: the core checks its real routes (Sama Mix 50 = Arsselli only).
      body: JSON.stringify(offer ? { operation_key: operationKey, offer } : { operation_key: operationKey, amount }),
      signal: AbortSignal.timeout(8_000),
    });
    if (!res.ok) return true;
    const body = await res.json().catch(() => null);
    return body?.available !== false;
  } catch {
    return true;
  }
}

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

type Job = {
  job_id: number; core_key: string; status: string; phone: string; amount: number; created_at: string;
  kind: string; offer_label: string | null;
};

// Send (or resend: same key, same request) to the core and record what it said.
// Returns the shop status, or null when the core could not be reached (the job stays as it is).
async function sendToCore(job: Job): Promise<string | null> {
  let res: Response;
  try {
    res = await fetch(`${FLEXY_API}/operations`, {
      method: "POST",
      headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({
        // Sent again as what it is: an offer is never re-sent as ordinary credit.
        ...(job.kind === "offer"
          ? { operation_key: offerKey(job.phone), offer: job.offer_label, amount: job.amount }
          : { operation_key: creditKey(job.phone), amount: job.amount }),
        idempotency_key: job.core_key,
        phone: job.phone,
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
  // 409 (SOURCE_BUSY: waiting for a SIM, STATION_NOT_READY…) keeps the job queued: asked again on the next refresh.
  else if (res.status >= 400 && res.status < 500 && res.status !== 409) status = "not_sent";
  else return null;
  await mark(job, status, body?.operation?.network_reply ?? null);
  return status;
}

async function mark(job: Job, status: string, reply: string | null): Promise<void> {
  const res = await serviceRpc("store_flexy_mark", { p_job_id: job.job_id, p_status: status, p_reply: reply });
  // Never silent: a refused mark keeps the shop's money held and its number busy.
  if (!res.ok) console.error("store-flexy mark", job.job_id, status, res.status, await res.text().catch(() => ""));
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
      await mark(job, status, op.network_reply ?? null);
    } else if (status === "sent" && Date.now() - Date.parse(job.created_at) > UNDECIDED_REVIEW_MS) {
      await mark(job, "review", op.network_reply ?? null);
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
    // An offer's price is the number its name ends with (the database checks it again).
    const kind = body.kind === "offer" ? "offer" : "630";
    const label = kind === "offer" ? String(body.offer ?? "").trim() : null;
    const phone = String(body.phone ?? "");
    const ooredooOffer = kind === "offer" && /^0[57]/.test(phone.replace(/\D/g, ""));
    // Mobilis: the number its name ends with; Ooredoo / Djezzy: the price Flexy Core shows for it (Flexy Core checks it again)
    const amount = ooredooOffer ? (await corePrice(phone.replace(/\D/g, ""), label ?? "")) ?? NaN
      : kind === "offer" ? Number(/([0-9]+)$/.exec(label ?? "")?.[1] ?? NaN) : Number(body.amount);
    if (ooredooOffer && !Number.isFinite(amount)) return json(req, 422, { ok: false, error: "FLEXY_OFFER_INVALID" });
    if (!ooredooOffer && !(await coreAvailable(kind === "offer" ? OP_OFFER : creditKey(phone), amount, label))) {
      return json(req, 422, { ok: false, error: "FLEXY_UNAVAILABLE" });
    }
    const created = await serviceRpc("store_flexy_create_v3", {
      p_token: token, p_kind: kind, p_phone: String(body.phone ?? ""), p_amount: amount,
      p_offer_code: null, p_offer_label: label, p_request_id: body.request_id ?? null,
    });
    const rows = await created.json().catch(() => null);
    // The database names the refusal (FLEXY_CLOSED, FLEXY_PHONE_BUSY, INSUFFICIENT_BALANCE...).
    if (!created.ok || !Array.isArray(rows) || !rows[0]) {
      return json(req, 422, { ok: false, error: String(rows?.message ?? "FLEXY_REFUSED") });
    }
    const job = { ...rows[0], kind, offer_label: label } as Job;
    const status = job.status === "queued" ? (await sendToCore(job)) ?? "queued" : job.status;
    return json(req, 200, { ok: true, job_id: job.job_id, status });
  }

  if (route === "/shop/refresh") {
    const open = await serviceRpc("store_flexy_open_jobs_v2", { p_customer_token: token });
    const jobs = await open.json().catch(() => null);
    if (!open.ok || !Array.isArray(jobs)) return json(req, 401, { ok: false, error: "INVALID_SESSION" });
    await Promise.all((jobs as Job[]).map(followUp));
    return json(req, 200, { ok: true, open: jobs.length });
  }

  // «أوتوميكس» (owner 2026-10-29): which quick offers a SIM can take now, before the line is known.
  // {offers: up to 4 names} → {available: {name: bool}}. Unavailable = the owner is told by the core.
  if (route === "/shop/available") {
    const s = await flexyStatusOf(token);
    if (!s) return json(req, 401, { ok: false, error: "INVALID_SESSION" });
    if (!s.enabled || !s.open || !s.offers) return json(req, 403, { ok: false, error: "FLEXY_CLOSED" });
    const names = (Array.isArray(body.offers) ? body.offers : []).filter((x: unknown) => typeof x === "string").slice(0, 4) as string[];
    const answers = await Promise.all(names.map((n) => coreAvailable(OP_OFFER, NaN, n)));
    return json(req, 200, { ok: true, available: Object.fromEntries(names.map((n, i) => [n, answers[i]])) });
  }

  // Offers for a number: Flexy Core keeps the line's group (or discovers it, no money) and
  // returns the group's offers a connected SIM can run. The shop polls while it is discovering.
  if (route === "/shop/offers") {
    // store_flexy_status is the shop's own read (anon), not a service function.
    const s = await flexyStatusOf(token);
    if (!s) return json(req, 401, { ok: false, error: "INVALID_SESSION" });
    if (!s.enabled) return json(req, 403, { ok: false, error: "FLEXY_NOT_ENABLED" });
    // An Ooredoo or Djezzy number: its offers have their own switch for this shop (v1.55, v1.56)
    const prefix = String(body.phone ?? "").replace(/\D/g, "").replace(/^213/, "0").slice(0, 2);
    const allowed = prefix === "05" ? s.offers_ooredoo : prefix === "07" ? s.offers_djezzy : s.offers;
    if (!s.open || !allowed) return json(req, 403, { ok: false, error: "FLEXY_CLOSED" });
    try {
      const res = await fetch(`${FLEXY_API}/offers/lookup`, {
        method: "POST",
        headers: { authorization: `Bearer ${FLEXY_KEY}`, "content-type": "application/json" },
        // «دُفع» (owner 2026-11-01): the shop says the number's SABBAQLI debt was paid elsewhere
        body: JSON.stringify({ phone: String(body.phone ?? ""), ...(body.debt_paid === true ? { debt_paid: true } : {}) }),
        signal: AbortSignal.timeout(25_000),
      });
      const b = await res.json().catch(() => ({}));
      // An Ooredoo number that owes a SABBAQLI loan (Flexy Core 0145): no offer until it is paid in full
      if (b?.status === "debt") return json(req, 200, { ok: true, status: "debt", debt: Number(b.debt) || 0, group: null, offers: [] });
      // A paid offer waits for a Sama SIM: the discovery comes after it (Flexy Core, owner 2026-10-27); the shop keeps asking.
      if (res.status === 409 && b?.error === "DISCOVERY_DEFERRED") return json(req, 200, { ok: true, status: "discovering", group: null, offers: [] });
      if (!res.ok) return json(req, 422, { ok: false, error: String(b?.error ?? "FLEXY_REFUSED") });
      // Only what a shop needs: the status, the group and the offers it can buy now.
      const offers = Array.isArray(b.offers)
        ? b.offers.filter((o: { available?: boolean }) => o.available)
          .map((o: { label: string; family: string; amount: number }) => ({ label: o.label, family: o.family, amount: o.amount }))
        : [];
      return json(req, 200, { ok: true, status: String(b.status ?? "unknown"), group: b.group ?? null, offers });
    } catch {
      return json(req, 502, { ok: false, error: "FLEXY_UNAVAILABLE" });
    }
  }

  return json(req, 404, { ok: false, error: "ROUTE_NOT_FOUND" });
}

async function sweep(req: Request): Promise<Response> {
  if (!SERVICE_KEY || !FLEXY_KEY) return json(req, 500, { ok: false, error: "FLEXY_NOT_CONFIGURED" });
  const body = await req.json().catch(() => null);
  const open = await serviceRpc("store_flexy_sweep_jobs_v2", { p_secret: typeof body?.secret === "string" ? body.secret : "" });
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
