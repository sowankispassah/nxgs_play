import { activePricing, corsHeaders, functionError, json, readBody, supabaseAdmin, syncDiscoveredConsoles } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });
  const body = await readBody(req);

  try {
    const supabase = supabaseAdmin();
    await syncDiscoveredConsoles(supabase, body.discovered);
    await supabase.rpc("release_expired_reservations_sql");
    await supabase.rpc("release_expired_sessions_sql");

    const { data, error } = await supabase.rpc("reserve_available_console");
    if (error)
      throw error;
    const row = Array.isArray(data) ? data[0] : null;
    if (!row)
      return json({ error: true, message: "No console available" }, 409);

    const catalog = await activePricing();
    return json({
      reservation: row.reservation,
      console: row.console,
      ...catalog,
    });
  } catch (error) {
    return functionError(error);
  }
});
