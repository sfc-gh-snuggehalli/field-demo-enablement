Call Transcript Corpus (synthetic)
==================================

24 synthetic customer call transcripts for the RelayFox SMS/MMS marketing
platform, used as the grounding corpus for the CALL_TRANSCRIPTS_SEARCH
Cortex Search service.

Breakdown by call type (from the CALL_ID prefix):
  - support     (CS-...)  10 files  transcript_support_01..10.txt
  - sales       (SD-/SE-)  8 files  transcript_sales_01..08.txt
  - compliance  (CE-...)   6 files  transcript_compliance_01..06.txt

Each .txt file has a header block (CALL_ID, DATE, DURATION, CALL_TYPE,
PARTICIPANTS, BRAND/MERCHANT, ACCOUNT_TIER) followed by [mm:ss] Speaker:
dialogue turns. The CALL_ID inside each file joins to manifest.csv, which
carries CALL_ID, DATE, CALL_TYPE, BRAND and a one-line SUMMARY.

These are fully synthetic and client-agnostic: the platform is the fictional
"RelayFox" and competitor/vendor mentions have been neutralized to fictional
names. Brand/merchant names (Harbor & Pine Home, LumaLeaf Beauty, etc.) are
invented and are used as the `brand` search attribute for filtered retrieval.
