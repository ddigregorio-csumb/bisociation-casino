# Bisociation Casino

An interactive slot-machine exercise for recombining business models, products/services, and markets into new venture ideas.

## Play

Public game: https://ddigregorio-csumb.github.io/bisociation-casino/

Click the red **Feeling lucky** knob for three independently randomized ingredients. Turn individual wheels with their arrows, keyboard, scrolling, or swiping to select a combination yourself. Browse each wheel to choose an option or insert your own. Custom options and private notes stay in your browser.

Rate your combination on two independent 1–10 scales: **How promising is it?** and **How ridiculous is it?** Choose both scores, then **Rate & share** to publish it on the community board, or **Save privately** to keep it in your notebook. You can edit both ratings on your private ideas and on any shared idea, including your own. The community board shows separate averages and vote counts, and can sort by newest, most promising, or most ridiculous. Ratings are one per browser guest identity per idea per scale; changing a score replaces that guest's previous score. This is a classroom creativity exercise, not a verified-person voting system.

## Hosting and database

GitHub Pages serves the static game from `main`, `/ (root)`. The published `index.html` is self-contained, with embedded styles, scripts, and reel graphics. The editable local source is split into HTML, CSS, JavaScript, and SVG files; `python3 build_release.py` produces `release/index.html`, which is published as the repository's root `index.html`.

Shared ideas and ratings use the dedicated `bisociation-casino` Supabase project (`tbiefntviubefpmzujji`). Guest sign-in is enabled; visitors do not need an email address or password.

For a replacement database, apply `database/schema.sql` followed by `database/002_dual_ratings.sql` in the dedicated project's SQL Editor, enable anonymous sign-ins, and configure the project URL and **publishable** browser key in `config.js` before rebuilding the release. For an existing installation, apply only `database/002_dual_ratings.sql` before deploying the updated game. It preserves existing ideas and promising scores; older ideas start with no ridiculous ratings, not zero scores. Never publish a secret or service-role key. The schema enables row-level security, blocks direct table access, and provides narrow authenticated functions for publishing, listing, and rating ideas. Publishing an idea and its two initial ratings is atomic; retries are idempotent. Each guest can publish up to 30 ideas per hour.

The host can moderate an idea by setting `bc_ideas.hidden` to `true` in the Supabase Table Editor. Public lists omit hidden ideas and private guest IDs. Supabase service availability and quotas are separate from GitHub Pages; a paused project must be resumed in Supabase for community sharing to work.

## Local preview

Run `python3 -m http.server 4173` in this directory, then open http://localhost:4173/. The game works without database configuration, but community sharing requires the configured Supabase project.
