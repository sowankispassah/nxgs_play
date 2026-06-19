import { asString, corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    const storeId = asString(body.store_id);
    const timePlanId = asString(body.time_plan_id);
    const amountPaise = Math.round(Number(body.amount_paise));
    if (!storeId || !timePlanId || !Number.isFinite(amountPaise) || amountPaise <= 0)
      throw new Error("invalid_pricing");

    const pricing = {
      store_id: storeId,
      time_plan_id: timePlanId,
      amount_paise: amountPaise,
      currency: asString(body.currency) || "INR",
      active: body.active !== false,
    };

    const supabase = supabaseAdmin();
    const query = id
      ? supabase.from("store_time_plan_prices").update(pricing).eq("id", id)
      : supabase.from("store_time_plan_prices").upsert(pricing, { onConflict: "store_id,time_plan_id" });
    const { data, error } = await query.select("*").single();
    if (error)
      throw error;

    return json({ pricing: data });
  } catch (error) {
    return functionError(error);
  }
});
