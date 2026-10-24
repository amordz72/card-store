// card-store → Flexy Core bridge (read-only phase).
//
// The browser never sees the Flexy key: this function reads it from the Edge
// secret FLEXY_CARD_STORE_KEY and calls flexy-api server-side. Only store
// admins may call it for now (checked with public.store_admin_is_admin under
// the caller's own Supabase session). No money, no USSD, no write anywhere.
//
//   GET  /store-flexy/capabilities → flexy-api GET  /v1/capabilities
//   POST /store-flexy/validate     → flexy-api POST /v1/validate

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: await cors(req) });

  try {
    if (!(await isStoreAdmin(req.headers.get("authorization") ?? ""))) return json(req, 403, { ok: false, error: "NOT_ADMIN" });
    if (!FLEXY_KEY) return json(req, 500, { ok: false, error: "FLEXY_KEY_MISSING" });

    const route = new URL(req.url).pathname.replace(/^.*\/store-flexy/, "");
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
