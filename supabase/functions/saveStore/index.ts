import { asString, corsHeaders, functionError, json, readBody, requireControllerAdmin, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    const name = asString(body.name);
    if (!name)
      throw new Error("invalid_store");

    const store = {
      name,
      location: asString(body.location),
      phone: asString(body.phone),
      email: asString(body.email),
      notes: asString(body.notes),
      active: body.active !== false,
    };

    const supabase = supabaseAdmin();
    const query = id
      ? supabase.from("stores").update(store).eq("id", id)
      : supabase.from("stores").insert(store);
    const { data, error } = await query.select("*").single();
    if (error)
      throw error;

    return json({ store: data });
  } catch (error) {
    return functionError(error);
  }
});
