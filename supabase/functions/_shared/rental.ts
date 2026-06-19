import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (req.method === "OPTIONS")
    return {};
  try {
    return await req.json();
  } catch {
    return {};
  }
}

export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function supabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole)
    throw new Error("missing_supabase_service_configuration");
  return createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function tokenSecret(): string {
  const configured = Deno.env.get("CONTROLLER_ADMIN_TOKEN_SECRET");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const secret = configured || serviceRole;
  if (!secret)
    throw new Error("missing_admin_token_secret");
  return secret;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes)
    binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function hmac(data: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(tokenSecret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return base64UrlEncode(new Uint8Array(digest));
}

export async function createControllerAdminToken(): Promise<{ token: string; expires_at: string }> {
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000);
  const payload = base64UrlEncode(new TextEncoder().encode(JSON.stringify({
    scope: "controller_admin",
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(expiresAt.getTime() / 1000),
  })));
  const signature = await hmac(payload);
  return { token: `${payload}.${signature}`, expires_at: expiresAt.toISOString() };
}

export async function verifyControllerAdminToken(token: string): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 2)
    return false;

  const expected = await hmac(parts[0]);
  if (expected !== parts[1])
    return false;

  try {
    const payloadText = new TextDecoder().decode(base64UrlDecode(parts[0]));
    const payload = JSON.parse(payloadText);
    return payload?.scope === "controller_admin"
      && typeof payload?.exp === "number"
      && payload.exp > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

export async function requireControllerAdmin(body: Record<string, unknown>) {
  const token = asString(body.admin_token);
  if (!token || !(await verifyControllerAdminToken(token)))
    throw new Error("unauthorized_controller_admin");
}

export function normalizeConsoleIdentifier(value: unknown): string {
  return asString(value).toLowerCase().replace(/[^a-f0-9]/g, "");
}

export async function syncDiscoveredConsoles(
  supabase: ReturnType<typeof supabaseAdmin>,
  discoveredValue: unknown,
) {
  const discovered = Array.isArray(discoveredValue) ? discoveredValue : [];
  const discoveredByMac = new Map<string, Record<string, unknown>>();

  for (const item of discovered) {
    if (!item || typeof item !== "object")
      continue;
    const row = item as Record<string, unknown>;
    const identifier = normalizeConsoleIdentifier(row.console_identifier || row.mac_address || row.mac);
    if (!identifier)
      continue;
    discoveredByMac.set(identifier, row);
  }

  const { data: savedConsoles, error: savedError } = await supabase
    .from("consoles")
    .select("id, mac_address, state, disabled_at");
  if (savedError)
    throw savedError;

  const seenIds: string[] = [];
  for (const saved of savedConsoles ?? []) {
    const identifier = normalizeConsoleIdentifier(saved.mac_address);
    const discoveredConsole = discoveredByMac.get(identifier);
    if (!discoveredConsole)
      continue;

    seenIds.push(saved.id);
    const tailscaleIp = asString(discoveredConsole.tailscale_ip || discoveredConsole.ip_address || discoveredConsole.address);
    const updates: Record<string, unknown> = { last_seen_at: new Date().toISOString() };
    if (tailscaleIp)
      updates.tailscale_ip = tailscaleIp;
    if (saved.state === "offline" && !saved.disabled_at)
      updates.state = "available";

    const { error } = await supabase
      .from("consoles")
      .update(updates)
      .eq("id", saved.id);
    if (error)
      throw error;
  }

  return { discovered_count: discoveredByMac.size, matched_count: seenIds.length };
}

export async function activePricing() {
  const supabase = supabaseAdmin();
  const { data: stores, error: storesError } = await supabase
    .from("stores")
    .select("id, name, location, phone, email, notes, active")
    .eq("active", true)
    .order("name");
  if (storesError)
    throw storesError;

  const { data: timePlans, error: timePlansError } = await supabase
    .from("time_plans")
    .select("id, name, duration_minutes, active, sort_order")
    .eq("active", true)
    .order("sort_order")
    .order("duration_minutes");
  if (timePlansError)
    throw timePlansError;

  const { data: pricing, error: pricingError } = await supabase
    .from("store_time_plan_prices")
    .select("id, store_id, time_plan_id, amount_paise, currency, active")
    .eq("active", true);
  if (pricingError)
    throw pricingError;

  return {
    stores: stores ?? [],
    time_plans: timePlans ?? [],
    pricing: pricing ?? [],
    test_payment_bypass: await appSettingEnabled(supabase, "test_payment_bypass"),
  };
}

export async function appSettingEnabled(supabase: ReturnType<typeof supabaseAdmin>, key: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  if (error)
    throw error;

  const value = String(data?.value ?? "").trim().toLowerCase();
  return ["1", "true", "yes", "enabled", "on"].includes(value);
}

export async function pricingForSelection(storeId: string, timePlanId: string) {
  const supabase = supabaseAdmin();
  const { data, error } = await supabase
    .from("store_time_plan_prices")
    .select("id, store_id, time_plan_id, amount_paise, currency, active, time_plans(id, name, duration_minutes, active), stores(id, name, active)")
    .eq("active", true)
    .eq("store_id", storeId)
    .eq("time_plan_id", timePlanId)
    .single();
  if (error || !data)
    throw new Error("pricing_not_found");
  const timePlan = Array.isArray(data.time_plans) ? data.time_plans[0] : data.time_plans;
  const store = Array.isArray(data.stores) ? data.stores[0] : data.stores;
  if (!timePlan?.active || !store?.active)
    throw new Error("pricing_not_found");
  if (!timePlan.duration_minutes || timePlan.duration_minutes <= 0)
    throw new Error("invalid_duration");
  return data;
}

function razorpayAuthHeader(): string {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!keyId || !keySecret)
    throw new Error("missing_razorpay_configuration");
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

export async function createRazorpayOrder(args: {
  amount: number;
  currency: string;
  receipt: string;
  notes: Record<string, string>;
}) {
  const response = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      Authorization: razorpayAuthHeader(),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: args.amount,
      currency: args.currency,
      receipt: args.receipt,
      notes: args.notes,
    }),
  });

  const data = await response.json();
  if (!response.ok)
    throw new Error(data?.error?.description ?? "razorpay_order_failed");
  return data;
}

export async function fetchRazorpayPayment(paymentId: string) {
  const response = await fetch(`https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`, {
    headers: { Authorization: razorpayAuthHeader() },
  });
  const data = await response.json();
  if (!response.ok)
    throw new Error(data?.error?.description ?? "razorpay_payment_lookup_failed");
  return data;
}

export async function verifyRazorpaySignature(orderId: string, paymentId: string, signature: string): Promise<boolean> {
  const secret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!secret)
    throw new Error("missing_razorpay_configuration");

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(`${orderId}|${paymentId}`));
  const expected = Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return expected === signature;
}

export function functionError(error: unknown, fallback = "request_failed"): Response {
  const message = error instanceof Error ? error.message : fallback;
  const status =
    message.includes("unauthorized") ? 401 :
    message.includes("not_found") ? 404 :
    message.includes("invalid") ? 400 :
    message.includes("active_customer") || message.includes("not_available_for_manual_lock") ? 409 :
    message.includes("expired") ? 409 :
    500;
  return json({ error: true, message }, status);
}
