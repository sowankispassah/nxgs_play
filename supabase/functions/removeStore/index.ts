import { asString, corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    if (!id)
      throw new Error("invalid_store");

    const supabase = supabaseAdmin();
    const { count: priceCount, error: priceError } = await supabase
      .from("store_time_plan_prices")
      .select("id", { count: "exact", head: true })
      .eq("store_id", id);
    if (priceError)
      throw priceError;

    const { count: paymentCount, error: paymentError } = await supabase
      .from("payments")
      .select("id", { count: "exact", head: true })
      .eq("store_id", id);
    if (paymentError)
      throw paymentError;

    const { count: sessionCount, error: sessionError } = await supabase
      .from("play_sessions")
      .select("id", { count: "exact", head: true })
      .eq("store_id", id);
    if (sessionError)
      throw sessionError;

    if ((priceCount ?? 0) > 0 || (paymentCount ?? 0) > 0 || (sessionCount ?? 0) > 0)
      return json({ error: true, message: "store_not_safe_to_remove" }, 409);

    const { error } = await supabase.from("stores").delete().eq("id", id);
    if (error)
      throw error;

    return json({ ok: true });
  } catch (error) {
    return functionError(error);
  }
});
