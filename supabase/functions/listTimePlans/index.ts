import { corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("time_plans")
      .select("*")
      .order("sort_order")
      .order("duration_minutes");
    if (error)
      throw error;

    return json({ time_plans: data ?? [] });
  } catch (error) {
    return functionError(error);
  }
});
