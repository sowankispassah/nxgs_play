import { corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const supabase = supabaseAdmin();
    const { data: stores, error } = await supabase
      .from("stores")
      .select("*")
      .order("name");
    if (error)
      throw error;

    const { data: pricing, error: pricingError } = await supabase
      .from("store_time_plan_prices")
      .select("store_id");
    if (pricingError)
      throw pricingError;

    const counts = new Map<string, number>();
    for (const row of pricing ?? [])
      counts.set(row.store_id, (counts.get(row.store_id) ?? 0) + 1);

    return json({
      stores: (stores ?? []).map((store) => ({
        ...store,
        pricing_count: counts.get(store.id) ?? 0,
      })),
    });
  } catch (error) {
    return functionError(error);
  }
});
