// ==============================================================================
// SUPABASE EDGE FUNCTION: admin-notifier
// Location: supabase/functions/admin-notifier/index.ts
// Runtime: Deno / Supabase Edge Functions
// Description: Securely dispatches email alerts to rootdeckdev01@gmail.com
//              when new issues are submitted or updated.
//              Protects all SMTP/API credentials on server-side.
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const ADMIN_EMAIL = "rootdeckdev01@gmail.com";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") || "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface NotificationPayload {
  type?: "new_issue" | "new_user" | "new_download";
  record?: {
    id?: number | string;
    project?: string;
    details?: string;
    user_id?: string;
    screenshot_url?: string | null;
    created_at?: string;
    email?: string;
    user_name?: string;
    user_email?: string;
    raw_user_meta_data?: {
      name?: string;
    };
  };
  user_name?: string;
  user_email?: string;
  project?: string;
  details?: string;
  screenshot_url?: string | null;
  created_at?: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload: NotificationPayload = await req.json();

    const projectName =
      payload.project ||
      payload.record?.project ||
      "RootDeck Platform";

    const issueDetails =
      payload.details ||
      payload.record?.details ||
      "No details provided.";

    const userName =
      payload.user_name ||
      payload.record?.user_name ||
      payload.record?.raw_user_meta_data?.name ||
      "Registered User";

    const userEmail =
      payload.user_email ||
      payload.record?.user_email ||
      payload.record?.email ||
      "Unknown Email";

    const screenshotUrl =
      payload.screenshot_url ||
      payload.record?.screenshot_url;

    const issueId = payload.record?.id || "N/A";
    const timestamp =
      payload.created_at ||
      payload.record?.created_at ||
      new Date().toISOString();

    const emailSubject = `[RootDeck Alert] New Issue Reported: [${projectName}]`;

    const emailHtml = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0b0f19; color: #f3f4f6; margin: 0; padding: 20px; }
          .container { max-width: 600px; margin: 0 auto; background: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 28px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
          .badge { display: inline-block; background: #00f2fe; color: #0b0f19; font-weight: 700; font-size: 11px; padding: 4px 10px; border-radius: 9999px; text-transform: uppercase; letter-spacing: 0.5px; }
          h2 { color: #00f2fe; margin-top: 14px; margin-bottom: 20px; font-size: 20px; }
          .info-table { width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 14px; }
          .info-table td { padding: 8px 0; border-bottom: 1px solid #1f2937; }
          .label { color: #9ca3af; width: 130px; }
          .value { color: #f3f4f6; font-weight: 600; }
          .value-accent { color: #00f2fe; font-weight: 600; }
          .details-box { background: #0b0f19; border: 1px solid #1f2937; border-left: 4px solid #00f2fe; border-radius: 6px; padding: 14px; margin: 18px 0; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; color: #e5e7eb; white-space: pre-wrap; word-break: break-word; line-height: 1.5; }
          .screenshot-box { margin-top: 16px; border: 1px solid #1f2937; border-radius: 8px; overflow: hidden; }
          .screenshot-box img { max-width: 100%; display: block; }
          .footer { margin-top: 24px; padding-top: 16px; border-top: 1px solid #1f2937; font-size: 12px; color: #6b7280; text-align: center; }
        </style>
      </head>
      <body>
        <div class="container">
          <span class="badge">RootDeck Issue Monitor</span>
          <h2>New Issue Submitted</h2>
          <table class="info-table">
            <tr>
              <td class="label">Project:</td>
              <td class="value">${projectName} (Issue #${issueId})</td>
            </tr>
            <tr>
              <td class="label">User Name:</td>
              <td class="value">${userName}</td>
            </tr>
            <tr>
              <td class="label">User Email:</td>
              <td class="value-accent">${userEmail}</td>
            </tr>
            <tr>
              <td class="label">Timestamp:</td>
              <td class="value">${new Date(timestamp).toLocaleString()}</td>
            </tr>
          </table>

          <div style="font-size: 13px; color: #9ca3af; margin-bottom: 6px;">Issue Details:</div>
          <div class="details-box">${issueDetails}</div>

          ${screenshotUrl ? `
            <div style="font-size: 13px; color: #9ca3af; margin-top: 16px; margin-bottom: 6px;">Attached Screenshot:</div>
            <div class="screenshot-box">
              <a href="${screenshotUrl}" target="_blank">
                <img src="${screenshotUrl}" alt="Issue Screenshot" />
              </a>
            </div>
          ` : ""}

          <div class="footer">
            <p style="margin: 0 0 6px 0;">To reply, update the <code style="color: #00f2fe;">admin_reply</code> field directly in the Supabase Table Editor or RootDeck Admin Portal.</p>
            <p style="margin: 0;">Automated alert from RootDeck Serverless Edge Runtime.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    // If Resend API Key is not set, log locally and return graceful response
    if (!RESEND_API_KEY) {
      console.warn("RESEND_API_KEY is not set. Logging email payload to server logs:");
      console.log({
        to: ADMIN_EMAIL,
        subject: emailSubject,
        userName,
        userEmail,
        projectName,
        issueDetails
      });

      return new Response(
        JSON.stringify({
          success: true,
          message: "Notification logged to server console (configure RESEND_API_KEY in Supabase secrets to dispatch live emails)",
          preview: {
            to: ADMIN_EMAIL,
            subject: emailSubject,
            user_name: userName,
            user_email: userEmail
          }
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Send email via Resend REST API
    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "RootDeck System <notifications@rootdeck.dev>",
        to: [ADMIN_EMAIL],
        subject: emailSubject,
        html: emailHtml,
      }),
    });

    const resendData = await resendResponse.json();

    return new Response(
      JSON.stringify({ success: true, resendData }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: any) {
    console.error("Admin notifier error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
