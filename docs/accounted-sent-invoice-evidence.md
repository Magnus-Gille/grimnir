# Accounted evaluation: evidence for originally sent invoice PDFs (GRIM-238)

Status: **owner-run read-only check procedure.** Nothing here may be executed by an agent: it
requires the owner's own logged-in Fortnox session and touches real financial data.

## Question

Only regenerated invoice previews exist for the Accounted evaluation. The exact PDF bytes that were
delivered to customers are not preserved. Does Fortnox itself retain the originals (sent-invoice
history or e-mail log)? If yes, the evidence gap can be closed by export. If not, the gap is
recorded as accepted.

## Why it matters

A regenerated preview is a rendering of today's data, not the document the customer received.
For a Fortnox replacement the question "can I show exactly what was sent" has to have an answer,
even if the answer is "no, and that is accepted".

## Procedure (owner, read-only)

1. In Fortnox, open a sample of sent invoices that span the period (suggested: the oldest, the
   newest, one with a credit note, one e-mailed and one sent by other channel). Use the sample,
   not the full set, for this check.
2. For each, record only: invoice number, send channel, and whether the invoice view offers
   (a) the stored sent PDF, (b) an e-mail log entry with the attachment, or (c) only regenerate.
3. Do not mark anything as sent, resend, or print through a path that changes state. Use viewing
   and download only.
4. If originals are retained, decide the export route (manual download of the sample, or a
   read-only bulk path) and record where the files will live. They are customer documents:
   store them in the private archive, never in git.
5. If originals are not retained for some or all channels, record the gap as accepted for
   evaluation, with the date, in the GRIM-238 comment.

## Result record (paste into GRIM-238)

| Field | Value |
|---|---|
| Date checked | |
| Sample size and span | |
| Originals retained: yes / partial / no | |
| Channels where retained | |
| Export route and private storage location (no paths in git) | |
| Gap accepted: yes / no / not needed | |

## Boundaries

- No Fortnox writes, no invoice state changes, no bulk automation by an agent.
- Do not paste customer names, amounts or document contents into tickets or this repository.
- If the result changes the pilot's evidence claims, update GRIM-240 as well.
