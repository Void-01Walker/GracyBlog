// ================================================================
//  GracyBlog — notify-subscribers Edge Function
//
//  Triggered by gracyblog.html when a new post is published.
//  Fetches every active subscriber and sends them an email via Resend.
//
//  SETUP (one-time):
//  1. Install the Supabase CLI:  npm i -g supabase
//  2. Link your project:         supabase login
//                                supabase link --project-ref mmaeznospyyowqecxdzc
//  3. Set secrets:
//       supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxxxx
//       supabase secrets set FROM_EMAIL=newsletter@yourdomain.com
//       supabase secrets set SITE_URL=https://yourdomain.com
//  4. Deploy:                    supabase functions deploy notify-subscribers
//
//  FREE TIER NOTE:
//  Resend free tier allows 3 000 emails/month and 100/day.
//  Sign up at https://resend.com — no credit card required.
//  You must verify a sending domain (or use onboarding@resend.dev for testing).
// ================================================================

import { serve }        from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
  // Handle CORS pre-flight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { title, excerpt, siteUrl } = await req.json() as {
      title:   string
      excerpt: string
      siteUrl: string
    }

    if (!title) {
      return new Response(JSON.stringify({ error: 'title is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Fetch active subscribers using the service-role key (bypasses RLS) ──
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: subscribers, error: dbError } = await supabase
      .from('subscribers')
      .select('email')
      .eq('status', 'active')

    if (dbError) throw new Error(`DB error: ${dbError.message}`)
    if (!subscribers?.length) {
      return new Response(JSON.stringify({ sent: 0, message: 'No active subscribers' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const emails  = subscribers.map((s: { email: string }) => s.email)
    const siteLink = siteUrl || Deno.env.get('SITE_URL') || ''

    // ── Email HTML — styled to match GracyBlog's palette ──
    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#faf8f3;font-family:'Georgia',serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#faf8f3;padding:40px 0">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#faf8f3;border:1px solid #e5dfd0;border-radius:8px;overflow:hidden">

          <!-- Header -->
          <tr>
            <td style="background:#1a1714;padding:24px 32px">
              <span style="font-family:Georgia,serif;font-size:22px;font-weight:700;color:#faf8f3;letter-spacing:-.5px">
                Graci<span style="color:#c04a1a">Blog</span>
              </span>
              <span style="font-family:monospace;font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#7a7060;margin-left:12px">
                // Newsletter
              </span>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding:32px 32px 24px">
              <p style="font-family:monospace;font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:#c04a1a;margin:0 0 16px">
                New article
              </p>
              <h1 style="font-family:Georgia,serif;font-size:28px;font-weight:700;color:#1a1714;line-height:1.2;margin:0 0 16px;letter-spacing:-.5px">
                ${title}
              </h1>
              ${excerpt ? `
              <p style="font-family:Georgia,serif;font-style:italic;font-size:17px;color:#3d3830;line-height:1.7;margin:0 0 28px;padding-bottom:24px;border-bottom:1px solid #e5dfd0">
                ${excerpt}
              </p>` : ''}
              <a href="${siteLink}"
                 style="display:inline-block;background:#c04a1a;color:#ffffff;padding:13px 26px;text-decoration:none;border-radius:4px;font-family:'DM Sans',sans-serif,Arial;font-size:14px;font-weight:600;letter-spacing:.02em">
                Read the full article →
              </a>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:20px 32px;border-top:1px solid #e5dfd0;background:#f0ece2">
              <p style="font-family:monospace;font-size:10px;color:#7a7060;line-height:1.6;margin:0">
                You received this because you subscribed at GracyBlog.
                <br/>To unsubscribe, reply to this email with "unsubscribe" in the subject.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`

    // ── Send via Resend ──
    const RESEND_KEY = Deno.env.get('RESEND_API_KEY')!
    const FROM       = Deno.env.get('FROM_EMAIL')!

    const resendRes = await fetch('https://api.resend.com/emails', {
      method:  'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    FROM,
        to:      emails,
        subject: `New post: ${title}`,
        html,
      }),
    })

    const resendData = await resendRes.json()

    if (!resendRes.ok) {
      throw new Error(`Resend error: ${JSON.stringify(resendData)}`)
    }

    return new Response(
      JSON.stringify({ sent: emails.length, resend: resendData }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
