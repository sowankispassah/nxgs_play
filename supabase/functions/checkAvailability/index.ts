import { activePricing, corsHeaders, functionError, json, readBody, supabaseAdmin, syncDiscoveredConsoles } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });
  const body = await readBody(req);

  try {
    const supabase = supabaseAdmin();
    await syncDiscoveredConsoles(supabase, body.discovered);
    const { data, error } = await supabase.rpc("count_available_consoles");
    if (error)
      throw error;

    const availableCount = Number(data ?? 0);
    const catalog = await activePricing();
    return json({
      available: availableCount > 0,
      available_count: availableCount,
      ...catalog,
    });
  } catch (error) {
    return functionError(error);
  }
});
