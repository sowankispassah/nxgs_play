import { asString, corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    if (!id)
      throw new Error("invalid_pricing");

    const supabase = supabaseAdmin();
    const { error } = await supabase
      .from("store_time_plan_prices")
      .delete()
      .eq("id", id);
    if (error)
      throw error;

    return json({ ok: true });
  } catch (error) {
    return functionError(error);
  }
});
