import { asString, corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    const name = asString(body.name);
    const durationMinutes = Number(body.duration_minutes);
    if (!name || !Number.isFinite(durationMinutes) || durationMinutes <= 0)
      throw new Error("invalid_time_plan");

    const timePlan = {
      name,
      duration_minutes: Math.round(durationMinutes),
      sort_order: Math.round(Number(body.sort_order ?? durationMinutes)),
      active: body.active !== false,
    };

    const supabase = supabaseAdmin();
    const query = id
      ? supabase.from("time_plans").update(timePlan).eq("id", id)
      : supabase.from("time_plans").insert(timePlan);
    const { data, error } = await query.select("*").single();
    if (error)
      throw error;

    return json({ time_plan: data });
  } catch (error) {
    return functionError(error);
  }
});
