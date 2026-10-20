# Demo Script: {{DECK_TITLE}}

About {{TOTAL_MINUTES}} minutes for {{AUDIENCE}}, plus Q&A. The [Cuts](#cuts) bring it to {{CUT_MINUTES}}. It interleaves the deck (`presentations/{{SLUG}}.html`) with {{LIVE_SURFACES}}. Slide-by-slide detail lives in `presentations/{{SLUG}}-speaker-notes.md`; this file is the run of show.

The audience should leave with three points:

1. **{{TAKEAWAY_1_TITLE}}.** {{TAKEAWAY_1_BODY}}
2. **{{TAKEAWAY_2_TITLE}}.** {{TAKEAWAY_2_BODY}}
3. **{{TAKEAWAY_3_TITLE}}.** {{TAKEAWAY_3_BODY}}

How to read the beats: **Say** is spoken (paraphrase freely), **Do** is a click or keystroke, **Show** is where to point and the value the room should see, **If** is the fallback.

## Pre-flight

### The day before

- `./demo.sh build --yes` has run on the demo account and every CHECK line passed (README, Quick start).
- Rehearse once end to end, and screenshot each expected result: {{SCREENSHOT_LIST}}. They are your fallback if the network or a live call fails.
{{DAY_BEFORE_EXTRA}}

### 30 minutes before

{{THIRTY_MIN_BEFORE_LIST}}
- Tab 1: the deck at slide 1. {{BROWSER_TABS}}

### Screen setup

- Browser at 125-150% zoom; results must be readable from the back row.
- Hide bookmarks, notifications and the terminal.
- {{START_STATE}}

## Run of show

| # | Segment | Where | Minutes | Ends at |
|---|---|---|---|---|
{{RUN_OF_SHOW_ROWS}}

{{SKIPPED_SLIDES_NOTE}}

{{SEGMENTS}}

## Cuts

Cut from the top of this list first:

{{CUTS_LIST}}

Never cut segment {{NEVER_CUT_SEGMENT}}. {{NEVER_CUT_REASON}}

## Recovery tips

| Symptom | Likely cause | Recovery |
|---|---|---|
{{RECOVERY_ROWS}}

## Q&A prep

{{QA_ITEMS}}

## After the talk

{{AFTER_THE_TALK_LIST}}
- When you're done with the demo for good: `./demo.sh teardown --yes`.
