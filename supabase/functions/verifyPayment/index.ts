import {
  corsHeaders,
  fetchRazorpayPayment,
  functionError,
  json,
  readBody,
  supabaseAdmin,
  verifyRazorpaySignature,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    const paymentId = String(body.payment_id ?? "");
    const razorpayPaymentId = String(body.razorpay_payment_id ?? "");
    const razorpayOrderId = String(body.razorpay_order_id ?? "");
    const razorpaySignature = String(body.razorpay_signature ?? "");
    if (!paymentId || !razorpayPaymentId || !razorpayOrderId || !razorpaySignature)
      return json({ error: true, message: "invalid_payment" }, 400);

    const supabase = supabaseAdmin();
    const { data: payment, error: paymentError } = await supabase
      .from("payments")
      .select("*")
      .eq("id", paymentId)
      .eq("razorpay_order_id", razorpayOrderId)
      .eq("status", "order_created")
      .single();
    if (paymentError || !payment)
      throw new Error("invalid_payment");

    const validSignature = await verifyRazorpaySignature(razorpayOrderId, razorpayPaymentId, razorpaySignature);
    if (!validSignature)
      return json({ error: true, message: "invalid_payment_signature" }, 400);

    const razorpayPayment = await fetchRazorpayPayment(razorpayPaymentId);
    if (razorpayPayment.order_id !== razorpayOrderId || Number(razorpayPayment.amount) !== Number(payment.amount_paise))
      return json({ error: true, message: "payment_mismatch" }, 400);
    if (razorpayPayment.status !== "captured")
      return json({ error: true, message: "payment_not_captured" }, 402);

    const rpcName = payment.kind === "extension" ? "confirm_extension_payment" : "confirm_initial_payment";
    const { data, error } = await supabase.rpc(rpcName, {
      p_payment_id: payment.id,
      p_razorpay_payment_id: razorpayPaymentId,
      p_razorpay_signature: razorpaySignature,
    });
    if (error)
      throw error;
    const row = Array.isArray(data) ? data[0] : null;
    if (!row)
      throw new Error("payment_confirm_failed");

    return json({
      payment: row.payment,
      session: row.session,
      console: row.console,
    });
  } catch (error) {
    return functionError(error);
  }
});
