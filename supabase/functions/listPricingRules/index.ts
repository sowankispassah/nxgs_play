import { corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("store_time_plan_prices")
      .select("id, store_id, time_plan_id, amount_paise, currency, active, stores(name), time_plans(name, duration_minutes, sort_order)")
      .order("store_id");
    if (error)
      throw error;

    return json({
      pricing: (data ?? []).map((row) => {
        const store = Array.isArray(row.stores) ? row.stores[0] : row.stores;
        const plan = Array.isArray(row.time_plans) ? row.time_plans[0] : row.time_plans;
        return {
          id: row.id,
          store_id: row.store_id,
          time_plan_id: row.time_plan_id,
          amount_paise: row.amount_paise,
          currency: row.currency,
          active: row.active,
          store_name: store?.name ?? "",
          time_plan_name: plan?.name ?? "",
          duration_minutes: plan?.duration_minutes ?? 0,
          sort_order: plan?.sort_order ?? 0,
        };
      }),
    });
  } catch (error) {
    return functionError(error);
  }
});
