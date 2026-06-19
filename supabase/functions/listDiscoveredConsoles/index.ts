import {
  asString,
  corsHeaders,
  functionError,
  json,
  normalizeConsoleIdentifier,
  readBody,
  requireControllerAdmin,
  supabaseAdmin,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const discovered = Array.isArray(body.discovered) ? body.discovered : [];
    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("consoles")
      .select("id, mac_address");
    if (error)
      throw error;

    const saved = new Set((data ?? [])
      .map((row) => normalizeConsoleIdentifier(row.mac_address))
      .filter(Boolean));

    const consoles = discovered
      .map((item) => item && typeof item === "object" ? item as Record<string, unknown> : {})
      .map((item) => ({
        console_identifier: normalizeConsoleIdentifier(item.console_identifier || item.mac_address || item.mac),
        detected_name: asString(item.detected_name || item.name),
        ip_address: asString(item.ip_address || item.address),
        tailscale_ip: asString(item.tailscale_ip || item.ip_address || item.address),
        state: asString(item.state),
        remote_play_target: asString(item.remote_play_target || item.target || "PS5").toUpperCase() === "PS4" ? "PS4" : "PS5",
        registered_host_nickname: asString(item.registered_host_nickname || item.detected_name || item.name),
      }))
      .filter((item) => item.console_identifier && !saved.has(item.console_identifier));

    return json({ consoles });
  } catch (error) {
    return functionError(error);
  }
});
