-- Drivalry: check-in posts ("I got home"), Stage 3. Apply after 0002.
--
-- A check-in is a feed post of kind 'checkin' whose body carries only the
-- saved place's label chosen by the poster ("Home"), never coordinates. Only
-- circle members and friends see it, through the existing can_view rule.

alter type post_kind add value if not exists 'checkin';
