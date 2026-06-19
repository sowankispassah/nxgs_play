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

    const identifier = normalizeConsoleIdentifier(body.console_identifier || body.mac_address);
    const tailscaleIp = asString(body.tailscale_ip || body.ip_address);
    const name = asString(body.name || body.detected_name);
    if (!identifier || !tailscaleIp || !name)
      throw new Error("invalid_console");

    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("consoles")
      .insert({
        name,
        state: "available",
        tailscale_ip: tailscaleIp,
        mac_address: identifier,
        registered_host_nickname: asString(body.registered_host_nickname || body.detected_name || name),
        remote_play_target: asString(body.remote_play_target).toUpperCase() === "PS4" ? "PS4" : "PS5",
        console_pin: asString(body.console_pin),
        added_by: asString(body.added_by) || "controller_admin",
        last_seen_at: new Date().toISOString(),
      })
      .select("*")
      .single();
    if (error)
      throw error;

    return json({ console: data });
  } catch (error) {
    return functionError(error);
  }
});
